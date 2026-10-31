function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const r = get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/workflows/themecoreplus.yml/runs?per_page=8');
const obj = JSON.parse(r);
(obj.workflow_runs||[]).forEach(x=>console.log(x.id, x.head_sha.slice(0,10), x.status, x.conclusion, x.created_at));
console.log('---RELEASES---');
const rel = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/releases?per_page=10'));
rel.forEach(x=>console.log(x.tag_name, x.draft?'draft':'published', x.published_at));
