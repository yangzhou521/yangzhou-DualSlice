// 原始回包：看清楚 GitHub API 到底返回了什么（限流/权限/正常）。
var api = 'https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs?branch=main&per_page=2';
var url = ObjC.use('NSURL').URLWithString_(api);
var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
req.setValue_forHTTPHeaderField_('ApelinCIProbe/1.0', 'User-Agent');

var resp = ObjC.use('NSMutableData').data();
var nsResp = null;
var conn = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
if (!conn) { print('ERROR: nil data'); throw 'nil'; }
var s = ObjC.use('NSString').alloc().initWithData_encoding_(conn, 4);
print('len=' + conn.length());
print(s.substringToIndex_(600));
