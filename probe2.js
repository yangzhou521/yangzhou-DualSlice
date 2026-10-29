// probe2.js —— 逐类尝试取类对象，并打印 ObjC 反射面的键。
function getc(name) {
  try { return ObjC.classes[name]; } catch (e) { return null; }
}
var out = {};
out.objcKeys = Object.keys(ObjC).join(',');
try { out.use1 = String(ObjC.use('SpringBoardHome')); } catch (e) { out.use1 = 'ERR ' + String(e); }
try { out.use2 = String(ObjC.use('SpringBoard')); } catch (e) { out.use2 = 'ERR ' + String(e); }
var names = ['SBIcon', 'SBLeafIcon', 'SBApplicationIcon', 'SBFolderIcon', 'SBIconView', 'SBIconBadgeView',
              'SBHIconAccessoryCountedMapImageTuple', 'SBFolderIconImageCache', 'UIImage'];
var found = {};
for (var i = 0; i < names.length; i++) { found[names[i]] = !!getc(names[i]); }
out.found = found;
var c = getc('SBFolderIcon');
if (c) {
  try { out.folderIconKeys = Object.keys(c).slice(0, 60).join(','); } catch (e) { out.folderIconKeys = 'ERR ' + String(e); }
}
var icon = getc('SBIcon');
if (icon) {
  try { out.sbiconKeys = Object.keys(icon).slice(0, 60).join(','); } catch (e) { out.sbiconKeys = 'ERR ' + String(e); }
}
print(JSON.stringify(out));
