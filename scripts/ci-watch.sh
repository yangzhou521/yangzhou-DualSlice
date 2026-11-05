#!/bin/sh
# ci-watch.sh —— 云编译守护壳脚本
# 用法：sh scripts/ci-watch.sh
# 被 LaunchDaemon（StartInterval=60）或 agent 手动调用；不依赖 agent 存活。
# 通过动态发现当前 jbroot hash，避免随重越狱而失效。
set -u
# 动态发现 jbroot：遍历容器路径查找 .jbroot-<hash> 模式
CONTAINER_DIR="/private/var/containers/Bundle/Application"
JBROOT_HASH=$(ls -d "${CONTAINER_DIR}"/.jbroot-* 2>/dev/null | head -1 | sed 's|.*/..jbroot-||' || echo "E310C5932A2403A8")
export APELIN_PROJECT_ROOT="${APELIN_PROJECT_ROOT:-/private/var/containers/Bundle/Application/.jbroot-${JBROOT_HASH}/var/mobile/Documents/wiki.qaq.apelin/Projects/yangzhouDualSlice}"
cd "$APELIN_PROJECT_ROOT" || exit 1
icli probe scripts/ci-watch.js
