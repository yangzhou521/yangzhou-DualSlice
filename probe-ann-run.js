// 读指定 run 的 job 注解（公开仓库匿名可读）
var RUN = "41061274672";
var REPO = "yangzhou521/yangzhou-DualSlice";
var NSData = ObjC.use('NSData');
var NSURL = ObjC.use('NSURL');
var NSString = ObjC.use('NSString');
function get(u) {
  var d = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(u));
  if (!d) return "NIL";
  return NSString.alloc().initWithData_encoding_(d, 4).toString();
}
var jt = get("https://api.github.com/repos/" + REPO + "/actions/runs/" + RUN + "/jobs?per_page=20");
if (jt === "NIL") { print("jobs NIL"); }
else {
  var jobs = JSON.parse(jt).jobs || [];
  for (var i = 0; i < jobs.length; i++) {
    var j = jobs[i];
    print("[" + i + "] " + j.name + " " + j.status + "/" + j.conclusion);
    var at = get(j.check_run_url + "/annotations");
    if (at === "NIL") { print("  ann NIL"); continue; }
    var ann = JSON.parse(at);
    for (var k = 0; k < ann.length; k++) {
      if (ann[k].annotation_level === "warning" && ann[k].title === "") continue;
      print("  - [" + ann[k].annotation_level + "] " + ann[k].title + " :: " +
            String(ann[k].message).substring(0, 500));
    }
  }
}