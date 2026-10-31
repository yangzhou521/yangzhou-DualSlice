function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const a = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/check-runs/124411764082/annotations'));
(a||[]).forEach(x=>console.log('---',x.annotation_level, x.title, x.path, '\n'+String(x.message).slice(0,1500)));
