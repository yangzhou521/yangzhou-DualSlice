// 侦察桥能拿到什么：类的方法/ivar 列表、父类的实现信息（探针跑在 icli 自己进程里，先自己把面板 bundle 载进来）
var real = '/var/containers/Bundle/Application/.jbroot-1368F5DC986DAB0C/Library/PreferenceBundles/ThemeCorePlusPrefs.bundle';
var b = ObjC.use('NSBundle').bundleWithPath_(real);
print('load=' + b.load());
print('ObjC keys: ' + Object.getOwnPropertyNames(ObjC).join(','));

var K = ObjC.classes.TCRootListController;
var S = ObjC.classes.PSListController;
print('K class keys: ' + Object.getOwnPropertyNames(K).join(','));
try { print('K ownMethods: ' + (K.$ownMethods || []).join(',')); } catch (e) { print('K ownMethods: ' + e); }
try { print('K ivars: ' + JSON.stringify(K.$ivars)); } catch (e) { print('K ivars: ' + e); }
try { print('S ivars: ' + JSON.stringify(S.$ivars)); } catch (e) { print('S ivars: ' + e); }
try {
  var m = (S.$ownMethods || []).filter(function (n) { return /[Ss]pecifier|Section|reload/.test(n); });
  print('S 相关方法: ' + m.join(','));
} catch (e) { print('S specifier methods: ' + e); }
try { print('superchain: ' + K.$superClass + ' -> ' + S.$superClass); } catch (e) { print('chain: ' + e); }
