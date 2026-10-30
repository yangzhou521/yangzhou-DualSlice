// probe-png3.js —— 在 icli 进程里把 PNG 解出来量像素（本机没有 python3，纯 JS 手写 inflate）。
// 目的：坐实「主题图标为什么显示成空白」——是遮罩把图标裁没了，还是素材本身就是一层玻璃？

var R = '/var/containers/Bundle/Application/.jbroot-BE7CF66DAF7343C6/Library/ThemeCore';

// ---------- inflate ----------
var LBASE = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258];
var LEXT  = [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0];
var DBASE = [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577];
var DEXT  = [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];

function construct(lengths, n) {
  var count = new Array(16); var i;
  for (i = 0; i < 16; i++) count[i] = 0;
  for (i = 0; i < n; i++) count[lengths[i]]++;
  var symbol = [];
  if (count[0] !== n) {
    var offs = new Array(16); offs[0] = 0; offs[1] = 0;
    for (i = 1; i < 15; i++) offs[i + 1] = offs[i] + count[i];
    for (i = 0; i < n; i++) if (lengths[i]) symbol[offs[lengths[i]]++] = i;
  }
  return { count: count, symbol: symbol };
}

function inflateRaw(data) {
  var pos = 0, bitbuf = 0, bitcnt = 0, out = [];
  function bits(n) {
    var val = bitbuf;
    while (bitcnt < n) { val |= data[pos++] << bitcnt; bitcnt += 8; }
    bitbuf = val >>> n; bitcnt -= n;
    return val & ((1 << n) - 1);
  }
  function decode(h) {
    var code = 0, first = 0, index = 0;
    for (var len = 1; len <= 15; len++) {
      code |= bits(1);
      var count = h.count[len];
      if (code - count < first) return h.symbol[index + (code - first)];
      index += count; first += count; first <<= 1; code <<= 1;
    }
    throw new Error('bad huffman code');
  }
  function codes(lit, dist) {
    for (;;) {
      var sym = decode(lit);
      if (sym < 0) throw new Error('bad lit');
      if (sym < 256) { out.push(sym); }
      else if (sym === 256) { return; }
      else {
        sym -= 257;
        if (sym >= 29) throw new Error('bad len sym');
        var len = LBASE[sym] + bits(LEXT[sym]);
        var ds = decode(dist);
        if (ds < 0 || ds >= 30) throw new Error('bad dist');
        var d = DBASE[ds] + bits(DEXT[ds]);
        if (!d || d > out.length) throw new Error('bad dist back');
        for (var i = 0; i < len; i++) out.push(out[out.length - d]);
      }
    }
  }
  var fixedLit = null, fixedDist = null, last = 0;
  do {
    last = bits(1);
    var type = bits(2);
    if (type === 0) {
      bitbuf = 0; bitcnt = 0;
      var len = data[pos] | (data[pos + 1] << 8);
      pos += 4;
      for (var i = 0; i < len; i++) out.push(data[pos++]);
    } else if (type === 1) {
      if (!fixedLit) {
        var l = [];
        for (var s = 0; s < 288; s++) l.push(s < 144 ? 8 : (s < 256 ? 9 : (s < 280 ? 7 : 8)));
        fixedLit = construct(l, 288);
        var dl = []; for (var s2 = 0; s2 < 30; s2++) dl.push(5);
        fixedDist = construct(dl, 30);
      }
      codes(fixedLit, fixedDist);
    } else if (type === 2) {
      var hlit = bits(5) + 257, hdist = bits(5) + 1, hclen = bits(4) + 4;
      var order = [16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15];
      var clen = new Array(19);
      for (var i = 0; i < 19; i++) clen[i] = 0;
      for (var i2 = 0; i2 < hclen; i2++) clen[order[i2]] = bits(3);
      var clh = construct(clen, 19);
      var lens = [], total = hlit + hdist;
      while (lens.length < total) {
        var sym = decode(clh);
        if (sym < 16) lens.push(sym);
        else if (sym === 16) { var prev = lens[lens.length - 1]; var r = 3 + bits(2); for (var k = 0; k < r; k++) lens.push(prev); }
        else if (sym === 17) { var r2 = 3 + bits(3); for (var k2 = 0; k2 < r2; k2++) lens.push(0); }
        else { var r3 = 11 + bits(7); for (var k3 = 0; k3 < r3; k3++) lens.push(0); }
      }
      codes(construct(lens.slice(0, hlit), hlit), construct(lens.slice(hlit, total), hdist));
    } else throw new Error('bad block type ' + type);
  } while (!last);
  return out;
}

// ---------- PNG ----------
// fs.read 只肯读文本（"not UTF-8 text"），二进制走 NSData → Latin-1 字符串，一个字符正好一个字节。
var NSData = ObjC.use('NSData');
var NSString = ObjC.use('NSString');
function bytesOf(path) {
  var d = NSData.dataWithContentsOfFile_(path);
  if (!d) throw new Error('missing ' + path);
  var s = NSString.alloc().initWithData_encoding_(d, 5);   // NSISOLatin1StringEncoding
  if (!s) throw new Error('latin1 decode failed');
  var a = [];
  for (var i = 0; i < s.length; i++) a.push(s.charCodeAt(i) & 255);
  return a;
}

function u32(a, o) { return ((a[o] << 24) | (a[o+1] << 16) | (a[o+2] << 8) | a[o+3]) >>> 0; }
function u16(a, o) { return (a[o] << 8) | a[o+1]; }

function decodePNG(path) {
  var b = bytesOf(path);
  if (!(b[0] === 137 && b[1] === 80 && b[2] === 78 && b[3] === 71)) return { err: 'not png' };
  var o = 8, w = 0, h = 0, bd = 0, ct = 0, il = 0, idat = [], plte = null, trns = null;
  while (o + 8 <= b.length) {
    var len = u32(b, o), type = String.fromCharCode(b[o+4], b[o+5], b[o+6], b[o+7]);
    var body = o + 8;
    if (type === 'IHDR') { w = u32(b, body); h = u32(b, body + 4); bd = b[body + 8]; ct = b[body + 9]; il = b[body + 12]; }
    else if (type === 'IDAT') { for (var i = 0; i < len; i++) idat.push(b[body + i]); }
    else if (type === 'PLTE') { plte = b.slice(body, body + len); }
    else if (type === 'tRNS') { trns = b.slice(body, body + len); }
    else if (type === 'IEND') break;
    o = body + len + 4;
  }
  var channels = ({ 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 })[ct];
  if (!channels) return { w: w, h: h, err: 'unsupported colortype ' + ct };
  if (il) return { w: w, h: h, err: 'interlaced' };
  if (bd !== 8) return { w: w, h: h, err: 'bitdepth ' + bd };
  // IDAT 是 zlib 流：跳过 2 字节头，尾部 4 字节 adler 会被 inflate 忽略
  var raw = inflateRaw(idat.slice(2));
  var stride = w * channels, bpp = channels, prev = new Array(stride);
  for (var i = 0; i < stride; i++) prev[i] = 0;
  var cur = new Array(stride), p = 0, pixels = [];
  for (var y = 0; y < h; y++) {
    var ft = raw[p++];
    for (var x = 0; x < stride; x++) {
      var rv = raw[p++], a = x >= bpp ? cur[x - bpp] : 0, up = prev[x], c = x >= bpp ? prev[x - bpp] : 0, v = 0;
      if (ft === 0) v = rv;
      else if (ft === 1) v = rv + a;
      else if (ft === 2) v = rv + up;
      else if (ft === 3) v = rv + ((a + up) >> 1);
      else {
        var pp = a + up - c, pa = Math.abs(pp - a), pb = Math.abs(pp - up), pc = Math.abs(pp - c);
        v = rv + ((pa <= pb && pa <= pc) ? a : (pb <= pc ? up : c));
      }
      cur[x] = v & 255;
    }
    for (var x2 = 0; x2 < w; x2++) {
      var alpha = 255;
      if (ct === 6) alpha = cur[x2 * 4 + 3];
      else if (ct === 4) alpha = cur[x2 * 2 + 1];
      else if (ct === 3) alpha = (trns && cur[x2] < trns.length) ? trns[cur[x2]] : 255;
      pixels.push(alpha);
    }
    for (var i2 = 0; i2 < stride; i2++) prev[i2] = cur[i2];
  }
  var hit = 0, sum = 0, minx = w, miny = h, maxx = -1, maxy = -1;
  for (var j = 0; j < pixels.length; j++) {
    var al = pixels[j];
    sum += al;
    if (al >= 8) {
      hit++;
      var px = j % w, py = (j - px) / w;
      if (px < minx) minx = px; if (px > maxx) maxx = px;
      if (py < miny) miny = py; if (py > maxy) maxy = py;
    }
  }
  return {
    w: w, h: h, ct: ct, bd: bd,
    cov: hit / pixels.length,
    meanA: sum / (pixels.length * 255),
    bbox: maxx < 0 ? 'none' : (minx + ',' + miny + ',' + (maxx - minx + 1) + 'x' + (maxy - miny + 1))
  };
}

// ---------- 量 ----------
var targets = [
  ['badge.透明玻璃', R + '/角标：透明玻璃/Bundles/com.apple.springboard/SBBadgeBG@3x.png'],
  ['badge.液态玻璃', R + '/液态玻璃.theme/Bundles/com.apple.springboard/SBBadgeBG@3x.png'],
  ['folder.ANEM', R + '/液态玻璃.theme/Bundles/com.apple.springboard/ANEMFolderIconBG@3x.png'],
  ['mask', R + '/液态玻璃.theme/com.apple.mobileicons.framework/AppIconMask@3x.png'],
  ['icon.Translate', R + '/液态玻璃.theme/IconBundles/com.apple.Translate-large.png'],
  ['icon.Safari', R + '/液态玻璃.theme/IconBundles/com.apple.mobilesafari-large.png']
];
var out = [];
targets.forEach(function (t) {
  try {
    var r = decodePNG(t[1]);
    out.push(t[0] + ' ' + JSON.stringify(r));
  } catch (e) {
    out.push(t[0] + ' ERR ' + e);
  }
});
print(out.join('\n'));