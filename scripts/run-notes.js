// 读某次 run 的注解（公开仓库匿名可读），用于看云编译 fail 的 error: 行。
// 用法：icli probe scripts/run-notes.js 42000753633
// 参数通过环境变量传：RUN_ID=42000753633 icli probe scripts/run-notes.js
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
var env = ObjC.use('NSProcessInfo').processInfo().environment();
var id = String(env.objectForKey_('RUN_ID') || '');
if (!id) { print('ERROR: 需要 RUN_ID'); throw 'no run id'; }

var jobs = get('https://api.github.com/repos/' + R + '/actions/runs/' + id + '/jobs');
var list = jobs.valueForKey_('jobs');
print('jobs=' + list.count());
for (var i = 0; i < list.count(); i++) {
    var j = list.objectAtIndex_(i);
    print('job ' + j.valueForKey_('name') + ' concl=' + j.valueForKey_('conclusion'));
    var steps = j.valueForKey_('steps');
    if (steps) {
        for (var s = 0; s < steps.count(); s++) {
            var st = steps.objectAtIndex_(s);
            if (String(st.valueForKey_('conclusion')) == 'failure') {
                print('  FAILED STEP: ' + st.valueForKey_('name'));
            }
        }
    }
    var notes = get('https://api.github.com/repos/' + R + '/check-runs/' + j.valueForKey_('id') + '/annotations');
    if (notes && notes.count) {
        for (var k = 0; k < notes.count(); k++) {
            var a = notes.objectAtIndex_(k);
            print('  [' + a.valueForKey_('annotation_level') + '] ' + a.valueForKey_('title') + ' :: ' + a.valueForKey_('message'));
        }
    }
}