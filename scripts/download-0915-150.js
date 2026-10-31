// 一次下两个包：ThemeCorePlus 0.9.15（含图标布局备份）+ CountdownHUD 1.5.0（注销弹窗）
var jobs = [
  ['https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.9.15/com.yangzhou.themecoreplus_0.9.15_iphoneos-arm64e.deb',
   '/var/mobile/Documents/com.yangzhou.themecoreplus_0.9.15_iphoneos-arm64e.deb'],
  ['https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/countdownhud-v1.5.0/com.yangzhou.countdownhud_1.5.0_iphoneos-arm64e.deb',
   '/var/mobile/Documents/com.yangzhou.countdownhud_1.5.0_iphoneos-arm64e.deb']
];

var fm = ObjC.use('NSFileManager').defaultManager();

for (var i = 0; i < jobs.length; i++) {
  var urlStr = jobs[i][0];
  var destPath = jobs[i][1];
  var url = ObjC.use('NSURL').URLWithString_(urlStr);
  if (!url) { print('ERROR bad URL ' + urlStr); continue; }
  var data = ObjC.use('NSData').dataWithContentsOfURL_(url);
  if (!data) { print('ERROR nil data ' + urlStr); continue; }
  var len = data.length();
  var ok = data.writeToFile_atomically_(destPath, true);
  var attrs = fm.attributesOfItemAtPath_error_(destPath, null);
  var diskSize = attrs ? attrs.valueForKey_('NSFileSize') : 0;
  print('file=' + destPath + ' ok=' + ok + ' len=' + len + ' disk=' + diskSize);
}
