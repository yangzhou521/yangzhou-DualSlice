// probe-png2.js —— 找一条能在 icli 进程里读到 PNG 原始字节的路。
var out = [];
function L(s) { out.push(String(s)); }
function T(x) { return x === null ? 'null' : (x === undefined ? 'undefined' : typeof x); }

L('typeof fs=' + T(fs));
try { L('fs keys: ' + Object.getOwnPropertyNames(fs).join(',')); } catch (e) { L('fs err ' + e); }
try { L('__describe(fs)=' + __describe(fs)); } catch (e) { L('desc err ' + e); }

var PATH = '/var/containers/Bundle/Application/.jbroot-BE7CF66DAF7343C6/Library/ThemeCore/液态玻璃.theme/com.apple.mobileicons.framework/AppIconMask@3x.png';

try {
  var b = __fs_read(PATH);
  L('__fs_read => ' + T(b) + ' len=' + (b && b.length) + ' keys=' + (b && Object.getOwnPropertyNames(b).slice(0, 8).join(',')));
  if (b && b.length) L('first bytes: ' + [].slice.call(b, 0, 8).join(' '));
} catch (e) { L('__fs_read err ' + e); }

try { L('__fs_stat=' + JSON.stringify(__fs_stat(PATH))); } catch (e) { L('stat err ' + e); }

// NSData → 字节：试 Latin-1 字符串来回
var NSData = ObjC.use('NSData');
var NSString = ObjC.use('NSString');
var d = NSData.dataWithContentsOfFile_(PATH);
if (d) {
  var s = NSString.alloc().initWithData_encoding_(d, 5);   // NSISOLatin1StringEncoding
  L('latin1 string: ' + T(s) + ' len=' + (s ? s.length : -1));
  if (s) L('codes: ' + [0, 1, 2, 3, 4, 5, 6, 7].map(function (i) { return s.charCodeAt(i); }).join(' '));
  try {
    var back = s.dataUsingEncoding_(5);
    L('roundtrip data len=' + (back ? back.length() : -1));
  } catch (e) { L('rt err ' + e); }
  // 试解压（PNG 的 IDAT 是 zlib 流；libcompression 的 ZLIB 是裸 deflate，两种都试）
  [0, 1, 2, 3].forEach(function (alg) {
    try {
      var r = d.decompressedDataUsingAlgorithm_error_(alg, null);
      L('decompress alg ' + alg + ' => ' + T(r) + ' len=' + (r && r.length()));
    } catch (e) { L('decompress alg ' + alg + ' err ' + e); }
  });
}

print(out.join('\n'));