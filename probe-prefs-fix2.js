// 分辨：表格的段数到底由谁决定？逐组用全新实例做对照，互不污染。
var real = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/ThemeCorePlusPrefs.bundle';
var b = ObjC.use('NSBundle').bundleWithPath_(real);
print('load=' + b.load());

var K = ObjC.classes.TCRootListController;

function mk() {
  var c = K.alloc().init();
  c.view();
  return c;
}
function kvc(c) {
  var v = c.valueForKey_('_specifiers');
  return v ? ('count=' + v.count()) : 'nil';
}
function cnt(c) {
  var tv = null;
  try { tv = c.table(); } catch (e) { return 'table threw'; }
  if (!tv) return 'no table';
  var s = c.numberOfSectionsInTableView_(tv), total = 0;
  for (var i = 0; i < s; i++) {
    try { total += c.tableView_numberOfRowsInSection_(tv, i); } catch (e) { return 'sections=' + s + ' sec' + i + ' THREW'; }
  }
  return 'sections=' + s + ' rows=' + total;
}

// T1 只 view()：看 -specifiers 有没有被父类在加载期调用过
var t1 = mk();
print('T1 view only        : ' + cnt(t1) + '  kvc=' + kvc(t1));

// T2 经 KVC 直接写 ivar（不经 setSpecifiers:）
var t2 = mk();
t2.setValue_forKey_(t2.specifiers(), '_specifiers');
print('T2 kvc ivar write   : ' + cnt(t2) + '  kvc=' + kvc(t2));

// T3 setSpecifiers:（已知能建起缓存）
var t3 = mk();
t3.setSpecifiers_(t3.specifiers());
print('T3 setSpecifiers:   : ' + cnt(t3) + '  kvc=' + kvc(t3));

// T4 先 setSpecifiers: 建好缓存，再走我们自己的 -reloadSpecifiers（它先把 _specifiers 置 nil）
var t4 = mk();
t4.setSpecifiers_(t4.specifiers());
print('T4 before reload    : ' + cnt(t4));
t4.reloadSpecifiers();
print('T4 after reload     : ' + cnt(t4) + '  kvc=' + kvc(t4));

// T5 只调 -reloadSpecifiers（我们的实现：置 nil 再 super）
var t5 = mk();
t5.reloadSpecifiers();
print('T5 reload only      : ' + cnt(t5) + '  kvc=' + kvc(t5));

// T6 先 setSpecifiers: 再 setSpecifiers: 同一个数组第二次（看是否幂等）
var t6 = mk();
t6.setSpecifiers_(t6.specifiers());
var a = t6.specifiers();
t6.setSpecifiers_(a);
print('T6 set twice        : ' + cnt(t6) + '  same array=' + (t6.valueForKey_('_specifiers') === a));
