// 下载 SileoWallpaper 0.1.9 合并包的 deb 到真根 Documents（icli 以 mobile 身份跑）
var url  = "https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/sileowallpaper-v0.1.9/com.sileowallpaper.tweak_0.1.9_iphoneos-arm64e.deb";
var dest = "/var/mobile/Documents/sileowallpaper-0.1.9.deb";
var NSData = ObjC.use('NSData');
var NSURL  = ObjC.use('NSURL');
var data = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
if (!data) { print("fetch-nil (Release 可能还没生成)"); }
else {
  print("size=" + data.length() + " write=" + data.writeToFile_atomically_(dest, true) + " dest=" + dest);
}
