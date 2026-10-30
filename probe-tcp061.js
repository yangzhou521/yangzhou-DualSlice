// 查 ThemeCorePlus 0.6.1 这轮 CI：run 状态 + check-run 注解（sha256 / deb-url）
// 用法：icli probe "$APELIN_PROJECT_ROOT/probe-tcp061.js"
var NSData = ObjC.use('NSData');
var NSURL = ObjC.use('NSURL');
var NSString = ObjC.use('NSString');

function get(u) {
  var d = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(u));
  if (!d) return null;
  return NSString.alloc().initWithData_encoding_(d, 4).toString();
}

var REPO = "yangzhou521/yangzhou-DualSlice";
var SHA = "ef781ae168ac19c88c62182eb196ad72e43ffde0";

// 1) 这一提交的 run 与 check-runs
var runs = get("https://api.github.com/repos/" + REPO + "/actions/runs?per_page=6");
var runLine = "run: 未找到该提交的运行";
if (runs) {
  var idx = runs.indexOf('"' + SHA + '"');
  if (idx >= 0) {
    var head = runs.substring(Math.max(0, idx - 3000), idx);
    var ids = head.match(/"id":(\d+)/g);
    var st = runs.substring(idx, idx + 3000).match(/"status":"([a-z_]+)"/);
    var cc = runs.substring(idx, idx + 3000).match(/"conclusion":(null|"[a-z_]+")/);
    runLine = "run id=" + (ids ? ids[ids.length - 1] : "?") +
              " status=" + (st ? st[1] : "?") +
              " conclusion=" + (cc ? cc[1] : "?");
  }
}
print(runLine);

// 2) check-runs：名字 / 状态 / 结论 / id
var checks = get("https://api.github.com/repos/" + REPO + "/commits/" + SHA + "/check-runs");
var checkIds = [];
if (!checks) { print("checks-fetch-nil"); }
else {
  var re = /"id":(\d+),"name":"([^"]*)"[^}]*?"status":"([a-z_]+)","conclusion":(null|"[a-z_]+")/g;
  var m, lines = [];
  while ((m = re.exec(checks)) !== null) {
    lines.push("check " + m[1] + " " + m[2] + " " + m[3] + "/" + m[4]);
    checkIds.push(m[1]);
  }
  print(lines.length ? lines.join("\n") : ("checks-raw: " + checks.substring(0, 300)));
}

// 3) 每个 check-run 的注解正文（notice title=deb::… sha256=…、title=deb-url::…）
for (var i = 0; i < checkIds.length; i++) {
  var ann = get("https://api.github.com/repos/" + REPO + "/check-runs/" + checkIds[i] + "/annotations");
  if (!ann) { print("ann" + checkIds[i] + "-nil"); continue; }
  var re2 = /"annotation_level":"([a-z]+)","title":"([^"]*)","message":"([^"]*)"/g;
  var m2, out = [];
  while ((m2 = re2.exec(ann)) !== null) out.push("  [" + m2[1] + "] " + m2[2] + " :: " + m2[3]);
  print("annotations " + checkIds[i] + " n=" + out.length);
  if (out.length) print(out.join("\n"));
}
