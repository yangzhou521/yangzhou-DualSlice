// 模拟设置 App 打开面板时的真实调用链：加载视图 → viewWillAppear（会 reloadSpecifiers）→ 读表格行数。
// 只读：不写任何偏好、不动任何文件。
var real = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/ThemeCorePlusPrefs.bundle';

var b = ObjC.use('NSBundle').bundleWithPath_(real);
print('load() = ' + b.load());

var C = ObjC.classes.TCRootListController;
var c = C.alloc().init();

function count(label) {
  var tv = null;
  try { tv = c.table(); } catch (e) { print(label + ' table() threw: ' + e); }
  if (!tv) { print(label + ' no table'); return; }
  var s = tv.numberOfSections(), total = 0;
  for (var i = 0; i < s; i++) total += tv.numberOfRowsInSection_(i);
  print(label + ' sections=' + s + ' rows=' + total);
}

print('specifiers() = ' + c.specifiers().count());
c.view();
print('view loaded = ' + c.isViewLoaded());
count('after view:');

c.viewWillAppear_(false);
count('after viewWillAppear:');
print('specifiers() after = ' + c.specifiers().count());
