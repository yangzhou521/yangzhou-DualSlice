// 下载 ThemeCorePlus 1.0.44 deb 到 /var/mobile/Documents
// 1.0.44 = 云端最新（Release tag themecoreplus-v1.0.44，run 41627275001 @ 0a34c657 success）
var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v1.0.44/com.yangzhou.themecoreplus_1.0.44_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/com.yangzhou.themecoreplus_1.0.44_iphoneos-arm64e.deb';

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