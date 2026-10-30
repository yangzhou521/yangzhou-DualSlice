// 下载 0.9.4 的 deb 到真根 Documents（本机没有 curl/wget，只能走 NSData），并打印 sha256。
var url  = "https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.9.4/com.yangzhou.themecoreplus_0.9.4_iphoneos-arm64e.deb";
var dest = "/var/mobile/Documents/themecoreplus-0.9.4.deb";
var NSData = ObjC.use('NSData');
var NSURL   = ObjC.use('NSURL');
var data = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
if (!data) { print("fetch-nil"); }
else {
  var len = data.length();
  var ok  = data.writeToFile_atomically_(dest, true);
  print("size=" + len + " write=" + ok + " dest=" + dest);
  // CC_SHA256 走 ObjC 反射（C 函数要 ObjC.declare）
  var CC = ObjC.declare('CC_SHA256', 'void', ['id', 'unsigned long', 'id']);
  var hash = NSData.dataWithLength_(32);
  CC(data.bytes(), len, hash.mutableBytes());
  var hexBytes = hash.bytes();
  var hex = "";
  var NSMutableString = ObjC.use('NSMutableString');
  var s = NSMutableString.string();
  for (var i = 0; i < 32; i++) {
    var b = hexBytes[i] & 0xff;
    s.appendString_((b < 16 ? "0" : "") + b.toString(16));
  }
  print("sha256=" + s.toString());
}
