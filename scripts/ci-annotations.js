// 把某次 CI run 的 check-run annotations 原样打印（匿名可读）。
// 用法：icli probe scripts/ci-annotations.js   （run id 改下面的 runId）
var runId = '41170405550';
var base = 'https://api.github.com/repos/yangzhou521/yangzhou-DualSlice';

function getText(path) {
    var url = ObjC.use('NSURL').URLWithString_(base + path);
    var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
    req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
    req.setValue_forHTTPHeaderField_('ApelinCIProbe/1.0', 'User-Agent');
    var data = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
    if (!data) return '';
    var s = ObjC.use('NSString').alloc().initWithData_encoding_(data, 4);
    return String(s);
}

var runText = getText('/actions/runs/' + runId);
var m = /"head_sha"\s*:\s*"([0-9a-f]{40})"/.exec(runText);
var sha = m ? m[1] : null;
print('run=' + runId + ' sha=' + sha);
if (!sha) { print(runText.substring(0, 600)); throw 'x'; }

var checkText = getText('/commits/' + sha + '/check-runs');
var ids = checkText.match(/"id"\s*:\s*(\d{6,})/g) || [];
var uniq = [];
for (var i = 0; i < ids.length; i++) {
    var id = ids[i].replace(/\D/g, '');
    if (uniq.indexOf(id) < 0) uniq.push(id);
}
for (var k = 0; k < uniq.length; k++) {
    print('CHECKRUN ' + uniq[k]);
    print('  ' + getText('/check-runs/' + uniq[k] + '/annotations'));
}
