---
name: load-all-skills-memory-repos
description: 硬性规定：任何对话、任何工程开工前，必须把本机全部本地技能包、全部记忆（含其他工程/其他对话）、以及用户 GitHub 云端（仅越狱插件相关的 yangzhou521/AxsTweakKit 与 yangzhou-DualSlice）的技能与项目全部调用一遍再动手，并保持本机与云端技能同步。
---

# 硬性规定：每轮开工先调用「本机全部技能 + 全部记忆 + GitHub 云端（仅越狱插件仓库）的技能与项目」

> **这是用户定下的硬性规定**，写在这里、也写进用户各工程的 AGENTS.md 与全局记忆里。
> 用户 2026-10-30 多次要求，原话：
> 「本机的全部本地技能包加上我的 github 仓库的项目都要调用！结合使用！这个写在硬性规定和本机记忆同步到 github 云端！本次和下次和以后所有对话和工程全部调用！」
> 「以后要调用本机、本地的全部技能包和全部记忆和我的 github 云端的全部技能和项目！写成硬性规定进入技能包内！」
> 「仓库清单查到了一共 4 个 只写入的越狱插件相关的项目!别的不要动！」
>
> **动手之前把这些全部调用一遍：不许只挑一份，不许凭记忆代替真读，不许跳过记忆；账号下与越狱插件无关的仓库一律不写、不动、不碰。**

## 0. 顺序

1. 本机技能包（逐份真读）→ 2. 全部记忆（含别的工程/对话）→ 3. GitHub 云端（仅越狱插件仓库）的技能与项目 → 4. 改完把两边同步（含本技能包本身的任何改动）。任何一步漏了，等于没按约定干活，要在汇报里说清漏了哪一步。

## 1. 本机全部技能包（逐份真读）

```
apelin_skill_list                 # 先看清单（用户随时可能新增技能）
apelin_skill_read a11-roothide-ondevice
apelin_skill_read axs-ios-tweaks
apelin_skill_read respring-notify-countdown
apelin_skill_read load-all-skills-memory-repos
apelin_skill_read icli-status-self-check
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

## 3. GitHub 云端（**只用越狱插件相关的两个仓库**）

| 仓库 | 分支 | 是什么 |
| --- | --- | --- |
| `yangzhou521/AxsTweakKit` | `master` | 越狱工程工具箱：模板 `Templates/AxsDualSlice`、生成/自检脚本、CI 工作流模板、命名空间与面板写法约定。**新插件、新工程优先复用它的形状。** |
| `yangzhou521/yangzhou-DualSlice` | `main` | 实际产品与脚本：ThemeCorePlus（主题引擎 + 设置面板）、CountdownHUD（倒计时胶囊）、`scripts/*.sh`、`skills/`（云端技能副本）、各条 CI 工作流 |

- **账号下其它仓库（BPB-Worker-Panel、edgetunnel 这类 fork，与越狱插件无关）不写、不动、不碰，也不引用。** 即使是同一个账号，也不要顺手去改、去提交、去删。
- **云端技能** = `yangzhou-DualSlice` 的 `skills/` 目录（本机技能目录的版本化副本）＋ `AxsTweakKit` 里的模板与脚本。本机与云端不一致时，先同步（第 4 步）再动手。
- 读云端文件：`apelin_web_fetch`（页面 / API / raw 文件）；或 `icli probe` + `NSData`/`NSURLForString` 拉 `raw.githubusercontent.com`、`api.github.com`（本机没有 curl/wget/python3，也没有 web 搜索；GitHub 匿名 API 有每小时限速，被限了过一会儿再试）。
- 写新东西前先看这两个仓库里已有的同类实现，不另起一套。

## 4. 两边保持一致（云端同步）

本机技能目录改动后（包括本文件本身）：

```
sh scripts/sync-skills.sh        # 本机技能目录 → 仓库 skills/（脚本在 yangzhou-DualSlice）
```

再 `git_commit` + `git_push` 到对应分支（本仓库 `main`，AxsTweakKit 是 `master`）。**只有本机改了、没 push，就等于没同步；云端改了、没拉回本机，别的对话也读不到。**

## 5. 与其它硬性约定一起用（不许只顾这一条）

- **设备状态自己查（用户 2026-10-30 16:30 全权限）**：要设备/插件/云端此刻状态才能决定下一步的事，一律自己用 `icli` / `irisin-cli` / `icli probe` + `NSData` / GitHub API 查完再汇报，不把查询推回用户、不让他截图或读屏替我（详见技能 `icli-status-self-check`）。
- 装包 / 注销（respring）/ 杀进程前：`respring-notify-countdown` 的通知 + 正文里 5 秒倒计时（本机唯一注销入口 `sh scripts/respring-guard.sh`）。全权限不免这条仪式。
- 离开 Apelin 取证：桌面 / 插件设置内 / 别的 App 三类去处统一 60 秒硬上限，且必须自己回来；外出前预告、回来交代并写清秒数。
- 本机编不了任何东西（A11 缺 FEAT_LRCPC）：一律 GitHub Actions 云编译 arm64 + arm64e 双切片，再用 `irisin-cli install` 装到本机、重启进程读诊断验证。
