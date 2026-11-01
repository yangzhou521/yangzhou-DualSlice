// 读指定 check-run 的 annotations（匿名 GitHub API，公开仓库可读）
// 用法：icli probe scripts/ci-anno2.js <run_id>
var runId = '41268973979';

// 先拿 run 对应的 check suite -> check runs
var urlStr = 'https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs/' + runId + '/jobs?per_page=30';
var url = ObjC.use('NSURL').URLWithString_(urlStr);
var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
req.setValue_forHTTPHeaderField_('ApelinCIProbe/1.0', 'User-Agent');
var data = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
if (!data) { print('ERROR: no data'); throw 'no data'; }
var jobs = ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(data, 0, null);
if (!jobs) { print('ERROR: bad json'); throw 'bad json'; }
var arr = jobs.valueForKey_('jobs');
var n = arr.count();
print('jobs=' + n);
for (var i = 0; i < n; i++) {
    var j = arr.objectAtIndex_(i);
    var steps = j.valueForKey_('steps');
    var sc = steps ? steps.count() : 0;
    print('job=' + j.valueForKey_('name') + ' concl=' + (j.valueForKey_('conclusion')||'-') + ' steps=' + sc);
    if (steps) {
        for (var k = 0; k < sc; k++) {
            var st = steps.objectAtIndex_(k);
            var c = st.valueForKey_('conclusion');
            if (c != 'success' && c != 'skipped' && c != 'neutral') {
                print('  FAIL step[' + k + ']=' + st.valueForKey_('name') + ' concl=' + c);
            }
        }
    }
}
