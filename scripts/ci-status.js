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
