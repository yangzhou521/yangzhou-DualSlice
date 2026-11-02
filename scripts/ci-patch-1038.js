// 打 1.0.38（41a9a8b）这次提交里 ThemeCorePlus 源码的补丁，直接看改了什么、找编译错误
function fetch(urlStr) {
    var url = ObjC.use('NSURL').URLWithString_(urlStr);
    var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
    req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
    req.setValue_forHTTPHeaderField_('ApelinCIProbe/1.0', 'User-Agent');
    var data = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
    if (!data) return null;
    return ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(data, 0, null);
}
var j = fetch('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/commits/41a9a8b');
if (!j) { print('ERR no data'); }
else {
    var files = j.valueForKey_('files');
    var n = files ? files.count() : 0;
    print('files=' + n);
    for (var i = 0; i < n; i++) {
        var f = files.objectAtIndex_(i);
        var name = f.valueForKey_('filename');
        print('===== ' + name + ' ' + f.valueForKey_('status') + ' +' + f.valueForKey_('additions') + ' -' + f.valueForKey_('deletions'));
        var patch = f.valueForKey_('patch');
        if (patch) print(String(patch));
    }
}
