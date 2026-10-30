// ci-status.js —— 读一次 GitHub Actions 的运行状态，只打印关心的几个字段。
const runId = 41125249209;
const url = 'https://api.github.com/repos/yangzhou521/yangzhou-DualSlice/actions/runs/' + runId;
const nsurl = ObjC.use('NSURL').URLWithString_(url);
const data = ObjC.use('NSData').dataWithContentsOfURL_(nsurl);
if (!data) throw new Error('no data');
const text = ObjC.use('NSString').alloc().initWithData_encoding_(data, 4);
const json = JSON.parse(String(text));
const out = ['status=' + json.status, 'conclusion=' + json.conclusion,
             'updated=' + json.updated_at];
if (json.conclusion && json.conclusion !== 'success') out.push('bad=' + json.conclusion);
out.join(' | ');
