// 查 0.9.4 那次云编译（提交 15e62d17）：找对应 run，打印状态与注解。
// 注解匿名可读（公开仓库），日志要登录；所以只看 annotations。
var NSData = ObjC.use('NSData');
var NSURL = ObjC.use('NSURL');
var NSString = ObjC.use('NSString');
var REPO = "yangzhou521/yangzhou-DualSlice";
var SHA = "15e62d17";

function get(url) {
  var data = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
  if (!data) return "NIL";
  return NSString.alloc().initWithData_encoding_(data, 4).toString();
}

var runsText = get("https://api.github.com/repos/" + REPO + "/actions/runs?per_page=10");
if (runsText === "NIL") { print("runs: NIL"); } else {
  var runs = (JSON.parse(runsText).workflow_runs) || [];
  print("runs: " + runs.length);
  var hit = null;
  for (var i = 0; i < runs.length; i++) {
    var r = runs[i];
    var short = String(r.head_sha).substring(0, 8);
    print("[" + i + "] " + r.id + " " + short + " " + r.name + " " + r.status + "/" + r.conclusion);
    if (short === SHA && hit === null) hit = r;
  }
  if (!hit) { print("未找到 " + SHA + " 的 run"); }
  else {
    print("== run " + hit.id + " status=" + hit.status + " conclusion=" + hit.conclusion
          + " created=" + hit.created_at);
    var jobsText = get("https://api.github.com/repos/" + REPO + "/actions/runs/" + hit.id + "/jobs?per_page=20");
    if (jobsText === "NIL") { print("jobs: NIL"); }
    else {
      var jobs = (JSON.parse(jobsText).jobs) || [];
      print("jobs: " + jobs.length);
      for (var m = 0; m < jobs.length; m++) {
        var j = jobs[m];
        print("[" + m + "] " + j.name + "  " + j.status + "/" + j.conclusion);
        var annText = get(j.check_run_url + "/annotations");
        if (annText === "NIL") { print("    annotations: NIL"); continue; }
        var ann = JSON.parse(annText);
        print("    annotations: " + ann.length);
        for (var k = 0; k < ann.length; k++) {
          print("    - [" + ann[k].annotation_level + "] " + ann[k].title + " :: "
                + String(ann[k].message).substring(0, 900));
        }
      }
    }
  }
}
