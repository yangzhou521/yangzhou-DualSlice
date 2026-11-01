// 下载 ThemeCorePlus 1.0.30（Release themecoreplus-v1.0.30）
// 用法： icli probe scripts/dl-tcp-1030.js
var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v1.0.30/com.yangzhou.themecoreplus_1.0.30_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/tcp-1.0.30.deb';

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
