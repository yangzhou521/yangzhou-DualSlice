// 下载 0.8.0 的 deb 到真根 Documents（本机没有 curl/wget，只能走 NSData）。
var url  = "https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.8.0/com.yangzhou.themecoreplus_0.8.0_iphoneos-arm64e.deb";
var dest = "/var/mobile/Documents/themecoreplus-0.8.0.deb";
var NSData = ObjC.use('NSData');
var NSURL   = ObjC.use('NSURL');
var data = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
if (!data) { print("fetch-nil"); }
else {
  var len = data.length();
  var ok  = data.writeToFile_atomically_(dest, true);
  print("size=" + len + " write=" + ok + " dest=" + dest);
}
