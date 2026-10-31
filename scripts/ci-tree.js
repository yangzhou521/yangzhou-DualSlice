function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const t = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/git/trees/main?recursive=1'));
(t.tree||[]).map(x=>x.path).filter(p=>p.indexOf('ThemeCorePlus/Sources')===0||p.indexOf('Badges')>=0).forEach(p=>console.log(p));
