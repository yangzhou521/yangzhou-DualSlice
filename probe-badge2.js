// 角标双层根因侦察：把 SpringBoardHome/SpringBoard 载进 icli 进程，看 SBIconBadgeView 家族
// 到底声明了哪些方法（找底板从哪来）、父类、ivar。
var paths = [
  '/System/Library/PrivateFrameworks/SpringBoardHome.framework/SpringBoardHome',
  '/System/Library/PrivateFrameworks/SpringBoardUIServices.framework/SpringBoardUIServices',
  '/System/Library/PrivateFrameworks/SpringBoardFoundation.framework/SpringBoardFoundation',
  '/System/Library/CoreServices/SpringBoard.app/SpringBoard'
];
paths.forEach(function (p) {
  try {
    var b = ObjC.use('NSBundle').bundleWithPath_(p);
    if (!b) { print('PATH miss ' + p); return; }
    print('load ' + b.load() + '  ' + p);
  } catch (e) { print('ERR ' + p + ' :: ' + e); }
});

print('--- ObjC 顶层键 ---');
try { print(Object.getOwnPropertyNames(ObjC).join(',')); } catch (e) {}

var names = ['SBIconBadgeView', 'SBIconBadge', 'SBHIconAccessory', 'SBIconBadgeViewContainer',
             'SBIconAccessoryView', 'SBIconAccessoryImageView', 'SBHIconBadgeView'];
names.forEach(function (n) {
  var C = ObjC.classes[n];
  if (!C) { print('CLASS ' + n + ' = null'); return; }
  var sup = '?'; try { sup = C.$superClass; } catch (e) { sup = '?' + e; }
  print('CLASS ' + n + '  super=' + sup);
  try { print('  own: ' + (C.$ownMethods || []).join(' | ')); } catch (e) { print('  own ERR ' + e); }
  try { if (C.$ivars) print('  ivars: ' + JSON.stringify(C.$ivars)); } catch (e) {}
});
