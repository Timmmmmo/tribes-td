#!/usr/bin/env bash
# 把 Tribes TD 推到 GitHub 并开启 Pages。
#
# 用法：
#   bash tools/push_github.sh <你的GitHub用户名>/tribes-td
#
# 前提：本机已经能对 GitHub 免密推送（HTTPS 走凭据管理器 / SSH key 任一即可）。
# 脚本只做三件事：建 remote、推送、告诉你去哪儿开 Pages。

set -euo pipefail

REPO="${1:-}"
if [ -z "$REPO" ]; then
  echo "用法: bash tools/push_github.sh <用户名>/<仓库名>" >&2
  echo "例:   bash tools/push_github.sh hjzha/tribes-td" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 1) 保证 web/index.html 是最新的（单文件产物，源码在 web/src/）
echo "==> 重新打包 web/index.html"
python tools/build_web.py

# 2) 没有远端就加，有了就改
REMOTE="https://github.com/${REPO}.git"
if git remote get-url origin >/dev/null 2>&1; then
  echo "==> 更新 origin -> $REMOTE"
  git remote set-url origin "$REMOTE"
else
  echo "==> 添加 origin -> $REMOTE"
  git remote add origin "$REMOTE"
fi

# 3) 提交 + 推送
echo "==> 提交"
git add -A
if ! git diff --cached --quiet; then
  git commit -m "build: 更新 web 单文件产物"
fi

echo "==> 推送 main"
git push -u origin main

BRANCH="$(git rev-parse --abbrev-ref HEAD)"

cat <<EOF

推送完成。接下来手动做一步（GitHub 不允许脚本直接开 Pages）：

  1. 打开 https://github.com/${REPO}/settings/pages
  2. Source 选 "GitHub Actions"
  3. 等 Actions 里 "Deploy playable web build to GitHub Pages" 跑完（约 1 分钟）

可玩链接：
  https://$(echo "$REPO" | cut -d/ -f1).github.io/$(echo "$REPO" | cut -d/ -f2)/

（工作流文件：.github/workflows/pages.yml，只发布 web/ 目录，零构建。
 当前分支：$BRANCH）
EOF
