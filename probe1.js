// probe1.js —— 看 icli probe 的反射面能不能枚举方法，并尝试载入 SpringBoardHome。
var out = {};
out.objcKeys = Object.keys(ObjC);
try {
  out.useSpringBoardHome = String(ObjC.use('SpringBoardHome'));
} catch (e) {
  out.useSpringBoardHome = 'ERR ' + String(e);
}
var c = ObjC.classes.SBFolderIcon;
out.hasSBFolderIcon = !!c;
if (c) {
  try { out.classKeys = Object.keys(c); } catch (e) { out.classKeys = 'ERR ' + String(e); }
  try { out.metas = Object.getOwnPropertyNames(c).slice(0, 40); } catch (e) { out.metas = 'ERR ' + String(e); }
}
var si = ObjC.classes.SBIcon;
out.hasSBIcon = !!si;
if (si) {
  try { out.sbiconKeys = Object.getOwnPropertyNames(si).slice(0, 40); } catch (e) { out.sbiconKeys = 'ERR ' + String(e); }
}
print(JSON.stringify(out));
