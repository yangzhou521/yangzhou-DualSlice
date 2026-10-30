// 装完新包后的复核：模拟设置 App 的真实生命周期，看表格有没有段行。
// 探针跑在 icli 自己进程里（不是设置进程），bundle 由脚本自己 load。
var real = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/ThemeCorePlusPrefs.bundle';
var b = ObjC.use('NSBundle').bundleWithPath_(real);
print('load=' + b.load());

var K = ObjC.classes.TCRootListController;

function mk() { return K.alloc().init(); }
function kvcCount(c) {
  var v = c.valueForKey_('_specifiers');
  return v ? String(v.count()) : 'nil';
}
function cnt(c) {
  var tv = c.table();
  if (!tv) return 'no table';
  var s = c.numberOfSectionsInTableView_(tv), total = 0;
  for (var i = 0; i < s; i++) {
    try { total += c.tableView_numberOfRowsInSection_(tv, i); }
    catch (e) { return 'sections=' + s + ' sec' + i + ' 抛异常'; }
  }
  return 'sections=' + s + ' rows=' + total;
}

// A: 只 view()（旧版这里是 0 段）
var a = mk(); a.view();
print('A view()                : ' + cnt(a) + '  kvc=' + kvcCount(a));

// B: view() + viewWillAppear:(YES) —— 设置 App 的真实路径（我们的 -viewWillAppear: 会调 reloadSpecifiers）
var c = mk(); c.view(); c.viewWillAppear_(true);
print('B view+viewWillAppear   : ' + cnt(c) + '  kvc=' + kvcCount(c));

// C: 再 viewWillAppear 一次（返回面板的路径，重入防护要挡住了才不炸）
c.viewWillAppear_(true);
print('C 再 viewWillAppear     : ' + cnt(c) + '  kvc=' + kvcCount(c));

// D: 手动 reloadSpecifiers 两次（开关回调就是这条路）
c.reloadSpecifiers(); c.reloadSpecifiers();
print('D reload x2             : ' + cnt(c) + '  kvc=' + kvcCount(c));

// E: 面板里的开关/按钮单元是否都在（读第一段的行文本）
var specs = c.specifiers();
var names = [];
for (var j = 0; j < specs.count(); j++) {
  try { names.push(String(specs.objectAtIndex_(j).name())); } catch (e) { names.push('?'); }
}
print('E 单元数=' + specs.count() + ' 名称=' + names.join(' | '));
