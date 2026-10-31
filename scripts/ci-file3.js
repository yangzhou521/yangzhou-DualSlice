function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const t = get('https://raw.githubusercontent.com/yangzhou521/yangzhou-DualSlice/main/ThemeCorePlus/Sources/ThemeCorePlusHooks.h');
if(!t){console.log('nofile');}else{t.split('\n').forEach((l,i)=>console.log((i+1)+': '+l));}
