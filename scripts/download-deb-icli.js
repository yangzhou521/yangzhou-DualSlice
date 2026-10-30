// 用 icli probe 下载 Release 资产（本机没有 curl/wget/python3）
// 用法： icli probe scripts/download-deb-icli.js
// 改 URL 与 destPath 即可下别的包（destPath 写在真根 Documents 下，可被 Files 看见）
var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/countdownhud-v1.3.0/com.yangzhou.countdownhud_1.3.0_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/countdownhud-1.3.0.deb';

var url = ObjC.use('NSURL').URLWithString_(urlStr);
if (!url) { print('ERROR: bad URL'); throw 'bad URL'; }

var data = ObjC.use('NSData').dataWithContentsOfURL_(url);
if (!data) { print('ERROR: NSData returned nil'); throw 'nil data'; }

var len = data.length();
var ok = data.writeToFile_atomically_(destPath, true);

var fm = ObjC.use('NSFileManager').defaultManager();
var attrs = fm.attributesOfItemAtPath_error_(destPath, null);
var diskSize = attrs ? attrs.valueForKey_('NSFileSize') : 0;
print('downloaded=' + ok + ' len=' + len + ' diskSize=' + diskSize + ' path=' + destPath);
