var names = ['SBHClockApplicationIconImageView','SBHClockApplicationIcon','SBHCalendarApplicationIcon'];
var lines = [];
for (var i = 0; i < names.length; i++) {
  var K = null;
  try { K = ObjC.classes[names[i]]; } catch (e) { K = null; }
  if (!K) { lines.push(names[i] + '=absent'); continue; }
  var ms = K.$ownMethods, arr = [];
  for (var j = 0; j < ms.length && j < 80; j++) arr.push(String(ms[j]));
  lines.push(names[i] + ' super=' + K.$superClass.$className + ' methods[' + ms.length + ']=' + arr.join(','));
}
lines.join('\n');
