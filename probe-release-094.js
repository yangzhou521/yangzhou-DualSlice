// 读 Release themecoreplus-v0.9.4 的资产信息（名字、大小、digest）——公开仓库匿名可读。
var NSData = ObjC.use('NSData');
var NSURL = ObjC.use('NSURL');
var NSString = ObjC.use('NSString');

function get(url) {
  var data = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
  if (!data) return "NIL";
  return NSString.alloc().initWithData_encoding_(data, 4).toString();
}

var txt = get("https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/releases/tags/themecoreplus-v0.9.4");
if (txt === "NIL") { print("release: NIL"); }
else {
  var rel = JSON.parse(txt);
  print("tag=" + rel.tag_name + " name=" + rel.name + " published=" + rel.published_at);
  var assets = rel.assets || [];
  print("assets: " + assets.length);
  for (var i = 0; i < assets.length; i++) {
    var a = assets[i];
    print("[" + i + "] " + a.name + " size=" + a.size + " digest=" + a.digest
          + " updated=" + a.updated_at);
    print("    url=" + a.browser_download_url);
  }
}
