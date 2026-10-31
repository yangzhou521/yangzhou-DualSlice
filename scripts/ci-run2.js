function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const r = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/workflows/themecoreplus.yml/runs?per_page=3'));
(r.workflow_runs||[]).forEach(x=>console.log(x.id, x.status, x.conclusion, x.head_sha.slice(0,10)));
