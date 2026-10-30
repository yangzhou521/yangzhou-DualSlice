// 查 sileowallpaper.yml 最近一次 run 的状态与注解（本机没 curl，用 NSData 拉 GitHub API）。
var NSData = ObjC.use('NSData');
var NSURL = ObjC.use('NSURL');
var NSString = ObjC.use('NSString');

var repo = "yangzhou521/yangzhou-DualSlice";
function get(u) {
  var d = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(u));
  if (!d) return null;
  return "" + NSString.alloc().initWithData_encoding_(d, 4);
}

var txt = get("https://api.github.com/repos/" + repo + "/actions/workflows/sileowallpaper.yml/runs?per_page=3");
if (!txt) { console.log("NO_DATA runs"); }
else {
  var re = /"id":(\d+),"name":"[^"]*","node_id":"[^"]*","head_branch":"([^"]*)","head_sha":"([0-9a-f]+)"/g;
  var m, runs = [];
  while ((m = re.exec(txt)) !== null) {
    var tail = txt.substring(m.index, m.index + 3000);
    var st = /"status":"([^"]*)"/.exec(tail);
    var cc = /"conclusion":(null|"[^"]*")/.exec(tail);
    runs.push({ id: m[1], sha: m[3].substring(0, 8), status: st ? st[1] : "?", concl: cc ? cc[1] : "?" });
  }
  if (!runs.length) { console.log("raw: " + txt.substring(0, 400)); }
  runs.forEach(function (r) {
    console.log("run id=" + r.id + " sha=" + r.sha + " status=" + r.status + " conclusion=" + r.concl);
  });
  if (runs.length) {
    var a = get("https://api.github.com/repos/" + repo + "/actions/runs/" + runs[0].id + "/annotations");
    if (!a) console.log("NO_DATA annotations");
    else {
      var are = /"path":"([^"]*)","start_line":(\d+)[\s\S]*?"message":"([\s\S]*?)","title":"([^"]*)"/g;
      var am, n = 0;
      while ((am = are.exec(a)) !== null) {
        n++;
        console.log("[" + am[4] + "] " + am[3].replace(/\\n/g, " | "));
      }
      if (!n) console.log("annotations raw: " + a.substring(0, 300));
    }
  }
}
