function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const r = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs/41172682266'));
console.log('sha', r.head_sha.slice(0,10), 'branch', r.head_branch, 'event', r.event, 'msg', r.head_commit.message.split('\n')[0]);
const jobs = JSON.parse(get(r.jobs_url));
(jobs||[]).forEach(j=>console.log('job', j.name, j.status, j.conclusion));
