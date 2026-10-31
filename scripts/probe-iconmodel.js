// 查这些类在 icli 所在进程里看不看得见（注意：icli 的进程不是 SpringBoard，
// 只能查「类在不在 dyld 共享缓存里」，用来判断名字对不对，不能直接当 SpringBoard 的结论）。
var names = [];
for (var k in ObjC.classes) {
  if (/IconModel|IconState|IconController|IconManager/.test(k)) names.push(k);
}
print('count=' + names.length);
print(names.join('\n'));
