// 下载 ThemeCorePlus 1.0.39 deb 到 /var/mobile/Documents
// 1.0.39 = 设置面板照 ThemeCore 对齐（页脚作者/越狱源、二级页标题+组头+页脚）+ 用户给的包详情文案
var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v1.0.39/com.yangzhou.themecoreplus_1.0.39_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/com.yangzhou.themecoreplus_1.0.39_iphoneos-arm64e.deb';

var url = ObjC.use('NSURL').URLWithString_(urlStr);
if (!url) { print('ERROR: bad URL'); throw 'bad URL'; }

var data = ObjC.use('NSData').dataWithContentsOfURL_(url);
if (!data) { print('ERROR: NSData returned nil'); throw 'nil data'; }

var len = data.length();
var ok = data.writeToFile_atomically_(destPath, true);

var fm = ObjC.use('NSFileManager').defaultManager();
var attrs = fm.attributesOfItemAtPath_error_(destPath, null);
var diskSize = attrs ? attrs.valueForKey_('NSFileSize') : 0;
print('downloaded=' + ok + ' len=' + len + ' diskSize=' + diskSize + ' path=' + destPath);
