// 下载 ThemeCorePlus 0.9.22 deb（安全模式修复：构造函数里不再枚举全进程类 + 启动护栏）到 /var/mobile/Documents。
// 用法：icli probe scripts/download-tcp-0922.js
var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.9.22/com.yangzhou.themecoreplus_0.9.22_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/com.yangzhou.themecoreplus_0.9.22_iphoneos-arm64e.deb';

var url = ObjC.use('NSURL').URLWithString_(urlStr);
if (!url) { print('ERROR: bad URL'); throw 'bad URL'; }

var data = ObjC.use('NSData').dataWithContentsOfURL_(url);
if (!data) { print('ERROR: NSData returned nil (资产可能还没生成)'); throw 'nil data'; }

var ok = data.writeToFile_atomically_(destPath, true);
var fm = ObjC.use('NSFileManager').defaultManager();
var attrs = fm.attributesOfItemAtPath_error_(destPath, null);
var diskSize = attrs ? attrs.valueForKey_('NSFileSize') : 0;

print('downloaded=' + ok + ' len=' + data.length() + ' diskSize=' + diskSize + ' path=' + destPath);
