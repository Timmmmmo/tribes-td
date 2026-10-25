class_name BossPhases
extends RefCounted
## BOSS 的两个阶段转换。
##
## 为什么要做：原来 BOSS 只是一只「血很厚的重装」，玩家打它的过程里没有任何
## 决策点 —— 打不过就是打不过，打得过就是等它慢慢走完。这是全程最长的一次
## 交互，却是最平的一段。加阶段转换花不了多少代码，但它把「一场输出考试」
## 变成了「两次临时改构筑」。
##
## 两个阶段的选型原则：每一阶段必须**告诉玩家一个具体的错误**，
## 而不是单纯变强（单纯变强只会让人觉得被欺负）。
##
##   70% → 召唤三只斥候。惩罚「只堆单体、没有清场」。
##   40% → 狂暴（移速 ×1.55）。惩罚「没有减速/毒，靠时间磨」。
##
## 实现约束和 status.gd 一样：一行不改 addons/td_core，只读写公开字段。

const BOSS_ID := &"boss"

## 触发阈值，按当前血量比例。顺序必须从高到低。
const THRESHOLDS: Array[float] = [0.70, 0.40]

const SUMMON := {
	"into": &"scout",
	"count": 3,
	"hp_scale": 0.55,
	"bounty_scale": 0.5,
}

const ENRAGE_SPEED := 1.55

const PHASE_TITLE := {
	2: "第一阶段 · 召唤援军",
	3: "第二阶段 · 狂暴",
}

const PHASE_DETAIL := {
	2: "三只斥候从它身上裂出来 —— 你缺清场",
	3: "护甲崩开，移速暴涨 —— 你缺减速和毒",
}

## 召唤请求。签名和 StatusSystem.split_requested 一致，main 用同一个处理函数接。
signal summon_requested(into: StringName, hp: float, speed: float, bounty: int,
	path: PackedVector2Array, count: int)

## 阶段推进。main 接住做飘字 + 震屏 + toast。
signal phase_changed(phase: int, title: String, detail: String)

var spawner: TDWaveSpawner
var content: TDContent

var _phase: Dictionary = {}      ## boss instance_id -> 已达到的阶段（1/2/3）
var _base_speed: Dictionary = {} ## boss instance_id -> 原始移速（狂暴按它算，不叠加）
var _enraged: Dictionary = {}    ## boss instance_id -> true


func setup(p_spawner: TDWaveSpawner, p_content: TDContent) -> void:
	spawner = p_spawner
	content = p_content
	clear()


func clear() -> void:
	# 三个表都是按 instance_id 记的，实体一销毁就是死数据，直接丢掉。
	# 不需要在这里还原 speed：敌人对象跟着 spawner 一起 free。
	_phase.clear()
	_base_speed.clear()
	_enraged.clear()


func tick(_delta: float) -> void:
	if spawner == null:
		return
	for e: TDEnemy in spawner.enemies:
		if e.id != BOSS_ID or e.done:
			continue
		_tick_one(e)
	_stabilize()


func _tick_one(e: TDEnemy) -> void:
	var key: int = e.get_instance_id()
	if not _base_speed.has(key):
		_base_speed[key] = e.speed
		_phase[key] = 1
	var ratio: float = clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0)
	var cur: int = int(_phase.get(key, 1))
	# 血量可能一次被打掉两档（攒技能秒掉 30%），所以用 while 顺着推，不跳阶段
	while cur < THRESHOLDS.size() + 1 and ratio <= THRESHOLDS[cur - 1]:
		cur += 1
		_phase[key] = cur
		_enter(e, cur)


func _enter(e: TDEnemy, phase: int) -> void:
	if phase == 2:
		_summon(e)
	elif phase == 3:
		_enraged[e.get_instance_id()] = true
	phase_changed.emit(phase, str(PHASE_TITLE.get(phase, "")),
		str(PHASE_DETAIL.get(phase, "")))


func _summon(src: TDEnemy) -> void:
	if content == null or spawner == null:
		return
	var into := StringName(str(SUMMON["into"]))
	var base: Dictionary = content.enemies.get(into, {})
	if base.is_empty():
		return
	var trimmed: PackedVector2Array = StatusSystem.trim_forward_path(src)
	if trimmed.size() < 2:
		return
	# HP 跟着当前波数缩放，否则第 15 波的援军会被前期的塔一枪一个
	var hp: float = float(base.get("hp", 10.0)) * float(SUMMON["hp_scale"]) \
		* pow(spawner.hp_scale_per_wave, maxi(spawner.wave_index, 0))
	var bounty: int = maxi(1, int(round(float(base.get("bounty", 5)) \
		* float(SUMMON["bounty_scale"]))))
	summon_requested.emit(into, hp, float(base.get("speed", 60.0)), bounty, trimmed,
		int(SUMMON["count"]))


## 狂暴不能只在进入阶段那一刻改一次 speed：
## 如果改的瞬间它正好被眩晕（speed 被压成 0），乘上去还是 0，永远醒不过来。
## 所以每帧幂等地对一次账，眩晕结束时 status 还原旧值，下一帧这里再压上去。
func _stabilize() -> void:
	for key: int in _enraged.keys():
		var e: Variant = _find(key)
		if e == null:
			continue
		var enemy: TDEnemy = e
		if enemy.speed <= 0.0:
			continue  # 正在被眩晕 / 已停下，不抢
		var want: float = float(_base_speed.get(key, enemy.speed)) * ENRAGE_SPEED
		if absf(enemy.speed - want) > 0.01:
			enemy.speed = want


func _find(key: int) -> Variant:
	for e: TDEnemy in spawner.enemies:
		if e.get_instance_id() == key:
			return e
	return null


## 当前阶段（1 = 满血，2 = 已召唤，3 = 已狂暴）。HUD 用来画血条上的刻度。
func phase_of(e: TDEnemy) -> int:
	return int(_phase.get(e.get_instance_id(), 1))


func is_enraged(e: TDEnemy) -> bool:
	return _enraged.has(e.get_instance_id())


## 下一个阈值（0~1），没有就返回 -1。HUD 用它在血条上画刻度。
func next_threshold(e: TDEnemy) -> float:
	var p: int = phase_of(e)
	if p - 1 >= THRESHOLDS.size():
		return -1.0
	return THRESHOLDS[p - 1]


## 给测试和 HUD 用的一句话状态。
func phase_label(e: TDEnemy) -> String:
	var p: int = phase_of(e)
	if p <= 1:
		return ""
	return str(PHASE_TITLE.get(p, ""))
