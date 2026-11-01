// 检查 owngoal-dev/Apelin 最新 release，若有新版本则下载 arm64e deb 到真根 Documents。
// 用法： icli probe scripts/check-apelin-update.js
// 比对基准：项目内 scripts/apelin-version.txt（记录上一次看到的版本 tag）。
var seenPath = '/private/var/mobile/Containers/Shared/AppGroup/.jbroot-6C676B29A7087F99/var/mobile/Documents/wiki.qaq.apelin/Projects/yangzhouDualSlice/scripts/apelin-version.txt';
var apiUrl = 'https://api.github.com/repos/owngoal-dev/Apelin/releases/latest';

var url = ObjC.use('NSURL').URLWithString_(apiUrl);
var data = ObjC.use('NSData').dataWithContentsOfURL_(url);
if (!data) { print('ERROR: no data'); throw 'no data'; }

var json = ObjC.use('NSJSONSerialization').JSONObjectWithData_options_error_(data, 0, null);
if (!json) { print('ERROR: bad json'); throw 'bad json'; }

var tag = json.objectForKey_('tag_name').toString();
var assets = json.objectForKey_('assets');
var count = assets.count();
var debUrl = null;
for (var i = 0; i < count; i++) {
    var a = assets.objectAtIndex_(i);
    var name = a.objectForKey_('name').toString();
    if (name.indexOf('wiki.qaq.apelin_') === 0 && name.indexOf('_iphoneos-arm64e.deb') >= 0) {
        debUrl = a.objectForKey_('browser_download_url').toString();
        break;
    }
}

// 读本地已见版本
var seen = '';
var fm = ObjC.use('NSFileManager').defaultManager();
if (fm.fileExistsAtPath_(seenPath)) {
    var sdata = ObjC.use('NSData').dataWithContentsOfFile_(seenPath);
    if (sdata) {
        seen = ObjC.use('NSString').alloc().initWithData_encoding_(sdata, 4).toString().replace(/\s+/g, '');
    }
}

if (tag === seen) {
    print('NO_UPDATE tag=' + tag);
} else {
    var out = { tag: tag, seen: seen, debUrl: debUrl || '' };
    if (debUrl) {
        var durl = ObjC.use('NSURL').URLWithString_(debUrl);
        var ddata = ObjC.use('NSData').dataWithContentsOfURL_(durl);
        if (ddata) {
            var dest = '/var/mobile/Documents/apelin-' + tag + '.deb';
            var ok = ddata.writeToFile_atomically_(dest, true);
            out.downloaded = ok ? 'true' : 'false';
            out.dest = dest;
            out.size = String(ddata.length());
        } else {
            out.downloaded = 'false';
            out.reason = 'deb data nil';
        }
    }
    print('UPDATE ' + JSON.stringify(out));
    // 更新本地基准
    ObjC.use('NSString').stringWithString_(tag + '\n').writeToFile_atomically_encoding_error_(seenPath, true, 4, null);
}
