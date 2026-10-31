function get(u){const nsurl=ObjC.use('NSURL').URLWithString_(u);const data=ObjC.use('NSData').dataWithContentsOfURL_(nsurl);if(!data)return null;const t=ObjC.use('NSString').alloc().initWithData_encoding_(data,4);return String(t);}
['f573d74aacd22152d838ad85b4e1d413907e56fb','0d13dfa4fe5acbfc21d8f5708e471e2dc999852e','2aea179312c6935091497e331da6b2d6d727f098'].forEach(function(sha){
  const c = JSON.parse(get('https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/commits/'+sha));
  console.log('=== '+sha.slice(0,10)+' '+c.commit.message.split('\n')[0]);
  (c.files||[]).forEach(f=>console.log('  '+f.status+' '+f.filename));
});
