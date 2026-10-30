// 「生效主题」二级页点开即闪退：在本机复现，拿异常的 reason（那里写着不认识的选择器）。
// 跑法: icli probe probe-picker3.js
var real = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/ThemeCorePlusPrefs.bundle';
ObjC.use('NSBundle').bundleWithPath_(real).load();

var C = ObjC.classes.TCPThemeListController;
print('类存在: ' + (C ? 'yes' : 'NO'));
if (!C) {
    print('（面板 bundle 里没有这个类：装置上的包还是旧版？）');
} else {
    var c = C.alloc().init();
    print('title=' + c.title());
    try {
        var sp = c.specifiers();
        print('specifiers 项数=' + (sp ? sp.count() : 'nil'));
        for (var i = 0; sp && i < sp.count(); i++) {
            var s = sp.objectAtIndex_(i);
            print('  [' + i + '] ' + s.name() + '  类=' + s.className() +
                  ' cell=' + s.cell() + ' detail=' + s.detail() +
                  ' set=' + s.setterName() + ' get=' + s.getterName());
        }
    } catch (e) {
        print('specifiers 抛异常: ' + e);
    }
    try { c.view(); print('view() OK'); } catch (e) { print('view() 闪退点: ' + e); }
    try { c.viewWillAppear_(true); print('viewWillAppear OK'); } catch (e) { print('viewWillAppear 抛: ' + e); }
    try {
        var tv = c.table();
        if (!tv) { print('table=nil'); } else {
            var n = c.numberOfSectionsInTableView_(tv), total = 0;
            for (var i = 0; i < n; i++) total += c.tableView_numberOfRowsInSection_(tv, i);
            print('sections=' + n + ' rows=' + total);
        }
    } catch (e) {
        print('表格读取抛: ' + e);
    }
}