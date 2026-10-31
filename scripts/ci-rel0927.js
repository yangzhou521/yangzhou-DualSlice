function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const rel = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/releases?per_page=4'));
rel.forEach(x=>{
  if(/0\.9\.2[5-9]/.test(x.tag_name)){
    console.log('tag', x.tag_name, x.draft?'draft':'published', x.published_at);
    (x.assets||[]).forEach(a=>console.log('  asset', a.name, a.size, a.browser_download_url));
  }
});
console.log('---annotations---');
const anno = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs/41172682266/annotations'));
// annotations endpoint may not exist via this path; try check-runs
