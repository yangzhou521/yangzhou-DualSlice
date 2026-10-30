// 面板类名冲突取证 A：先加载 ThemeCore（com.susudear.themecoreprefs）的面板，再加载我们的。
// 只读设备状态；类注册发生在 icli 自己的进程里，退出即消失。
var NSBundle = ObjC.use('NSBundle');
var NSFileManager = ObjC.use('NSFileManager');

// 候选路径：引导根命名空间 / 真根 jbroot 前缀，谁先命中用谁。
var roots = ['/Library/PreferenceBundles/', '/rootfs/Library/PreferenceBundles/'];
var jb = null;
try {
  var apps = NSFileManager.defaultManager().contentsOfDirectoryAtPath_error_('/rootfs/private/var/containers/Bundle/Application/', null);
  if (apps) {
    for (var i = 0; i < apps.count(); i++) {
      var n = String(apps.objectAtIndex_(i));
      if (n.indexOf('.jbroot-') === 0) { jb = '/rootfs/private/var/containers/Bundle/Application/' + n; }
    }
  }
} catch (e) { print('scan jbroot: ' + e); }
if (jb) roots.push(jb + '/Library/PreferenceBundles/');
print('jbroot 候选 = ' + jb);

function loadBundle(root, name) {
  var b = NSBundle.bundleWithPath_(root + name + '.bundle');
  if (!b) return null;
  var ok = false;
  try { ok = b.load(); } catch (e) { print('load ' + name + ' threw: ' + e); }
  print('load ' + name + ' -> ' + ok + ' path=' + root);
  return b;
}

// 用「谁会响应哪个方法」判断当前 TCRootListController 这个符号落在哪个镜像上。
var MINE = ['tcpBuildSpecifiers', 'tcpThemePicker', 'tcpRescanThemes', 'tcpRestoreNativeAppearance'];
var THEIRS = ['refreshIcons', 'tc_openRepository:', 'tcThemeList'];

function who() {
  var K = ObjC.classes.TCRootListController;
  if (!K) return 'missing';
  var inst = null;
  try { inst = K.alloc().init(); } catch (e) { return 'alloc 失败: ' + e; }
  var mine = [], theirs = [];
  for (var i = 0; i < MINE.length; i++) {
    try { if (inst.respondsToSelector_(MINE[i])) mine.push(MINE[i]); } catch (e) {}
  }
  for (var j = 0; j < THEIRS.length; j++) {
    try { if (inst.respondsToSelector_(THEIRS[j])) theirs.push(THEIRS[j]); } catch (e) {}
  }
  return '我们的方法[' + mine.join(',') + '] 他们的方法[' + theirs.join(',') + ']';
}

print('before : ' + who());
loadBundle(roots[0], 'ThemeCorePrefs') || loadBundle(roots[1], 'ThemeCorePrefs') || loadBundle(roots[2], 'ThemeCorePrefs');
print('加载 ThemeCore 后 : ' + who());
var b2 = loadBundle(roots[0], 'ThemeCorePlusPrefs');
if (!b2) b2 = loadBundle(roots[1], 'ThemeCorePlusPrefs');
if (!b2 && jb) b2 = loadBundle(jb + '/Library/PreferenceBundles/', 'ThemeCorePlusPrefs');
print('再加载我们的后   : ' + who());
