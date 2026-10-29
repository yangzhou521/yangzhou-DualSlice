// probe3.js —— 在 icli 进程里加载 SpringBoardHome / SpringBoard，反射出真实类与方法名。
// 目的：把角标、文件夹、图标三类钩子点的选择器名坐实，避免盲猜。
const out = [];

function note(s) { out.push(String(s)); }

function tryLoad(path) {
  try {
    const b = ObjC.use('NSBundle').bundleWithPath_(path);
    if (!b) { note('nobundle ' + path); return; }
    note('load ' + path + ' => ' + b.load());
  } catch (e) { note('err ' + path + ' :: ' + e); }
}

tryLoad('/System/Library/PrivateFrameworks/SpringBoardHome.framework');
tryLoad('/System/Library/PrivateFrameworks/SpringBoard.framework');
tryLoad('/System/Library/PrivateFrameworks/IconServices.framework');

note('ObjC keys: ' + Object.getOwnPropertyNames(ObjC).join(','));
try { note('classes keys: ' + Object.getOwnPropertyNames(ObjC.classes).slice(0, 20).join(',')); } catch (e) { note('classes err ' + e); }

const names = ['SBIcon', 'SBIconView', 'SBIconImageView', 'SBIconBadgeView', 'SBLeafIcon',
               'SBApplicationIcon', 'SBFolderIcon', 'SBFolderIconImageView', 'SBFolderIconImageCache',
               'SBHIconAccessoryCountedMapImageTuple', 'SBHIconAccessoryCountedMap'];
for (const n of names) {
  try {
    const c = ObjC.use(n);
    if (!c) { note(n + ': null'); continue; }
    note(n + ': ok, keys=' + Object.getOwnPropertyNames(c).join(','));
  } catch (e) { note(n + ': err ' + e); }
}

JSON.stringify(out);
out.join('\n');
