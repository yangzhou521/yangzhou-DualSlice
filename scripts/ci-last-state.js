// icli probe scripts/ci-last-state.js
// 守护脚本用：只输出 yangzhou-DualSlice/main 最新一次工作流运行的一行结论。
// 输出示例：id=41692942642 sha=0fb2da7b status=completed concl=success created=2026-11-03T18:20:59Z
var api = 'https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs?branch=main&per_page=1';

var url = ObjC.use('NSURL').URLWithString_(api);
var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
req.setValue_forHTTPHeaderField_('ApelinCIDaemon/1.0', 'User-Agent');

var data = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
if (!data) { print('concl=unknown'); throw 'no data'; }
var j = ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(data, 0, null);
if (!j) { print('concl=unknown'); throw 'bad json'; }

var runs = j.valueForKey_('workflow_runs');
if (!runs || runs.count() === 0) { print('concl=unknown'); throw 'no runs'; }

var r = runs.objectAtIndex_(0);
print('id=' + r.valueForKey_('id') +
      ' sha=' + r.valueForKey_('head_sha') +
      ' status=' + r.valueForKey_('status') +
      ' concl=' + (r.valueForKey_('conclusion') || 'null') +
      ' created=' + r.valueForKey_('created_at'));
