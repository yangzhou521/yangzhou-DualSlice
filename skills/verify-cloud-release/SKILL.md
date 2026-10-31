---
name: verify-cloud-release
description: After a GitHub Actions cloud build produces a release, or before reporting its state: re-query the run status right before you report (never trust an earlier in-progress read), and use the GitHub compare API (base...head) to list the actual changed files so you can prove a fix did not leak into unrelated files (e.g. a tweak's business-logic source). Also: git reflog/log lines are "old new … message" (two SHA columns) — do not misattribute commit messages to the wrong SHA.
---

# 云编译产物：发布前验纯度、报状态前重查

本机无法编译，所有 .deb 都走 GitHub Actions 双切片云编译。我们常需要：① 告诉用户某次 run 成功/失败；② 证明某次 Release 只包含预期改动、没把无关文件（比如某 tweak 的业务逻辑源文件）带进去。

## 1. 报 CI 状态前，先重查一次
你早些时候读到的 `in_progress` 可能几分钟后就 `completed` 了。在**向用户陈述成功/失败之前**，重新拉一次状态，不要拿旧读数当现况：
- 单 run：`https://api.github.com/repos/<owner>/<repo>/actions/runs/<run_id>` 看 `status`/`conclusion`。
- 最近几次：`https://api.github.com/repos/<owner>/<repo>/actions/runs?per_page=5`。
- 工具：`apelin_web_fetch`（匿名，有每小时限速，被限了等一会儿再试）；本机没有 curl/wget/python3。

## 2. 用 compare API 证明 Release 的变更文件
要证明「文件 X 没有混进这次发布」：取发布提交 R 与基线提交 B，拉
`https://api.github.com/repos/<owner>/<repo>/compare/B...R`，
读 `files[]`（每项 `filename`/`status`/`additions`/`deletions`）即为真实改动清单；`ahead_by`/`behind_by`/`total_commits` 顺便确认没有分叉。
- 实例：用 `5811a2b6...cb3a307b` 核实 `ThemeCorePlusLayout.m` **不在** 0.9.24 的变更里 —— 于是 0.9.24 的布局代码与 0.9.23 逐字节相同，装它不会让布局诊断失真。
- 注意 B...R 的方向：base 在前、head 在后；`files` 是 base→head 的净差异。

## 3. 正确读 git 历史，别张冠李戴
`.git/logs/HEAD` 每行是 `<old> <new> <author> <date> commit: <msg>`：两个 SHA 是「父 → 子」，后面的 message 属于 `<new>`（子提交）。读的时候别把 message 当成另一个 SHA 的，否则会误报「提交说明被覆盖 / 历史交错」。判断是否有并发提交相互覆盖，以**云端 compare 的 files 与 ahead/behind** 为准，不靠本地日志猜。

## 4. 沉淀
任何可复用的「验证 / 调试纪律」（像上面这三条）本身也要存成技能包并同步云端——这是用户定的硬规矩：解决/化解冲突后 → 写技能 → 上传，不许只改代码不沉淀。
