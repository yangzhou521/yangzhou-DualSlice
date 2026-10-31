function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const cr = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs/41158895611'));
console.log('checkruns', cr.check_suite_id);
const suite = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs/41158895611'));
const crs = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/commits/2aea179312c6935091497e331da6b2d6d727f098/check-runs'));
(crs.check_runs||[]).forEach(c=>console.log('cr', c.id, c.name, c.conclusion, c.output&&c.output.title, c.output&&c.output.summary));
