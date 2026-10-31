function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
const r = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/releases?per_page=4'));
r.forEach(x=>{console.log('tag='+x.tag_name+' published='+x.published_at+' draft='+x.draft);
 (x.assets||[]).forEach(a=>console.log('   '+a.name+' '+a.size+' '+a.browser_download_url));});
