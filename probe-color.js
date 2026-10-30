// 量系统三色：先把动态色解析成具体色，再读分量
var UIColor = ObjC.use('UIColor');
var UITraitCollection = ObjC.use('UITraitCollection');
var tc = UITraitCollection.currentTraitCollection();

function dump(name, uiColor) {
  var line = name;
  var resolved = uiColor;
  try { resolved = uiColor.resolvedColorWithTraitCollection_(tc) || uiColor; } catch (e) {}
  line += " resolved=" + resolved.description();
  try {
    var ci = resolved.CIColor();
    if (ci) line += " r=" + ci.red() + " g=" + ci.green() + " b=" + ci.blue();
  } catch (e) { line += " [CIColor 仍失败]"; }
  print(line);
}

dump("systemGreen", UIColor.systemGreenColor());
dump("systemOrange", UIColor.systemOrangeColor());
dump("systemRed", UIColor.systemRedColor());
