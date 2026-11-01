# 断点续做机制（本设备落地版）

> 来源：用户 2026-11-01 附件《第三方智能体断点续做·合并精简版》+ 本机实操校准。
> 原则一句话：**状态外置 + 自动恢复 + 恢复前重校验权限**。

## 一、为什么不用附件里那些工具

附件三类方案（tidebase / lh-harness / LangGraph / Dapr / djobs…）都要 Python/Node、独立服务或
LangGraph 运行时 —— **本机没有工具链、没有 python3/node，也不能装**。所以只借它们的思路，
落地成本为零的两个文件：

| 附件概念 | 本机实现 |
| --- | --- |
| 外部可恢复运行时状态 | `scripts/WORK-STATE.md`（人读）+ `scripts/WORK-STATE.json`（机读） |
| checkpoint / resume | 每轮开头读 json，`status=running` 就接着干，不等指令 |
| Epistemic Savepoints（存假设与决策） | json 的 `why` 字段：记「为什么这么干」，防止重开后推翻自己的判断 |
| 恢复前重校验权限（最重要） | `guard` 字段：恢复时重读冻结清单、确认要动设备仍走弹窗、确认包版本没被别人改 |

## 二、本机版规则（已写进 AGENTS.md ㊵ / 记忆）

1. **每轮第一件事**读 `scripts/WORK-STATE.json`（`sh scripts/work-state.sh get`）。
2. **每轮最后一件事件**更新它（`sh scripts/work-state.sh set ...`）。
3. `status=running` → 直接接着做；`blocked` → 只有当轮弹框请用户拍板；`done` → 报结果并清空。
4. 用户中途插话 → 办完立刻回来，报「已回到 XXX 继续」，不反问。
5. **恢复时不信自己**：核对 `guard` 里的三项再动手。

## 三、我的意见：这套要真有用，得补三条

1. **断点必须带「证据指纹」**：只写「1.0.24 已编译」会被时间骗，要写 commit sha + run id。
   恢复时先比它们，对不上就当没做（我已在 json 里用 `evidence` 字段）。
2. **一条主线只有一个断点**：多写会分叉、会互相覆盖，旧任务进 `docs/cases/` 而不是塞进 WORK-STATE。
3. **恢复后第一动作是「读现场」不是「读自己」**：先查设备/CI 的真实状态（`dpkg -l`、`ci-status.js`、
   诊断键），再对照断点。断点是假设，现场才是事实 —— 这条比附件里任何工具都重要。
