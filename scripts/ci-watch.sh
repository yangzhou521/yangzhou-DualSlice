#!/bin/sh
# ci-watch.sh —— 云编译守护壳脚本
# 用法：sh scripts/ci-watch.sh
# 被 LaunchDaemon（StartInterval=60）或 agent 手动调用；不依赖 agent 存活。
set -u
export APELIN_PROJECT_ROOT="${APELIN_PROJECT_ROOT:-/private/var/containers/Bundle/Application/.jbroot-E310C5932A2403A8/var/mobile/Documents/wiki.qaq.apelin/Projects/yangzhouDualSlice}"
cd "$APELIN_PROJECT_ROOT" || exit 1
icli probe scripts/ci-watch.js
