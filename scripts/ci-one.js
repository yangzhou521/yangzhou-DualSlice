const id = '41158895611';
function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const run = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs/'+id));
console.log('run', run.name, run.head_sha, run.conclusion);
const jobs = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs/'+id+'/jobs'));
(jobs.jobs||[]).forEach(j=>{
  console.log('job', j.name, j.conclusion);
  (j.steps||[]).forEach(s=>console.log('  step', s.name, s.conclusion));
});
