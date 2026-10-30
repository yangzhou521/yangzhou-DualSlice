// 临时探针：查 yangzhou-DualSlice 最近的 workflow run（本机没 curl，用 NSData 拉 API）。
var out = [];
function line(s) { out.push(s); }

var repo = "yangzhou521/yangzhou-DualSlice";
var u = "https://api.github.com/repos/" + repo + "/actions/runs?per_page=6";
var d = NSData.dataWithContentsOfURL(NSURL.URLWithString(u));
if (!d) { console.log("NO_DATA: 拉不到 " + u); }
else {
  var s = NSString.alloc().initWithDataEncoding(d, 4);
  var txt = "" + s;
  var j = null;
  try { j = NSJSONSerialization.JSONObjectWithDataOptionsError(d, 0, null); } catch (e) { j = null; }
  if (!j) {
    line("JSON 解析失败，原始前 400 字：" + txt.substring(0, 400));
  } else {
    var runs = j["workflow_runs"];
    line("runs=" + runs.length);
    for (var i = 0; i < runs.length; i++) {
      var r = runs[i];
      line([r["run_number"], ("" + r["head_sha"]).substring(0, 8), r["name"], r["status"],
            r["conclusion"], r["created_at"], r["id"]].join(" | "));
    }
  }
}
console.log(out.join("\n"));
