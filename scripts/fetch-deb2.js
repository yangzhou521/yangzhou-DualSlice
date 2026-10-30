// fetch-deb2.js —— 先探哪儿能写，再把 deb 落盘。
const url = 'https://github.com/yangzhou521/yangzhou-DualSlice/releases/download/themecoreplus-v0.9.11/com.yangzhou.themecoreplus_0.9.11_iphoneos-arm64e.deb';
const data = ObjC.use('NSData').dataWithContentsOfURL_(ObjC.use('NSURL').URLWithString_(url));
if (!data) throw new Error('download failed');
const tmp = String(ObjC.use('NSTemporaryDirectory')());
const cands = [tmp + 'tcp0911.deb', '/tmp/tcp0911.deb', '/rootfs/tmp/tcp0911.deb',
               '/rootfs/var/mobile/Documents/tcp0911.deb'];
const lines = ['bytes=' + data.length(), 'tmpdir=' + tmp];
for (const p of cands) {
  let ok = false;
  try { ok = data.writeToFile_atomically_(p, true); } catch (e) { lines.push(p + ' ERR ' + e); continue; }
  lines.push(p + ' => ' + ok);
}
lines.join('\n');
