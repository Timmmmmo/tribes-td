class_name RunReport
extends RefCounted
## 一局结算与失败归因。
##
## 为什么这个值得单独做一个类：塔防输了以后最常见的一句话是「我再试试」，
## 而玩家其实不知道自己刚才错在哪 —— 于是下一局会重复同一个错误。
## 归因页要做的事只有一件：把「你输了」翻译成「你死于什么」。
##
## 判断依据不是感觉，是数值：记录每种怪漏了几只、各掉多少生命，
## 谁掉得多谁就是主因。然后用一张对照表把这个主因翻译成一条可执行的建议。
##
## 这个类不碰任何渲染，纯数据，可以 headless 测。

## 每种怪的「下次怎么办」。键是 content.json 里的 enemy id。
## 写法要求：一句话说清**机制**，不要写「多造塔」这种正确的废话。
const TIPS := {
	&"scout": "斥候 96 速，是全场最快的怪。漏它通常不是缺伤害，是缺减速。",
	&"soldier": "步兵是基础怪。漏一群说明清场太慢 —— 加溅射，或者把塔往前段压，让它多走几座塔。",
	&"brute": "重装 3 点护甲，小伤害会被吃掉大半。毒无视护甲，比继续堆单体伤害快得多。",
	&"flyer": "飞行只吃能对空的塔。回去看一眼你造的是不是全地面塔。",
	&"boss": "BOSS 一只掉 6 血，等于六只步兵。攒着裁决和冰封，等它走进塔群里一起砸。",
}

const TIP_UNKNOWN := "这一局的漏怪构成很分散，说明没有单一短板 —— 是整体输出不够，该升档了。"

const EARLY_WAVE := 5
const TIP_EARLY := "第 %d 波就守不住，问题在开局经济：先两座弓箭滚起来，别急着攒钱解锁下一档。"
const TIP_LATE := "守到第 %d 波才崩，构筑本身没问题，是后期的钱没换成伤害 —— 攒够一次质变，别平均投资。"

var waves_cleared: int = 0
var total_waves: int = 0

var kills: Dictionary = {}        ## enemy id -> 只数
var leaks: Dictionary = {}        ## enemy id -> 只数
var leak_damage: Dictionary = {}  ## enemy id -> 掉了多少生命

var gold_earned: int = 0
var towers_built: int = 0
var hero_level: int = 1
var lives_left: int = 0
var max_lives: int = 0
var duration: float = 0.0
var won: bool = false

var content: TDContent


func setup(p_content: TDContent) -> void:
	content = p_content


func record_kill(e: TDEnemy) -> void:
	var key: StringName = e.id
	kills[key] = int(kills.get(key, 0)) + 1


func record_leak(e: TDEnemy) -> void:
	var key: StringName = e.id
	leaks[key] = int(leaks.get(key, 0)) + 1
	var dmg: int = maxi(1, e.leak_damage)
	leak_damage[key] = int(leak_damage.get(key, 0)) + dmg


func enemy_name(id: StringName) -> String:
	if content != null:
		var d: Dictionary = content.enemies.get(id, {})
		if d.has("name"):
			return str(d["name"])
	return String(id)


func kill_count() -> int:
	var n: int = 0
	for v: int in kills.values():
		n += v
	return n


func leak_count() -> int:
	var n: int = 0
	for v: int in leaks.values():
		n += v
	return n


## 漏掉的总生命。这是判断「谁害死了你」的唯一正确权重：
## 漏 3 只重装（2 血/只）= 6 点，比漏 4 只斥候（1 血/只）= 4 点更致命，
## 但按只数排会把斥候排到第一。所以按掉血排。
func leak_damage_total() -> int:
	var n: int = 0
	for v: int in leak_damage.values():
		n += v
	return n


## 主因：{id, name, count, damage, share}。没有漏怪就返回空字典。
func blame() -> Dictionary:
	var total: int = leak_damage_total()
	if total <= 0:
		return {}
	var worst: StringName = &""
	var worst_dmg: int = -1
	for key: StringName in leak_damage.keys():
		var d: int = int(leak_damage[key])
		if d > worst_dmg:
			worst_dmg = d
			worst = key
	return {
		"id": worst,
		"name": enemy_name(worst),
		"count": int(leaks.get(worst, 0)),
		"damage": worst_dmg,
		"share": float(worst_dmg) / float(total),
	}


## 漏怪构成，按掉血从多到少。给结算页列前三条。
func breakdown(limit: int = 3) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for key: StringName in leak_damage.keys():
		rows.append({
			"id": key,
			"name": enemy_name(key),
			"count": int(leaks.get(key, 0)),
			"damage": int(leak_damage[key]),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["damage"]) > int(b["damage"]))
	if rows.size() > limit:
		rows.resize(limit)
	return rows


## 一句话建议。先按「主因」给具体机制，主因不明确才退回「整体输出不够」。
## 但早期崩盘永远优先讲开局，因为那时原因一定是经济不是构筑。
func advice() -> String:
	if won:
		return "通关了。下一局试试不提前开波，看纯经济能撑到第几波。"
	if waves_cleared < EARLY_WAVE:
		return TIP_EARLY % maxi(waves_cleared, 1)
	var b: Dictionary = blame()
	if b.is_empty():
		return TIP_UNKNOWN
	var id: StringName = b["id"]
	if TIPS.has(id):
		return str(TIPS[id])
	return TIP_UNKNOWN


## 结算页要显示的全部内容。渲染层只管排版，不再做判断。
func verdict() -> Dictionary:
	var lines: Array[String] = []
	lines.append("坚持到第 %d 波" % waves_cleared)
	lines.append("清掉 %d 只 · 漏掉 %d 只 · 掉了 %d 点生命" % [
		kill_count(), leak_count(), leak_damage_total()])
	lines.append("攒下 %d 金币 · 造了 %d 座塔 · 英雄 Lv.%d" % [
		gold_earned, towers_built, hero_level])

	var b: Dictionary = blame()
	var blame_line: String = ""
	if not b.is_empty():
		blame_line = "%s ×%d　掉了 %d 点生命（占 %d%%）" % [
			b["name"], b["count"], b["damage"], int(round(float(b["share"]) * 100.0))]

	return {
		"won": won,
		"title": "守住最后一波" if won else "基地失守",
		"headline": "第 %d / %d 波　生命 %d / %d" % [
			waves_cleared, total_waves, lives_left, max_lives],
		"blame": blame_line,
		"lines": lines,
		"breakdown": breakdown(),
		"advice": advice(),
		"duration": duration,
	}


## 时长格式化成 3:24。结算页和悬浮提示都用它。
static func clock(seconds: float) -> String:
	var s: int = maxi(0, int(seconds))
	return "%d:%02d" % [s / 60, s % 60]
