// 外网自检：一次回答「这台设备现在能不能访问外网、GitHub API 通不通、是不是被限流」。
// 用法：icli probe scripts/net-check.js
// 判读：
//   net=ok  → 外网通（拿到了 API 的真实应答）
//   net=ratelimit → 通，但被 GitHub 匿名额度限流（换个时间/带 token 的请求即可）
//   net=fail → 不通（没网或被墙）→ 这时 push 也会失败，才需要请用户开 VPN
var api = 'https://api.github.com/rate_limit';

var t0 = Date.now();
var url = ObjC.use('NSURL').URLWithString_(api);
if (!url) { print('net=fail reason=badurl'); throw 'bad url'; }

var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
req.setValue_forHTTPHeaderField_('ApelinNetCheck/1.0', 'User-Agent');
req.setTimeoutInterval_(12.0);

var data = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
var ms = Date.now() - t0;
if (!data) { print('net=fail ms=' + ms + ' reason=nodata'); throw 'no data'; }

var json = ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(data, 0, null);

if (json != null && json.valueForKey_('resources') != null) {
    var core = json.valueForKey_('resources').valueForKey_('core');
    print('net=ok ms=' + ms +
          ' limit=' + core.valueForKey_('limit') +
          ' left=' + core.valueForKey_('remaining') +
          ' reset=' + core.valueForKey_('reset'));
} else {
    print('net=other ms=' + ms + ' len=' + data.length());
}
