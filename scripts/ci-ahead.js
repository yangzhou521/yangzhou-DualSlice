function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const c = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/commits?sha=main&per_page=6'));
c.forEach(x=>console.log(x.sha.slice(0,10), x.commit.author.date, x.commit.message.split('\n')[0]));
