// 用 icli probe 下载 ThemeCorePlus 的 Release 资产（本机没有 curl/wget/python3）
// 用法： icli probe scripts/download-tcp.js
// 版本变了只改 VERSION（tag 与资产名都跟着它，tag 规则：themecoreplus-v<VERSION>）。
// 落盘路径用真根前缀，Files 里能看见，irisin-cli 也认这个路径。
var VERSION = '0.9.15';
var urlStr = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v'
    + VERSION + '/com.yangzhou.themecoreplus_' + VERSION + '_iphoneos-arm64e.deb';
var destPath = '/var/mobile/Documents/themecoreplus-' + VERSION + '.deb';

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
