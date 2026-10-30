// 取证（2）：icli 进程里没有加载 SpringBoardHome，先 dlopen 它，再反射图标绘制相关方法。
// 跑法: icli probe probe-sbh2.js
function loadFW(path) {
    try {
        var b = ObjC.use('NSBundle').bundleWithPath_(path);
        if (!b) { print('bundle 取不到: ' + path); return false; }
        var ok = b.load();
        print('load(' + path.split('/').pop() + ') = ' + ok);
        return !!ok;
    } catch (e) { print('load 抛: ' + e); return false; }
}
loadFW('/System/Library/PrivateFrameworks/SpringBoardHome.framework');
try {
    var img = ObjC.use('UIImage');
    print('UIImage 在: ' + (img ? 'yes' : 'no'));
} catch (e) {}

function dump(name) {
    var C = null;
    try { C = ObjC.classes[name]; } catch (e) {}
    if (!C) { print('=== ' + name + ': 不可得'); return; }
    var list = null;
    try { list = C.$ownMethods; } catch (e) {}
    if (!list) { try { list = C.methods; } catch (e) {} }
    if (!list) { print('=== ' + name + ': 拿不到方法清单'); return; }
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var s = '' + list[i];
        if (/[Ii]mage|[Cc]ontents|[Cc]ache|[Dd]isplay|[Rr]eload/.test(s)) out.push(s);
    }
    out.sort();
    print('=== ' + name + ' 方法数=' + list.length + ' 命中=' + out.length);
    for (var j = 0; j < out.length; j++) print('   ' + out[j]);
}
['SBIconImageView', 'SBIcon', 'SBHIconImageCache', 'SBIconImageCrossfadeView', 'SBIconView'].forEach(dump);