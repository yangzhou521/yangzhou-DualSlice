// 读指定 run 的 check-run annotations（dump 整个 output 对象）
var runId = '41268973979';

function fetch(urlStr) {
    var url = ObjC.use('NSURL').URLWithString_(urlStr);
    var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
    req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
    req.setValue_forHTTPHeaderField_('ApelinCIProbe/1.0', 'User-Agent');
    var data = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
    if (!data) return null;
    return ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(data, 0, null);
}

var run = fetch('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs/' + runId);
var sha = run.valueForKey_('head_sha');

var cr = fetch('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/commits/' + sha + '/check-runs');
var arr = cr.valueForKey_('check_runs');
var r = arr.objectAtIndex_(0);
var out = r.valueForKey_('output');
var anns = out.valueForKey_('annotations');
// anns 可能是 NSArray；用 count 反射
var cnt = 0;
try { cnt = anns.count(); } catch (e) { cnt = 0; }
print('annos=' + cnt);
for (var k = 0; k < cnt; k++) {
    var ann = anns.objectAtIndex_(k);
    print('---');
    print('level=' + ann.valueForKey_('annotation_level'));
    print('title=' + ann.valueForKey_('title'));
    print('msg=' + ann.valueForKey_('message'));
}
