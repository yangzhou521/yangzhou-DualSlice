// 取证：SpringBoardHome 里管图标绘制的那几个类，究竟声明了哪些「图」相关的方法。
// 目的：别猜站点，直接看 iOS 16.7 上 SBIconImageView / SBHIconImageCache / SBIcon 的方法清单。
// 跑法: icli probe probe-sbh.js
function dump(name) {
    var C = null;
    try { C = ObjC.use(name); } catch (e) { print(name + ': ObjC.use 抛 ' + e); }
    if (!C) { try { C = ObjC.classes[name]; } catch (e) {} }
    if (!C) { print('=== ' + name + ': 不可得'); return; }
    var list = null;
    try { list = C.$ownMethods; } catch (e) {}
    if (!list) { try { list = C.methods; } catch (e) {} }
    if (!list) { print('=== ' + name + ': 类有，但拿不到方法清单'); return; }
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var s = '' + list[i];
        if (/[Ii]mage|[Ii]con|[Cc]ontents|[Cc]ache|[Rr]eload|[Dd]isplay/.test(s)) out.push(s);
    }
    out.sort();
    print('=== ' + name + ' 方法数=' + list.length + ' 命中=' + out.length);
    for (var j = 0; j < out.length; j++) print('   ' + out[j]);
}
['SBIconImageView', 'SBIcon', 'SBHIconImageCache', 'SBFolderIconImageView',
 'SBIconImageCrossfadeView', 'SBIconView'].forEach(dump);