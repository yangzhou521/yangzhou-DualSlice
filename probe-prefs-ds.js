// 表格到底从哪儿拿数据：dataSource/delegate 是谁，数据源方法各返回多少。
var real = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/ThemeCorePlusPrefs.bundle';
var b = ObjC.use('NSBundle').bundleWithPath_(real);
b.load();
var C = ObjC.classes.TCRootListController;
var c = C.alloc().init();
c.view();

function try_ (label, fn) { try { print(label + ' = ' + fn()); } catch (e) { print(label + ' threw: ' + e); } }

var tv = c.table();
print('table class = ' + (tv ? tv.$class : 'nil'));
try_('view class', function () { return c.view().$class; });
try_('dataSource', function () { var d = tv.dataSource(); return d ? d.$class : 'nil'; });
try_('delegate', function () { var d = tv.delegate(); return d ? d.$class : 'nil'; });
try_('numSectionsInTable', function () { return c.numberOfSectionsInTableView_(tv); });
try_('rowsInSection0', function () { return c.tableView_numberOfRowsInSection_(tv, 0); });
try_('specifiers()', function () { return c.specifiers().count(); });
try_('kvc specifiers', function () { return c.valueForKey_('specifiers'); });
try_('responds reload', function () { return c.respondsToSelector_('reloadSpecifiers'); });
try_('kvc _specifiers', function () { return c.valueForKey_('_specifiers'); });
try_('subviews', function () { return c.view().subviews().count(); });
