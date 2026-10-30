// 只查 Release 资产列表：名字 / 体积 / digest / 更新时间
var NSData = ObjC.use('NSData');
var NSURL = ObjC.use('NSURL');
var NSString = ObjC.use('NSString');
var u = "https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/releases/428365135/assets";
var d = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(u));
if (!d) print("fetch-nil");
else {
  var t = NSString.alloc().initWithData_encoding_(d, 4).toString();
  var re = /"name":"([^"]+)","label":[^,]*,"uploader"[^}]*?"size":(\d+)[^}]*?"updated_at":"([^"]+)"/g;
  var m, out = [];
  while ((m = re.exec(t)) !== null) out.push(m[1] + " size=" + m[2] + " updated=" + m[3]);
  if (out.length === 0) {
    var re2 = /"name":"([^"]+)"|"size":(\d+)|"updated_at":"([^"]+)"|"digest":"([^"]+)"/g, m2, o2 = [];
    while ((m2 = re2.exec(t)) !== null) o2.push(m2[0]);
    out = o2;
  }
  print(out.join("\n"));
}