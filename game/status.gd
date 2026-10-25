class_name StatusSystem
extends RefCounted
## 敌人状态机 —— 毒 / 眩晕 / 分裂。
##
## 为什么要包一层而不是改 addons/td_core：
## 上游是 MIT 的独立仓库，一行不改才能在它更新时直接覆盖。所以这里全部用
## 「读公开字段 + 写公开字段」的方式实现，一个内核方法都不重写：
##
##   毒   —— 累加到 1 点再调 take_damage(1 + armor)。内核公式是
##           dealt = max(1, amount - armor)，所以加回 armor 就等于「无视护甲的真实伤害」。
##           顺带绕开「每帧至少 1 点」的钳制：不累积的话 60fps 会变成 60 DPS。
##   眩晕 —— 把 speed 暂存后清零，advance() 算出来的 step 就是 0。
##   分裂 —— 只算出「在哪、裂成什么、多少血」，实际生成交给 main。
##           生成要碰 spawner.enemies 和信号连接，那是游戏层的事。
##
## 一条容易漏的规则：毒把人毒死了，**功勋要算给施毒的那座塔**。
## 内核只在 TDTower._hit 里 +1 kills，DOT 不走那条路，所以这里手动补。

## 部族机制表。MVP 阶段先放代码里，避免动 content.json 的生成管线；
## 正确做法是进数据表（见 docs/FUN.md 第五节第 3 项）。
const TOWER_MECHANICS := {
	"r": {"poison_ratio": 0.15, "poison_time": 2.5},  # 游侠：毒，无视护甲
	"b": {"stun": 0.30},                              # 狂战：击晕，打断推进
	"s": {"stun": 0.16},                              # 剑咏：轻微打断
}

## 重装怪死后裂成两只斥候。惩罚「只堆单体输出、清场慢」的构筑。
const SPLIT_ON_DEATH := {
	&"brute": {"into": &"scout", "count": 2, "hp_scale": 0.30, "bounty_scale": 0.5},
}

## BOSS 不能被无限控。眩晕按这个系数打折。
const BOSS_STUN_SCALE := 0.35

## 分裂请求。由 main 接住并真正生成敌人。
signal split_requested(into: StringName, hp: float, speed: float, bounty: int,
	path: PackedVector2Array, count: int)

var spawner: TDWaveSpawner
var content: TDContent

var _poison: Dictionary = {}  ## enemy instance_id -> {e, dps, time, tower, acc}
var _stun: Dictionary = {}    ## enemy instance_id -> {e, time, speed}


func setup(p_spawner: TDWaveSpawner, p_content: TDContent) -> void:
	spawner = p_spawner
	content = p_content
	clear()


func clear() -> void:
	# 清状态前先把被我们压成 0 的速度还回去，否则重开一局后同 id 的怪会一直站着
	for key: int in _stun.keys():
		var rec: Dictionary = _stun[key]
		var e: Variant = rec.get("e")
		if is_instance_valid(e):
			(e as TDEnemy).speed = float(rec["speed"])
	_poison.clear()
	_stun.clear()


## 塔开火时调用，按部族前缀决定附加效果。
func on_tower_fired(tower: TDTower, target: TDEnemy) -> void:
	if tower == null or target == null or target.done:
		return
	var prefix: String = String(tower.id).left(1)
	var mech: Dictionary = TOWER_MECHANICS.get(prefix, {})
	if mech.is_empty():
		return
	if mech.has("poison_ratio"):
		var dps: float = tower.damage * float(mech["poison_ratio"])
		_apply_poison(target, dps, float(mech.get("poison_time", 2.0)), tower)
	if mech.has("stun"):
		var dur: float = float(mech["stun"])
		if target.id == &"boss":
			dur *= BOSS_STUN_SCALE
		_apply_stun(target, dur)


func _apply_poison(e: TDEnemy, dps: float, dur: float, tower: TDTower) -> void:
	var key: int = e.get_instance_id()
	var rec: Dictionary = _poison.get(key, {})
	if rec.is_empty():
		_poison[key] = {"e": e, "dps": dps, "time": dur, "tower": tower, "acc": 0.0}
		return
	# 同一只怪被多座塔上毒：取最高 DPS，时长刷新。不做叠加，避免堆塔把毒算爆。
	rec["dps"] = maxf(float(rec["dps"]), dps)
	rec["time"] = maxf(float(rec["time"]), dur)
	# 施毒者记最后一次的塔 —— 击杀归属给「最后上毒的那座」，规则简单且可预期
	rec["tower"] = tower


func _apply_stun(e: TDEnemy, dur: float) -> void:
	var key: int = e.get_instance_id()
	var rec: Dictionary = _stun.get(key, {})
	if not rec.is_empty():
		# 已经在晕：只延长，不要把 speed 覆盖成 0
		rec["time"] = maxf(float(rec["time"]), dur)
		return
	if e.speed <= 0.0:
		return
	_stun[key] = {"e": e, "time": dur, "speed": e.speed}
	e.speed = 0.0


func tick(delta: float) -> void:
	if spawner == null:
		return
	_tick_stun(delta)
	_tick_poison(delta)


func _tick_stun(delta: float) -> void:
	for key: int in _stun.keys():
		var rec: Dictionary = _stun[key]
		var e: Variant = rec.get("e")
		if not is_instance_valid(e) or (e as TDEnemy).done:
			_stun.erase(key)
			continue
		rec["time"] = float(rec["time"]) - delta
		if float(rec["time"]) <= 0.0:
			(e as TDEnemy).speed = float(rec["speed"])
			_stun.erase(key)


func _tick_poison(delta: float) -> void:
	for key: int in _poison.keys():
		var rec: Dictionary = _poison[key]
		var e: Variant = rec.get("e")
		if not is_instance_valid(e) or (e as TDEnemy).done:
			_poison.erase(key)
			continue
		var enemy: TDEnemy = e
		rec["time"] = float(rec["time"]) - delta
		if float(rec["time"]) <= 0.0:
			_poison.erase(key)
			continue
		rec["acc"] = float(rec["acc"]) + float(rec["dps"]) * delta
		# 攒够 1 点再打：内核每次至少扣 1 点，逐帧打会把毒放大 60 倍
		if float(rec["acc"]) < 1.0:
			continue
		var dmg: float = float(rec["acc"])
		rec["acc"] = 0.0
		# +armor 抵消内核的护甲减免，等价于真实伤害
		enemy.take_damage(dmg + enemy.armor)
		if enemy.done and enemy.hp <= 0.0:
			# 毒击杀：补记功勋归属。内核只在 TDTower._hit 里 +1，DOT 不走那条路。
			var tower: Variant = rec.get("tower")
			if is_instance_valid(tower):
				(tower as TDTower).kills += 1
			_poison.erase(key)


## 敌人死亡时由 main 调用。命中分裂规则就发请求。
func try_split(e: TDEnemy) -> void:
	var rule: Dictionary = SPLIT_ON_DEATH.get(e.id, {})
	if rule.is_empty() or content == null or spawner == null:
		return
	var trimmed: PackedVector2Array = _trim_path(e)
	if trimmed.size() < 2:
		return
	var into := StringName(str(rule["into"]))
	var base: Dictionary = content.enemies.get(into, {})
	if base.is_empty():
		return
	var hp: float = float(base.get("hp", 10.0)) * float(rule["hp_scale"]) \
		* pow(spawner.hp_scale_per_wave, maxi(spawner.wave_index, 0))
	var bounty: int = maxi(1, int(round(float(base.get("bounty", 5)) * float(rule["bounty_scale"]))))
	var count: int = int(rule["count"])
	split_requested.emit(into, hp, float(base.get("speed", 60.0)), bounty, trimmed, count)


## 从敌人当前位置往后重铺一条路径。
## 直接给它整条 path 是错的：setup() 会把 position 重置到 path[0]，
## 分裂出来的小怪会瞬间被传送回出生点。
## 这里只用公开字段（path / progress）反推，不碰私有的 _seg。
func _trim_path(e: TDEnemy) -> PackedVector2Array:
	var out := PackedVector2Array([e.position])
	var walked: float = 0.0
	for i: int in range(1, e.path.size()):
		walked += e.path[i - 1].distance_to(e.path[i])
		if walked > e.progress + 0.5:
			out.append(e.path[i])
	if out.size() < 2 and e.path.size() >= 2:
		out.append(e.path[e.path.size() - 1])
	return out


func has_status(e: TDEnemy) -> Dictionary:
	var key: int = e.get_instance_id()
	return {
		"poison": _poison.has(key),
		"stun": _stun.has(key),
	}
