# 解析 Mach-O 的 Objective-C 元数据：类名 + 每个类自己声明的方法。
# 用法： od -An -v -tx1 slice | gawk -f scripts/macho-objc.awk
# 只读、离线，不碰设备。
function u8(o) { return B[o] }
function u32(o) { return B[o] + B[o+1]*256 + B[o+2]*65536 + B[o+3]*16777216 }
function u64(o) {
  return u32(o) + u32(o+4) * 4294967296
}
function hexval(s,   i, v, c) {
  v = 0
  for (i = 1; i <= length(s); i++) {
    c = index("0123456789abcdef", tolower(substr(s, i, 1)))
    if (c == 0) return -1
    v = v * 16 + (c - 1)
  }
  return v
}
# vmaddr -> 文件偏移
function a2o(addr,   i) {
  for (i = 0; i < nsec; i++) {
    if (addr >= sec_addr[i] && addr < sec_addr[i] + sec_size[i])
      return sec_off[i] + (addr - sec_addr[i])
  }
  return -1
}
function cstr(addr,   o, s, c, k) {
  o = a2o(addr)
  if (o < 0) return "?"
  s = ""
  for (k = 0; k < 200; k++) {
    c = B[o+k]
    if (c == 0 || c == "") break
    s = s sprintf("%c", c)
  }
  return s
}
# chained fixup rebase 解码（arm64e / 64 位）
function decode_ptr(raw) {
  if (chained == 0) return raw
  if (raw == 0) return 0
  # bind (bit 62) 不是 rebase
  if (and(rshift(raw, 62), 1) == 1) return -1
  if (and(rshift(raw, 63), 1) == 1) {
    # auth rebase: target 32 位
    return and(raw, 4294967295)
  }
  # rebase: target 36 位 | high8 << 56
  return and(raw, 68719476735)
}
function read_ptr(o) { return decode_ptr(u64(o)) }
BEGIN { n = 0; nsec = 0; nclass = 0; chained = 0 }
{ for (i = 1; i <= NF; i++) { B[n] = hexval($i); n++ } }
END {
  if (u32(0) != 4277009103) { print "not a thin mach-o (magic " u32(0) ")"; exit 1 }
  ncmds = u32(16); off = 32
  clslist_addr = 0; clslist_size = 0
  for (c = 0; c < ncmds; c++) {
    cmd = u32(off); cmdsize = u32(off+4)
    if (cmd == 25) {                       # LC_SEGMENT_64
      segname = ""
      for (k = 0; k < 16; k++) { ch = B[off+8+k]; if (ch == 0) break; segname = segname sprintf("%c", ch) }
      seg_vm = u64(off+24); seg_foff = u32(off+40)
      nsects = u32(off+64); soff = off+72
      for (s = 0; s < nsects; s++) {
        sname = ""; sgname = ""
        for (k = 0; k < 16; k++) { ch = B[soff+k]; if (ch == 0) break; sname = sname sprintf("%c", ch) }
        for (k = 0; k < 16; k++) { ch = B[soff+16+k]; if (ch == 0) break; sgname = sgname sprintf("%c", ch) }
        sec_addr[nsec] = u64(soff+32)
        sec_size[nsec] = u64(soff+40)
        sec_off[nsec] = u32(soff+48)
        sec_name[nsec] = sname
        sec_seg[nsec] = sgname
        if (sname == "__objc_classlist") { clslist_addr = sec_addr[nsec]; clslist_size = sec_size[nsec] }
        soff += 80
        nsec++
      }
    } else if (cmd == 2147483700) {        # LC_DYLD_CHAINED_FIXUPS
      chained = 1
    }
    off += cmdsize
  }
  printf("sections=%d chained=%d classlist=%d@%d\n", nsec, chained, int(clslist_size/8), clslist_addr)
  if (clslist_addr == 0) { print "no __objc_classlist"; exit 0 }
  o = a2o(clslist_addr)
  cnt = clslist_size / 8
  for (i = 0; i < cnt; i++) {
    cls = read_ptr(o + i*8)
    co = a2o(cls)
    if (co < 0) continue
    ro = read_ptr(co + 32)
    roo = a2o(ro - and(ro, 7))
    if (roo < 0) continue
    name = cstr(read_ptr(roo + 24))
    base = read_ptr(roo + 32)
    print "CLASS " name
    mo = a2o(base)
    if (mo < 0) continue
    entsize = and(u32(mo), 65532)
    mcount = u32(mo + 4)
    mlvm = base
    for (m = 0; m < mcount; m++) {
      eo = mo + 8 + m * entsize
      if (entsize >= 24) {
        sel = cstr(read_ptr(eo))
      } else {
        noff = u32(eo)
        if (noff >= 2147483648) noff -= 4294967296
        # 相对格式：偏移相对 method_t 自身
        sel = cstr(mlvm + 8 + m * entsize + noff)
      }
      print "  - " sel
    }
  }
}