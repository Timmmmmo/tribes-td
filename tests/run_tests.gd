extends SceneTree
## Headless 自测 —— 只测本项目自有的机制，不重复测 td_core（那边已有 54 项）。
##
## 跑法：
##   godot --headless --path . -s res://tests/run_tests.gd
## 期望最后一行：RESULT: PASS <n> checks, 0 failures，退出码 0。

const PATH: PackedVector2Array = [Vector2(0, 0), Vector2(200, 0), Vector2(200, 200)]

var _pass: int = 0
var _fail: int = 0
var _section: String = ""


func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL [%s] %s" % [_section, msg])


func section(name: String) -> void:
	_section = name
	print("-- %s" % name)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var content: TDContent = TDContent.load_file("res://data/content.json")

	section("content_loads")
	check(content.errors.is_empty(), "content.json 无解析错误: %s" % str(content.errors))
	check(content.towers.size() == 32, "32 个防御单位，实际 %d" % content.towers.size())
	check(content.enemies.size() == 5, "5 种敌人，实际 %d" % content.enemies.size())
	check(content.waves.size() == 15, "15 波，实际 %d" % content.waves.size())

	section("map_valid")
	var errs: Array[String] = content.make_map().validate()
	check(errs.is_empty(), "地图无错: %s" % str(errs))

	section("tier_ladder")
	## 阶梯式价位：每档必须严格 ×1.9 以上，否则「攒钱等质变」的张力消失。
	var prices: Array = [40, 90, 190, 400, 850, 1800, 3800]
	for i: int in range(1, prices.size()):
		check(int(prices[i]) >= int(prices[i - 1]) * 1.9,
			"第 %d 档价位跳幅足够 (%d -> %d)" % [i + 1, prices[i - 1], prices[i]])
	## 每个塔的 cost 必须等于它所属档位的价位，否则阶梯就断了。
	for tid: StringName in content.tower_order:
		var d: Dictionary = content.tower_def(tid)
		var tier: int = int(d.get("tier", 1))
		check(int(d.get("cost", 0)) == int(prices[tier - 1]),
			"%s 价位与第 %d 档一致" % [String(tid), tier])

	section("professions")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	var profs: Array = (raw as Dictionary).get("professions", [])
	check(profs.size() == 6, "6 个部族，实际 %d" % profs.size())
	for p: Dictionary in profs:
		var ids: Array = p.get("towers", [])
		check(ids.size() >= 5, "%s 至少 5 档，实际 %d" % [str(p.get("name")), ids.size()])
		for id: Variant in ids:
			check(content.towers.has(StringName(str(id))),
				"%s 的 %s 在塔表里存在" % [str(p.get("name")), str(id)])

	section("dps_per_gold_sanity")
	## 数值健康度：同职业内，相邻档位的「每金币 DPS」不应出现超过 3 倍的反差，
	## 否则会出现「某一档永远最优」的单点解，玩家就没有选择了。
	for p: Dictionary in profs:
		var prev: float = -1.0
		for id: Variant in p.get("towers", []):
			var d: Dictionary = content.tower_def(StringName(str(id)))
			var dps: float = float(d.get("damage", 1.0)) / maxf(float(d.get("interval", 1.0)), 0.05)
			var per: float = dps / float(maxi(int(d.get("cost", 1)), 1))
			if prev >= 0.0:
				var ratio: float = per / maxf(prev, 0.00001)
				check(ratio > 0.33 and ratio < 3.0,
					"%s 的 %s 每金币 DPS 未偏离上一档 3 倍 (%.4f vs %.4f)" % [
						str(p.get("name")), String(tid_name(d)), per, prev])
			prev = per

	section("merit_core")
	var merit: MeritSystem = MeritSystem.new()
	check(merit.merit == 0, "初始功勋 0")
	check(merit.is_unlocked(1), "第 1 档默认解锁")
	check(not merit.is_unlocked(2), "第 2 档默认锁定")
	merit.add(10)
	check(merit.merit == 10, "加 10 功勋")
	check(not merit.try_unlock(2), "功勋不足时无法解锁第 2 档")
	merit.add(10)
	check(merit.try_unlock(2), "功勋够了解锁第 2 档")
	check(merit.merit == 6, "解锁扣掉 14 功勋（20-14=6），实际 %d" % merit.merit)
	check(merit.pop_cap() == 5, "解锁第 2 档后人口上限 5，实际 %d" % merit.pop_cap())

	section("merit_only_from_tower_kills")
	## 核心规则：功勋只来自防御单位自己的击杀。
	var econ: TDEconomy = TDEconomy.new(500, 20)
	var m2: MeritSystem = MeritSystem.new()
	var tower: TDTower = content.make_tower(&"r1")
	root.add_child(tower)
	var towers: Array[TDTower] = [tower]
	m2.sync_kills(towers, content, econ)
	check(m2.merit == 0, "没有击杀时功勋为 0")
	tower.kills = 3
	m2.sync_kills(towers, content, econ)
	check(m2.merit == 3, "3 次击杀 → 3 功勋，实际 %d" % m2.merit)
	m2.sync_kills(towers, content, econ)
	check(m2.merit == 3, "重复结算不重复计功勋（差值法），实际 %d" % m2.merit)

	var enemy: TDEnemy = _enemy(10.0, 50.0)
	enemy.take_damage(9999.0)
	m2.sync_kills(towers, content, econ)
	check(m2.merit == 3, "技能/环境击杀不计功勋（呼应原版召唤物规则），实际 %d" % m2.merit)

	section("rogue_bonus_gold")
	var econ2: TDEconomy = TDEconomy.new(100, 20)
	var m3: MeritSystem = MeritSystem.new()
	var rogue: TDTower = content.make_tower(&"g1")
	root.add_child(rogue)
	var rt: Array[TDTower] = [rogue]
	rogue.kills = 2
	var before: int = econ2.gold
	m3.sync_kills(rt, content, econ2)
	## g1 的 bonus_gold = 2，2 次击杀 → +4 金币（bounty 由 td_core 自己结算，这里只测加成）
	check(econ2.gold - before == 4, "盗贼 2 次击杀额外 +4 金币，实际 +%d" % (econ2.gold - before))

	section("skill_economy")
	var m4: MeritSystem = MeritSystem.new()
	m4.add(5)
	check(not m4.pay_for_skill(&"rally"), "功勋不足（5<8）时无法用增援")
	m4.add(5)
	check(m4.pay_for_skill(&"rally"), "功勋够（10>=8）时可用增援")
	check(m4.merit == 2, "增援扣 8 功勋，剩 2，实际 %d" % m4.merit)

	section("wave_simulation")
	## 跑一波，验证金币能增长、敌人能被清掉。用的是 td_core 的 headless 接口。
	var c2: TDContent = TDContent.load_file("res://data/content.json")
	var sp: TDWaveSpawner = TDWaveSpawner.new()
	sp.auto_tick = false
	sp.configure(c2)
	root.add_child(sp)
	var g0: int = sp.economy.gold
	check(sp.start_next_wave(), "第 1 波可以开始")
	var t2: TDTower = c2.make_tower(&"r7")
	check(sp.place_tower_at_cell(t2, Vector2i(1, 0)), "高阶单位能放在 (1,0)")
	var guard: int = 0
	while sp.enemies_left_in_wave() > 0 and guard < 6000:
		sp.advance(0.016)
		guard += 1
	check(sp.enemies_left_in_wave() == 0, "第 1 波在 %d 帧内被清空" % guard)
	check(sp.economy.gold > g0, "清波后金币增长（%d -> %d）" % [g0, sp.economy.gold])

	## 收尾
	print("")
	if _fail == 0:
		print("RESULT: PASS %d checks, 0 failures" % _pass)
		quit(0)
	else:
		print("RESULT: FAIL %d checks, %d failures" % [_pass, _fail])
		quit(1)


func tid_name(d: Dictionary) -> String:
	return str(d.get("id", "?"))


func _enemy(hp: float, speed: float) -> TDEnemy:
	var e: TDEnemy = TDEnemy.new()
	e.setup(PATH, hp, speed, 5)
	root.add_child(e)
	return e
