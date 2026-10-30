// 下载 SileoFix 1.0.3 的 deb 到真根 Documents（icli 以 mobile 身份跑，/var/mobile 是真路径）
var url  = "https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/sileofix-v1.0.3/com.yangzhou.sileofix_1.0.3_iphoneos-arm64e.deb";
var dest = "/var/mobile/Documents/sileofix-1.0.3.deb";
var NSData = ObjC.use('NSData');
var NSURL  = ObjC.use('NSURL');
var data = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
if (!data) { print("fetch-nil (Release 可能还没生成)"); }
else {
  print("size=" + data.length() + " write=" + data.writeToFile_atomically_(dest, true) + " dest=" + dest);
}