function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const p = process.argv[2];
const t = get('https://raw.githubusercontent.com/yangzhou521/yangzhou-DualSlice/main/'+p);
if(!t){console.log('nofile');}
else {const lines=t.split('\n');lines.forEach((l,i)=>{if(i>=265&&i<=285)console.log((i+1)+': '+l);});}
