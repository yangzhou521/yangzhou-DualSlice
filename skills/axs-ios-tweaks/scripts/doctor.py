#!/usr/bin/env python3
"""Read-only checks for generated projects; never builds or installs anything."""

import argparse
import json
import os
import plistlib
import re
import shutil
import sys
from pathlib import Path


TOKEN = re.compile(r"__[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*__")
SYSTEM_METHODS = {
    "init", "dealloc", "specifiers", "readPreferenceValue", "setPreferenceValue",
    "initWithStyle", "refreshCellContentsWithSpecifier", "prepareForReuse",
    "layoutSubviews", "tableView",
}


def check_project(project):
    project = Path(project)
    results = []

    def report(level, message):
        results.append((level, message))

    try:
        meta = json.loads((project / "tweak.json").read_text(encoding="utf-8"))
        prefix, symbol, domain = meta["class_prefix"], meta["symbol_prefix"], meta["package"]
        if meta["schema"] != 1:
            raise ValueError("unsupported tweak.json schema")
        if not re.fullmatch(r"[A-Z][A-Za-z0-9]+", prefix):
            raise ValueError("invalid class_prefix")
        if not re.fullmatch(r"[a-z][a-z0-9]*_[a-z][a-z0-9]*", symbol):
            raise ValueError("invalid symbol_prefix")
        if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", domain):
            raise ValueError("invalid package")
        if not all(isinstance(meta[key], bool) for key in ("preferences", "slider")):
            raise ValueError("preferences and slider must be booleans")
        if meta["slider"] and not meta["preferences"]:
            raise ValueError("slider requires preferences")
    except (OSError, ValueError, KeyError, TypeError) as error:
        report("ERROR", "Cannot read project metadata: " + str(error))
        return results

    if any(char.isspace() for char in str(project.resolve())):
        report("ERROR", "Theos project path contains whitespace")
    required = [
        "control", "Makefile", "build.sh", prefix + "Build.mk", prefix + ".plist",
        "Hooks/" + prefix + "Main.xm", "Headers/" + prefix + "Private.h",
        "Sources/" + prefix + "Config.h", "Sources/" + prefix + "Config.m",
        "Sources/" + prefix + "Preferences.h", "Sources/" + prefix + "Paths.h",
    ]
    if meta.get("github_actions", False):
        required.append(".github/workflows/build.yml")
    if meta["preferences"]:
        required += [
            prefix + "Prefs/Makefile", prefix + "Prefs/" + prefix + "RootListController.h",
            prefix + "Prefs/" + prefix + "RootListController.m",
            prefix + "Prefs/Resources/Info.plist", prefix + "Prefs/Resources/" + prefix + "Root.plist",
            "layout/Library/PreferenceLoader/Preferences/" + prefix + "Prefs.plist",
        ]
    if meta["slider"]:
        required += [prefix + "Prefs/" + prefix + "SliderCell" + ext for ext in (".h", ".m")]
    for name in required:
        if not (project / name).is_file():
            report("ERROR", "Missing " + name)

    control = {}
    try:
        for line in (project / "control").read_text(encoding="utf-8").splitlines():
            if line and not line[0].isspace():
                key, value = line.split(":", 1)
                control[key] = value.strip()
        if control.get("Package") != domain:
            report("ERROR", "control Package differs from tweak.json")
        depends = control.get("Depends", "")
        if meta["preferences"] and "preferenceloader" not in depends:
            report("ERROR", "PreferenceBundle requires preferenceloader dependency")
    except (OSError, ValueError) as error:
        report("ERROR", "Invalid control: " + str(error))

    plists = {}
    for path in project.rglob("*"):
        if not path.is_file() or any(part in {".theos", "packages", ".git"} for part in path.relative_to(project).parts):
            continue
        relative = path.relative_to(project).as_posix()
        if path.suffix not in {".m", ".h", ".xm", ".plist", ".mk", ".sh", ".json", ".yml", ".yaml"} and path.name not in {"Makefile", "control"}:
            continue
        try:
            raw = path.read_bytes()
            if raw.startswith(b"\xef\xbb\xbf"):
                report("ERROR", relative + ": UTF-8 BOM")
            text = raw.decode("utf-8")
        except (OSError, UnicodeError) as error:
            report("ERROR", relative + ": " + str(error))
            continue
        if TOKEN.search(text):
            report("ERROR", relative + ": unresolved template token")
        if path.suffix == ".sh" and b"\r\n" in raw:
            report("ERROR", relative + ": shell script requires LF line endings")
        if path.suffix == ".plist":
            try:
                decoded = plistlib.loads(raw)
                if not isinstance(decoded, dict):
                    raise ValueError("top-level plist must be a dictionary")
                plists[relative] = decoded
            except Exception as error:
                report("ERROR", relative + ": invalid plist: " + str(error))
        if path.suffix not in {".h", ".m", ".xm"}:
            continue
        if not path.stem.startswith(prefix):
            report("ERROR", relative + ": custom source filename lacks plugin prefix")
        for declaration in re.finditer(
                r"@(interface|implementation|protocol)\s+([A-Za-z_]\w*)(?:\s*\((\w*)\))?", text):
            kind, name, category = declaration.groups()
            if category is not None and category:
                if not category.startswith(prefix):
                    report("ERROR", relative + ": unnamespaced category " + category)
            elif not (kind != "implementation" and relative.startswith("Headers/")):
                if not name.startswith(prefix):
                    report("ERROR", relative + ": unnamespaced class/protocol " + name)
        function_pattern = (
            r"^[ \t]*(?:(?:static|inline|extern)\s+)*(?:const\s+)?"
            r"(?:void|BOOL|bool|id|int|char|long|short|double|float|size_t|"
            r"[A-Z]\w*(?:<[^>\n]+>)?)\s+\**\s*([A-Za-z_]\w*)\s*\("
        )
        if not relative.startswith("Headers/"):
            for function in re.findall(function_pattern, text, re.M):
                if not function.startswith(symbol + "_"):
                    report("ERROR", relative + ": custom function lacks plugin prefix: " + function)
        if path.suffix != ".xm" and not relative.startswith("Headers/"):
            for method in re.findall(r"^[+-]\s*\([^)]*\)\s*([A-Za-z_]\w*)", text, re.M):
                if method not in SYSTEM_METHODS and not method.startswith(symbol + "_"):
                    report("ERROR", relative + ": custom selector lacks plugin prefix: " + method)
        for include in re.findall(r'^\s*#import\s+"([^"]+)"', text, re.M):
            candidates = [path.parent / include, project / "Sources" / include, project / "Headers" / include]
            if not any(item.is_file() for item in candidates):
                report("ERROR", relative + ": missing local import " + include)

    filter_plist = plists.get(prefix + ".plist", {})
    try:
        bundles = filter_plist["Filter"]["Bundles"]
        if not bundles or not all(isinstance(item, str) for item in bundles):
            raise ValueError("Bundles must be a nonempty list of strings")
        if meta["bundle"] not in bundles:
            report("WARN", "Filter changed from manifest bundle; review and update tweak.json")
        if bundles != ["com.apple.springboard"]:
            report("WARN", "Custom filter: replace the sample SpringBoard hook and verify target methods")
    except (KeyError, TypeError, ValueError) as error:
        report("ERROR", "Invalid injection filter: " + str(error))

    if meta["preferences"]:
        entry_path = "layout/Library/PreferenceLoader/Preferences/" + prefix + "Prefs.plist"
        entry = plists.get(entry_path, {}).get("entry", {})
        if not isinstance(entry, dict):
            report("ERROR", "PreferenceLoader entry must be a dictionary")
            entry = {}
        info = plists.get(prefix + "Prefs/Resources/Info.plist", {})
        if entry.get("bundle") != prefix + "Prefs" or entry.get("detail") != prefix + "RootListController":
            report("ERROR", "PreferenceLoader entry has mismatched bundle/controller")
        if info.get("NSPrincipalClass") != entry.get("detail") or info.get("CFBundleIdentifier") != domain + ".preferences":
            report("ERROR", "PreferenceBundle Info.plist identity mismatch")
        root = plists.get(prefix + "Prefs/Resources/" + prefix + "Root.plist", {})
        items = root.get("items", [])
        if not isinstance(items, list):
            report("ERROR", "Preference specifiers must be a list")
            items = []
        for item in items:
            if not isinstance(item, dict):
                report("ERROR", "Preference specifier must be a dictionary")
                continue
            if "key" in item and item.get("defaults") != domain:
                report("ERROR", "Preference key uses another plugin's domain: " + str(item["key"]))
            cell_class = item.get("cellClass")
            if cell_class and (not isinstance(cell_class, str) or not cell_class.startswith(prefix)):
                report("ERROR", "Custom cell lacks plugin namespace: " + str(cell_class))
        if meta["slider"] and not any(isinstance(item, dict) and item.get("cellClass") == prefix + "SliderCell" for item in items):
            report("ERROR", "Slider component has no plist specifier")
    if not any(level == "ERROR" for level, _ in results):
        report("OK", "Project structure, local imports, plist identities and namespaces")
    report("NOTE", "Static checks only; not a Theos compile or device test")
    return results


def check_environment(scheme):
    results = []
    theos = os.environ.get("THEOS")
    if not theos:
        results.append(("ERROR", "THEOS is not set"))
    else:
        root = Path(theos).expanduser()
        for name in ("makefiles/common.mk", "makefiles/tweak.mk", "makefiles/bundle.mk"):
            if not (root / name).is_file():
                results.append(("ERROR", "Missing toolchain file: " + str(root / name)))
        include_roots = [root / "include", root / "vendor/include"]
        header = "roothide.h" if scheme == "roothide" else "rootless.h"
        if not any((include / header).is_file() for include in include_roots):
            results.append(("ERROR", "Missing toolchain header: " + header))
        if not list((root / "sdks").glob("iPhoneOS*.sdk")):
            results.append(("WARN", "No Theos-local iOS SDK found; verify SDKROOT or platform SDK discovery"))
    for command in ("make", "perl", "clang", "dpkg-deb"):
        binary = shutil.which(command)
        results.append(("OK" if binary else "WARN",
                        command + (": " + binary if binary else " not on PATH; check Theos toolchain overrides")))
    if os.name == "nt":
        results.append(("WARN", "Native Windows is not a supported Theos build environment; use WSL/Linux or a configured device shell"))
    if scheme == "roothide":
        results.append(("NOTE", "Roothide additionally requires its compatible Theos fork and libraries"))
    results.append(("NOTE", "Environment checks do not establish Minis import or on-device build compatibility"))
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", nargs="?")
    parser.add_argument("--environment", action="store_true")
    parser.add_argument("--scheme", choices=("rootful", "rootless", "roothide"), default="rootless")
    args = parser.parse_args()
    if not args.project and not args.environment:
        parser.error("provide a project directory or --environment")
    results = check_project(args.project) if args.project else []
    if args.environment:
        results += check_environment(args.scheme)
    for level, message in results:
        print("[{}] {}".format(level, message))
    return 1 if any(level == "ERROR" for level, _ in results) else 0


if __name__ == "__main__":
    sys.exit(main())
