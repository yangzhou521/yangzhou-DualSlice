// 「生效主题」二级页为什么空：框架的 PSListItemsController 到底读 specifier 的哪个键？
// 跑在 icli 进程里，自己 load 面板 bundle，用真实的 picker specifier 逐组试。
var real = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/ThemeCorePlusPrefs.bundle';
ObjC.use('NSBundle').bundleWithPath_(real).load();

var K = ObjC.classes.TCRootListController;
function newRoot() { var c = K.alloc().init(); c.view(); c.viewWillAppear_(true); return c; }
function findPicker(c) {
  var sp = c.specifiers();
  for (var i = 0; i < sp.count(); i++) {
    var s = sp.objectAtIndex_(i);
    if (String(s.name()).indexOf('生效主题') === 0) return s;
  }
  return null;
}
function rowsOf(picker) {
  var P = ObjC.classes.PSListItemsController;
  if (!P) return 'no PSListItemsController';
  var d = P.alloc().init();
  try { d.setSpecifier_(picker); } catch (e) { return 'setSpecifier 异常: ' + e; }
  try { d.view(); d.viewWillAppear_(true); } catch (e) { return 'view 异常: ' + e; }
  var tv = d.table();
  if (!tv) return 'no table';
  var n = d.numberOfSectionsInTableView_(tv), total = 0;
  for (var i = 0; i < n; i++) {
    try { total += d.tableView_numberOfRowsInSection_(tv, i); } catch (e) { return '第' + i + '段行数抛异常'; }
  }
  var ds = d.specifiers();
  return 'sections=' + n + ' rows=' + total + ' specifiers=' + (ds ? ds.count() : 'nil');
}
function titlesFor(vals) {
  var M = ObjC.classes.NSMutableArray.array();
  for (var i = 0; i < vals.count(); i++) {
    var v = String(vals.objectAtIndex_(i));
    M.addObject_(v.length ? v.split('/').pop() : '系统原生外观');
  }
  return M;
}

var c1 = newRoot(), p1 = findPicker(c1);
print('A 现状            : ' + rowsOf(p1));
print('   propertyForKey(titles)=' + p1.propertyForKey_('titles'));

var c2 = newRoot(), p2 = findPicker(c2);
var vals = p2.valueForKey_('values'), titles = titlesFor(vals);
print('   values 项数=' + vals.count() + ' 拟用标题=' + titles);
p2.setProperty_forKey_(titles, 'titles');
print('B setProperty titles: ' + rowsOf(p2) + ' 读回=' + p2.propertyForKey_('titles'));

var c3 = newRoot(), p3 = findPicker(c3);
p3.setProperty_forKey_(titles, 'validTitles');
p3.setProperty_forKey_(p3.valueForKey_('values'), 'validValues');
print('C validTitles     : ' + rowsOf(p3));
