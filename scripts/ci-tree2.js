function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const c = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/commits/a51d4e225ea2f231a90bbf37fad065dc18c1d089'));
(c.files||[]).forEach(f=>console.log(f.status+' '+f.filename));
