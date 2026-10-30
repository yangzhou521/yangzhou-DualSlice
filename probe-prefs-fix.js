// 定位修法：PSListController 自己有没有 -specifiers/-setSpecifiers:，
// 以及把我们的数组灌回它的内部存储后，表格是否就出现行数。
var real = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/ThemeCorePlusPrefs.bundle';
var b = ObjC.use('NSBundle').bundleWithPath_(real);
b.load();

function resp(o, sel) { try { return o.respondsToSelector_(sel); } catch (e) { return 'threw ' + e; } }

var P = ObjC.classes.PSListController;
print('PSListController: specifiers=' + resp(P, 'specifiers')
      + ' setSpecifiers:=' + resp(P, 'setSpecifiers:')
      + ' reloadSpecifiers=' + resp(P, 'reloadSpecifiers')
      + ' loadSpecifiersFromPlistName:target:=' + resp(P, 'loadSpecifiersFromPlistName:target:')
      + ' numberOfSectionsInTableView:=' + resp(P, 'numberOfSectionsInTableView:'));

var c = ObjC.classes.TCRootListController.alloc().init();
c.view();
var tv = c.table();

function rows() {
  var s = c.numberOfSectionsInTableView_(tv), total = 0;
  for (var i = 0; i < s; i++) {
    try { total += c.tableView_numberOfRowsInSection_(tv, i); } catch (e) { return 'section ' + i + ' threw'; }
  }
  return 'sections=' + s + ' rows=' + total;
}

print('before : ' + rows());
try { c.setSpecifiers_(c.specifiers()); print('setSpecifiers: ok'); } catch (e) { print('setSpecifiers: threw ' + e); }
print('after  : ' + rows());
