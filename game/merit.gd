class_name MeritSystem
extends RefCounted
## 功勋系统 —— 与金币并行的第二资源，是本作与普通塔防的分野。
##
## 三条规则直接继承自《人族无敌》的机制内核：
##
## 1. 功勋只能来自「防御单位自己的击杀」。
##    主动技能打死的怪不计功勋。这条规则是双资源张力的源头 ——
##    玩家必须决定：是攒功勋（换取更高的塔），还是花功勋买技能救场。
##
## 2. 金币管「现在有多少塔」，功勋管「塔能长到多高」。
##    两条资源不可兑换，也不可互相替代。
##
## 3. 档位解锁是累计式的，不可回退。
##    原版 16 档价位在手机端压缩为 7 档，但「每档质变、中间无过度态」的设计保留。

signal merit_changed(total: int)
signal tier_unlocked(tier: int)

## 解锁第 n 档所需的累计功勋。阶梯递增，与金币价位（40/90/190/.../3800）同构：
## 越往后的档位，功勋门槛的涨幅越大，逼玩家在中期做「要不要冲高档」的决策。
const TIER_REQ: Dictionary = {2: 14, 3: 34, 4: 70, 5: 130, 6: 210, 7: 320}

## 人口上限：基础 4，随档位解锁提升，封顶 12。
## 人口 = 场上防御单位数量。原版「废塔占人口分摊输出」的取舍由此产生。
const POP_BASE: int = 4
const POP_MAX: int = 12

## 主动技能。三个都消耗功勋，构成「攒功勋 vs 用功勋」的即时抉择。
const SKILLS: Array[Dictionary] = [
	{
		"id": &"rally", "name": "增援", "cost": 8,
		"desc": "立刻获得 90 金币。经济不顺时唯一的翻盘手段。",
		"hotkey": 1,
	},
	{
		"id": &"freeze", "name": "冰封", "cost": 18,
		"desc": "全场敌人减速 55%，持续 4 秒。",
		"hotkey": 2,
	},
	{
		"id": &"verdict", "name": "裁决", "cost": 40,
		"desc": "对最前方最强的敌人造成 420 点真实伤害。此击杀不计功勋。",
		"hotkey": 3,
	},
]

var merit: int = 0
var unlocked: Dictionary = {1: true}
var max_tier_seen: int = 1

var _seen_kills: Dictionary = {}
var _used_count: Dictionary = {}


## 每帧扫描防御单位的击杀增量，换算成功勋。
## 用实例 id 做键：单位被卖掉后条目自然失效，不会串账。
func sync_kills(towers: Array[TDTower], content: TDContent, econ: TDEconomy) -> void:
	for t: TDTower in towers:
		var key: int = t.get_instance_id()
		var before: int = int(_seen_kills.get(key, 0))
		if t.kills <= before:
			continue
		var delta: int = t.kills - before
		_seen_kills[key] = t.kills
		add(delta)
		# 盗贼系：击杀额外产出金币。这是「经济型职业」的全部价值所在。
		var def: Dictionary = content.tower_def(t.id)
		var bonus: int = int(def.get("bonus_gold", 0))
		if bonus > 0:
			econ.earn(bonus * delta)


func add(amount: int) -> void:
	if amount <= 0:
		return
	merit += amount
	merit_changed.emit(merit)


func can_afford(cost: int) -> bool:
	return merit >= cost


func spend(cost: int) -> bool:
	if cost < 0 or merit < cost:
		return false
	merit -= cost
	merit_changed.emit(merit)
	return true


## 解锁第 n 档。成功返回 true。
func try_unlock(tier: int) -> bool:
	if is_unlocked(tier):
		return false
	var req: int = required_merit(tier)
	if req <= 0 or merit < req:
		return false
	spend(req)
	unlocked[tier] = true
	max_tier_seen = maxi(max_tier_seen, tier)
	tier_unlocked.emit(tier)
	return true


func is_unlocked(tier: int) -> bool:
	return bool(unlocked.get(tier, false))


func required_merit(tier: int) -> int:
	return int(TIER_REQ.get(tier, 0))


## 下一个未解锁档位；全部解锁则返回 0。
func next_locked_tier() -> int:
	for tier: int in range(1, 8):
		if not is_unlocked(tier):
			return tier
	return 0


func pop_cap() -> int:
	## 人口随已解锁档位增长：每多一档 +1，封顶 12。
	return mini(POP_MAX, POP_BASE + (max_tier_seen - 1))


func skill_by_id(id: StringName) -> Dictionary:
	for s: Dictionary in SKILLS:
		if s["id"] == id:
			return s
	return {}


func can_use_skill(id: StringName) -> bool:
	var s: Dictionary = skill_by_id(id)
	if s.is_empty():
		return false
	return can_afford(int(s["cost"]))


## 扣除技能消耗。真正的效果由调用方施加（需要 spawner / enemies）。
func pay_for_skill(id: StringName) -> bool:
	var s: Dictionary = skill_by_id(id)
	if s.is_empty():
		return false
	if not spend(int(s["cost"])):
		return false
	_used_count[id] = int(_used_count.get(id, 0)) + 1
	return true


func used_count(id: StringName) -> int:
	return int(_used_count.get(id, 0))


func reset() -> void:
	merit = 0
	unlocked = {1: true}
	max_tier_seen = 1
	_seen_kills.clear()
	_used_count.clear()
	merit_changed.emit(merit)
