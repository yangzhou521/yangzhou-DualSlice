// 复核「生效主题」二级页为什么空：拿真实 picker specifier，再让框架的
// PSListItemsController 按它建一次页，看它读到了什么。
var real = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/ThemeCorePlusPrefs.bundle';
var b = ObjC.use('NSBundle').bundleWithPath_(real);
print('load=' + b.load());

var K = ObjC.classes.TCRootListController;
var c = K.alloc().init();
c.view(); c.viewWillAppear_(true);

var specs = c.specifiers(), picker = null;
for (var i = 0; i < specs.count(); i++) {
  var s = specs.objectAtIndex_(i);
  if (String(s.name()).indexOf('生效主题') === 0) picker = s;
}
if (!picker) { print('picker 未找到'); }
else {
  print('picker cellType=' + picker.cellType());
  print('values=' + picker.valueForKey_('values'));
  print('titles=' + picker.valueForKey_('titles'));
  print('validValues=' + picker.valueForKey_('validValues'));
  print('validTitles=' + picker.valueForKey_('validTitles'));

  var P = ObjC.classes.PSListItemsController;
  print('PSListItemsController=' + (P ? '有' : '无'));
  if (P) {
    var d = P.alloc().init();
    try { d.setSpecifier_(picker); } catch (e) { print('setSpecifier 异常: ' + e); }
    try { d.setRootController_(c); } catch (e) { print('setRootController 异常(可忽略): ' + e); }
    d.view(); d.viewWillAppear_(true);
    var tv = d.table(), s2 = 0, total = 0;
    if (tv) {
      s2 = d.numberOfSectionsInTableView_(tv);
      for (var j = 0; j < s2; j++) { try { total += d.tableView_numberOfRowsInSection_(tv, j); } catch (e) { print('  行数抛异常 sec' + j); } }
    }
    print('详情页 sections=' + s2 + ' rows=' + total + ' table=' + (tv ? '有' : '无'));
    var ds = d.specifiers();
    print('详情页 specifiers=' + (ds ? ds.count() : 'nil'));
    if (ds) for (var k = 0; k < ds.count(); k++) { try { print('  [' + k + '] ' + String(ds.objectAtIndex_(k).name())); } catch (e) {} }
  }
}
