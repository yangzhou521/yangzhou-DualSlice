// 拉最新 CI 产物（静态 tag themecoreplus-v0.6.0，资产每次运行重建）
var url  = "https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.6.0/com.yangzhou.themecoreplus_0.6.0_iphoneos-arm64e.deb";
var dest = "/var/mobile/Documents/themecoreplus-list2.deb";
var NSData = ObjC.use('NSData');
var NSURL  = ObjC.use('NSURL');
var data = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
if (!data) { print("fetch-nil"); }
else {
  print("size=" + data.length() + " write=" + data.writeToFile_atomically_(dest, true) + " dest=" + dest);
}