// Download ThemeCorePlus 0.9.24 deb (角标双层修复) to /var/mobile/Documents。
// 用途：核对 deb 内的 dylib sha256，与 scripts/version-lock.txt 的 dylib_sha256 对齐。
var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.9.24/com.yangzhou.themecoreplus_0.9.24_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/com.yangzhou.themecoreplus_0.9.24_iphoneos-arm64e.deb';

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
