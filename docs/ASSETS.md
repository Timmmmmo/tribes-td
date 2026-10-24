# 素材与第三方代码清单

## 代码

| 名称 | 地址 | 许可 | 用法 |
|---|---|---|---|
| godot-tower-defense-core-lite | https://github.com/openclawaimac/godot-tower-defense-core-lite | **MIT** | 塔防内核，位于 `addons/td_core/`，未改动。许可全文见 `docs/LICENSE-td_core-MIT.txt` |

MIT 允许商用、修改、再分发，唯一义务是保留版权声明与许可全文。本项目已保留。

## 美术

**当前版本没有任何图片依赖 —— 画面 100% 由代码程序化绘制。**

| 层 | 做法 | 在哪 |
|---|---|---|
| 棋盘地形 | 开局一次性烘焙成 576×960 贴图：连续渐变草地 + 5200 根草叶 + 石板路瓦片（12 套变体） | `game/art.gd` · `TDArt.bake_map()` |
| 塔 | 八边形石台（顶点色渐变）+ 旋转符文环 + 炮管 + 塔身辉光/内高光 | `game/main.gd` · `_draw_tower()` |
| 敌人 | 五种轮廓 + 上下渐变 + 高光 + 朝向眼睛 + 圆角血条 | `game/main.gd` · `_draw_enemy()` |
| 特效 | 软光斑贴图（一次性烘焙的径向渐变）、粒子、光束、飘字、震屏 | `TDArt.glow()` + `main.gd` 特效层 |
| HUD | 圆角玻璃面板（渐变 + 描边 + 顶边内高光） | `game/hud.gd` · `_panel()` |

两个关键技巧，换别的引擎也通用：

1. **Godot 没有 `createLinearGradient`** —— 用 `draw_polygon(points, colors)` 的顶点色插值代替，
   给上下顶点不同颜色就等于拿到了线性渐变。
2. **径向渐变**用一张 128×128 的软光斑贴图拉伸，而不是叠同心圆。
   同心圆在暗底上一定能看出色阶。

### 历史素材（已不再加载）

| 名称 | 地址 | 许可 | 现状 |
|---|---|---|---|
| Kenney Tower Defense (Top-Down) | https://kenney.nl/assets/tower-defense-top-down | **CC0 1.0** | `assets/sprites/` 里保留 10 张参考图，**代码已不引用**，导出时被 `exclude_filter` 排除 |

早期 Godot 版用过其中两张（草/土、士兵）做贴图，实际效果比程序化绘制更平：
那两张「草」「土」其实是纯色块，铺上去等于把草地刷成一块油漆。
换成程序化绘制后才有了本文开头那张分层表。CC0 无署名义务，保留文件只是留个来路。

## 字体

| 名称 | 地址 | 许可 | 用法 |
|---|---|---|---|
| Noto Sans SC | https://github.com/googlefonts/noto-cjk | **OFL 1.1** | 打包的中文子集 `assets/fonts/game_cjk.ttf`（175KB） |

**为什么必须打包**：Godot 的 Web 导出里 `SystemFont` 查不到宿主字体，中文会全部渲染成豆腐块。
桌面端仍有系统字体优先，打包子集只作为 `fallback` 和 Web 端的主字体。

**为什么是子集**：完整 Noto Sans SC 有 8MB，而本作用到的汉字一共 707 个。
`tools/subset_font.py` 会扫描 `data/content.json` 与所有 `.gd` 里的文本，用
`fontTools.subset` 裁出只含这些字的 TTF，实测 8136KB → 175KB。
源字体（`assets/fonts/src_*.otf`）不进仓库，需要重新生成时按 README 下载即可。

OFL 允许嵌入、修改、再分发，义务是保留版权声明与许可全文，且修改版本不得使用保留字体名。
子集属于「修改版本」，因此输出文件命名为 `game_cjk.ttf` 而非 Noto 系列名。

## 明确排除的素材

调研阶段评估过、但因许可原因**未引入**：

| 名称 | 排除原因 |
|---|---|
| quiver-dev/tower-defense-godot4（Outpost Assault） | MIT，但其美术资源走 Git LFS 且部分来源不明，无法逐张确认许可 |
| LucasFerguson/Godot-4-Tower-Defense-Template | MIT，但美术风格与 Kenney top-down 不统一，混用会导致画面割裂。仅作架构参考（`_ref/`，未纳入版本控制） |
| LPC (Liberated Pixel Cup) 素材库 | CC-BY-SA 3.0 + GPLv3，**传染性许可**，商业化风险高 |
| 魔兽争霸 III 原始美术 | 暴雪版权，任何形式使用都不允许 |

## 版权红线（商业化前必读）

本项目的**机制**借鉴自《人族无敌》，这不构成侵权 —— 玩法规则、数值结构、系统设计不受著作权保护。

但以下四类**绝对不能沿用**：

1. **名称**：「人族无敌」是原作者的地图名。
2. **角色与剧情**：雅典娜、魑魅魍魉军团、国王哈迪斯，这是原作者的创作表达。
3. **魔兽 IP 元素**：人族/兽族/不死/暗夜的设定、单位名、美术，属于暴雪。
4. **原作地图文件**：`.w3x` 文件本身受保护，不能解包取其资源。

本项目已全部替换为原创命名（六部族：游侠 / 咒术 / 猎手 / 盗贼 / 狂战 / 剑咏），
BOSS 名「雅典娜化身」**仅为开发期占位，上线前必须改掉**。
