// 查指定 tag 的 Release 资产（匿名 GitHub API），打印 name/size/digest/下载地址
// 用法：icli probe scripts/verify-yz530.js
var tag = 'yzthemecoreplus-v5.3.0';
var api = 'https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/releases/tags/' + tag;

var url = ObjC.use('NSURL').URLWithString_(api);
var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
req.setValue_forHTTPHeaderField_('ApelinCIProbe/1.0', 'User-Agent');

var data = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
if (!data) { print('ERROR: 网络失败（可能要 VPN 或限流）'); throw 'no data'; }
var rel = ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(data, 0, null);
if (!rel || rel.valueForKey_('message')) {
    print('ERROR: ' + (rel ? rel.valueForKey_('message') : '解析失败'));
    throw 'bad release';
}
print('tag=' + rel.valueForKey_('tag_name'));
var assets = rel.valueForKey_('assets');
for (var i = 0; assets && i < assets.count(); i++) {
    var a = assets.objectAtIndex_(i);
    print('asset=' + a.valueForKey_('name')
        + ' size=' + a.valueForKey_('size')
        + ' digest=' + (a.valueForKey_('digest') || '-'));
    print('url=' + a.valueForKey_('browser_download_url'));
}
