// 取证（3）：看 icli probe 的 ObjC 桥到底给了什么反射接口（上一版 $ownMethods 拿到的是空）。
// 跑法: icli probe probe-sbh3.js
print('typeof ObjC = ' + typeof ObjC);
try { print('ObjC 键: ' + Object.keys(ObjC).join(',')); } catch (e) { print('keys(ObjC) 抛 ' + e); }
if (ObjC && ObjC.api) {
    try { print('ObjC.api 键: ' + Object.keys(ObjC.api).join(',')); } catch (e) {}
}
try {
    var b = ObjC.use('NSBundle').bundleWithPath_('/System/Library/PrivateFrameworks/SpringBoardHome.framework');
    b.load();
} catch (e) { print('load 抛 ' + e); }
var C = ObjC.classes.SBIconImageView;
if (!C) { print('类不可得'); } else {
    try { print('C 键: ' + Object.keys(C).join(',')); } catch (e) { print('keys(C) 抛 ' + e); }
    try { print('$ownMethods 类型=' + typeof C.$ownMethods + ' 长度=' + (C.$ownMethods && C.$ownMethods.length)); } catch (e) { print('$ownMethods 抛 ' + e); }
    try { print('methods 类型=' + typeof C.methods); } catch (e) {}
    try { print('$ownMethodNames=' + (C.$ownMethodNames && C.$ownMethodNames.length)); } catch (e) {}
    try { print('super=' + C.$super); } catch (e) {}
    try { print('respondsTo setImage: ' + C.respondsToSelector_(ObjC.selector('setImage:'))); } catch (e) { print('responds 抛 ' + e); }
    ['setImage:', 'displayedImage', 'contentsImage', 'squareContentsImage', 'icon',
     '_configureIconImageView:', 'updateImageAnimated:', 'setIconImageInfo:'].forEach(function (s) {
        try {
            var sel = ObjC.selector(s);
            print(s + ' -> ' + (C.instanceMethod ? 'x' : '') + (!!sel));
        } catch (e) { print(s + ' selector 抛 ' + e); }
    });
}