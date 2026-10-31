var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.9.29/com.yangzhou.themecoreplus_0.9.29_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/com.yangzhou.themecoreplus_0.9.29_iphoneos-arm64e.deb';
var nsurl = ObjC.use('NSURL').URLWithString_(urlStr);
var data = ObjC.use('NSData').dataWithContentsOfURL_(nsurl);
if(!data){ console.log('DOWNLOAD_FAIL'); } else {
  data.writeToFile_atomically_(destPath, true);
  console.log('saved', data.length()+'B');
}
