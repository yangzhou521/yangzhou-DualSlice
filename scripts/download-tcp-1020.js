// Download ThemeCorePlus 1.0.20 deb。
var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v1.0.20/com.yangzhou.themecoreplus_1.0.20_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/com.yangzhou.themecoreplus_1.0.20_iphoneos-arm64e.deb';
var url = ObjC.use('NSURL').URLWithString_(urlStr);
var data = ObjC.use('NSData').dataWithContentsOfURL_(url);
if (!data) { print('ERROR: nil data'); throw 'nil'; }
var ok = data.writeToFile_atomically_(destPath, true);
print('downloaded=' + ok + ' len=' + data.length());
