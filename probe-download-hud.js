// 拉 CountdownHUD 1.1.0 的 Release 资产到真根 Documents（icli 以 mobile 身份跑）
var url  = "https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/countdownhud-v1.1.0/com.yangzhou.countdownhud_1.1.0_iphoneos-arm64e.deb";
var dest = "/var/mobile/Documents/countdownhud-1.1.0.deb";
var NSData = ObjC.use('NSData');
var NSURL  = ObjC.use('NSURL');
var data = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
if (!data) { print("fetch-nil"); }
else {
  print("size=" + data.length() + " write=" + data.writeToFile_atomically_(dest, true) + " dest=" + dest);
}
