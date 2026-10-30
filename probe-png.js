// probe-png.js —— 量主题素材的像素：遮罩是不是「把图标裁没了」、图标素材本身覆盖多少。
// 只用桥能拿到的东西：先看有没有 C 函数调用的口子，没有就走 NSData+NSFileManager 的路。
var out = [];
function L(s) { out.push(String(s)); }

L('ObjC keys: ' + Object.getOwnPropertyNames(ObjC).join(','));
try { L('global keys: ' + Object.getOwnPropertyNames(this).join(',')); } catch (e) { L('g err ' + e); }
L('typeof Native=' + (typeof Native) + ' typeof Module=' + (typeof Module) + ' typeof C=' + (typeof C));

var NSData = ObjC.use('NSData');
try { L('NSData classmethods: ' + Object.getOwnPropertyNames(NSData).join(',')); } catch (e) { L('nd ' + e); }

var PATH = '/var/containers/Bundle/Application/.jbroot-BE7CF66DAF7343C6/Library/ThemeCore/液态玻璃.theme/com.apple.mobileicons.framework/AppIconMask@3x.png';
var d = NSData.dataWithContentsOfFile_(PATH);
L('mask data: ' + (d ? d.length() : 'nil'));

// NSData 的字节怎么读？试几条常见路。
if (d) {
  try { L('data bytes typeof=' + (typeof d.bytes) + ' => ' + d.bytes()); } catch (e) { L('bytes err ' + e); }
  try { L('length keys: ' + Object.getOwnPropertyNames(d).join(',')); } catch (e) { L('own ' + e); }
  try { L('utf8 head: ' + ObjC.use('NSString').alloc().initWithData_encoding_(d, 4)); } catch (e) { L('utf8 err ' + e); }
}

print(out.join('\n'));