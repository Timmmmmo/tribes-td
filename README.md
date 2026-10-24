# Tribes TD · 六部族塔防

把《人族无敌》这套玩法搬到手机上的一次工程实现。**保留机制内核，重做结构与时长。**

竖屏 720×1280，Godot 4.7，typed GDScript，面向中低端安卓机（GL Compatibility 渲染后端）。

---

## 在线试玩（Web 版，现在是主线）

👉 **https://tribes-td.app.workbuddy.host/?sharecode=U7H7AJWP6F**

手机打开最好使，横屏也行，浏览器直接跑，不用装引擎。

工程上有两条腿：

| 实现 | 位置 | 用途 |
|---|---|---|
| **Web 版（canvas 2D）** | `web/` | 真正能点开就玩的版本。画布 2D 全程序化绘制，零外部素材、零构建步骤。 |
| Godot 版（typed GDScript） | `game/` `addons/` `scenes/` | 目标形态，数值与 Web 版同源（同一份 `content.json`）。 |

两版共用同一套数值表 `data/content.json`（生成脚本 `tools/gen_content.py` 会把它复制到 `web/`），
所以调平衡只改一处，两边同时生效。

### Web 版怎么跑

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

仓库里已经放好了 `.github/workflows/pages.yml`，推上去就能用：

```bash
git init -b main && git add . && git commit -m "Tribes TD"
git remote add origin https://github.com/<你的账号>/tribes-td.git
git push -u origin main
```

然后到仓库 **Settings → Pages → Source** 选 **GitHub Actions**。
下一次 push 会自动把 `web/` 发到 `https://<你的账号>.github.io/tribes-td/`。

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
| 毒 / 弹射 / 眩晕的**真机制** | ⏳ 未做，当前用溅射 + 减速近似（见 ROADMAP） |
| 局外养成（六条职业线）、异步 PvP | ⏳ 未开始（属于迭代三） |
| 美术（Web 版） | ✅ 程序化绘制：地形预渲染、八边形石台塔、粒子、飘字、渐变 HUD |
| 美术（Godot 版） | ⏳ 仍为占位（Kenney CC0 + 程序化形状） |

**重要说明**：本机没有安装 Godot 引擎，所以运行时行为**没有实机验证过**。
已完成的是：`gdparse` 全量语法解析通过、`gdlint` 风格检查、数据一致性脚本校验（价位阶梯 / 路径正交 / 价位与档位对齐）。
你第一次用 Godot 打开时需要先让它完成一次导入（见下），如果哪里跑不起来，把报错贴给我。

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
| 选中/升级/出售 | 点已有塔 → 上方出现操作条 | 同 |
| 解锁下一档 | 点顶部进度条 / `K` | 点顶部进度条 |
| 换部族 | 点右上角部族条 / `Tab` | 点右上角部族条 |
| 技能 | `1` `2` `3` | 点底部技能按钮 |
| 重开 | `R` | — |

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
game/main.gd        状态机、输入、建造校验、棋盘与单位自绘
game/hud.gd         竖屏 HUD，全自绘 + 手动命中测试
web/                可玩的 canvas 2D 版。index.html 是打包产物（单文件），源码在 web/src/
web/src/js/         core.js（纯逻辑）/ render.js（全程序化绘制）/ main.js（引导与输入）
tools/build_web.py  把 web/src 内联成单文件 index.html
data/content.json   数值表（由 tools/gen_content.py 生成，不要手改）
tools/gen_content.py 数值生成器，带自查断言
tests/run_tests.gd  headless 自测
docs/               设计决策 / 迭代路线 / 素材许可
```

**为什么 data/content.json 要用脚本生成？** 因为 32 个塔的价位必须与档位表严格对齐，
手写 JSON 一定会漂。`gen_content.py` 里带了断言，价位一错，脚本直接失败。

---

## 素材与第三方代码

| 用途 | 来源 | 许可 |
|---|---|---|
| 塔防核心逻辑 | [godot-tower-defense-core-lite](https://github.com/openclawaimac/godot-tower-defense-core-lite) | MIT |
| 贴图（地面/士兵） | [Kenney Tower Defense Top-Down](https://kenney.nl/assets/tower-defense-top-down) | CC0 |
| 中文 HUD 字体 | 系统字体（微软雅黑 / 苹方 / Noto Sans CJK），不打包字体文件 | — |

MIT 与 CC0 都可商用，无需署名（但我们仍在 `docs/ASSETS.md` 里记录了出处）。
**没有引入任何 GPL / CC-BY-SA 素材**，避免后续商业化时的传染性许可问题。

美术是占位级别。真正的美术投入在立项之后，且必须重做世界观 —— 原版的「人族 / 雅典娜 / 魑魅魍魉」
属于暴雪 IP 与原作者创作，商业产品不能沿用。**机制不受版权保护，外壳必须换掉。**

---

## 已知限制

1. Godot 版的运行时行为没有实机验证（本机无 Godot 引擎）。首次导入出错请反馈。
2. Godot 版塔与敌人是程序化形状 + Kenney 小图，不是成品美术；Web 版是全程序化绘制。
3. 毒 / 弹射 / 眩晕只有近似，没有独立机制。
4. 只有 1 张地图、1 个难度。原版的「灾厄 / 大灾变」难度阶梯未做。
5. 没有存档、没有局外成长、没有联网。
6. Web 版没有音效，也没有做多语言。
