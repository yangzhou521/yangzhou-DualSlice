// 在 icli 进程里试着加载设置面板 bundle：验证它能不能 dlopen、类能不能注册。
// 只读设备状态，不改任何东西（类注册在 icli 自己的进程里，进程退出即消失）。
var real = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/ThemeCorePlusPrefs.bundle';

function cls(name) {
  try { var c = ObjC.classes[name]; return c ? (c.$class || 'present') : 'missing'; }
  catch (e) { return 'err:' + e; }
}

print('before TCRootListController = ' + cls('TCRootListController'));

var NSBundle = ObjC.use('NSBundle');
var b = NSBundle.bundleWithPath_(real);
print('bundle handle = ' + (b ? 'yes' : 'nil'));
if (b) {
  print('bundle id = ' + b.bundleIdentifier());
  print('executablePath = ' + b.executablePath());
  print('isLoaded before = ' + b.isLoaded());
  var ok = false;
  try { ok = b.load(); } catch (e) { print('load threw: ' + e); }
  print('load() = ' + ok);
}

print('after TCRootListController = ' + cls('TCRootListController'));
print('after TCPThemeStore = ' + cls('TCPThemeStore'));
print('after PSListController = ' + cls('PSListController'));
