// 查指定 sha 的 CI check-run 里 error 级别的注解（匿名可读），只打印错误。
// 用法：icli probe scripts/ci-err.js    （sha 改这里）
var sha = '331961fcb0d74233b9e802dc3eec0aebe8893eb5';
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

var checkText = getText('/commits/' + sha + '/check-runs');
var ids = checkText.match(/"id"\s*:\s*(\d{6,})/g) || [];
var uniq = [];
for (var i = 0; i < ids.length; i++) {
    var id = ids[i].replace(/\D/g, '');
    if (uniq.indexOf(id) < 0) uniq.push(id);
}
print('sha=' + sha + ' checkruns=' + uniq.length);
for (var k = 0; k < uniq.length; k++) {
    var t = getText('/check-runs/' + uniq[k] + '/annotations');
    var re = /\{"path"[^{}]*?"message":"((?:[^"\\]|\\.)*)"[^{}]*?\}/g;
    var m, n = 0;
    while ((m = re.exec(t)) !== null && n < 12) {
        var s = m[1].replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
        if (/error:|警告|error\b/i.test(s) || s.length > 200) {
            print('--- ANN ' + (++n) + ' ---');
            print(s.substring(0, 1200));
        }
    }
}