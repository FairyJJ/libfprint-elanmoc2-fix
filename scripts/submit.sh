#!/bin/bash
# 一键准备上游提交：clone elanmoc2 分支 → apply 补丁 → commit
# 只在本地 /tmp 操作，不推送任何东西。push 命令由本脚本最后打印。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLONE=/tmp/lfp-upstream
URL=https://gitlab.freedesktop.org/Depau/libfprint.git
BRANCH=elanmoc2
PUSHBR=elanmoc2-fix-verify-uaf

if [ ! -d "$CLONE/.git" ]; then
    echo "== clone $BRANCH =="
    rm -rf "$CLONE"
    git clone --depth 1 -b "$BRANCH" "$URL" "$CLONE"
fi
cd "$CLONE"

echo "== HEAD =="
git log -1 --format="%h %s"

echo "== apply patch =="
git apply --check "$ROOT/patch/elanmoc2-verify-retry-fix.patch"
git apply "$ROOT/patch/elanmoc2-verify-retry-fix.patch"
git diff --stat

echo "== commit =="
git -c user.name="FairyJJ" -c user.email="FairyJJ@users.noreply.github.com" \
    commit -a -F "$ROOT/docs/commit-message.txt"
git log -1 --format="%h %s"

cat <<EOF

== 完成。推送并自动开 MR（把 <user> 换成你的 gitlab 用户名）：
   cd $CLONE
   git remote add mine https://gitlab.freedesktop.org/<user>/libfprint.git
   git push -o merge_request.create=true \\
            -o merge_request.title="elanmoc2: Fix use-after-free and double-report on verify retry" \\
            -o merge_request.target_project=Depau/libfprint \\
            -o merge_request.target_branch=$BRANCH \\
            mine HEAD:$PUSHBR
EOF
