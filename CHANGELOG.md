# Changelog

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [1.4.2] - 2026-11-19

### 修复 (Fixes)

- **经软链调用时自身排除失效**：`SELF_DIR` 与扫描根取的是逻辑路径，而 find 结果是物理路径，二者对不上，reaper 经软链（如 `~/.gemini/config/skills/...`）调用时会把自己的 SKILL.md 和 fixtures 报成墓碑。所有 `pwd` 统一改为 `pwd -P`
- **`temp_*.py` 不再误报虚拟环境里的第三方包**：pip 自带 `_internal/utils/temp_dir.py`，旧规则会命中。AI 幽灵扫描跳过 `.venv*/`、`venv/`、`site-packages/`

### 测试 (Tests)

- 新增 T9：脚本和目标目录分别经软链传入，断言不报墓碑、自检显示「项目很干净」
- 新增 T10：`.venv`、`venv/`、`site-packages` 下的 `temp_*.py` 不报，仓库根的 `temp_*.py` 仍报
- 用修复前的 `scripts/reap.sh` 跑同一套测试，T9/T10 共 5 条断言失败（52/5），确认新测试能抓到这两个问题

## [1.4.1] - 2026-11-19

### 修复 (Fixes)

- **worktree 收割不再粉碎未跟踪文件**：旧判据只看 diff，未跟踪的新文件会随 `remove --force` 一起被删。现在只有 `git status --porcelain` 全空才算干净，否则跳过并报「有未提交或未跟踪文件」
- 移除 worktree 改用不带 `--force` 的 `git worktree remove`，git 自身的安全检查不再被绕过
- 改为解析 `git worktree list --porcelain`，含空格的路径能完整识别
- 新增跳过规则：主工作区（在 linked worktree 里运行时也不会把它列为候选）、locked worktree、游离 HEAD 上有未入任何分支的提交的 worktree
- 游离 HEAD 判据用 `for-each-ref --contains HEAD refs/heads refs/remotes`。`branch -a --contains HEAD` 在游离时会输出「* (no branch)」，永不为空，旧写法下这条保护从未生效
- 目录已被手动删掉的失效 worktree 记录，`--apply` 时执行一次 `git worktree prune`

### 测试 (Tests)

- 新增 T8：覆盖干净/未跟踪/含空格路径/locked/游离 HEAD/主工作区/失效记录 prune。断言路径统一用 `pwd -P`，避免 macOS `/var` 与 `/private/var` 前缀不一致导致「不包含」断言空过

## [1.4.0] - 2026-11-17

### 新特性 (Features)

- 并入 resource-audit（owner 指令「卫生清理技能整合进墓碑」）：新增「无消费方资源」对象类别（密钥/模型/缓存/分支/任务，判据「谁在用」而非「多大多旧」），触发词并入磁盘清理/治理盘点/资源审计/密钥审计/无消费方/孤儿密钥；原技能入土归档
- 新增「清理域地图」：与 service-retirement（退役流程，需授权）、cron-management（定时器卫生）划清语义边界 —— 墓碑铁律免请示绝不适用于服务/凭据/数据退役
- service-retirement 明确保留独立：其免授权边界与墓碑免请示语义冲突，合并会造成用垃圾回收的刀切生产资产

## [1.3.0] - 2026-11-17

### 新特性 (Features)

- 铁律新增第 4 条「验证后被取代」：经实测被更优通道取代、保留即双写漂移的能力直接入土（owner 判例：agent-global-rules-sync 被 magpie library instructions 通道取代后收割归档）
- 调度落地：com.webkubor.tombstone-reaper 每日 04:35 自动 --bury（owner 原话「我不是每天都在清理吗」——此前无任何调度，纯手动）

## [1.2.0] - 2026-10-23

### 新特性 (Features)

- **🧟 会话过程资产收割 (`--sessions`)**：任务结束后无人认领的过程资产有了统一判据 ——
  - **已并入的本地分支**：`git merge-base --is-ancestor` 相对当前 HEAD 判定，排除 main/master/develop/trunk 与当前分支，**排除被 worktree 占用的分支**（被占分支 `-d` 必失败，教训来自 GHAM 清理：17 个 worktree 占死 15 条已并入分支）；
  - **远端已并入分支**：相对 origin/main 同理判定，需 `--apply --remote` 才删；
  - **/tmp 项目遗留**：`<项目名>-*` / `<项目名>_*` 且 mtime 超过 `REAP_SESS_STALE_DAYS`（默认 7 天）且**不在最近 1 小时内**（双保险）且无活跃进程占用（`lsof +D`，保护并行会话）；macOS `/tmp` 与 `/private/tmp` 以设备号+inode 去重；
  - **stash**：默认只报告，`--apply --stash` 才 drop（stash 常藏未收编工作）；
  - **Agent 浏览器 TaskSpace**：委托 `cs browser gc`（装了 cs 才生效）。
- 功德账本新增 `total_branches` / `total_tmp_items` / `total_worktrees` 三个维度，`--stats` 战报可见「🧟 累计收割会话遗留」。

### 背景

owner 2026-10-23 在 GHAM 仓库大清理（18 分支 + 17 worktree + /tmp 诊断脚本 + 浏览器窗口）后提问：
「为啥不把这些测试的遗留、分支、worktree、浏览器测试完的窗口统一放入 GC？」
—— 门禁只管代码，没有人管过程资产。本版本把过程资产 GC 做进收割判据。

## [1.1.0] - 2026-09-19

### 新特性 (Features)

- **🤖 AI 幽灵碎片收割**：自动定位并物理粉碎 AI Agent 遗留的脚手架、`*.rej`（Patch 失败抛弃块）、`*.scratch.*`、`scratch/temp_*` 临时脚本，防止污染后续 Agent 检索池并造成逻辑幻觉。
- **⚡ 依赖与构建缓存安全蒸发 (`--cache` / `--system-cache` / `--deep`)**：
  - 项目级缓存：`__pycache__`、`.pytest_cache`、`.turbo`、`.next`、`.eslintcache` 等；
  - 开发者全局依赖缓存：一键安全清理 `npm` 临时全局包与 npx 运行时（`~/.npm/_npx`）、`pip` wheel 缓存、`go clean -cache`、`brew cleanup` 及桌面客户端更新残留（`~/Library/Caches/@*updater`）。
- **📜 功德卡片全面升级**：卡片支持独立展示 AI 碎片粉碎数量、项目缓存与系统依赖缓存释放体积，磁盘空间按 B/KB/MB/GB 动态单位换算，减法战绩一目了然。

## [1.0.1] - 2026-09-18

### 修复（Round 3 起持续打磨）

- **自我排除**：reap.sh 不再吃自己的目录 / 自己的归档（避免「自食其果」）
- **撞名归档**：归档目录同名时按版本号 / 时间戳自增，避免覆盖
- **macOS 兼容**：`/tmp` 在 macOS 是 `/private/tmp` 符号链接，路径解析统一走 `cd && pwd` 兼容
- **工作树 reap**：HEAD 干净且非主工作树的安全 prune（仅 `--apply` 模式）
- **未知参数 `exit 2`**（Round 2 修复）：`--typo` / 非目录的 arg 不再静默回退 dry-run

## [1.0.0] - 2026-09-?? (init)

- `feat: 支持 --stats 随时查看累计功德账本`
- `feat: 🪦 初始化 tombstone-reaper-skill 墓碑收割与减法清道夫`

### 触发对象（v1 起稳定）

- ⚰️ **墓碑技能**：`SKILL.md` frontmatter 自称已废（【已停用】/`status: deprecated`/…）
- 🗑️ **幽灵垃圾**：`*.bak` / `*.bak2` / `*.update.lock` / `*~` / `*.tmp` / `*.orig` 等临时与备份
- 📄 **草稿碎片**：< 100 字节且无 frontmatter 的散落 `.md`
- 🌳 **孤立工作树**：仅 `--apply` —— HEAD 干净且非主工作树，安全 prune

---

完整 commit 列表见 `git log`。
