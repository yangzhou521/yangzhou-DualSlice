// 下载 CountdownHUD 1.6.11 deb（icli probe 语法：ObjC.use）
// 用法：icli probe scripts/download-ch1611.js
// 1.6.10（5ch，已发 Release）作废勿装；本脚本只取 1.6.11。
var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/countdownhud-v1.6.11/com.yangzhou.countdownhud_1.6.11_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/com.yangzhou.countdownhud_1.6.11_iphoneos-arm64e.deb';

var url = ObjC.use('NSURL').URLWithString_(urlStr);
if (!url) { print('ERROR: bad URL'); throw 'bad URL'; }

var data = ObjC.use('NSData').dataWithContentsOfURL_(url);
if (!data) { print('ERROR: NSData returned nil（Release 还没发出来，或网络没通）'); throw 'nil data'; }

var len = data.length();
var ok = data.writeToFile_atomically_(destPath, true);

var fm = ObjC.use('NSFileManager').defaultManager();
var exists = fm.fileExistsAtPath_(destPath);
var attrs = fm.attributesOfItemAtPath_error_(destPath, null);
var diskSize = attrs ? attrs.valueForKey_('NSFileSize') : 0;

print('downloaded=' + ok + ' len=' + len + ' diskExists=' + exists + ' diskSize=' + diskSize + ' path=' + destPath);
