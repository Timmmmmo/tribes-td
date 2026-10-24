#!/usr/bin/env bash
# 用 GitHub PAT 一键把 Tribes TD 部署到 GitHub Pages。
#
# 用法：
#   GH_TOKEN=ghp_xxx bash tools/deploy_github.sh [仓库名]
#
# 需要的权限（Classic PAT）：repo + workflow
# 脚本会依次做：验 token → 建仓库（已存在则复用）→ 推 main → 开 Pages → 等构建 → 打印可玩链接。
#
# 如果 token 没有 workflow 权限（推不动 .github/workflows/），
# 脚本会自动退化成「把 web/ 推到 gh-pages 分支 + 用分支方式开 Pages」，一样能出链接。

set -uo pipefail

API="https://api.github.com"
REPO_NAME="${1:-tribes-td}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

die() { echo "✗ $*" >&2; exit 1; }

[ -n "${GH_TOKEN:-}" ] || die "缺少 GH_TOKEN"

api() { # method path [json]
  local m="$1" p="$2" d="${3:-}"
  if [ -n "$d" ]; then
    curl -sS -X "$m" -H "Authorization: token $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" -H "User-Agent: tribes-td-deploy" \
      -H "Content-Type: application/json" -d "$d" "$API$p"
  else
    curl -sS -X "$m" -H "Authorization: token $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" -H "User-Agent: tribes-td-deploy" "$API$p"
  fi
}

json() { python -c "import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$1"; }

# ---------------------------------------------------------------- 1) 验 token
echo "==> 校验 token"
ME="$(api GET /user)"
LOGIN="$(printf '%s' "$ME" | json "d.get('login','')" 2>/dev/null || true)"
[ -n "$LOGIN" ] || die "token 无效：$(printf '%s' "$ME" | json "d.get('message','?')")"
echo "    账号：$LOGIN"

SLUG="$LOGIN/$REPO_NAME"

# ---------------------------------------------------------------- 2) 建仓库
echo "==> 创建仓库 $SLUG"
RES="$(api POST /user/repos "{\"name\":\"$REPO_NAME\",\"private\":false,\"has_issues\":false,\"has_wiki\":false,\"description\":\"六部族塔防：双资源塔防的 Godot 实现与可玩 Web 版\"}")"
if printf '%s' "$RES" | grep -q '"full_name"'; then
  echo "    已创建"
elif printf '%s' "$RES" | grep -q 'already exists'; then
  echo "    仓库已存在，复用"
else
  die "建仓库失败：$(printf '%s' "$RES" | json "d.get('message','?')")"
fi

# ---------------------------------------------------------------- 3) 推送
echo "==> 重新打包 web/index.html"
python tools/build_web.py >/dev/null || die "打包失败"

PUSH_URL="https://x-access-token:${GH_TOKEN}@github.com/${SLUG}.git"
git -c credential.helper= remote remove origin >/dev/null 2>&1 || true
git -c credential.helper= remote add origin "https://github.com/${SLUG}.git"

git add -A
git diff --cached --quiet || git -c user.name="$LOGIN" -c user.email="${LOGIN}@users.noreply.github.com" \
  commit -q -m "build: 更新 web 单文件产物" || true

MODE="workflow"
echo "==> 推送 main"
if ! git -c credential.helper= push -q "$PUSH_URL" HEAD:main 2>/tmp/push.err; then
  if grep -qi "workflow" /tmp/push.err; then
    echo "    token 缺少 workflow 权限，改用 gh-pages 分支模式"
    MODE="branch"
  else
    cat /tmp/push.err >&2
    die "推送失败"
  fi
fi

# ---------------------------------------------------------------- 4) 开 Pages
if [ "$MODE" = "workflow" ]; then
  echo "==> 开启 Pages（GitHub Actions 模式）"
  api POST "/repos/${SLUG}/pages" '{"build_type":"workflow"}' >/dev/null
  api PUT  "/repos/${SLUG}/pages" '{"build_type":"workflow"}' >/dev/null
  api POST "/repos/${SLUG}/actions/workflows/pages.yml/dispatches" '{"ref":"main"}' >/dev/null
else
  echo "==> 准备 gh-pages 分支（只放 web/ 的内容）"
  TMP="$(mktemp -d)"
  cp -r web/. "$TMP"/
  rm -rf "$TMP/src" "$TMP/dev.html"
  ( cd "$TMP" && git init -q -b gh-pages \
      && git -c user.name="$LOGIN" -c user.email="${LOGIN}@users.noreply.github.com" add -A \
      && git -c user.name="$LOGIN" -c user.email="${LOGIN}@users.noreply.github.com" commit -q -m "deploy: web build" \
      && git -c credential.helper= push -q -f "$PUSH_URL" HEAD:gh-pages )
  rm -rf "$TMP"
  echo "==> 开启 Pages（分支模式）"
  api POST "/repos/${SLUG}/pages" '{"source":{"branch":"gh-pages","path":"/"}}' >/dev/null
  api PUT  "/repos/${SLUG}/pages" '{"source":{"branch":"gh-pages","path":"/"}}' >/dev/null
fi

# ---------------------------------------------------------------- 5) 等构建
echo "==> 等待 Pages 构建（最多 3 分钟）"
URL="https://$(printf '%s' "$LOGIN" | tr 'A-Z' 'a-z').github.io/${REPO_NAME}/"
for i in $(seq 1 36); do
  sleep 5
  ST="$(api GET "/repos/${SLUG}/pages" | json "d.get('status','')" 2>/dev/null || echo '')"
  CODE="$(curl -s -o /dev/null -w '%{http_code}' "$URL")"
  printf '    [%02d] pages=%s http=%s\n' "$i" "${ST:-?}" "$CODE"
  if [ "$CODE" = "200" ]; then
    echo
    echo "✓ 部署完成，可玩链接："
    echo "  $URL"
    exit 0
  fi
done

echo
echo "构建还没跑完，链接照这个用（通常再过一两分钟就好）："
echo "  $URL"
echo "  Actions 进度：https://github.com/${SLUG}/actions"
