// 查 SileoFix 的 CI run 状态（本机没 curl，用 NSData 拉 GitHub API）。
var NSData = ObjC.use('NSData');
var NSURL = ObjC.use('NSURL');
var NSString = ObjC.use('NSString');

var repo = "yangzhou521/yangzhou-DualSlice";
var u = "https://api.github.com/repos/" + repo + "/actions/runs?per_page=5";
var d = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(u));
if (!d) { console.log("NO_DATA " + u); }
else {
  var txt = "" + NSString.alloc().initWithData_encoding_(d, 4);
  var out = [];
  // 逐个 workflow_run 对象抓 name / status / conclusion / sha / run_number
  var re = /"id":(\d+),"name":"([^"]*)","node_id":"[^"]*","head_branch":"([^"]*)","head_sha":"([0-9a-f]+)"/g;
  var m;
  while ((m = re.exec(txt)) !== null) {
    var tail = txt.substring(m.index, m.index + 3000);
    var st = /"status":"([^"]*)"/.exec(tail);
    var cc = /"conclusion":(null|"[^"]*")/.exec(tail);
    var rn = /"run_number":(\d+)/.exec(tail);
    out.push("run#" + (rn ? rn[1] : "?") + " | " + m[2] + " | " + m[3] + " | " + m[4].substring(0, 8) +
             " | " + (st ? st[1] : "?") + " | " + (cc ? cc[1] : "?") + " | id=" + m[1]);
  }
  if (!out.length) out.push("raw: " + txt.substring(0, 300));
  console.log(out.join("\n"));
}