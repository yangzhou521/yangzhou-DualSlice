function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const crs = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/commits/2a7ef8902c243aa9c72d9ce40f0b0343360a65a8/check-runs'));
(crs.check_runs||[]).forEach(c=>{
  console.log('cr', c.id, c.name, c.conclusion);
  const annos = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/check-runs/' + c.id + '/annotations'));
  (annos||[]).forEach(a=>console.log('  anno:', a.annotation_level, a.path, a.start_line, a.message));
});
