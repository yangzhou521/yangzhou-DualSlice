// 查最近几次 CI 运行的状态（公开仓库，匿名可读）
var url = "https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs?per_page=3";
var NSData = ObjC.use('NSData');
var NSURL = ObjC.use('NSURL');
var data = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
if (!data) { print("fetch-nil"); }
else {
  var s = ObjC.use('NSString').alloc().initWithData_encoding_(data, 4);
  var text = s.toString();
  // 只挑要看的三样：状态、结论、提交号
  var re = /"head_sha":"([0-9a-f]{8})[0-9a-f]*"|"status":"([a-z_]+)"|"conclusion":"([a-z_]+)"/g;
  var m, out = [], run = 0;
  while ((m = re.exec(text)) !== null) {
    if (m[1]) { run++; out.push("run" + run + " sha=" + m[1]); }
    else if (m[2]) out.push("  status=" + m[2]);
    else if (m[3]) out.push("  conclusion=" + m[3]);
  }
  print(out.join("\n"));
  if (out.length === 0) print("raw-head: " + text.substring(0, 300));
}
