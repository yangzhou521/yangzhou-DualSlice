// 在设置进程（新装的包已就位）里量：新建一个面板控制器，表格到底有几段几行
var real = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/ThemeCorePlusPrefs.bundle';
var b = ObjC.use('NSBundle').bundleWithPath_(real);
print('load=' + b.load() + ' isLoaded=' + b.isLoaded());

var c = ObjC.classes.TCRootListController.alloc().init();
c.view();
var tv = c.table();
print('kvc _specifiers = ' + c.valueForKey_('_specifiers'));
print('specifiers() = ' + c.specifiers().count());
var s = c.numberOfSectionsInTableView_(tv), total = 0;
for (var i = 0; i < s; i++) {
  try { total += c.tableView_numberOfRowsInSection_(tv, i); } catch (e) { print('sec' + i + ' threw: ' + e); }
}
print('table: sections=' + s + ' rows=' + total);
