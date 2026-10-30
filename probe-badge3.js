// 先弄清 icli 进程里真根怎么拼，再载 SpringBoardHome 反射角标类
var fm = ObjC.use('NSFileManager').defaultManager();
function exists(p) { try { return fm.fileExistsAtPath_(p) ? 'YES' : 'no'; } catch (e) { return 'ERR ' + e; } }
var cands = [
  '/rootfs/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome',
  '/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome',
  '/rootfs/System/Library/PrivateFrameworks/SpringBoardFoundation.framework/SpringBoardFoundation',
  '/rootfs/System/Library/CoreServices/SpringBoard.app/SpringBoard',
  '/rootfs/System/Library/Frameworks/UIKit.framework/UIKit'
];
cands.forEach(function (p) { print(exists(p) + '  ' + p); });

// 列一下 PrivateFrameworks 里带 SpringBoard 的
try {
  var l = fm.contentsOfDirectoryAtPath_error_('/rootfs/System/Library/PrivateFrameworks', null);
  var arr = [];
  for (var i = 0; i < l.count(); i++) {
    var n = l.objectAtIndex_(i).toString();
    if (/SpringBoard|IconServices/.test(n)) arr.push(n);
  }
  print('PF-SBH: ' + arr.join(', '));
} catch (e) { print('list ERR ' + e); }

function load(p) {
  try {
    var b = ObjC.use('NSBundle').bundleWithPath_(p);
    if (!b) return 'no-bundle';
    return 'load=' + b.load();
  } catch (e) { return 'ERR ' + e; }
}
print('SBH: ' + load('/rootfs/System/Library/PrivateFrameworks/SpringBoardHome.framework'));

var names = ['SBIconBadgeView', 'SBIconBadge', 'SBHIconAccessory', 'SBIconAccessoryView',
             'SBIconView', 'SBIconImageView', 'SBIconListView'];
names.forEach(function (n) {
  var C = null; try { C = ObjC.classes[n]; } catch (e) { C = null; }
  if (!C) { print('CLASS ' + n + ' = null'); return; }
  var sup = '?'; try { sup = C.$superClass; } catch (e) { sup = '?'; }
  print('CLASS ' + n + '  super=' + sup);
  try { print('  own: ' + (C.$ownMethods || []).join(' | ')); } catch (e) { print('  own ERR ' + e); }
});
