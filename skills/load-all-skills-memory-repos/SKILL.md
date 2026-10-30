---
name: load-all-skills-memory-repos
description: 硬性规定：任何对话、任何工程开工前，必须把本机全部本地技能包、全部记忆（含其他工程/其他对话）、以及用户 GitHub 云端（仅越狱插件相关的 yangzhou521/AxsTweakKit 与 yangzhou-DualSlice）的技能与项目全部调用一遍再动手，并保持「硬性规定 + 技能包 + 记忆」三样本机与云端同步。
---

# 硬性规定：每轮开工先调用「本机全部技能 + 全部记忆 + GitHub 云端（仅越狱插件仓库）的技能与项目」

> **这是用户定下的硬性规定**，写在这里、也写进用户各工程的 AGENTS.md 与全局记忆里。
> 用户 2026-10-30 多次要求，原话：
> 「本机的全部本地技能包加上我的 github 仓库的项目都要调用！结合使用！这个写在硬性规定和本机记忆同步到 github 云端！本次和下次和以后所有对话和工程全部调用！」
> 「以后要调用本机、本地的全部技能包和全部记忆和我的 github 云端的全部技能和项目！写成硬性规定进入技能包内！」
> 「仓库清单查到了一共 4 个 只写入的越狱插件相关的项目!别的不要动！」
> 「本机上硬性规定、技能包和记忆以后同步上传云端 以后同步修改」（2026-10-30 17:19）
> 「云端修改只针对越狱插件项目！这也是硬性规定和记忆、技能包现在一起同步本机和云端」（2026-10-30 17:2x）
> 「我云端的非越狱插件项目永久不要动！这也是硬性规定和记忆、技能包现在一起同步本机和云端！」（2026-10-30 17:2x）
>
> **动手之前把这些全部调用一遍：不许只挑一份，不许凭记忆代替真读，不许跳过记忆；账号下与越狱插件无关的仓库一律永久不写、不动、不碰。**

## 0. 顺序

1. 本机技能包（逐份真读）→ 2. 全部记忆（含别的工程/对话）→ 3. GitHub 云端（仅越狱插件仓库）的技能与项目 → 4. 改完把**硬性规定 + 技能包 + 记忆三样**同步到云端。任何一步漏了，等于没按约定干活，要在汇报里说清漏了哪一步。

## 1. 本机全部技能包（逐份真读）

```
apelin_skill_list                 # 先看清单（用户随时可能新增技能）
apelin_skill_read a11-roothide-ondevice
apelin_skill_read axs-ios-tweaks
apelin_skill_read respring-notify-countdown
apelin_skill_read load-all-skills-memory-repos
apelin_skill_read icli-status-self-check
apelin_skill_read settings-switch-ui
```

- 本机技能目录（Apelin 真正读的那份）：`~/Documents/wiki.qaq.apelin/skills/`。清单里出现上面之外的，一并读。
- Apelin 内置技能（`apelin-tweak-development`、`apelin-bootstrap-paths`、`apelin-tweak-runtime`、`apelin-preference-bundle`、`apelin-project-description`、`apelin-external-build`、`apelin-device-executables`、`apelin-packaging-and-install`、`apelin-package-dependencies`、`apelin-crash-triage`、`apelin-icli`、`apelin-git-workflow`、`apelin-package-repository`）按任务需要读；命中的那份动手前必须读。

## 2. 全部记忆

```
apelin_memory_list                                  # 本工程 + 所有对话
apelin_memory_list all_projects: true               # 全部工程、全部对话
apelin_memory_list project: <folder|projectID>      # 指定别的工程
```

- 动手前把与本次任务有关的结论、坑、约定读完（尤其是别的工程已经踩过的坑）。
- 有新结论用 `apelin_memory_save` 写回；用户级偏好用 `scope: global`，工程事实用默认 project；更新已有记录要带 `apelin_memory_list` 给的 revision。
- 记忆与用户当前原话冲突时，以用户当前原话为准；被用户纠正过的内容不许照旧写回。
- 本机记忆文件：`~/Documents/wiki.qaq.apelin/memories.json`（Apelin 真正读的那份）。

## 3. GitHub 云端（**只用越狱插件相关的两个仓库**）

| 仓库 | 分支 | 是什么 |
| --- | --- | --- |
| `yangzhou521/AxsTweakKit` | `master` | 越狱工程工具箱：模板 `Templates/AxsDualSlice`、生成/自检脚本、CI 工作流模板、命名空间与面板写法约定。**新插件、新工程优先复用它的形状。** |
| `yangzhou521/yangzhou-DualSlice` | `main` | 实际产品与脚本：ThemeCorePlus（主题引擎 + 设置面板）、CountdownHUD（倒计时胶囊）、`scripts/*.sh`、`skills/`（云端技能副本）、`memory/`（云端记忆副本）、各条 CI 工作流 |

- **账号下其它仓库（BPB-Worker-Panel、edgetunnel 这类 fork，与越狱插件无关）永久不写、不动、不碰，也不引用。** 即使是同一个账号，也不要顺手去改、去提交、去删；「永久」= 以后每一次、每一个对话、每一个工程都算，不需要用户再交代。
- **云端的一切「修改」只针对这两个越狱插件项目，非越狱插件项目永久不碰**（用户 2026-10-30 17:2x 再次强调：「我云端的非越狱插件项目永久不要动！」，并要求这条与记忆、技能包一起同步本机与云端）：提交、push、建仓库、改工作流、开 issue 只落在 `AxsTweakKit` 与 `yangzhou-DualSlice`；账号下其它仓库不提交、不推送、不新建、不改设置、不提 issue、不删、不当参照系、读都不读。就是在允许的仓库上，新建仓库、发 issue 这类动作也要用户明确同意后才做。
- **本地与云端一起同步**：改完这三样（硬性规定 + 技能包 + 记忆）要一次 `sh scripts/sync-all.sh`（或 `sync-skills.sh` / `sync-memory.sh`）镜像到仓库，再同一个 `git_commit(all: true)` + `git_push` 上 `yangzhou-DualSlice` 的 `main`，不留半截状态。
- **云端技能** = `yangzhou-DualSlice` 的 `skills/` 目录（本机技能目录的版本化副本）＋ `AxsTweakKit` 里的模板与脚本。本机与云端不一致时，先同步（第 4 步）再动手。
- 读云端文件：`apelin_web_fetch`（页面 / API / raw 文件）；或 `icli probe` + `NSData`/`NSURLForString` 拉 `raw.githubusercontent.com`、`api.github.com`（本机没有 curl/wget/python3，也没有 web 搜索；GitHub 匿名 API 有每小时限速，被限了过一会儿再试）。
- 写新东西前先看这两个仓库里已有的同类实现，不另起一套。

## 4. 三样保持一致（云端同步：硬性规定 + 技能包 + 记忆）

用户 2026-10-30 17:19 原话：「本机上硬性规定、技能包和记忆以后同步上传云端 以后同步修改」。

| 什么 | 本机（Apelin 真正读的） | 云端（仓库里） | 怎么同步 |
| --- | --- | --- | --- |
| 硬性规定 | 工程 `AGENTS.md`（同类条文也在 `skills/*/SKILL.md`） | 仓库根 `AGENTS.md` | 就是仓库文件，push 即上传 |
| 技能包 | `~/Documents/wiki.qaq.apelin/skills/` | `skills/` | `sh scripts/sync-skills.sh [push\|pull]` |
| 记忆 | `~/Documents/wiki.qaq.apelin/memories.json` | `memory/memories.json` | `sh scripts/sync-memory.sh [push\|pull\|diff]` |

```
sh scripts/sync-all.sh           # 一把三样：AGENTS.md 核对 + 技能 push + 记忆 push
sh scripts/sync-all.sh diff      # 只比差异，不动文件
```

再 `git_commit`（`all: true`，三样在同一提交里）+ `git_push` 到对应分支（本仓库 `main`，AxsTweakKit 是 `master`）。**只有本机改了、没 push，就等于没同步；云端改了、没拉回本机，别的对话也读不到。** 不留「本机改了、云端还是旧版」的半截状态；`pull`（含 `sync-memory.sh pull`）会覆盖本机，先看它打印的 diff 再确认。

## 5. 与其它硬性约定一起用（不许只顾这一条）

- **设备状态自己查（用户 2026-10-30 16:30 全权限）**：要设备/插件/云端此刻状态才能决定下一步的事，一律自己用 `icli` / `irisin-cli` / `icli probe` + `NSData` / GitHub API 查完再汇报，不把查询推回用户、不让他截图或读屏替我（详见技能 `icli-status-self-check`）。
- 装包 / 注销（respring）/ 杀进程前：`respring-notify-countdown` 的通知 + 正文里 5 秒倒计时（本机唯一注销入口 `sh scripts/respring-guard.sh`）。全权限不免这条仪式。
- 离开 Apelin 取证：桌面 / 插件设置内 / 别的 App 三类去处统一 60 秒硬上限，且必须自己回来；外出前预告、回来交代并写清秒数。
- 系统设置里的插件面板：凡有「选择 / 开关」一律 iOS 原生 `UISwitch`，不用对号（技能 `settings-switch-ui`）。
- 本机编不了任何东西（A11 缺 FEAT_LRCPC）：一律 GitHub Actions 云编译 arm64 + arm64e 双切片，再用 `irisin-cli install` 装到本机、重启进程读诊断验证。
