// 列出 7497d5c(1.0.37 成功后) ... HEAD 之间改了哪些文件，定位 1.0.38 编译失败涉及面
function get(u){
    const nsurl = ObjC.use('NSURL').URLWithString_(u);
    const data = ObjC.use('NSData').dataWithContentsOfURL_(nsurl);
    if (!data) return null;
    const t = ObjC.use('NSString').alloc().initWithData_encoding_(data, 4);
    return String(t);
}
const j = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/compare/7497d5c...805ed24'));
if (!j || !j.files) { console.log('ERR ' + JSON.stringify(j).substring(0, 300)); }
else {
    console.log('commits=' + (j.commits ? j.commits.length : 0) + ' files=' + j.files.length);
    j.commits && j.commits.forEach(c => console.log('  c ' + (c.sha || '').substring(0, 7) + ' ' + (c.commit.message || '').split('\n')[0]));
    j.files.forEach(f => console.log('f ' + f.status + ' +' + f.additions + ' -' + f.deletions + ' ' + f.filename));
}
