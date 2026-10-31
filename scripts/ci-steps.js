// 看某次 CI run 的 job 步骤结论（匿名 GitHub API）。
// 用法：icli probe scripts/ci-steps.js   （run id 写死在下面）
var runId = '41158895611';
var base = 'https://api.github.com/repos/yangzhou521/yangzhou-DualSlice';

function get(path) {
    var url = ObjC.use('NSURL').URLWithString_(base + path);
    var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
    req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
    req.setValue_forHTTPHeaderField_('ApelinCIProbe/1.0', 'User-Agent');
    var data = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
    if (!data) return null;
    return ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(data, 0, null);
}

var jobs = get('/actions/runs/' + runId + '/jobs');
var js = jobs.valueForKey_('jobs');
for (var i = 0; i < js.count(); i++) {
    var j = js.objectAtIndex_(i);
    print('JOB ' + j.valueForKey_('name') + ' -> ' + j.valueForKey_('conclusion'));
    var steps = j.valueForKey_('steps');
    if (!steps) continue;
    for (var k = 0; k < steps.count(); k++) {
        var s = steps.objectAtIndex_(k);
        var st = s.valueForKey_('status');
        var cc = s.valueForKey_('conclusion');
        if (st != 'completed' || (cc && cc != 'success')) {
            print('  STEP ' + s.valueForKey_('number') + ' ' + s.valueForKey_('name') + ' -> ' + st + '/' + cc);
        }
    }
}
