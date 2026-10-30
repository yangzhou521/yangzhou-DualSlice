// 看云编译状态：最新几次 run 的 head_sha / status / conclusion
var url = "https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs?per_page=5";
var NSURL = ObjC.use('NSURL');
var NSData = ObjC.use('NSData');
var NSJSONSerialization = ObjC.use('NSJSONSerialization');
var d = NSData.dataWithContentsOfURL_(NSURL.URLWithString_(url));
if (!d) { print('fetch-nil'); }
else {
  var j = NSJSONSerialization.JSONObjectWithData_options_error_(d, 0, null);
  if (!j) { print('parse-nil'); }
  else {
    var runs = j.objectForKey_('workflow_runs');
    var n = runs.count();
    for (var i = 0; i < n; i++) {
      var r = runs.objectAtIndex_(i);
      print('run ' + r.objectForKey_('id')
        + ' sha=' + r.objectForKey_('head_sha')
        + ' ' + r.objectForKey_('status')
        + '/' + r.objectForKey_('conclusion')
        + ' event=' + r.objectForKey_('event')
        + ' created=' + r.objectForKey_('created_at')
        + ' name=' + r.objectForKey_('name'));
    }
  }
}
