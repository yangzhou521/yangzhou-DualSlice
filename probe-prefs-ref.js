// 对照组：实例化两个「能用」的面板，看它们的表格在没被我们插手时有多少行，
// 以及它们藏在哪个 ivar 里（kvc 读 _specifiers）。
var root = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/';

function rowsOf(c) {
  var tv = null;
  try { tv = c.table(); } catch (e) { return 'table() threw: ' + e; }
  if (!tv) return 'no table';
  var s = 0;
  try { s = c.numberOfSectionsInTableView_(tv); } catch (e) { return 'sections threw: ' + e; }
  var total = 0;
  for (var i = 0; i < s; i++) {
    try { total += c.tableView_numberOfRowsInSection_(tv, i); } catch (e) { return 'sec' + i + ' threw'; }
  }
  return 'sections=' + s + ' rows=' + total;
}

function probe(name, cls) {
  try {
    var b = ObjC.use('NSBundle').bundleWithPath_(root + name + '.bundle');
    print('--- ' + name + ' load=' + (b ? b.load() : 'no bundle'));
    var K = ObjC.classes[cls];
    if (!K) { print('  class missing'); return; }
    var c = K.alloc().init();
    c.view();
    print('  after view(): ' + rowsOf(c));
    print('  kvc _specifiers = ' + c.valueForKey_('_specifiers'));
    var n = c.specifiers().count();
    print('  specifiers()=' + n + '  now: ' + rowsOf(c));
    print('  kvc _specifiers now = ' + c.valueForKey_('_specifiers'));
  } catch (e) {
    print('  threw: ' + e);
  }
}

probe('VerticalDockPrefs', 'VDRootListController');
probe('SystemBoxPrefs', 'SystemBoxRootListController');
