// 查最近一次 CI 运行的注解（公开仓库匿名可读；日志要登录，注解不用）
// 走 /actions/runs/{id}/jobs 拿每个 job 的 check_run_url，再取它的 annotations。
var NSData = ObjC.use('NSData');
var NSURL = ObjC.use('NSURL');
var NSString = ObjC.use('NSString');
var REPO = "yangzhou521/yangzhou-DualSlice";

function get(url) {
  var data = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
  if (!data) return "NIL";
  return NSString.alloc().initWithData_encoding_(data, 4).toString();
}

var runsText = get("https://api.github.com/repos/" + REPO + "/actions/runs?per_page=3");
var runs = JSON.parse(runsText);
var run = runs.workflow_runs[0];
print("run=" + run.id + " sha=" + run.head_sha.substring(0, 8)
      + " status=" + run.status + " conclusion=" + run.conclusion);

var jobsText = get("https://api.github.com/repos/" + REPO + "/actions/runs/" + run.id + "/jobs?per_page=20");
if (jobsText === "NIL") { print("jobs: NIL"); } else {
  var jobs = JSON.parse(jobsText).jobs || [];
  print("jobs: " + jobs.length);
  for (var i = 0; i < jobs.length; i++) {
    var j = jobs[i];
    print("[" + i + "] " + j.name + "  " + j.status + "/" + j.conclusion + "  checkRun=" + j.check_run_url);
    var annText = get(j.check_run_url + "/annotations");
    if (annText === "NIL") { print("    annotations: NIL"); continue; }
    var ann = JSON.parse(annText);
    print("    annotations: " + ann.length);
    for (var k = 0; k < ann.length; k++) {
      print("    - [" + ann[k].annotation_level + "] " + ann[k].title + " :: "
            + String(ann[k].message).substring(0, 700));
    }
  }
}
