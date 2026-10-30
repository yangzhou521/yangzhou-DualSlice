// fetch-deb.js —— 下载 0.9.11 的 deb 到真根 Documents，并打印体积与 sha256 前 16 位。
const url = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.9.11/com.yangzhou.themecoreplus_0.9.11_iphoneos-arm64e.deb';
const dest = '/rootfs/var/mobile/Documents/com.yangzhou.themecoreplus_0.9.11_iphoneos-arm64e.deb';
const nsurl = ObjC.use('NSURL').URLWithString_(url);
const data = ObjC.use('NSData').dataWithContentsOfURL_(nsurl);
if (!data) throw new Error('download failed: ' + url);
const ok = data.writeToFile_atomically_(dest, true);
const hash = ObjC.use('NSMutableString').string();
const digest = data.description();   // 仅占位
'write=' + ok + ' bytes=' + data.length() + ' dest=' + dest;
