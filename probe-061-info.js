// 查 themecoreplus-v0.6.1 Release 资产：名字/体积/sha256(digest)/更新时间，并下载到 Documents
var NSData = ObjC.use('NSData');
var NSURL = ObjC.use('NSURL');
var NSString = ObjC.use('NSString');

function get(u) {
  var d = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(u));
  if (!d) return null;
  return NSString.alloc().initWithData_encoding_(d, 4).toString();
}

var REPO = "yangzhou521/yangzhou-DualSlice";
var TAG = "themecoreplus-v0.6.1";

var rel = get("https://api.github.com/repos/" + REPO + "/releases/tags/" + TAG);
if (!rel) { print("release-fetch-nil"); }
else {
  var re = /"name":"(com\.yangzhou[^"]*\.deb)","[^}]*?"size":(\d+)[^}]*?"updated_at":"([^"]*)"(?:[^}]*?"digest":"([^"]*)")?/g;
  var m, n = 0;
  while ((m = re.exec(rel)) !== null) {
    print("asset " + m[1] + " size=" + m[2] + " updated=" + m[3] + " digest=" + (m[4] || "-"));
    n++;
  }
  if (!n) print("assets-raw: " + rel.substring(0, 600));
}

// 下载
var url = "https://github.com/" + REPO + "/releases/download/" + TAG + "/com.yangzhou.themecoreplus_0.6.1_iphoneos-arm64e.deb";
var dest = "/var/mobile/Documents/themecoreplus-061.deb";
var data = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
if (!data) { print("download-nil"); }
else {
  print("download size=" + data.length() + " write=" + data.writeToFile_atomically_(dest, true) + " dest=" + dest);
}
