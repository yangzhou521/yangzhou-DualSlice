var sessions = ObjC.use('NSFileManager').defaultManager();
var base = '/var/mobile/Documents/wiki.qaq.apelin/sessions/';
var ids = ['2c7ce9b8-6a28-4af3-bace-6828526d133b',
           '9dd92628-8d98-4836-a7e0-ae4d53f16c4d',
           '1328cf03-5504-47ad-bc9c-88579ed9dc75'];
var NSString = ObjC.use('NSString');
for (var i = 0; i < ids.length; i++) {
    var p = base + ids[i] + '/session.json';
    var data = ObjC.use('NSData').dataWithContentsOfFile_(p);
    if (!data) { print('MISS ' + p); continue; }
    var s = ObjC.cast(ObjC.use('NSString').alloc().initWithData_encoding_(data, 4), 'NSString');
    var before = s.length();
    var out = s.replaceOccurrencesOfString_withString_range_options_('"model":"kimi-k3-1"', '"model":"deepseek-v4.1-flash"', ObjC.CFMakeRange(0, before), 0);
    var n = out.length();
    var ok = ObjC.use('NSData').dataWithBytes_length_(out.UTF8String(), n).writeToFile_atomically_(p, true);
    // 读回验证
    var d2 = ObjC.use('NSData').dataWithContentsOfFile_(p);
    var s2 = ObjC.cast(ObjC.use('NSString').alloc().initWithData_encoding_(d2, 4), 'NSString');
    var m = s2.rangeOfString('"model":"').location;
    var tail = s2.substringFromIndex(m);
    print(ids[i] + ' ok=' + ok + ' model=' + tail.substring(0, 40).replace('\n', ' '));
}
