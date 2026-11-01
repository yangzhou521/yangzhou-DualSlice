// 查 yangzhou-DualSlice 的 release 列表（匿名 GitHub API）
var api = 'https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/releases?per_page=5';

var url = ObjC.use('NSURL').URLWithString_(api);
var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
req.setValue_forHTTPHeaderField_('ApelinCIProbe/1.0', 'User-Agent');

var data = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
if (!data) { print('ERROR: 网络失败'); throw 'no data'; }
var resp = ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(data, 0, null);
if (!resp) { print('ERROR: JSON 解析失败'); throw 'bad json'; }
var arr = resp.count() > 0 ? resp.objectAtIndex_(0) : null;
if (!arr) { print('no releases'); throw 'none'; }
var n = arr.count();
print('releases=' + n);
for (var i = 0; i < n; i++) {
    var r = arr.objectAtIndex_(i);
    var assets = r.valueForKey_('assets');
    var names = [];
    if (assets) {
        for (var j = 0; j < assets.count(); j++) {
            names.push(assets.objectAtIndex_(j).valueForKey_('name'));
        }
    }
    print('tag=' + r.valueForKey_('tag_name') + ' draft=' + r.valueForKey_('draft') + ' published=' + (r.valueForKey_('published_at')||'-') + ' assets=' + names.join(','));
}
