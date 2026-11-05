// 查 AppIcon 这条线：main 上最近 5 次 run 的 name/path/conclusion + appicon 相关 Release 资产。
// 用法：icli probe scripts/appicon-ci.js
function get(url) {
    var u = ObjC.use('NSURL').URLWithString_(url);
    var req = ObjC.use('NSMutableURLRequest').requestWithURL_(u);
    req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
    req.setValue_forHTTPHeaderField_('AppIconCIProbe/1.0', 'User-Agent');
    var d = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
    if (!d) return null;
    return ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(d, 0, null);
}

var R = 'yangzhou521/yangzhou-DualSlice';

var runs = get('https://api.github.com/repos/' + R + '/actions/runs?branch=main&per_page=5');
if (!runs) { print('ERROR: 无网络'); throw 'no net'; }
var list = runs.valueForKey_('workflow_runs');
print('runs=' + (list ? list.count() : 0));
if (list) {
    for (var i = 0; i < list.count(); i++) {
        var r = list.objectAtIndex_(i);
        print(['  id=' + r.valueForKey_('id'),
               'wf=' + r.valueForKey_('name'),
               'path=' + r.valueForKey_('path'),
               'sha=' + String(r.valueForKey_('head_sha')).substring(0, 8),
               'status=' + r.valueForKey_('status'),
               'concl=' + (r.valueForKey_('conclusion') || 'null'),
               'created=' + r.valueForKey_('created_at')].join(' '));
    }
}

var rels = get('https://api.github.com/repos/' + R + '/releases?per_page=6');
print('--- releases ---');
if (rels) {
    for (var i = 0; i < rels.count(); i++) {
        var rel = rels.objectAtIndex_(i);
        var tag = String(rel.valueForKey_('tag_name'));
        if (tag.indexOf('appicon') < 0) continue;
        var assets = rel.valueForKey_('assets');
        var parts = [];
        for (var j = 0; j < assets.count(); j++) {
            var a = assets.objectAtIndex_(j);
            parts.push(a.valueForKey_('name') + '(' + a.valueForKey_('size') + 'B)');
        }
        print('  ' + tag + ' ' + String(rel.valueForKey_('created_at')) + ' assets=' + parts.join(','));
        var first = assets.count() ? assets.objectAtIndex_(0) : null;
        if (first) print('  url=' + first.valueForKey_('browser_download_url'));
    }
}