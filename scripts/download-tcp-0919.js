// 下载 ThemeCorePlus 0.9.19 deb（lay 诊断每拍现写）到 /var/mobile/Documents。
// 用法：icli probe scripts/download-tcp-0919.js
var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.9.19/com.yangzhou.themecoreplus_0.9.19_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/com.yangzhou.themecoreplus_0.9.19_iphoneos-arm64e.deb';

var url = ObjC.use('NSURL').URLWithString_(urlStr);
if (!url) { print('ERROR: bad URL'); throw 'bad URL'; }

var data = ObjC.use('NSData').dataWithContentsOfURL_(url);
if (!data) { print('ERROR: NSData returned nil (资产可能还没生成)'); throw 'nil data'; }

var ok = data.writeToFile_atomically_(destPath, true);
var fm = ObjC.use('NSFileManager').defaultManager();
var attrs = fm.attributesOfItemAtPath_error_(destPath, null);
var diskSize = attrs ? attrs.valueForKey_('NSFileSize') : 0;

print('downloaded=' + ok + ' len=' + data.length() + ' diskSize=' + diskSize + ' path=' + destPath);
