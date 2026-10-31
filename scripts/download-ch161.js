// Download CountdownHUD 1.6.1 deb via NSData (synchronous, follows redirects)
// 用法：icli probe scripts/download-ch161.js
var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/countdownhud-v1.6.1/com.yangzhou.countdownhud_1.6.1_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/com.yangzhou.countdownhud_1.6.1_iphoneos-arm64e.deb';

var url = ObjC.use('NSURL').URLWithString_(urlStr);
if (!url) { print('ERROR: bad URL'); throw 'bad URL'; }

var data = ObjC.use('NSData').dataWithContentsOfURL_(url);
if (!data) { print('ERROR: NSData returned nil'); throw 'nil data'; }

var len = data.length();
var ok = data.writeToFile_atomically_(destPath, true);

var fm = ObjC.use('NSFileManager').defaultManager();
var exists = fm.fileExistsAtPath_(destPath);
var attrs = fm.attributesOfItemAtPath_error_(destPath, null);
var diskSize = attrs ? attrs.valueForKey_('NSFileSize') : 0;

print('downloaded=' + ok + ' len=' + len + ' diskExists=' + exists + ' diskSize=' + diskSize + ' path=' + destPath);
