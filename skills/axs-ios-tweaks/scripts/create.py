#!/usr/bin/env python3
"""Render self-contained Theos projects. Python 3.8+, standard library only."""

import argparse
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path
from xml.sax.saxutils import escape


SKILL_ROOT = Path(__file__).resolve().parent.parent
TOKEN = re.compile(r"__[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*__")
IDENTIFIER = re.compile(r"[A-Z][A-Za-z0-9]*\Z")
SLUG = re.compile(r"[a-z][a-z0-9]*\Z")
BUNDLE = re.compile(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\Z")
BINARY_ASSET_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic", ".ico", ".icns",
    ".pdf", ".ttf", ".otf", ".car",
}


def one_line(value, label):
    if not isinstance(value, str) or not value or any(c in value for c in "\r\n\0"):
        raise ValueError("{} must be a nonempty single line".format(label))
    return value


def objc(value):
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\t", "\\t")


def substitute(text, values):
    def replace(match):
        token = match.group()
        if token not in values:
            raise ValueError("unknown template token: " + token)
        return values[token]
    return TOKEN.sub(replace, text)


def project_values(args, defaults):
    if not IDENTIFIER.fullmatch(args.name):
        raise ValueError("--name must be an ASCII PascalCase identifier, e.g. TouchTrail")
    slug = args.id or args.name.lower()
    if not SLUG.fullmatch(slug):
        raise ValueError("--id must start with a lowercase letter and contain only a-z/0-9")
    if slug != args.name.lower():
        raise ValueError("--id must equal the lowercase --name to prevent namespace drift")
    if args.slider and not args.preferences:
        raise ValueError("--slider requires --preferences")
    if not IDENTIFIER.fullmatch(defaults["class_prefix"]):
        raise ValueError("defaults.class_prefix must be an ASCII class prefix")
    domain = defaults["package_prefix"] + "." + slug
    if not BUNDLE.fullmatch(domain) or not BUNDLE.fullmatch(args.bundle):
        raise ValueError("package prefix and --bundle must form valid dotted identifiers")
    sdk_version = defaults["sdk_version"]
    if not isinstance(sdk_version, str) or not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", sdk_version):
        raise ValueError("sdk_version must be an explicit version such as 16.5")
    minimum_ios = args.minimum_ios or defaults["minimum_ios"]
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", minimum_ios):
        raise ValueError("--minimum-ios must be a version such as 14.0")
    if int(minimum_ios.split(".")[0]) < 14:
        raise ValueError("this template supports iOS 14+; older targets need a separate adaptation")
    jb_minimum_ios = minimum_ios if int(minimum_ios.split(".")[0]) >= 15 else "15.0"
    display = one_line(args.display_name or args.name, "display name")
    description = one_line(args.description or display, "description")
    prefix = defaults["class_prefix"] + args.name
    symbol = defaults["class_prefix"].lower() + "_" + slug
    repository = one_line(defaults["repository_url"], "repository URL").rstrip("/")
    if not repository.startswith("https://"):
        raise ValueError("repository_url must use https://")
    for key in ("author", "section", "version", "telegram_url", "telegram_fallback", "qq_url"):
        one_line(defaults[key], key)
    if not re.fullmatch(r"\d[A-Za-z0-9.+:~-]*", defaults["version"]):
        raise ValueError("version must be a Debian version starting with a digit")
    values = {
        "__NAME__": args.name,
        "__SLUG__": slug,
        "__PREFIX__": prefix,
        "__SYMBOL__": symbol,
        "__DOMAIN__": domain,
        "__BUNDLE__": args.bundle,
        "__SDK_VERSION__": sdk_version,
        "__MIN_IOS__": minimum_ios,
        "__JB_MIN_IOS__": jb_minimum_ios,
        "__DISPLAY__": display,
        "__DESCRIPTION__": description,
        "__AUTHOR__": defaults["author"],
        "__SECTION__": defaults["section"],
        "__VERSION__": defaults["version"],
        "__CI_RELEASE_TITLE__": json.dumps(
            display + " v${{ steps.bump.outputs.package_version }}", ensure_ascii=False),
        "__REPOSITORY__": repository,
        "__TELEGRAM__": defaults["telegram_url"],
        "__TELEGRAM_FALLBACK__": defaults["telegram_fallback"],
        "__QQ__": defaults["qq_url"],
        "__DEFAULT_ENABLED__": "NO" if args.preferences else "YES",
        "__SUBPROJECTS__": (
            "SUBPROJECTS += {0}Prefs\ninclude $(THEOS_MAKE_PATH)/aggregate.mk".format(prefix)
            if args.preferences else ""
        ),
        "__DEPENDS__": "mobilesubstrate, preferenceloader" if args.preferences else "mobilesubstrate",
        "__SLIDER_PROTOCOL__": " <{}SliderCellHandler>".format(prefix) if args.slider else "",
        "__SLIDER_IMPORT__": '#import "{}SliderCell.h"'.format(prefix) if args.slider else "",
        "__SLIDER_METHODS__": "",
        "__SLIDER_PLIST__": "",
    }
    if args.slider:
        fragments = SKILL_ROOT / "assets" / "slider"
        values["__SLIDER_METHODS__"] = substitute(
            (fragments / "controller.inc").read_text(encoding="utf-8"), values)
        values["__SLIDER_PLIST__"] = substitute(
            (fragments / "specifier.inc").read_text(encoding="utf-8"), values)
    manifest = {
        "schema": 1, "name": args.name, "id": slug, "display_name": display,
        "class_prefix": prefix, "symbol_prefix": symbol, "package": domain,
        "bundle": args.bundle, "sdk_version": sdk_version, "minimum_ios": minimum_ios,
        "preferences": args.preferences, "slider": args.slider,
        "github_actions": not args.no_github_actions,
    }
    return values, manifest


def render_group(group, values, stage, seen):
    if not group.is_dir():
        raise ValueError("missing template group: " + str(group))
    for source in sorted(group.rglob("*")):
        if not source.is_file() or source.suffix == ".inc":
            continue
        relative = substitute(source.relative_to(group).as_posix(), values)
        if relative in seen:
            raise ValueError("template output collision: " + relative)
        seen.add(relative)
        output = stage / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        if source.suffix.lower() in BINARY_ASSET_SUFFIXES:
            shutil.copyfile(source, output)
            continue
        text = source.read_text(encoding="utf-8")
        replacements = values
        if source.suffix == ".plist":
            replacements = {key: value if key == "__SLIDER_PLIST__" else escape(value)
                            for key, value in values.items()}
        elif source.suffix in (".h", ".m", ".xm"):
            replacements = {key: value if key in ("__SLIDER_IMPORT__", "__SLIDER_METHODS__")
                            else objc(value) for key, value in values.items()}
        result = substitute(text, replacements)
        if TOKEN.search(result):
            raise ValueError("unresolved template token in " + relative)
        with output.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write(result)
        if output.suffix == ".sh":
            output.chmod(output.stat().st_mode | 0o111)


def generate(args):
    defaults = json.loads((SKILL_ROOT / "assets" / "defaults.json").read_text(encoding="utf-8"))
    values, manifest = project_values(args, defaults)
    destination = Path(args.destination).expanduser().absolute()
    if destination.exists() or destination.is_symlink():
        raise ValueError("output already exists; refusing to overwrite: " + str(destination))
    if any(char.isspace() for char in str(destination)):
        raise ValueError("Theos project paths must not contain whitespace")
    destination.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".axs-ios-tweaks-", dir=str(destination.parent)))
    try:
        groups = ["base"]
        if not args.no_github_actions:
            groups.append("github-actions")
        if args.preferences:
            groups.append("preferences")
        if args.slider:
            groups.append("slider")
        seen = set()
        for group in groups:
            render_group(SKILL_ROOT / "assets" / group, values, stage, seen)
        with (stage / "tweak.json").open("w", encoding="utf-8", newline="\n") as handle:
            json.dump(manifest, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        stage.rename(destination)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return destination


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("destination", help="new output directory (must not exist)")
    result.add_argument("--name", required=True, help="ASCII code name, e.g. TouchTrail")
    result.add_argument("--id", help="lowercase code name; defaults to --name.lower()")
    result.add_argument("--display-name", help="user-facing name, including Chinese")
    result.add_argument("--description")
    result.add_argument("--bundle", default="com.apple.springboard")
    result.add_argument("--minimum-ios")
    result.add_argument("--preferences", action="store_true")
    result.add_argument("--slider", action="store_true")
    result.add_argument("--no-github-actions", action="store_true",
                        help="omit the default GitHub Actions build/release workflow")
    return result


def main():
    try:
        destination = generate(parser().parse_args())
    except (ValueError, OSError, KeyError, TypeError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 1
    print("Created " + str(destination))
    print("Next: python3 scripts/doctor.py " + str(destination))
    return 0


if __name__ == "__main__":
    sys.exit(main())
