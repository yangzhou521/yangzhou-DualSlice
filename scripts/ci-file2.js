function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
function show(p, a, b){
  const t = get('https://raw.githubusercontent.com/yangzhou521/yangzhou-DualSlice/main/'+p);
  console.log('### '+p);
  if(!t){console.log('nofile');return;}
  t.split('\n').forEach((l,i)=>{if(i+1>=a&&i+1<=b)console.log((i+1)+': '+l);});
}
show('ThemeCorePlus/Sources/ThemeCorePlusHooks.m', 270, 282);
show('ThemeCorePlus/Sources/ThemeCorePlusLayout.m', 385, 393);
