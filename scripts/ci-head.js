function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const r = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/git/ref/heads/main'));
console.log('main sha = '+r.object.sha);
const c = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/commits/'+r.object.sha));
console.log('msg: '+c.commit.message.split('\n')[0]);
(c.files||[]).forEach(f=>console.log('  '+f.status+' '+f.filename));
