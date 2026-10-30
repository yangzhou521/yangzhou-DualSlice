var url  = "https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.6.0/com.yangzhou.themecoreplus_0.6.0_iphoneos-arm64e.deb";
var dest = "/var/mobile/Documents/com.yangzhou.themecoreplus_0.6.0.deb";
var NSData = ObjC.use('NSData');
var NSURL   = ObjC.use('NSURL');
var data = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
if (!data) { print("fetch-nil"); }
else {
  var len = data.length();
  var ok  = data.writeToFile_atomically_(dest, true);
  print("size=" + len + " write=" + ok + " dest=" + dest);
}
