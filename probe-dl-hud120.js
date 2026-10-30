// 下载 CountdownHUD 1.2.0 的 Release 资产到真根 Documents。
// 用法：icli probe probe-dl-hud120.js
var URL = ObjC.use('NSURL');
var Data = ObjC.use('NSData');

var url = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/countdownhud-v1.2.0/com.yangzhou.countdownhud_1.2.0_iphoneos-arm64e.deb';
var dst = '/var/mobile/Documents/countdownhud-1.2.0.deb';

var out = { url: url, dst: dst, len: -1, wrote: null };
try {
  var d = Data.dataWithContentsOfURL(URL.URLWithString(url));
  out.len = d ? d.length() : -1;
  if (d) {
    try { out.wrote = d.writeToFile_atomically_(dst, true); }
    catch (e) { out.wrote = 'err:' + String(e); }
  }
} catch (e) {
  out.error = String(e);
}
JSON.stringify(out);
