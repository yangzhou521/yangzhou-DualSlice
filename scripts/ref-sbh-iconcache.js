// 反射 SBIcon / SBHIconImageCache 家族自己声明的方法（只读，不改任何东西）。
var names = ['SBHIconImageCache', 'SBHIconImageCacheHelper', 'SBIconImageCache', 'SBIconImageView'];
for (var i = 0; i < names.length; i++) {
    var cls = ObjC.classes[names[i]];
    if (!cls) { print(names[i] + ' = NIL'); continue; }
    var ms = cls.$ownMethods;
    var out = [];
    for (var j = 0; j < ms.length; j++) {
        var m = ms[j];
        var s = String(m);
        if (/icon|Image|Cache|generate|checkout/.test(s)) out.push(s);
    }
    print(names[i] + ' ownMethods(icon相关) = ' + out.join(','));
}
