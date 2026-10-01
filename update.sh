#!/usr/bin/env bash
# ============================================================
# 热血玛法 1.76 —— 一键更新上线
# ------------------------------------------------------------
# 用法：
#   ./update.sh                     使用默认提交信息
#   ./update.sh "修了法师技能伤害"    自定义提交信息
#
# 认证（二选一，凭据不落盘）：
#   A. 环境变量： export GH_TOKEN=ghp_xxx && ./update.sh
#   B. 已登录 gh： gh auth login  之后直接 ./update.sh
#
# 它会依次做：
#   1. 检查环境（git / 远程 / 工作区状态）
#   2. 跑 deploy.py 生成新版本号（这一步是关键，不能省）
#   3. 提交 + 推送
#   4. 轮询 GitHub Pages 构建状态直到完成
#   5. 线上实测 index.html / sw.js / manifest.json 是否 200
#   6. 校验线上 sw.js 的版本号与本地一致
# ============================================================
set -uo pipefail

REPO="pohiMin/malfa"
SITE="https://pohimin.github.io/malfa"
MSG="${1:-更新游戏内容}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- 配色 ----------
if [ -t 1 ]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[36m'; N=$'\033[0m'; BOLD=$'\033[1m'
else
  G=''; R=''; Y=''; B=''; N=''; BOLD=''
fi
ok()   { printf '  %s✔%s %s\n' "$G" "$N" "$1"; }
err()  { printf '  %s✘%s %s\n' "$R" "$N" "$1"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$1"; }
info() { printf '  %s·%s %s\n' "$B" "$N" "$1"; }
step() { printf '\n%s%s%s\n' "$BOLD" "$1" "$N"; }

cd "$DIR" || { err "无法进入目录 $DIR"; exit 1; }

printf '%s\n' "============================================================"
printf '%s\n' "热血玛法 1.76 —— 一键更新上线"
printf '%s\n' "============================================================"
printf '  目标：%s\n' "$REPO"
printf '  提交：%s\n' "$MSG"

# ============ 1. 环境检查 ============
step "[1/6] 环境检查"

command -v git >/dev/null 2>&1 || { err "未安装 git"; exit 1; }
ok "git 可用（$(git --version | awk '{print $3}')）"

command -v python3 >/dev/null 2>&1 || { err "未安装 python3"; exit 1; }
ok "python3 可用"

[ -f deploy.py ]     || { err "缺少 deploy.py"; exit 1; }
[ -f index.html ]    || { err "缺少 index.html"; exit 1; }
[ -f sw.js ]         || { err "缺少 sw.js"; exit 1; }
ok "必需文件齐全"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  err "当前目录不是 git 仓库（应先 git init 并关联远程）"
  exit 1
fi
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
ok "git 仓库正常（分支 $BRANCH）"

if ! git remote get-url origin >/dev/null 2>&1; then
  err "未配置远程 origin"
  exit 1
fi
REMOTE_URL="$(git remote get-url origin)"
ok "远程已配置：$REMOTE_URL"

# 安全检查：远程 URL 里不该内嵌令牌
if printf '%s' "$REMOTE_URL" | grep -qE 'ghp_|github_pat_|:[^/@]+@'; then
  warn "远程 URL 内嵌了凭据，正在清理…"
  git remote set-url origin "https://github.com/${REPO}.git"
  ok "已清理为 https://github.com/${REPO}.git"
fi

# 认证方式：环境变量优先，其次 gh
AUTH=""
if [ -n "${GH_TOKEN:-}" ]; then
  AUTH="env"
  ok "使用环境变量 GH_TOKEN 认证"
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  AUTH="gh"
  ok "使用 gh CLI 已登录凭据认证"
else
  warn "未检测到可用凭据（GH_TOKEN 未设置，gh 也未登录）"
  warn "推送时可能要求输入用户名/密码，届时用 token 作为密码即可"
  AUTH="none"
fi

# ============ 2. 生成新版本号 ============
step "[2/6] 生成新版本号"
OLD_VER="$(grep -oP "CACHE_VERSION = '\K[^']+" sw.js || echo '未知')"
info "当前版本：$OLD_VER"

if ! python3 deploy.py; then
  err "deploy.py 执行失败，已中止"
  exit 1
fi

NEW_VER="$(grep -oP "CACHE_VERSION = '\K[^']+" sw.js || echo '未知')"
if [ "$NEW_VER" = "$OLD_VER" ]; then
  warn "版本号没变（$NEW_VER）—— 浏览器可能不会触发更新"
  warn "如果确实改动了 index.html，请确认 deploy.py 正常写入"
else
  ok "版本号已更新：$OLD_VER → $NEW_VER"
fi

# ============ 3. 提交并推送 ============
step "[3/6] 提交并推送"

if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
  warn "工作区没有变化，无需推送"
  SKIP_PUSH=1
else
  SKIP_PUSH=0
  git add -A
  CHANGED="$(git diff --cached --name-only | wc -l | tr -d ' ')"
  ok "待提交文件：$CHANGED 个"
  git diff --cached --name-only | sed 's/^/      /'

  if ! git commit -q -m "$MSG"; then
    err "提交失败"
    exit 1
  fi
  ok "已提交：$MSG"

  export GIT_TERMINAL_PROMPT=0
  PUSH_URL="$REMOTE_URL"
  [ "$AUTH" = "env" ] && PUSH_URL="https://pohiMin:${GH_TOKEN}@github.com/${REPO}.git"

  if timeout 300 git push "$PUSH_URL" "$BRANCH:$BRANCH" 2>&1 | tail -5; then
    ok "推送成功"
  else
    err "推送失败"
    err "常见原因：凭据无效/已作废、网络不通、权限不足"
    exit 1
  fi
fi

if [ "${SKIP_PUSH:-0}" = "1" ]; then
  info "跳过推送，直接进入线上校验"
fi

# ============ 4. 等待 Pages 构建 ============
step "[4/6] 等待 GitHub Pages 构建"
BUILT=0
for i in $(seq 1 24); do
  if [ -n "${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
    ST="$(GH_TOKEN="$GH_TOKEN" timeout 30 gh api "repos/${REPO}/pages/builds/latest" \
          --jq '.status' 2>/dev/null || echo '?')"
  else
    ST='?'
  fi
  case "$ST" in
    built)   ok "构建完成（第 ${i} 次查询）"; BUILT=1; break ;;
    errored) err "构建报错，请查看 https://github.com/${REPO}/actions"; break ;;
    building) info "[$i] 构建中…" ;;
    *)       info "[$i] 状态未知，继续等待…" ;;
  esac
  sleep 10
done
[ "$BUILT" = "1" ] || warn "未能确认构建完成，继续做线上实测"

# ============ 5. 线上实测 ============
step "[5/6] 线上实测"
sleep 5
FAIL=0
for f in "" "index.html" "sw.js" "manifest.json" "icons/icon-192.png"; do
  CODE="$(timeout 25 curl -s -o /dev/null -w '%{http_code}' --max-time 20 "${SITE}/${f}" 2>/dev/null || echo 000)"
  if [ "$CODE" = "200" ]; then
    ok "/${f:-（首页）}  →  200"
  else
    err "/${f:-（首页）}  →  $CODE"
    FAIL=1
  fi
done

# ============ 6. 校验线上版本号 ============
step "[6/6] 校验线上版本号"
LIVE_VER="$(timeout 25 curl -s --max-time 20 "${SITE}/sw.js" 2>/dev/null | grep -oP "CACHE_VERSION = '\K[^']+" || echo '')"
if [ -z "$LIVE_VER" ]; then
  warn "读不到线上版本号（CDN 可能还在同步，稍等 1~2 分钟再刷新）"
elif [ "$LIVE_VER" = "$NEW_VER" ]; then
  ok "线上版本号已同步：$LIVE_VER"
else
  warn "线上版本号仍是 $LIVE_VER，本地是 $NEW_VER"
  warn "GitHub 的 CDN 有缓存，通常 1~2 分钟后自动一致"
fi

# ============ 汇总 ============
printf '\n%s\n' "============================================================"
if [ "$FAIL" = "0" ]; then
  printf '%s%s 更新完成%s\n' "$BOLD" "$G" "$N"
  printf '  版本：%s\n' "$NEW_VER"
  printf '  地址：%s/\n' "$SITE"
  printf '\n  玩家下次打开即为新版；若 SW 有更新，底部会弹「点击更新」。\n'
else
  printf '%s%s 更新已推送，但线上校验有失败项%s\n' "$BOLD" "$Y" "$N"
  printf '  GitHub Pages 构建通常需要 1~2 分钟，可稍后手动刷新：\n'
  printf '  %s/\n' "$SITE"
fi
printf '%s\n' "============================================================"
