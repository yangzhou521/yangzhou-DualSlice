function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
['scripts/ci-ahead.js','scripts/ci-tree2.js','scripts/ci-check.js'].forEach(function(p){
  const t=get('https://raw.githubusercontent.com/yangzhou521/yangzhou-DualSlice/main/'+p);
  console.log(p+' -> '+(t?'已在远端':'不在远端'));
});
