class_name WaveIntel
extends RefCounted
## 波次情报 —— 把 waves 里那堆 {enemy, count, interval} 翻译成玩家能用来决策的东西。
##
## 为什么这个文件值得存在：`TDWaveSpawner.wave_preview()` 在内核里早就写好了，
## 但从来没被调用过。没有情报，「造什么塔」就退化成「买得起就买」，
## 六个部族的克制关系只是数值表上的字，玩家一辈子不会主动去配。
##
## 情报的设计要点不是「显示数字」，是**只给一个建议**。
## 给出「飞行 10 只」+「需要能对空」两行，比列出全部属性有效得多 ——
## 玩家的注意力只有一次机会，给多了等于没给。

const TAG_BOSS := "BOSS"
const TAG_FLYING := "飞行"
const TAG_ARMORED := "重甲"
const TAG_SWARM := "怪海"
const TAG_FAST := "疾行"

## 建议的优先级。越靠前越「不看就必崩」。
## BOSS 最高是因为它一漏就是 6 点血，其次是飞行（对空塔不通用）。
const HINT_ORDER: Array[String] = [TAG_BOSS, TAG_FLYING, TAG_ARMORED, TAG_SWARM, TAG_FAST]

const HINTS := {
	TAG_BOSS: "漏一只掉 6 血，攒技能",
	TAG_FLYING: "需要能对空",
	TAG_ARMORED: "需要高单伤或毒（毒无视护甲）",
	TAG_SWARM: "需要溅射",
	TAG_FAST: "需要减速",
}


## 某一波的敌人构成。[{id, name, count, tags, color}]
## 同一类型的多组会合并（第 10 波是两个重装组，玩家眼里就是「10 只重装」）。
static func rows(content: TDContent, wave: int) -> Array[Dictionary]:
	var merged: Dictionary = {}
	var order: Array[String] = []
	for g: Dictionary in content.wave_groups(wave):
		var id: String = str(g.get("enemy", ""))
		if not merged.has(id):
			merged[id] = {"id": id, "count": 0, "flying": false, "armor": 0.0,
				"speed": 0.0, "hp": 0.0}
			order.append(id)
		var m: Dictionary = merged[id]
		m["count"] = int(m["count"]) + int(g.get("count", 0))
		m["flying"] = bool(m["flying"]) or bool(g.get("flying", false))
		m["armor"] = maxf(float(m["armor"]), float(g.get("armor", 0.0)))
		m["speed"] = maxf(float(m["speed"]), float(g.get("speed", 0.0)))
		m["hp"] = maxf(float(m["hp"]), float(g.get("hp", 0.0)))

	var out: Array[Dictionary] = []
	for id: String in order:
		var m: Dictionary = merged[id]
		var def: Dictionary = content.enemies.get(StringName(id), {})
		out.append({
			"id": id,
			"name": str(def.get("name", id)),
			"count": int(m["count"]),
			"tags": tags_for(m),
			"color": color_for(id, m),
		})
	return out


static func tags_for(m: Dictionary) -> Array[String]:
	var tags: Array[String] = []
	if float(m.get("hp", 0.0)) >= 1000.0:
		tags.append(TAG_BOSS)
	if bool(m.get("flying", false)):
		tags.append(TAG_FLYING)
	if float(m.get("armor", 0.0)) >= 3.0:
		tags.append(TAG_ARMORED)
	if int(m.get("count", 0)) >= 12:
		tags.append(TAG_SWARM)
	if float(m.get("speed", 0.0)) >= 85.0:
		tags.append(TAG_FAST)
	return tags


## 敌人没有颜色字段（美术是按 id 硬编码的），这里跟 main.gd 的 _enemy_color 对齐。
static func color_for(id: String, m: Dictionary) -> Color:
	match id:
		"brute":
			return Color("#F0A878")
		"flyer":
			return Color("#A8E0FF")
		"boss":
			return Color("#FF8FA8")
		"scout":
			return Color("#FFE98A")
		_:
			return Color("#CBDCEA")


## 没有触发任何标签时的默认建议。别留空 —— 空的建议栏会让整条控制带看起来像坏了，
## 而且「常规波可以攒钱」本身就是本作最该教给玩家的那句话。
const HINT_DEFAULT := "常规波，可以攒钱等质变"


## 这一波最该提醒玩家的一句话。
static func hint(rows_v: Array[Dictionary]) -> String:
	for want: String in HINT_ORDER:
		for r: Dictionary in rows_v:
			if (r["tags"] as Array).has(want):
				return str(HINTS.get(want, ""))
	return HINT_DEFAULT


## 「6 步兵 · 5 斥候」这样的单行摘要。超过 max_items 时折叠成「+3 种」。
static func summary(rows_v: Array[Dictionary], max_items: int = 3) -> String:
	var parts: Array[String] = []
	for i: int in range(mini(rows_v.size(), max_items)):
		var r: Dictionary = rows_v[i]
		parts.append("%d %s" % [int(r["count"]), str(r["name"])])
	if rows_v.size() > max_items:
		parts.append("+%d 种" % (rows_v.size() - max_items))
	return " · ".join(parts)
