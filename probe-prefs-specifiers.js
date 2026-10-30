// 在 icli 进程里实例化 TCRootListController 并跑一次建表，看返回多少个单元、名字是什么。
// 只读：建表本身只扫主题目录、读偏好，不写任何东西。
var real = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/ThemeCorePlusPrefs.bundle';

var b = ObjC.use('NSBundle').bundleWithPath_(real);
print('load() = ' + b.load());

var C = ObjC.classes.TCRootListController;
var c = C.alloc().init();
print('instance class = ' + (c.$class || '?'));

var specs = null;
try {
  specs = c.specifiers();
} catch (e) {
  print('specifiers() threw: ' + e);
}
if (specs) {
  var n = specs.count();
  print('specifier count = ' + n);
  for (var i = 0; i < n; i++) {
    var s = specs.objectAtIndex_(i);
    print('  [' + i + '] ' + (s.name() || '(no name)'));
  }
}
