class_name HeroUnit
extends RefCounted
## 英雄 —— RPG 的那双手。
##
## 它存在的意义不是「多一个塔」，而是给玩家一个**可以动的东西**：
## 哪一段要崩就把英雄拖过去补位，打完再拖回来。塔是静态的，英雄是主动的。
##
## 一条不能破的规则：**英雄击杀给金币，但不给功勋。**
## 功勋只来自防御单位自己的击杀，这是双资源博弈的根。原版里召唤物和技能击杀
## 都不计功勋，英雄同理 —— 否则「玩英雄」就成了绕过双资源博弈的捷径。
## 这条规则不靠文档提醒，靠代码路径保证：英雄只调 TDEnemy.take_damage()，
## 永远不碰 TDTower.kills，而 MeritSystem 只认 TDTower.kills。

const MAX_LEVEL := 10
const KILLS_PER_LEVEL := 6
const SLOTS: Array[String] = ["sword", "amulet", "boots"]
const SLOT_NAMES := {"sword": "剑", "amulet": "符", "boots": "靴"}
## 框里只有 28px 宽，写「护符」两个字一定折行。单字 + 颜色足够区分。
const SLOT_FULL := {"sword": "长剑", "amulet": "护符", "boots": "战靴"}
const SLOT_COLORS := {
	"sword": Color("#E8846B"),
	"amulet": Color("#8FB8E8"),
	"boots": Color("#8BE0A8"),
}
const EQUIP_MAX := 3
const MERGE_COUNT := 3

var pos: Vector2 = Vector2(300, 300)
var move_to: Vector2 = Vector2.ZERO
var has_move: bool = false
var level: int = 1
var kills: int = 0
var equipped: Dictionary = {"sword": 0, "amulet": 0, "boots": 0}

var aim: float = -PI / 2.0
var attack_flash: float = 0.0

var _cd: float = 0.0
## 重复装备的库存：{"sword:1": 2} 表示攒了 2 件一级剑，够 3 件自动合成二级
var _parts: Dictionary = {}


# ------------------------------------------------------------------ 属性

func attack() -> float:
	var base: float = 9.0 + 2.6 * float(level - 1)
	return base * (1.0 + 0.22 * float(int(equipped["sword"])))


func interval() -> float:
	return 0.85 * (1.0 - 0.10 * float(int(equipped["amulet"])))


func attack_range() -> float:
	return 118.0 + 14.0 * float(int(equipped["boots"]))


func travel_speed() -> float:
	return 210.0 + 22.0 * float(int(equipped["boots"]))


func slot_level(kind: String) -> int:
	return int(equipped.get(kind, 0))


# ------------------------------------------------------------------ 每帧

## 返回本次攻击的目标（没有目标返回 null）。调用方负责画弹道/粒子。
func tick(delta: float, enemies: Array[TDEnemy]) -> TDEnemy:
	attack_flash = maxf(0.0, attack_flash - delta)
	if has_move:
		pos = pos.move_toward(move_to, travel_speed() * delta)
		if pos.distance_to(move_to) < 1.0:
			has_move = false
	_cd -= delta
	if _cd > 0.0:
		return null
	var target: TDEnemy = _pick(enemies)
	if target == null:
		return null
	_cd = interval()
	aim = (target.position - pos).angle()
	attack_flash = 0.12
	target.take_damage(attack())
	if target.done and target.hp <= 0.0:
		kills += 1
		_maybe_level_up()
	return target


## 索敌策略跟「最先」一致：打得最靠前的，因为它最危险。
func _pick(enemies: Array[TDEnemy]) -> TDEnemy:
	var best: TDEnemy = null
	var best_progress: float = -INF
	var reach: float = attack_range()
	for e: TDEnemy in enemies:
		if e.done or e.position.distance_to(pos) > reach:
			continue
		if e.progress > best_progress:
			best_progress = e.progress
			best = e
	return best


func _maybe_level_up() -> void:
	while level < MAX_LEVEL and kills >= level * KILLS_PER_LEVEL:
		level += 1


# ------------------------------------------------------------------ 移动

func order_move(target: Vector2, bounds: Rect2) -> void:
	move_to = Vector2(
		clampf(target.x, bounds.position.x, bounds.end.x),
		clampf(target.y, bounds.position.y, bounds.end.y))
	has_move = true


func teleport(target: Vector2, bounds: Rect2) -> void:
	pos = Vector2(
		clampf(target.x, bounds.position.x, bounds.end.x),
		clampf(target.y, bounds.position.y, bounds.end.y))
	has_move = false


# ------------------------------------------------------------------ 装备

## 捡到一件装备。返回给玩家看的一句话（空串表示「收下了，没什么可说」）。
##
## 合成规则故意做成自动的：手机上不该为了合装备再开一层面板。
## 更好的那件直接换上；重复的攒着，三件同名同级自动升一级。
func pick_equipment(kind: String, lvl: int) -> String:
	if not equipped.has(kind):
		return ""
	var cur: int = int(equipped[kind])
	if lvl > cur:
		equipped[kind] = lvl
		return "%s 换上 %d 级" % [SLOT_FULL.get(kind, kind), lvl]
	if lvl >= EQUIP_MAX:
		return ""  # 已经满级，重复件没有去处
	var key: String = "%s:%d" % [kind, lvl]
	_parts[key] = int(_parts.get(key, 0)) + 1
	if int(_parts[key]) < MERGE_COUNT:
		return ""
	_parts.erase(key)
	var next: int = mini(EQUIP_MAX, lvl + 1)
	if next <= cur:
		return ""
	equipped[kind] = next
	return "%s 合成到 %d 级" % [SLOT_FULL.get(kind, kind), next]


func pending_count(kind: String, lvl: int) -> int:
	return int(_parts.get("%s:%d" % [kind, lvl], 0))


## 拾取范围内的掉落物，返回被捡走的那几个。
## 只算「哪些能捡」，删数组和放特效留给调用方 —— 这样这段逻辑可以单独测，
## 不用把整个场景实例化出来。
func collect_near(items: Array[Dictionary], radius: float) -> Array[Dictionary]:
	var got: Array[Dictionary] = []
	for it: Dictionary in items:
		if (it["pos"] as Vector2).distance_to(pos) <= radius:
			got.append(it)
	return got


func _stars() -> void:
	pass


# ------------------------------------------------------------------ 重开

func reset(start: Vector2) -> void:
	pos = start
	move_to = start
	has_move = false
	level = 1
	kills = 0
	equipped = {"sword": 0, "amulet": 0, "boots": 0}
	_parts.clear()
	aim = -PI / 2.0
	attack_flash = 0.0
	_cd = 0.0
