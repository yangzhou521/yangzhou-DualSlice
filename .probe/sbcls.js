var out = [];
var libs = [];
var n = ObjC.classes;
for (var k in n) { if (k.indexOf('IconImageView') >= 0) out.push(k); }
'IconImageView 子类: ' + out.join(',');
