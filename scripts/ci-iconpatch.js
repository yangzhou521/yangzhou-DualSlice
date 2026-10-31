function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const c = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/commits/88a3de2e43'));
(c.files||[]).forEach(f=>{
  if(/Icons\.m|Store\.m/.test(f.filename)){
    console.log('=== '+f.filename+' +'+f.additions+' -'+f.deletions+' ===');
    console.log(f.patch||'(no patch)');
  }
});
