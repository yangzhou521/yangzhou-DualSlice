// 查 yangzhou-DualSlice 在 main 上最近几次 CI 的状态（匿名 GitHub API，不需要 curl）。
// 用法：icli probe scripts/ci-status.js
var api = 'https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs?branch=main&per_page=3';

var url = ObjC.use('NSURL').URLWithString_(api);
var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
req.setValue_forHTTPHeaderField_('ApelinCIProbe/1.0', 'User-Agent');

var data = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
if (!data) { print('ERROR: 请求失败（无网络？）'); throw 'no data'; }

var resp = ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(data, 0, null);
if (!resp) { print('ERROR: JSON 解析失败 len=' + data.length()); throw 'bad json'; }

var runs = resp.valueForKey_('workflow_runs');
if (!runs) {
    print('API 报错: message=' + resp.valueForKey_('message'));
    throw 'no runs';
}
var n = runs.count();
print('runs=' + n);
for (var i = 0; i < n; i++) {
    var r = runs.objectAtIndex_(i);
    print([
        'id=' + r.valueForKey_('id'),
        'sha=' + r.valueForKey_('head_sha'),
        'status=' + r.valueForKey_('status'),
        'concl=' + (r.valueForKey_('conclusion') || 'null'),
        'created=' + r.valueForKey_('created_at'),
        'url=' + r.valueForKey_('html_url')
    ].join(' '));
}

// ---- Apelin 更新检查（用户 2026-11-02 00:02：「apelin更新情况我不问都不知道」）----
// 「进 GitHub」这个动作必然经过本脚本，所以把版本比对挂在这里 = 不依赖我记得去查。
// 有新版本就打印 update-available，并在汇报时写清更新内容。
print('---');
(function () {
    var url = ObjC.use('NSURL').URLWithString_('https://api.github.com/repos/owngoal-dev/Apelin/releases/latest');
    var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
    req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
    req.setValue_forHTTPHeaderField_('ApelinCIProbe/1.0', 'User-Agent');
    var d = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
    if (!d) { print('apelin{state=unknown;reason=no-net}'); return; }
    var j = ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(d, 0, null);
    if (!j) { print('apelin{state=unknown;reason=bad-json}'); return; }
    var latest = String(j.valueForKey_('tag_name') || 'unknown').replace(/^v/, '');
    var pub = String(j.valueForKey_('published_at') || 'unknown');
    var local = 'unknown';
    try {
        var fm = ObjC.use('NSFileManager').defaultManager();
        var roots = ObjC.use('NSArray').arrayWithArray_(fm.contentsOfDirectoryAtPath_error_('/private/var/containers/Bundle/Application', null));
        for (var i = 0; i < roots.count(); i++) {
            var b = String(roots.objectAtIndex_(i));
            if (b.indexOf('.jbroot') < 0) continue;
            var info = ObjC.use('NSDictionary').dictionaryWithContentsOfFile_('/private/var/containers/Bundle/Application/' + b + '/Applications/Apelin.app/Info.plist');
            if (info) { local = String(info.objectForKey_('CFBundleShortVersionString')); break; }
        }
    } catch (e) {}
    function vnum(s) { var m = String(s).match(/(\d+)\.(\d+)\.(\d+)/); return m ? [+m[1], +m[2], +m[3]] : null; }
    var lv = vnum(local), rv = vnum(latest);
    var state = 'unknown';
    if (lv && rv) {
        var newer = rv[0] > lv[0] || (rv[0] === lv[0] && rv[1] > lv[1]) || (rv[0] === lv[0] && rv[1] === lv[1] && rv[2] > lv[2]);
        state = newer ? 'update-available' : 'up-to-date';
    }
    print('apelin{local=' + local + ';latest=' + latest + ';state=' + state + ';published=' + pub +
          ';url=https://github.com/owngoal-dev/Apelin/releases/tag/v' + latest + '}');
})();
