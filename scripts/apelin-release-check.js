// 查 Apelin（owngoal-dev/Apelin）最新 release，并和本机已装版本比对。
// 用法：icli probe scripts/apelin-release-check.js
//
// 为什么单独一个文件（用户 2026-11-02 00:02 提问「apelin更新情况我不问都不知道」）：
//   以前「Apelin 更新监视」只写在记忆/AGENTS.md 里一句话，没有触发器 —— 写进文件 ≠ 会执行。
//   本脚本被 scripts/ci-status.js 主动调用，而 ci-status.js 是「每次进 GitHub 必跑」的动作，
//   于是「查 Apelin 更新」被绑进「查编译状态」，不可能漏。
//
// 输出：apelin{local=X.Y.Z;latest=A.B.C;state=up-to-date|update-available|unknown;...}

function getJSON(urlStr) {
    var url = ObjC.use('NSURL').URLWithString_(urlStr);
    var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
    req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
    req.setValue_forHTTPHeaderField_('ApelinReleaseCheck/1.0', 'User-Agent');
    var data = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
    if (!data) return null;
    var resp = ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(data, 0, null);
    return resp;
}

// ---- 1. 云端最新 release ----
var latest = 'unknown';
var published = 'unknown';
var releaseUrl = 'unknown';
var rel = getJSON('https://api.github.com/repos/owngoal-dev/Apelin/releases/latest');
if (rel) {
    var t = rel.valueForKey_('tag_name');
    if (t) latest = String(t).replace(/^v/, '');
    var p = rel.valueForKey_('published_at');
    if (p) published = String(p);
    var u = rel.valueForKey_('html_url');
    if (u) releaseUrl = String(u);
}

// ---- 2. 本机已装版本（icli app info wiki.qaq.apelin 的 version 字段）----
var local = 'unknown';
var build = 'unknown';
try {
    var fm = ObjC.use('NSFileManager').defaultManager();
    var apps = ObjC.use('NSArray').arrayWithArray_(fm.contentsOfDirectoryAtPath_error_('/var/containers/Bundle/Application', null));
    // Apelin 装在引导根的 Applications/ 下，不在 /var/containers/Bundle/Application
    var roots = fm.contentsOfDirectoryAtPath_error_('/private/var/containers/Bundle/Application', null);
    var cands = ObjC.use('NSArray').arrayWithArray_(roots);
    var m = cands.count();
    for (var i = 0; i < m; i++) {
        var b = String(cands.objectAtIndex_(i));
        if (b.indexOf('.jbroot') < 0) continue;
        var ip = '/private/var/containers/Bundle/Application/' + b + '/Applications/Apelin.app/Info.plist';
        var d = ObjC.use('NSDictionary').dictionaryWithContentsOfFile_(ip);
        if (d) {
            var vs = d.objectForKey_('CFBundleShortVersionString');
            var bv = d.objectForKey_('CFBundleVersion');
            if (vs) local = String(vs);
            if (bv) build = String(bv);
            break;
        }
    }
} catch (e) {
    // 找不到就留 unknown，不报错
}

// ---- 3. 比对 ----
function vnum(s) {
    var m = String(s).match(/(\d+)\.(\d+)\.(\d+)/);
    return m ? [parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10)] : null;
}
var state = 'unknown';
var lv = vnum(local), rv = vnum(latest);
if (lv && rv) {
    if (rv[0] > lv[0] || (rv[0] === lv[0] && rv[1] > lv[1]) || (rv[0] === lv[0] && rv[1] === lv[1] && rv[2] > lv[2])) {
        state = 'update-available';
    } else {
        state = 'up-to-date';
    }
}

print('apelin{local=' + local + ';build=' + build + ';latest=' + latest + ';state=' + state +
      ';published=' + published + ';url=' + releaseUrl + '}');
