# -*- coding: utf-8 -*-
"""生成 data/content.json —— 六部族塔防的数值表。

设计原则（继承自《人族无敌》的机制内核）：
1. 阶梯式价位：40 / 90 / 190 / 400 / 850 / 1800 / 3800，每档 ×2.0~2.2。
   相邻档之间没有「补一点」的中间态，逼玩家在「攒」和「铺」之间二选一。
2. 六部族 = 六套数值指纹，不是六张皮：
   游侠=低伤高攻速+减速 / 咒术=高伤低攻速+溅射 / 猎手=中伤高射程+对空
   盗贼=低伤+击杀额外金币 / 狂战=短射程高伤+强减速 / 剑咏=中伤+范围
3. 毒 / 弹射 / 眩晕在原版是独立机制，td_core 只提供
   「伤害 / 攻速 / 射程 / 溅射 / 减速(slow, slow_time) / 对空」六个维度，
   本切片用这六个维度组合近似表达，真机制留待迭代二（见 docs/ROADMAP.md）。

注意两处字段名必须对齐 td_core 的读取逻辑：
  - 敌人漏怪伤害字段是 "leak"，不是 "leak_damage"
  - 减速必须同时给 "slow"（速度乘数）和 "slow_time"（秒）
"""
import io
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TIERS = [40, 90, 190, 400, 850, 1800, 3800]

# 职业主色，塔按档位由暗到亮
TRIBE_COLORS = {
    "r": "#5BD1A6",  # 游侠
    "o": "#B07BE0",  # 咒术
    "h": "#E0C05B",  # 猎手
    "g": "#E07B5B",  # 盗贼
    "b": "#D14B4B",  # 狂战
    "s": "#5B9BE0",  # 剑咏
}


def shift(hex_color, t):
    """按档位把颜色由暗推到亮，t 在 0..1。"""
    h = hex_color.lstrip("#")
    rgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    dark = [c * 0.55 for c in rgb]
    light = [c + (1.0 - c) * 0.35 for c in rgb]
    out = [dark[i] + (light[i] - dark[i]) * t for i in range(3)]
    return "#%02X%02X%02X" % tuple(int(round(c * 255)) for c in out)


def tower(tid, name, desc, tier, dmg, rng, itv, **kw):
    d = {
        "id": tid,
        "name": name,
        "desc": desc,
        "cost": TIERS[tier],
        "tier": tier + 1,
        "damage": dmg,
        "range": rng,
        "interval": itv,
        "targeting": kw.pop("targeting", "first"),
        "splash": kw.pop("splash", 0),
        "hits_air": kw.pop("hits_air", True),
        "hits_ground": kw.pop("hits_ground", True),
        "slow": kw.pop("slow", 1.0),
        "slow_time": kw.pop("slow_time", 0.0),
        "color": shift(TRIBE_COLORS[tid[0]], tier / 6.0),
        "shape": kw.pop("shape", "square"),
        "bonus_gold": kw.pop("bonus_gold", 0),
    }
    # 三档内部升级：同一档位内的纵向成长，与「跨档解锁」是两条不同的曲线。
    lv = []
    for i in range(1, 4):
        lv.append({
            "cost": int(TIERS[tier] * (0.6 + 0.5 * i)),
            "damage": round(dmg * (1 + 0.42 * i), 1),
            "range": rng + 12 * i,
            "interval": round(itv * (1 - 0.09 * i), 3),
        })
    d["levels"] = lv
    d.update(kw)
    return d


# ---------------------------------------------------------------- 游侠 Ranger
# 低伤 / 高攻速 / 减速。前期最强，后期用减速给队友创造输出窗口。
RANGER = [
    tower("r1", "箭手", "射速快、伤害低。前期铺三个就能过前三波。", 0,
          3, 132, 0.50, shape="circle"),
    tower("r2", "毒羽", "命中附带减速，打不死也拖得住。", 1,
          5.5, 145, 0.45, slow=0.78, slow_time=1.6, shape="circle"),
    tower("r3", "猎鹰哨", "射程拉长，能同时覆盖两段路。", 2,
          9, 175, 0.42, shape="diamond"),
    tower("r4", "穿云手", "单点高伤，专治重甲。", 3,
          22, 190, 0.55, targeting="strongest", shape="diamond"),
    tower("r5", "冰晶塔", "大范围减速，是整条防线的骨架。", 4,
          16, 168, 0.38, splash=52, slow=0.62, slow_time=2.2, shape="hex"),
    tower("r6", "后羿", "全图最远的单体，BOSS 波的主力。", 5,
          58, 240, 0.62, targeting="strongest", shape="hex"),
    tower("r7", "射日台", "一次三连，溅射 + 长射程。终局单位。", 6,
          96, 260, 0.70, splash=70, shape="star"),
]

# ---------------------------------------------------------------- 咒术 Occult
# 高伤 / 低攻速 / 大溅射。清小怪海最快，打 BOSS 乏力。
OCCULT = [
    tower("o1", "学徒", "单体 6 点，慢，但便宜到可以堆。", 0,
          6, 120, 0.95),
    tower("o2", "暴风术士", "小范围溅射，第一波就够用。", 1,
          11, 128, 0.88, splash=40),
    tower("o3", "凤凰", "大范围持续灼烧（以溅射近似）。", 2,
          19, 140, 0.82, splash=64, shape="diamond"),
    tower("o4", "波浪术士", "范围再放大，清杂核心。", 3,
          38, 152, 0.92, splash=88, shape="hex"),
    tower("o5", "魔法院长", "终极法术，一次清半屏。", 4,
          74, 170, 1.05, splash=110, shape="star"),
]

# ---------------------------------------------------------------- 猎手 Hunter
# 中伤 / 高射程 / 对空强。原版要求塔朝向路径，本切片以「长射程 + 窄身位」近似。
HUNTER = [
    tower("h1", "小猎手", "射程一般，但能打空中。", 0,
          4, 138, 0.62),
    tower("h2", "鹰眼", "射程拉到 160，优先打最前面的。", 1,
          7, 160, 0.58, targeting="first", shape="diamond"),
    tower("h3", "高级猎手", "伤害翻倍，仍保持高射速。", 2,
          13, 172, 0.52, shape="diamond"),
    tower("h4", "狼王", "对空特化，飞行波不会翻车。", 3,
          27, 185, 0.50, shape="hex"),
    tower("h5", "猎王", "超远射程，站后排也能打满全场。", 4,
          52, 215, 0.45, targeting="strongest", shape="star"),
]

# ---------------------------------------------------------------- 盗贼 Rogue
# 低伤 / 高攻速 / 击杀额外金币。原版「偷钱」机制的直接移植。
ROGUE = [
    tower("g1", "扒手", "打得很轻，但每杀一个多给 2 金币。", 0,
          2.5, 118, 0.42, bonus_gold=2),
    tower("g2", "小强", "攻速极快，靠数量吃钱。", 1,
          4.2, 124, 0.34, bonus_gold=3, shape="circle"),
    tower("g3", "强盗", "单次伤害上来，经济开始滚。", 2,
          8.5, 134, 0.36, bonus_gold=4, shape="diamond"),
    tower("g4", "魔法大盗", "偷取效率翻倍，滚雪球的关键。", 3,
          15, 142, 0.34, bonus_gold=7, shape="hex"),
    tower("g5", "剑圣", "终局单位，钱越多它越强。", 4,
          34, 150, 0.28, bonus_gold=12, shape="star"),
]

# ---------------------------------------------------------------- 狂战 Berserker
# 短射程高伤 + 强减速。必须放路中间，回报和风险都最大。
BERSERK = [
    tower("b1", "苦工", "射程只有 100，但伤害是同价两倍。", 0,
          7, 100, 0.85),
    tower("b2", "打手", "短射程高伤，靠位置换输出。", 1,
          14, 106, 0.80, shape="circle"),
    tower("b3", "猛男", "命中带强减速，贴身缠住怪。", 2,
          24, 112, 0.78, splash=30, slow=0.72, slow_time=1.2, shape="diamond"),
    tower("b4", "拳击手", "范围击退（以溅射 + 减速近似）。", 3,
          44, 120, 0.82, splash=48, slow=0.80, slow_time=1.0, shape="hex"),
    tower("b5", "拳王", "近身最强单体，BOSS 波的答案。", 4,
          88, 128, 0.90, targeting="strongest", shape="star"),
]

# ---------------------------------------------------------------- 剑咏 Spellblade
# 均衡 + 范围。原版「游侠在前、魔剑在后」的配对玩法靠射程差实现。
SPELLBLADE = [
    tower("s1", "见习剑士", "均衡，没有明显短板。", 0,
          5, 128, 0.66),
    tower("s2", "魔剑士", "攻击附带小范围波及。", 1,
          10, 140, 0.62, splash=34, shape="circle"),
    tower("s3", "狼骑士", "射程长 + 溅射，适合放后排。", 2,
          18, 168, 0.60, splash=44, shape="diamond"),
    tower("s4", "喷火兵", "大范围清场，克小怪海。", 3,
          33, 148, 0.70, splash=76, shape="hex"),
    tower("s5", "剑咏宗师", "终极形态，溅射 100 的终局单位。", 4,
          66, 160, 0.75, splash=100, shape="star"),
]

TOWERS = RANGER + OCCULT + HUNTER + ROGUE + BERSERK + SPELLBLADE

# ---------------------------------------------------------------- 敌人
# 字段名对齐 td_core：漏怪伤害是 "leak"
ENEMIES = [
    {"id": "soldier", "name": "步兵", "hp": 42, "speed": 54, "armor": 0,
     "bounty": 6, "leak": 1, "flying": False},
    {"id": "scout", "name": "斥候", "hp": 26, "speed": 96, "armor": 0,
     "bounty": 5, "leak": 1, "flying": False},
    {"id": "brute", "name": "重装", "hp": 165, "speed": 38, "armor": 3,
     "bounty": 14, "leak": 2, "flying": False},
    {"id": "flyer", "name": "飞行", "hp": 58, "speed": 82, "armor": 1,
     "bounty": 8, "leak": 1, "flying": True},
    {"id": "boss", "name": "雅典娜化身", "hp": 1750, "speed": 30, "armor": 6,
     "bounty": 130, "leak": 6, "flying": False},
]


def wave(groups, bonus):
    return {"groups": [{"enemy": e, "count": c, "interval": i} for e, c, i in groups],
            "bonus": bonus}


# 15 波：1-5 发育 / 6-10 成型 / 11-15 决战
WAVES = [
    wave([("soldier", 6, 0.9)], 22),
    wave([("soldier", 8, 0.8)], 26),
    wave([("soldier", 6, 0.8), ("scout", 5, 0.5)], 30),
    wave([("scout", 12, 0.42)], 34),
    wave([("soldier", 10, 0.7), ("flyer", 4, 0.9)], 40),
    wave([("brute", 4, 1.3), ("soldier", 8, 0.6)], 48),
    wave([("flyer", 10, 0.55)], 52),
    wave([("brute", 6, 1.1), ("scout", 10, 0.4)], 58),
    wave([("soldier", 16, 0.45), ("flyer", 6, 0.7)], 64),
    wave([("brute", 8, 1.0), ("brute", 4, 1.0)], 72),
    wave([("flyer", 14, 0.45), ("scout", 14, 0.35)], 78),
    wave([("brute", 10, 0.9), ("flyer", 8, 0.6)], 86),
    wave([("soldier", 24, 0.35), ("brute", 8, 0.9)], 92),
    wave([("brute", 14, 0.8), ("flyer", 12, 0.5)], 104),
    wave([("boss", 1, 1.0), ("brute", 10, 0.9), ("flyer", 10, 0.6)], 160),
]

# 竖屏地图 9 × 15 格，cell 64 → 世界坐标 576 × 960
# 路径从顶部左侧进入，蛇形向下，底部出屏
MAP = {
    "cols": 9,
    "rows": 15,
    "cell": 64,
    "path": [[-1, 1], [2, 1], [2, 4], [6, 4], [6, 1], [7, 1],
             [7, 7], [2, 7], [2, 10], [7, 10], [7, 13], [3, 13], [3, 15]],
    "blocked": [[0, 5], [8, 3], [1, 9], [5, 9], [8, 11], [0, 14], [4, 6]],
}

DATA = {
    "start_gold": 150,
    "lives": 20,
    "hp_scale_per_wave": 1.14,
    "towers": TOWERS,
    "enemies": ENEMIES,
    "waves": WAVES,
    "map": MAP,
    # 以下为本切片自有扩展字段，td_core 会忽略不认识的键
    "tier_prices": TIERS,
    "professions": [
        {"id": "ranger", "name": "游侠", "color": TRIBE_COLORS["r"],
         "towers": [t["id"] for t in RANGER], "desc": "低伤高攻速 + 减速，前期最强"},
        {"id": "occult", "name": "咒术", "color": TRIBE_COLORS["o"],
         "towers": [t["id"] for t in OCCULT], "desc": "高伤低攻速 + 大溅射，清杂最快"},
        {"id": "hunter", "name": "猎手", "color": TRIBE_COLORS["h"],
         "towers": [t["id"] for t in HUNTER], "desc": "中伤高射程 + 对空，飞行波不翻车"},
        {"id": "rogue", "name": "盗贼", "color": TRIBE_COLORS["g"],
         "towers": [t["id"] for t in ROGUE], "desc": "低伤 + 击杀额外金币，滚雪球"},
        {"id": "berserk", "name": "狂战", "color": TRIBE_COLORS["b"],
         "towers": [t["id"] for t in BERSERK], "desc": "短射程高伤 + 强减速，靠位置换输出"},
        {"id": "spell", "name": "剑咏", "color": TRIBE_COLORS["s"],
         "towers": [t["id"] for t in SPELLBLADE], "desc": "均衡 + 范围，需要与游侠配对"},
    ],
}

if __name__ == "__main__":
    out = os.path.join(ROOT, "data", "content.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with io.open(out, "w", encoding="utf-8") as f:
        json.dump(DATA, f, ensure_ascii=False, indent=1)
    print("wrote %s" % out)
    print("towers=%d enemies=%d waves=%d" % (len(TOWERS), len(ENEMIES), len(WAVES)))

    p = MAP["path"]
    for i in range(1, len(p)):
        dx = abs(p[i][0] - p[i - 1][0])
        dy = abs(p[i][1] - p[i - 1][1])
        assert (dx == 0) != (dy == 0), "diagonal segment at %d" % i
    print("path OK: %d waypoints, orthogonal" % len(p))

    for i in range(1, len(TIERS)):
        assert TIERS[i] >= TIERS[i - 1] * 1.9, "tier gap too small at %d" % i
    print("tiers OK: %s" % TIERS)

    # 每条职业塔的价位必须等于所在档位，否则「阶梯」就断了
    by_id = {t["id"]: t for t in TOWERS}
    for prof in DATA["professions"]:
        for tid in prof["towers"]:
            t = by_id[tid]
            assert t["cost"] == TIERS[t["tier"] - 1], "cost mismatch %s" % tid
    print("profession cost ladder OK (%d towers)" % len(TOWERS))
