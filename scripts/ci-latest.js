// ci-latest.js —— 读 main 上最近几次 Actions 运行（含排队/进行中），打印关心的字段。
const url = 'https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs?branch=main&per_page=4';
const nsurl = ObjC.use('NSURL').URLWithString_(url);
const data = ObjC.use('NSData').dataWithContentsOfURL_(nsurl);
if (!data) throw new Error('no data');
const text = ObjC.use('NSString').alloc().initWithData_encoding_(data, 4);
const json = JSON.parse(String(text));
const runs = json.workflow_runs || [];
runs.map(function (r) {
  return [r.id, (r.head_sha || '').slice(0, 8), r.name, r.status, r.conclusion || '-', r.created_at].join(' ');
}).join('\n');
