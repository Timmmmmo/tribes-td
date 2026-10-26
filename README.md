# Tribes TD · 六部族塔防

把《人族无敌》这套玩法搬到手机上的一次工程实现。**保留机制内核，重做结构与时长。**

竖屏 720×1280，Godot 4.7，typed GDScript，面向中低端安卓机（GL Compatibility 渲染后端）。

---

## 在线试玩（两个版本，都能直接玩）

| 版本 | 链接 | 说明 |
|---|---|---|
| **引擎版（Godot 4.7.2 导出）** | **https://timmmmmo.github.io/tribes-td/godot/** | 真正的 Godot 构建，38MB wasm，首屏要等几秒。加 `?demo=1` 看满编布防，`?demo=1&report=1` 看结算归因页。 |
| 轻量版（canvas 2D） | https://timmmmmo.github.io/tribes-td/ | 纯 JS，88KB 单文件，秒开。 |

两个版本共用同一份数值表 `data/content.json`，规则完全一致。
美术也都是**全程序化绘制、零图片依赖**——两边观感现在是一个档次的，区别只在体积和启动速度。

GitHub Pages 托管，纯静态、无分享码、无鉴权、无 Cookie，转发多少手都不会坏。

> **踩过的坑 1（已解决）**：早先托管在 WorkBuddy 托管网关时，网关要求「用 `?sharecode=` 换 Cookie 才放行」。
> 分享码一旦被聊天工具截断，页面不是白屏，而是返回一张「链接不完整，地址缺少访问参数」的提示页——
> 看到那张图就是分享码丢了。搬到 GitHub Pages 后这个坑彻底没有了。

> **踩过的坑 2**：`web/index.html` 是单文件产物（JS 与数值表全内联，整页 1 个请求），
> 所以它既能在 GitHub Pages 上跑，也能直接双击本地文件跑，不依赖任何子资源。

> **踩过的坑 3**：Godot 的 Web 导出里 `SystemFont` 查不到系统字体，中文全变豆腐块。
> 现在打包一份 175KB 的 Noto Sans SC 子集（`tools/subset_font.py` 只留游戏用到的 707 个字）瑞底。

工程上有两条腿：

| 实现 | 位置 | 用途 |
|---|---|---|
| **Godot 版（typed GDScript）** | `game/` `addons/` `scenes/` | 主目标形态。已通过 184 项 headless 自测，可导出 Web。 |
| Web 版（canvas 2D） | `web/src/` → `web/index.html` | 纯 JS 重写，零构建、秒开，美术反而更好。 |

两版共用同一套数值表 `data/content.json`（生成脚本 `tools/gen_content.py` 会把它复制到 `web/`），
所以调平衡只改一处，两边同时生效。

### Godot 版怎么跑

需要 **Godot 4.7.x**（编辑器，不是模板）。仓库里已经带好了导出预设 `export_presets.cfg`。

```bash
# 1) 导入资源（首次、或新增了素材后跑）
godot --headless --path . --import

# 2) headless 自测：期望 RESULT: PASS 184 checks, 0 failures
godot --headless --path . -s res://tests/run_tests.gd

# 3) 导出网页版（需要 export templates，或跑下面的抽模板脚本）
godot --headless --path . --export-release "Web" build/web/index.html

# 4) 本地验证（必须 http，不能 file://；wasm 需要正确的 MIME）
python tools/serve_web.py build/web 8124
```

模板很大（官方 tpz 1.2GB），这里有个只抽 web 部分的脚本，实测只传 80MB 左右：

```bash
python tools/fetch_templates.py \
  https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz \
  "$APPDATA/Godot/export_templates/4.7.2.stable"
```

导出预设里 **`variant/thread_support=false`**，故意关掉多线程：这样不需要
`Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` 两个响应头，
GitHub Pages 这类不能自定义头的静态托管直接能跑。代价是性能低一些。

### Web 版（canvas）怎么跑

`web/index.html` 是**打包产物**（单文件，把所有 JS 和数值表内联进去，整页只发 1 个请求）。
源码在 `web/src/`：

```bash
python tools/build_web.py      # 改完源码跑一次，生成 web/index.html

# 开发时可以直接开 web/dev.html，它仍然分开加载 src/，改完刷新就见效
cd web && python -m http.server 8123
# 打开 http://127.0.0.1:8123/dev.html
```

**为什么要打成单文件？** 因为托管方的分享链接是「用 `?sharecode=` 换一个 Cookie 才放行子资源」的。
页面如果再去请求 `js/core.js`、`content.json`，而浏览器不落这个 Cookie（微信内置浏览器、
iOS 严格隐私模式都会），子请求就 403，直接白屏。内联之后零子请求，任何环境都能开——
顺带 `file://` 双击也能玩，不需要起服务。

### 想改成自己的 GitHub Pages

仓库里已经放好了 `.github/workflows/pages.yml`，推上去就能用。

**有 PAT 就一条命令**（需要 Classic token 的 `repo` + `workflow` 权限）：

```bash
GH_TOKEN=ghp_xxx bash tools/deploy_github.sh tribes-td
```

脚本会验 token、建仓库、推 main、开 Pages、等构建，最后直接把
`https://<账号>.github.io/tribes-td/` 打印出来。token 少了 `workflow` 权限时，
它会自动退化成「把 `web/` 推到 `gh-pages` 分支 + 分支模式开 Pages」，一样出链接。

没 token 就手动：

```bash
git init -b main && git add . && git commit -m "Tribes TD"
git remote add origin https://github.com/<你的账号>/tribes-td.git
git push -u origin main
```

然后到仓库 **Settings → Pages → Source** 选 **GitHub Actions**。
下一次 push 会自动把 `web/` 发到 `https://<你的账号>.github.io/tribes-td/`。

GitHub Pages 这条路的好处：**没有分享码、没有鉴权、没有 Cookie**，
链接永远是裸的 `https://xxx.github.io/tribes-td/`，转多少手都不会坏。

---

## 先看这个：当前完成度

| 模块 | 状态 |
|---|---|
| 双资源内核（金币 + 功勋） | ✅ 完成，有测试覆盖 |
| 六部族 32 个防御单位 / 7 档阶梯价位 | ✅ 数据完整，可直接玩 |
| 15 波关卡、5 种敌人（含 BOSS） | ✅ 完成 |
| 竖屏 HUD（自绘 + 手动命中测试） | ✅ 完成 |
| 三个主动技能（增援 / 冰封 / 裁决） | ✅ 完成 |
| 人口系统、档位解锁、档内升级、出售 | ✅ 完成 |
| 敌人**真机制**：毒（无视护甲）/ 眩晕 / 分裂 | ✅ 完成，包在 `game/status.gd`，不改内核 |
| 波次情报 + 手动开波 + 提前开波奖励 | ✅ 完成，「等」变成「要不要现在开」 |
| 英雄单位：拖动 / 自动索敌 / 装备三槽 | ✅ 完成，击杀给金币不给功勋 |
| 装备掉落 + 三合一合成 | ✅ 完成 |
| BOSS 两段转换（70% 召唤 / 40% 狂暴）+ 血条阶段刻度 | ✅ 完成，包在 `game/boss.gd`，不改内核 |
| 结算归因页：主因按掉血量排 + 漏怪构成 + 具体建议 | ✅ 完成，纯数据在 `game/report.gd`，可 headless 测 |
| 弹射 / 召唤物 | ⏳ 未做（见 ROADMAP 迭代二） |
| 局外养成（六条职业线）、异步 PvP | ⏳ 未开始（属于迭代三） |
| 美术（Web 版） | ✅ 程序化绘制：地形预渲染、八边形石台塔、粒子、飘字、渐变 HUD |
| 美术（Godot 版） | ✅ 程序化绘制，与 Web 版同档：地形烘焙、石台/符文环、渐变塔身、敌人面部、玻璃面板 HUD |

**验证状态**：Godot 4.7.2 已实机跑通全链路，不再是「只过了语法检查」。

| 环节 | 结果 |
|---|---|
| `--headless --import` | 通过，零错误 |
| `--headless -s res://tests/run_tests.gd` | **PASS 184 checks, 0 failures** |
| `--write-movie` 真实渲染 | 逐帧看过：地形分层、塔、敌人、特效、HUD 全部正常 |
| `--headless --export-release "Web"` | 38MB wasm + 389KB pck（资源全程序化，pck 里只有数值表、字体子集、脚本） |
| GitHub Pages 线上 | 已验证打开、可玩 |

另外有一个「路径核对」脚本，用来证明敌人坐标和地图路径严丝合缝：

```bash
godot --headless --path . -s res://tests/dump_path.gd
# 打印 13 个航点、43 个路径格、以及一只怪走完全程的逐帧坐标；最后一行 seam jumps: 0
```

---

## 怎么跑

1. 装 **Godot 4.7**（标准版，不需要 .NET）。
2. 打开 Godot → `导入` → 选本目录的 `project.godot`。
3. 首次导入会注册 `class_name` 并导入贴图，**耐心等它跑完**（第一次可能报一次错，再导一次就好）。
4. 按 F5 运行。

### 自动化测试

```bash
godot --headless --path . -s res://tests/run_tests.gd
# 期望最后一行： RESULT: PASS <n> checks, 0 failures
```

测试只覆盖本项目自有的机制（功勋归属、阶梯价位、部族完整性、数值健康度、波次模拟），
`addons/td_core` 那部分不重复测 —— 它自带 54 项检查，上游仓库里跑。

### 操作

| 操作 | 桌面 | 手机 |
|---|---|---|
| 选塔 | 点下方卡片 | 点下方卡片 |
| 造塔 | 点地图格子 | 点地图格子 |
| 选中/升级/出售 | 点已有塔 → 中部控制条变成塔操作 | 同 |
| **开下一波** | 点左下「开波」/ `空格` | 点左下「开波」 |
| **移动英雄** | 按住英雄拖到目标位置 | 同 |
| 解锁下一档 | 点顶部进度条 / `K` | 点顶部进度条 |
| 换部族 | 点右上角部族条 / `Tab` | 点右上角部族条 |
| 技能 | `1` `2` `3` | 点底部技能按钮 |
| 重开 | `R` | — |

### 调试开关（命令行传 `--xxx`，网页传 `?xxx=1`）

| 开关 | 作用 |
|---|---|
| `--demo` | 满编布防 + 解锁到第 7 档，用来看终局和截图 |
| `--report-demo [--win]` | 直接打开结算归因页（输 / 赢） |
| `--boss-demo` | 跳到第 15 波，并在 BOSS 出场那帧把它打到 38% |
| `--teach-demo` | **只按提示位造开局那 3 座塔**，用来逐帧检查前 10 秒那条链 |
| `--autoplay` | 准备期一出现就立刻开波，用来跑压力 |
| `--trace-tower` / `--trace-enemies` | 打印塔的击杀数和距离 / 敌人坐标，排查「塔不开火」 |

> `--teach-demo` 是本轮加的。它和 `--demo` 的区别是**不布防** —— 画面和真实首局一样空，
> 只有开局那三座。前 10 秒的每一个视觉反馈都要靠它逐帧看，因为这些东西
> 全都在 2 秒内发生完，截图截不到。

---

## 这个项目在解决什么问题

《人族无敌》原版有三个东西是它的灵魂，不能丢：

1. **双资源**：金币决定你现在有几个塔，功勋决定塔能长到多高。两条资源不可兑换。
2. **击杀归属**：功勋只算防御单位自己打死的怪。召唤物、技能抢走的人头不给功勋。
3. **阶梯价位**：40 / 90 / 190 / 400 / 850 / 1800 / 3800，相邻档之间没有「补一点」的中间态。

原版有三个东西是手机的天敌，必须改：

1. **56 波 / 40–60 分钟一局** → 改成 15 波 / 8–12 分钟。
2. **4 人实时分线协作** → 改成单人守一条蛇形路 + 路线分叉制造压力。
3. **大视野多路同屏 + 鼠标精度** → 改成竖屏单路全景 + 网格吸附 + 范围预览 + 落子前的伤害提示。

这三改三不改，就是本项目的全部设计决策。详见 `docs/DESIGN.md`。

---

## 目录结构

```
addons/td_core/     塔的放置/索敌/伤害、敌人寻路、波次调度（MIT，原样引用，未改动一行）
game/merit.gd       功勋系统：第二资源 / 档位解锁 / 人口 / 主动技能   ← 本项目核心
game/art.gd         程序化美术层：地形烘焙、顶点色渐变、软光斑、几何构造
game/main.gd        状态机、输入、建造校验、棋盘与单位自绘、特效层
game/hud.gd         竖屏 HUD，全自绘 + 手动命中测试
game/intel.gd       波次情报：把波次数据翻译成「下一波 12 只重装 · 需要高单伤或毒」
game/status.gd      敌人状态机：毒 / 眩晕 / 分裂（包一层，一行内核代码都没改）
game/hero.gd        英雄 + 装备三槽 + 三合一合成
game/boss.gd        BOSS 两段转换：70% 召唤援军 / 40% 狂暴
game/report.gd      一局结算与失败归因（纯数据，可 headless 测）
web/                可玩的 canvas 2D 版。index.html 是打包产物（单文件），源码在 web/src/
web/src/js/         core.js（纯逻辑）/ render.js（全程序化绘制）/ main.js（引导与输入）
tools/build_web.py  把 web/src 内联成单文件 index.html
data/content.json   数值表（由 tools/gen_content.py 生成，不要手改）
tools/gen_content.py 数值生成器，带自查断言
tests/run_tests.gd  headless 自测
docs/FUN.md         原版乐趣拆解、当前 demo 的五个病症、MVP 边界与执行顺序
docs/               设计决策 / 迭代路线 / 素材许可
```

**为什么 data/content.json 要用脚本生成？** 因为 32 个塔的价位必须与档位表严格对齐，
手写 JSON 一定会漂。`gen_content.py` 里带了断言，价位一错，脚本直接失败。

---

## 素材与第三方代码

| 用途 | 来源 | 许可 |
|---|---|---|
| 塔防核心逻辑 | [godot-tower-defense-core-lite](https://github.com/openclawaimac/godot-tower-defense-core-lite) | MIT |
| 中文 HUD 字体 | Noto Sans SC 子集（707 字 / 175KB，`tools/subset_font.py` 生成） | OFL 1.1 |
| 美术 | 无外部素材，全部代码程序化绘制 | — |

Godot 的 Web 导出里 `SystemFont` 查不到宿主字体，中文会全变豆腐块，
所以必须打包一份子集。OFL 允许嵌入与修改，义务是保留许可全文、且修改版不得使用保留字体名
（因此文件名是 `game_cjk.ttf` 而不是 Noto 系列名）。

`assets/sprites/` 里还留着 10 张 Kenney CC0 参考图，但**代码已不引用**，导出时也被排除。
**没有引入任何 GPL / CC-BY-SA 素材**，避免后续商业化时的传染性许可问题。

美术是占位级别。真正的美术投入在立项之后，且必须重做世界观 —— 原版的「人族 / 雅典娜 / 魑魅魍魉」
属于暴雪 IP 与原作者创作，商业产品不能沿用。**机制不受版权保护，外壳必须换掉。**

---

## 已知限制

1. 弹射 / 召唤物还没做；毒 / 眩晕 / 分裂、BOSS 两段转换、结算归因页都已经是真机制。
2. 难度阶梯还没调 —— 现在只有一套数值。
2. 没有结算归因页 —— 输了不知道死因，这条是 MVP 的最后一块（见 docs/FUN.md）。
2. 只有 1 张地图、1 个难度。原版的「灾厄 / 大灾变」难度阶梯未做。
3. 没有存档、没有局外成长、没有联网。
4. 两个版本都没有音效，也没有做多语言。
5. Godot Web 版关掉了多线程（`thread_support=false`）以避免 COOP/COEP 响应头，
   换来的是「任何静态托管都能跑」，代价是首屏编译 38MB wasm 偏慢。
