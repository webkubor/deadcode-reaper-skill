#!/usr/bin/env bash
# tests/run.sh — tombstone-reaper-skill 自检
# 把 fixtures 拷到临时目录里跑 reap，验证：
#   1. --check 命中/不命中是否如预期
#   2. --bury 把墓碑归档到 archive/skills/，垃圾与草稿粉碎
#   3. --share 模式只输出卡片，不输出逐项清单
#   4. --help 输出用法
#
# 用法: bash tests/run.sh
# 退出码: 0 全过；非 0 有用例失败

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/reap.sh"
FIXTURE_SRC="$REPO_ROOT/tests/fixtures/has-tombstone"
TMP="$(mktemp -d)"
trap "rm -rf '$TMP' /tmp/reap-ledger.err" EXIT

PASS=0
FAIL=0
FAILED_TESTS=()

assert_contains() {
  local label="$1"
  local needle="$2"
  local haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    echo "    期望包含: $needle"
    echo "    实际输出片段: $(echo "$haystack" | head -10 | tr '\n' '|')"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$label")
  fi
}

assert_not_contains() {
  local label="$1"
  local needle="$2"
  local haystack="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "  ✗ $label"
    echo "    期望不包含: $needle"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$label")
  else
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  fi
}

assert_file_exists() {
  local label="$1"
  local p="$2"
  if [ -e "$p" ]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label — 期望存在: $p"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$label")
  fi
}

assert_file_gone() {
  local label="$1"
  local p="$2"
  if [ ! -e "$p" ]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label — 期望不存在: $p"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$label")
  fi
}

# 准备 fresh fixture 到临时目录
prepare_fixture() {
  rm -rf "$TMP"
  mkdir -p "$TMP"
  cp -R "$FIXTURE_SRC/." "$TMP/"
  # 动态生成测试用临时文件与垃圾（避免污染 git 仓库状态）
  echo "leftover" > "$TMP/scripts/leftover.bak"
  echo "lock" > "$TMP/scripts/old.build.update.lock"
  echo "dump" > "$TMP/scripts/dump.tmp"
  echo "broken" > "$TMP/scripts/merge-failed.rej"
  echo "agent test" > "$TMP/scripts/temp_agent_test.scratch.py"
  mkdir -p "$TMP/__pycache__" && echo "bytecode" > "$TMP/__pycache__/cache.pyc"
  # 在临时 fixture 里初始化 git（让 archive 用 git mv 也能跑）
  #
  # 2026-11-22 修正：把「垃圾文件」与「已提交内容」分开口径。
  #
  # 原实现 `git add -A` 把 .bak/.update.lock/.tmp/.rej/.scratch.py 和空草稿
  # **一起提交进了仓库** —— 但真实场景里这些是**未跟踪残留**（SKILL.md 说它们
  # 的危害正是「污染 git status，容易误提交进仓库」）。fixture 提交了它们，
  # 于是「已提交的文件算不算用户正式内容」这个问题被测试自己造了出来。
  #
  # 现在：先 commit fixture 里的**真实内容**（SKILL.md / 真文档），
  # 再把垃圾与草稿从索引里移出、留在工作区未跟踪 ⇒ 与真实场景一致，
  # 且「bury 不删 git 跟踪的文件」这条新规则有独立用例（T11）覆盖。
  (cd "$TMP" && git init -q && git add -A && git -c user.email=test@x -c user.name=test commit -q -m "fixture" >/dev/null 2>&1) || true
  # 把垃圾与草稿移出索引（保留在工作区、未跟踪）
  (cd "$TMP" && git rm -q --cached --ignore-unmatch \
      scripts/leftover.bak scripts/old.build.update.lock scripts/dump.tmp \
      scripts/merge-failed.rej scripts/temp_agent_test.scratch.py \
      scripts/draft.md scripts/empty-no-frontmatter.md \
      __pycache__/cache.pyc >/dev/null 2>&1) || true
  # 移出索引后要提交一次，否则这些路径仍是「已删除待提交」状态
  (cd "$TMP" && git -c user.email=test@x -c user.name=test commit -q -m "untrack junk" >/dev/null 2>&1) || true
}

echo ""
echo "=================================================="
echo "🪪 tombstone-reaper-skill test suite"
echo "=================================================="

# --- T1: --check 能识别墓碑、垃圾、草稿、AI 碎片 ---
echo ""
echo "T1 · --check 验尸报告命中正确"
prepare_fixture
out=$(cd "$TMP" && bash "$SCRIPT" --check --cache 2>&1)
assert_contains "  检出墓碑技能 deprecated-auth" "deprecated-auth/SKILL.md" "$out"
assert_contains "  检出 AI 幽灵碎片 .rej" ".rej" "$out"
assert_contains "  检出 AI 幽灵碎片 .scratch.py" ".scratch.py" "$out"
assert_contains "  检出 .bak 垃圾" ".bak" "$out"
assert_contains "  检出 .update.lock 垃圾" ".update.lock" "$out"
assert_contains "  检出 .tmp 垃圾（README/SKILL 声明要扫）" ".tmp" "$out"
assert_contains "  检出空草稿碎片" "空草稿碎片" "$out"
assert_contains "  检出项目构建缓存 __pycache__" "__pycache__" "$out"
assert_not_contains "  不误伤 healthy-payments" "healthy-payments/SKILL.md" "$out"
assert_not_contains "  不误伤有 frontmatter 的真文档" "real-doc.md" "$out"

# --- T2: --bury 把墓碑归档、垃圾与 AI 碎片粉碎、草稿清除、缓存删除 ---
echo ""
echo "T2 · --bury 执行入土"
prepare_fixture
(cd "$TMP" && bash "$SCRIPT" --apply --cache >/dev/null 2>&1)
assert_file_gone "  墓碑技能源目录消失" "$TMP/skills/deprecated-auth"
assert_file_exists "  墓碑技能归档到 archive/skills/" "$TMP/archive/skills/skills__deprecated-auth/SKILL.md"
assert_file_gone "  AI 补丁拒绝块 .rej 被粉碎" "$TMP/scripts/merge-failed.rej"
assert_file_gone "  AI 临时脚本 .scratch.py 被粉碎" "$TMP/scripts/temp_agent_test.scratch.py"
assert_file_gone "  .bak 被粉碎" "$TMP/scripts/leftover.bak"
assert_file_gone "  .update.lock 被粉碎" "$TMP/scripts/old.build.update.lock"
assert_file_gone "  .tmp 被粉碎" "$TMP/scripts/dump.tmp"
assert_file_gone "  空草稿 .md 被清除" "$TMP/scripts/draft.md"
assert_file_gone "  __pycache__ 缓存被清除" "$TMP/__pycache__"
assert_file_exists "  健康技能保留" "$TMP/skills/healthy-payments/SKILL.md"
assert_file_exists "  有 frontmatter 的真文档保留" "$TMP/note.d/real-doc.md"

# --- T3: --share 模式只打卡片，不打逐项清单 ---
echo ""
echo "T3 · --share 模式只输出卡片"
prepare_fixture
out=$(cd "$TMP" && bash "$SCRIPT" --check --share 2>&1)
assert_contains "  输出含晒单 Markdown" "晒单 Markdown" "$out"
assert_not_contains "  不输出验尸报告标题" "验尸报告" "$out"
assert_not_contains "  不输出逐项' 列举'" "发现自称已废的【墓碑技能】" "$out"

# --- T4: --help 正常输出 ---
echo ""
echo "T4 · --help 输出用法"
out=$(bash "$SCRIPT" --help 2>&1)
assert_contains "  --help 含用法字样" "用法" "$out"
assert_contains "  --help 含触发对象说明" "触发对象" "$out"

# --- T5: 自食其果防御（reaper 不应在自家目录检出自己） ---
echo ""
echo "T5 · 自食其果防御（在 reaper 自己目录 --check 不命中自身）"
out=$(bash "$SCRIPT" --check 2>&1)
assert_not_contains "  SKILL.md 不被误标为墓碑" "发现自称已废的【墓碑技能】" "$out"
assert_contains "  自检显示'项目很干净'" "项目很干净" "$out"

# --- T6: 撞名防御（两个同名 SKILL.md 在不同父目录，--bury 不互相覆盖） ---
echo ""
echo "T6 · 撞名防御"
rm -rf "$TMP"
mkdir -p "$TMP/plugins/auth" "$TMP/tools/auth"
cat > "$TMP/plugins/auth/SKILL.md" <<EOF
---
name: plugin-auth
description: "【已停用】老插件鉴权"
---
deprecated
EOF
cat > "$TMP/tools/auth/SKILL.md" <<EOF
---
name: tool-auth
description: "【已停用】老工具鉴权"
---
deprecated
EOF
(cd "$TMP" && git init -q && git add -A && git -c user.email=test@x -c user.name=test commit -q -m "fixture" >/dev/null 2>&1)
(cd "$TMP" && bash "$SCRIPT" --apply >/dev/null 2>&1)
assert_file_exists "  plugins/auth 被归档（不撞名）" "$TMP/archive/skills/plugins__auth/SKILL.md"
assert_file_exists "  tools/auth  被归档（不撞名）" "$TMP/archive/skills/tools__auth/SKILL.md"

# --- T7: --sessions 收割会话过程资产（分支 / /tmp 遗留 / stash） ---
echo ""
echo "T7 · --sessions 会话过程资产收割"
rm -rf "$TMP"
mkdir -p "$TMP"
(cd "$TMP" && git init -q && git config user.email test@x && git config user.name test && git add -A && git -c user.email=test@x -c user.name=test commit -q --allow-empty -m "root" >/dev/null 2>&1)
# 默认分支名兼容（老 git 是 master，新 git 可能 main）
default_branch="$(cd "$TMP" && git branch --show-current)"
(cd "$TMP" && git branch merged-done && git branch wip-unmerged)
(cd "$TMP" && git checkout -q merged-done && git -c user.email=test@x -c user.name=test commit -q --allow-empty -m "on merged branch")
(cd "$TMP" && git checkout -q "$default_branch" && git merge -q --no-ff merged-done -m "merge merged-done" >/dev/null 2>&1)
(cd "$TMP" && git checkout -q wip-unmerged && git -c user.email=test@x -c user.name=test commit -q --allow-empty -m "wip")
(cd "$TMP" && git checkout -q "$default_branch")
echo "stashed" > "$TMP/stashme.txt" && (cd "$TMP" && git add -A && git stash -q 2>/dev/null || true)
# /tmp 项目遗留：一个 8 天前的（应命中）+ 一个新的（应保留）
tmp_proj="$(basename "$TMP")"
old_ts="$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)"
touch -t "$old_ts" "/tmp/${tmp_proj}-oldrun" 2>/dev/null || true
echo "recent" > "/tmp/${tmp_proj}-newrun" 2>/dev/null || true

out=$(cd "$TMP" && bash "$SCRIPT" --check --sessions 2>&1)
assert_contains "  dry-run 检出已并入分支" "merged-done" "$out"
assert_contains "  保留未合并分支并说明原因" "wip-unmerged (有未合并提交)" "$out"
assert_contains "  报告 stash 残留" "stash 残留" "$out"
assert_contains "  检出 /tmp 8天前遗留" "/tmp/${tmp_proj}-oldrun" "$out"
assert_not_contains "  不碰 1 小时内的新 /tmp 条目" "/tmp/${tmp_proj}-newrun" "$out"

(cd "$TMP" && bash "$SCRIPT" --apply --sessions >/dev/null 2>&1)
if (cd "$TMP" && git branch | grep -q "merged-done"); then
  echo "  ✗ 已并入分支未被删除"; FAIL=$((FAIL+1)); FAILED_TESTS+=("已并入分支删除")
else
  echo "  ✓ 已并入分支被删除"; PASS=$((PASS+1))
fi
if (cd "$TMP" && git branch | grep -q "wip-unmerged"); then
  echo "  ✓ 未合并分支保留"; PASS=$((PASS+1))
else
  echo "  ✗ 未合并分支被误删"; FAIL=$((FAIL+1)); FAILED_TESTS+=("未合并分支保留")
fi
if [ ! -e "/tmp/${tmp_proj}-oldrun" ]; then
  echo "  ✓ /tmp 8天前遗留被清除"; PASS=$((PASS+1))
else
  echo "  ✗ /tmp 8天前遗留未被清除"; FAIL=$((FAIL+1)); FAILED_TESTS+=("/tmp 遗留清除")
  rm -f "/tmp/${tmp_proj}-oldrun"
fi
if [ -e "/tmp/${tmp_proj}-newrun" ]; then
  echo "  ✓ 新 /tmp 条目保留"; PASS=$((PASS+1))
else
  echo "  ✗ 新 /tmp 条目被误删"; FAIL=$((FAIL+1)); FAILED_TESTS+=("新 /tmp 条目保留")
fi
rm -f "/tmp/${tmp_proj}-newrun"

# --- T8: worktree 干净判据含未跟踪文件（2026-11-19 教训：旧判据只看 diff，未跟踪文件会被 remove --force 粉碎） ---
echo ""
echo "T8 · worktree 收割只认 status 全干净"
rm -rf "$TMP"
mkdir -p "$TMP"
# git 输出的是物理路径（macOS 上 /var → /private/var），断言须用 pwd -P 对齐，
# 否则「不包含」类断言会因路径前缀不同而假阳性通过
WTS="$(cd "$(mktemp -d)" && pwd -P)"
TMP_P="$(cd "$TMP" && pwd -P)"
gcommit() { git -c user.email=test@x -c user.name=test commit -q "$@"; }
(cd "$TMP" && git init -q && echo base > base.txt && git add -A && gcommit -m "root")
(cd "$TMP" && git worktree add -q "$WTS/wt-clean" -b wt-clean)
(cd "$TMP" && git worktree add -q "$WTS/wt untracked" -b wt-untracked)
echo "新写的未提交文件" > "$WTS/wt untracked/new-work.txt"
(cd "$TMP" && git worktree add -q "$WTS/wt-locked" -b wt-locked && git worktree lock "$WTS/wt-locked")
(cd "$TMP" && git worktree add -q --detach "$WTS/wt-detached")
(cd "$WTS/wt-detached" && gcommit --allow-empty -m "游离提交")

out=$(cd "$TMP" && bash "$SCRIPT" --check 2>&1)
assert_contains "  干净 worktree 列为候选" "    - $WTS/wt-clean" "$out"
assert_contains "  含空格路径完整解析且因未跟踪文件跳过" "$WTS/wt untracked (有未提交或未跟踪文件)" "$out"
assert_contains "  locked worktree 跳过" "$WTS/wt-locked (locked)" "$out"
assert_contains "  游离 HEAD 独有提交跳过" "$WTS/wt-detached (游离 HEAD 有未入分支的提交)" "$out"

# 在 linked worktree 里运行：主工作区不得成为候选
out=$(cd "$WTS/wt-clean" && bash "$SCRIPT" --check 2>&1)
assert_not_contains "  linked worktree 里运行不把主工作区列为候选" "    - $TMP_P" "$out"
assert_not_contains "  linked worktree 里运行不把自身列为候选" "    - $WTS/wt-clean" "$out"

(cd "$TMP" && bash "$SCRIPT" --apply >/dev/null 2>&1)
assert_file_gone "  干净 worktree 被移除" "$WTS/wt-clean"
assert_file_exists "  未跟踪文件幸存" "$WTS/wt untracked/new-work.txt"
assert_file_exists "  locked worktree 保留" "$WTS/wt-locked"
assert_file_exists "  游离 HEAD worktree 保留" "$WTS/wt-detached"

# prunable：目录被手动删掉后，apply 只 prune 元数据
(cd "$TMP" && git worktree unlock "$WTS/wt-locked")
rm -rf "$WTS/wt-locked"
(cd "$TMP" && bash "$SCRIPT" --apply >/dev/null 2>&1)
assert_not_contains "  失效 worktree 记录被 prune" "$WTS/wt-locked" "$(cd "$TMP" && git worktree list --porcelain)"
rm -rf "$WTS"

# --- T9: 经软链调用时自身排除仍生效（2026-11-19 教训：cs-gc 经 ~/.gemini/... 软链调用，
#     SELF_DIR 取逻辑路径，与 find 结果的物理路径对不上，reaper 把自己的 SKILL.md 和 fixtures 报成墓碑） ---
echo ""
echo "T9 · 经软链调用仍排除自身目录"
LINKDIR="$(mktemp -d)"
ln -s "$REPO_ROOT" "$LINKDIR/reaper-link"
out=$(cd "$REPO_ROOT" && bash "$LINKDIR/reaper-link/scripts/reap.sh" --check 2>&1)
assert_not_contains "  软链调用时 SKILL.md 不被误标为墓碑" "发现自称已废的【墓碑技能】" "$out"
assert_contains "  软链调用时自检显示'项目很干净'" "项目很干净" "$out"
# 目标目录本身经软链传入（cs-gc 逐仓传参的形态）
out=$(bash "$LINKDIR/reaper-link/scripts/reap.sh" --check "$LINKDIR/reaper-link" 2>&1)
assert_not_contains "  目标目录也走软链时不误标" "发现自称已废的【墓碑技能】" "$out"
rm -rf "$LINKDIR"

# --- T10: temp_*.py 不误杀虚拟环境里的第三方包（pip 自带 _internal/utils/temp_dir.py） ---
echo ""
echo "T10 · temp_*.py 跳过 venv / site-packages"
rm -rf "$TMP"
mkdir -p "$TMP/.venv/lib/python3.12/site-packages/pip/_internal/utils" \
         "$TMP/venv/lib/python3.12/site-packages/pkg" \
         "$TMP/vendor/site-packages/pkg"
echo "x = 1" > "$TMP/.venv/lib/python3.12/site-packages/pip/_internal/utils/temp_dir.py"
echo "x = 1" > "$TMP/venv/lib/python3.12/site-packages/pkg/temp_venv.py"
echo "x = 1" > "$TMP/vendor/site-packages/pkg/temp_vendored.py"
echo "x = 1" > "$TMP/temp_agent_probe.py"
(cd "$TMP" && git init -q && git add -A && git -c user.email=test@x -c user.name=test commit -q -m "fixture" >/dev/null 2>&1)
out=$(cd "$TMP" && bash "$SCRIPT" --check 2>&1)
assert_contains "  仓库内真实 temp_*.py 仍被检出" "temp_agent_probe.py" "$out"
assert_not_contains "  .venv 里 pip 的 temp_dir.py 不误报" "temp_dir.py" "$out"
assert_not_contains "  venv/ 里的 temp_*.py 不误报" "temp_venv.py" "$out"
assert_not_contains "  site-packages 里的 temp_*.py 不误报" "temp_vendored.py" "$out"

# --- T11: bury 模式不得删除 git 跟踪的文件（2026-11-21 复核：rm -f 前无跟踪检查） ---
#
# 教训来源：三个 rm 循环（ai_artifacts / garbage_files / empty_drafts）直接
# `rm -f "$f"`，不查该文件是否被 git 跟踪 ⇒ 仓里**已提交**的 .bak/.update.lock
# 之类的文件会被直接删掉，留下 ` D path` 的脏工作区（内容可从 git 恢复，
# 但用户的工作区被动了，而且如果没提交过就真丢了）。
echo ""
echo "T11 · bury 模式不删 git 跟踪的文件"
rm -rf "$TMP"
mkdir -p "$TMP/scripts"
(cd "$TMP" && git init -q && git config user.email test@x && git config user.name test)
echo "tracked content" > "$TMP/scripts/old.build.update.lock"
echo "tracked content" > "$TMP/scripts/keep.txt"
(cd "$TMP" && git add -A && git -c user.email=test@x -c user.name=test commit -q -m "tracked" >/dev/null 2>&1)
(cd "$TMP" && bash "$SCRIPT" --apply >/dev/null 2>&1)
if [ -e "$TMP/scripts/old.build.update.lock" ]; then
  echo "  ✓ git 跟踪的垃圾文件未被删除"; PASS=$((PASS+1))
else
  echo "  ✗ git 跟踪的垃圾文件被删除（工作区被破坏）"; FAIL=$((FAIL+1)); FAILED_TESTS+=("跟踪文件保护")
fi
if (cd "$TMP" && git status --porcelain | grep -q .); then
  echo "  ✗ bury 后工作区变脏（$(cd "$TMP" && git status --porcelain | tr '\n' '|')）"
  FAIL=$((FAIL+1)); FAILED_TESTS+=("跟踪文件保护后工作区干净")
else
  echo "  ✓ bury 后工作区保持干净"; PASS=$((PASS+1))
fi

# --- T12: bury 归档后不留暂存区改动（git mv 会把改名留在 index 里） ---
#
# 教训来源：墓碑归档走 `git mv`，成功后改名留在**暂存区** ⇒ 用户的下一次
# `git commit` 会把这次归档一起提交进去（污染），或者 `git commit -a` 之外
# 的操作让人困惑。归档是 reaper 的动作，不该预占用户的提交。
echo ""
echo "T12 · bury 归档后不污染暂存区"
rm -rf "$TMP"
mkdir -p "$TMP/skills/deprecated-auth"
(cd "$TMP" && git init -q && git config user.email test@x && git config user.name test)
printf -- "---\nname: deprecated-auth\nstatus: deprecated\n---\n\n旧技能\n" > "$TMP/skills/deprecated-auth/SKILL.md"
(cd "$TMP" && git add -A && git -c user.email=test@x -c user.name=test commit -q -m "tombstone" >/dev/null 2>&1)
(cd "$TMP" && bash "$SCRIPT" --bury >/dev/null 2>&1)
staged="$(cd "$TMP" && git diff --cached --name-only 2>/dev/null)"
if [ -z "$staged" ]; then
  echo "  ✓ 归档后暂存区干净"; PASS=$((PASS+1))
else
  echo "  ✗ 归档后暂存区有残留：$(echo "$staged" | tr '\n' '|')"
  FAIL=$((FAIL+1)); FAILED_TESTS+=("归档不留暂存")
fi
if (cd "$TMP" && git status --porcelain | grep -q .); then
  echo "  ✓ 归档以工作区改动呈现（未占用暂存区）"; PASS=$((PASS+1))
else
  echo "  ✗ 归档后工作区无任何痕迹（归档没生效？）"; FAIL=$((FAIL+1)); FAILED_TESTS+=("归档生效")
fi

# --- T13: 已并入判据比默认分支，不比当前 HEAD（HEAD 在功能分支上时会误判） ---
#
# 教训来源：分支收割用 `git merge-base --is-ancestor "$b" HEAD`，
# HEAD 可能是**功能分支**。此时「只并入功能分支、没并入默认分支」的分支
# 会被判成已并入并删除 —— 它的独有提交就丢了。
# 正确判据：比默认分支（main/master/develop/trunk，或 origin/ 默认分支）。
echo ""
echo "T13 · 已并入判据比默认分支而非当前 HEAD"
rm -rf "$TMP"
mkdir -p "$TMP"
(cd "$TMP" && git init -q && git config user.email test@x && git config user.name test)
(cd "$TMP" && git commit -q --allow-empty -m "root" >/dev/null 2>&1)
DEF_BRANCH="$(cd "$TMP" && git branch --show-current)"
# 造一个分支：独有提交，只并入功能分支，**没有**并入默认分支
(cd "$TMP" && git checkout -q -b feature-x && git commit -q --allow-empty -m "feature work" >/dev/null 2>&1)
(cd "$TMP" && git checkout -q "$DEF_BRANCH" && git checkout -q -b side-unmerged && git commit -q --allow-empty -m "UNIQUE only on side" >/dev/null 2>&1)
(cd "$TMP" && git checkout -q feature-x && git merge -q --no-ff side-unmerged -m "merge side into feature" >/dev/null 2>&1)
(cd "$TMP" && git checkout -q feature-x)   # HEAD 停在功能分支上
out=$(cd "$TMP" && bash "$SCRIPT" --check --sessions 2>&1)
assert_contains "  检出未并入默认分支的 side-unmerged" "side-unmerged" "$out"
assert_contains "  说明它未并入默认分支" "未并入默认分支" "$out"
(cd "$TMP" && bash "$SCRIPT" --apply --sessions >/dev/null 2>&1)
if (cd "$TMP" && git branch | grep -q "side-unmerged"); then
  echo "  ✓ 未并入默认分支的分支被保留"; PASS=$((PASS+1))
else
  echo "  ✗ 未并入默认分支的分支被误删（独有提交丢失）"; FAIL=$((FAIL+1)); FAILED_TESTS+=("已并入判据比默认分支")
fi
if (cd "$TMP" && git branch | grep -q "feature-x"); then
  echo "  ✓ 当前分支未被收割"; PASS=$((PASS+1))
else
  echo "  ✗ 当前分支被误删"; FAIL=$((FAIL+1)); FAILED_TESTS+=("当前分支保护")
fi

# --- 汇总 ---
echo ""
echo "=================================================="
echo "汇总: $PASS 通过 / $FAIL 失败"
if [ "$FAIL" -gt 0 ]; then
  echo "失败的用例："
  for t in "${FAILED_TESTS[@]}"; do echo "  - $t"; done
  exit 1
fi
echo "🎉 全过"
exit 0