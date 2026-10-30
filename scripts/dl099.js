var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.9.9/com.yangzhou.themecoreplus_0.9.9_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/com.yangzhou.themecoreplus_0.9.9_iphoneos-arm64e.deb';
var url = ObjC.use('NSURL').URLWithString_(urlStr);
var data = ObjC.use('NSData').dataWithContentsOfURL_(url);
if (!data) { print('ERROR nil data'); throw 'nil'; }
var ok = data.writeToFile_atomically_(destPath, true);
var fm = ObjC.use('NSFileManager').defaultManager();
var attrs = fm.attributesOfItemAtPath_error_(destPath, null);
print('ok=' + ok + ' len=' + data.length() + ' size=' + (attrs?attrs.valueForKey_('NSFileSize'):0) + ' path=' + destPath);
