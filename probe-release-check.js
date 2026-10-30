// 核对：最新 CI 运行 + Release 里那个 deb 的体积与 sha256
var NSData = ObjC.use('NSData');
var NSURL = ObjC.use('NSURL');
var NSString = ObjC.use('NSString');
function get(u) {
  var d = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(u));
  if (!d) return null;
  return NSString.alloc().initWithData_encoding_(d, 4).toString();
}
var runs = get("https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs?per_page=4");
if (!runs) { print("runs-fetch-nil"); }
else {
  var re = /"id":(\d+),"name":"[^"]*","node_id"[^}]*?"head_sha":"([0-9a-f]{40})"[^}]*?"status":"([a-z_]+)"[^}]*?"conclusion":(null|"[a-z_]+")/g;
  var m, out = [];
  while ((m = re.exec(runs)) !== null) {
    out.push("run " + m[1] + " sha=" + m[2].substring(0, 8) + " " + m[3] + "/" + m[4]);
  }
  print(out.length ? out.join("\n") : ("raw: " + runs.substring(0, 400)));
}
var rel = get("https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/releases/tags/themecoreplus-v0.6.0");
if (!rel) { print("rel-fetch-nil"); }
else {
  var re2 = /"name":"([^"]*\.deb)","[^}]*?"size":(\d+),"download_count":[^,]*,"[^}]*?"digest":"([^"]*)"/g;
  var m2, out2 = [];
  while ((m2 = re2.exec(rel)) !== null) out2.push("asset " + m2[1] + " size=" + m2[2] + " digest=" + m2[3]);
  print(out2.length ? out2.join("\n") : ("raw-rel: " + rel.substring(0, 600)));
}