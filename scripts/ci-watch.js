// ci-watch.js —— 云编译独立守护查询脚本（agent 睡死时也能跑）
// 用法：icli probe scripts/ci-watch.js
// 依赖：icli probe（JavaScriptCore + ObjC 反射），本机无 curl/wget/python3 也能跑。
// 功能：查 yangzhou-DualSlice main 上最近一次 ThemeCorePlus CI 状态，
//       把状态写真根文件供 agent 下轮读取；
//       检测到首次 concl=success 时写 .ci-watch-success 标记，并向 CountdownHUD
//       写 .countdownhud-request 纯文案胶囊（不注销、不装包）。
// 路径全部用真根（/rootfs/…），不依赖 jbroot 哈希，不会随重越狱失效。
var api = 'https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs?branch=main&per_page=5';
var url = ObjC.use('NSURL').URLWithString_(api);
var req = ObjC.use('NSMutableURLRequest').requestWithURL_(url);
req.setValue_forHTTPHeaderField_('application/vnd.github+json', 'Accept');
req.setValue_forHTTPHeaderField_('ApelinCIWatch/1.0', 'User-Agent');
var data = ObjC.use('NSURLConnection').sendSynchronousRequest_returningResponse_error_(req, null, null);
if (!data) { print('ciwatch{state=netfail}'); throw 'no data'; }
var j = ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(data, 0, null);
if (!j) { print('ciwatch{state=badjson}'); throw 'bad json'; }
var runs = j.valueForKey_('workflow_runs');
if (!runs || runs.count() === 0) { print('ciwatch{state=noruns}'); throw 'no runs'; }
var r = runs.objectAtIndex_(0);
var id = String(r.valueForKey_('id'));
var sha = String(r.valueForKey_('head_sha'));
var status = String(r.valueForKey_('status') || '');
var concl = String(r.valueForKey_('conclusion') || 'null');
var created = String(r.valueForKey_('created_at') || '');
var statePath = '/rootfs/var/mobile/Documents/.ci-watch-state';
var fm = ObjC.use('NSFileManager').defaultManager();
var old = '';
var oldData = fm.contentsAtPath_(statePath);
if (oldData) { old = String(oldData) || ''; }
var newState = 'id=' + id + ' sha=' + sha + ' status=' + status + ' concl=' + concl + ' created=' + created + '\n';
var nsStr = ObjC.use('NSString').stringWithString_(newState);
var ok = nsStr.writeToFile_atomically_encoding_error_(statePath, true, 4, null);
print('ciwatch{id=' + id + ' sha=' + sha + ' status=' + status + ' concl=' + concl + ' written=' + ok + '}');
// 状态首次变为 success：写成功标记，并触发 CountdownHUD 纯文案胶囊提醒
if (concl === 'success' && old.indexOf('concl=success') < 0) {
    var okPath = '/rootfs/var/mobile/Documents/.ci-watch-success';
    ObjC.use('NSString').stringWithString_('1').writeToFile_atomically_encoding_error_(okPath, true, 4, null);
    var epoch = Math.floor(Date.now() / 1000);
    var content = epoch + '|8|!ThemeCorePlus 编译完成';
    var reqPath = '/rootfs/var/mobile/Library/Preferences/.countdownhud-request';
    ObjC.use('NSString').stringWithString_(content).writeToFile_atomically_encoding_error_(reqPath, true, 4, null);
    print('ciwatch{success-triggered=1}');
}
