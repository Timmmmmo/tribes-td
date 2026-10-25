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
	## 测试用 r7（3800 金币），但初始经济只有 150，所以先给足钱再记基准值。
	## 这一步不是作弊：这里要验证的是「放得下 + 能清波 + 金币增长」，
	## 不是验证贫穷状态下买不买得起（那条由 build_block_reason 覆盖）。
	sp.economy.earn(4000)
	check(sp.start_next_wave(), "第 1 波可以开始")
	var t2: TDTower = c2.make_tower(&"r7")
	check(sp.place_tower_at_cell(t2, Vector2i(1, 0)), "高阶单位能放在 (1,0)")
	## 基准值要放在「已经付过钱」之后，否则小怪赏金会被 3800 的建造成本吃掉，
	## 看起来像金币反而少了。
	var g0: int = sp.economy.gold
	var guard: int = 0
	while sp.enemies_left_in_wave() > 0 and guard < 6000:
		sp.advance(0.016)
		guard += 1
	check(sp.enemies_left_in_wave() == 0, "第 1 波在 %d 帧内被清空" % guard)
	check(sp.economy.gold > g0, "清波后金币增长（%d -> %d）" % [g0, sp.economy.gold])

	# ------------------------------------------------------------------ 本轮新增
	# 这四块对应 docs/FUN.md 里 MVP 的三根支柱：情报（决策）、状态机制（克制）、英雄（操作）。

	section("wave_intel")
	## 情报的价值在于「玩家能据此改构成」，所以至少要有：数量对、标签对、给建议。
	var w7: Array[Dictionary] = WaveIntel.rows(content, 6)  # 第 7 波：10 只飞行
	check(w7.size() == 1, "第 7 波只有一种敌人，实际 %d" % w7.size())
	if w7.size() == 1:
		check(int(w7[0]["count"]) == 10, "第 7 波 10 只，实际 %d" % int(w7[0]["count"]))
		check((w7[0]["tags"] as Array).has(WaveIntel.TAG_FLYING), "第 7 波标出「飞行」")
		check(WaveIntel.hint(w7).contains("对空"), "飞行波给出「需要能对空」")
	## 第 10 波是两个重装组（8 + 4），玩家眼里就是「12 只重装」。
	## 没合并的话玩家会看到两行「8 重装」和「4 重装」，读起来像两种不同的怪。
	var w10: Array[Dictionary] = WaveIntel.rows(content, 9)
	var brute_count: int = 0
	for r: Dictionary in w10:
		if str(r["id"]) == "brute":
			brute_count = int(r["count"])
	check(brute_count == 12, "第 10 波两组重装合并成 12 只，实际 %d" % brute_count)
	check(w10.size() == 1, "合并后只剩一行，实际 %d 行" % w10.size())
	check(WaveIntel.summary(w10) != "", "能给出单行摘要")

	section("status_poison")
	var sps: TDWaveSpawner = TDWaveSpawner.new()
	sps.auto_tick = false
	sps.configure(content)
	root.add_child(sps)
	var st: StatusSystem = StatusSystem.new()
	st.setup(sps, content)

	## 毒必须无视护甲。做法是给 take_damage 传 (dmg + armor)，正好被内核的
	## max(1, amount - armor) 抵消。用两只护甲差 10 点的怪对比来验证。
	var pa: TDEnemy = _enemy(100.0, 60.0)
	var pb: TDEnemy = _enemy(100.0, 60.0)
	pb.armor = 10.0
	var poisoner: TDTower = content.make_tower(&"r4")
	st.on_tower_fired(poisoner, pa)
	st.on_tower_fired(poisoner, pb)
	for i: int in range(200):
		st.tick(0.016)
	check(pa.hp < 100.0, "毒造成了伤害（%.2f）" % pa.hp)
	check(absf(pa.hp - pb.hp) < 0.001, "毒无视护甲：0 甲与 10 甲掉血一致 %s / %s" % [pa.hp, pb.hp])

	## 毒打死怪，功勋要算给施毒的那座塔。
	## 内核只在 TDTower._hit 里 +1 kills，DOT 不走那条路，所以这条规则必须单独守。
	var victim: TDEnemy = _enemy(2.0, 60.0)
	var killer: TDTower = content.make_tower(&"r7")
	var k0: int = killer.kills
	st.on_tower_fired(killer, victim)
	for i: int in range(400):
		st.tick(0.016)
	check(victim.done, "毒能把怪打死")
	check(killer.kills == k0 + 1, "毒击杀的功勋算给施毒塔（%d -> %d）" % [k0, killer.kills])

	section("status_stun")
	var stunned: TDEnemy = _enemy(200.0, 80.0)
	var brawler: TDTower = content.make_tower(&"b4")
	var base_speed: float = stunned.speed
	st.on_tower_fired(brawler, stunned)
	check(stunned.speed == 0.0, "眩晕把速度清零，实际 %s" % stunned.speed)
	for i: int in range(40):
		st.tick(0.016)
	check(is_equal_approx(stunned.speed, base_speed), "眩晕到期恢复原速，实际 %s" % stunned.speed)
	## BOSS 的眩晕要打折，否则可以被无限控
	var boss_like: TDEnemy = _enemy(9999.0, 30.0)
	boss_like.id = &"boss"
	st.on_tower_fired(brawler, boss_like)
	for i: int in range(8):  # 0.128 秒
		st.tick(0.016)
	check(boss_like.speed > 0.0, "BOSS 眩晕时长被压缩")

	section("status_split")
	var brute: TDEnemy = _enemy(165.0, 40.0)
	brute.id = &"brute"
	for i: int in range(120):
		brute.advance(0.016)
	var splits: Array = []
	var on_split := func(into: StringName, a_hp: float, a_sp: float, a_b: int, path: PackedVector2Array, count: int) -> void:
		splits.append({"into": into, "path": path, "count": count})
	st.split_requested.connect(on_split)
	st.try_split(brute)
	check(splits.size() == 1, "重装死亡触发一次分裂请求")
	if splits.size() == 1:
		check(int(splits[0]["count"]) == 2, "裂成 2 只")
		var path0: PackedVector2Array = splits[0]["path"]
		## 最容易踩的坑：直接给整条 path，setup() 会把 position 重置到 path[0]，
		## 分裂出来的小怪会瞬间被传送回出生点。
		check(path0.size() >= 2, "分裂路径至少两个点")
		check(path0[0].distance_to(brute.position) < 1.0, "分裂路径从死亡点开始")

	section("hero_rules")
	var hw: HeroUnit = HeroUnit.new()
	hw.reset(Vector2(100, 100))
	var prey: TDEnemy = _enemy(5.0, 60.0)
	prey.position = Vector2(110, 100)
	var targets: Array[TDEnemy] = [prey]
	var got: TDEnemy = hw.tick(5.0, targets)
	check(got != null, "英雄能索敌")
	check(prey.done, "英雄能打死怪")
	check(hw.kills == 1, "英雄记到 1 个击杀，实际 %d" % hw.kills)

	## 装备三合一：捡到更好的直接换，重复件攒三件升一级。
	var hg: HeroUnit = HeroUnit.new()
	hg.reset(Vector2.ZERO)
	hg.pick_equipment("sword", 1)
	check(hg.slot_level("sword") == 1, "捡到一级剑直接装备")
	for i: int in range(3):
		hg.pick_equipment("sword", 1)
	check(hg.slot_level("sword") == 2, "三件同名合成二级，实际 %d" % hg.slot_level("sword"))
	check(hg.attack() > HeroUnit.new().attack(), "装备真的提升了攻击力")

	## 拾取范围判定：掉落物是英雄「必须走过去」才拿到的，
	## 所以这条判定的半径必须准 —— 大了等于自动捡，小了玩家永远捡不到。
	var hpick: HeroUnit = HeroUnit.new()
	hpick.reset(Vector2(200, 200))
	var drops: Array[Dictionary] = [
		{"pos": Vector2(215, 200), "kind": "boots", "level": 1, "t": 0.0},
		{"pos": Vector2(260, 200), "kind": "boots", "level": 1, "t": 0.0},
	]
	var near: Array[Dictionary] = hpick.collect_near(drops, 26.0)
	check(near.size() == 1, "只捡半径内的掉落物，实际 %d" % near.size())

	section("hero_kill_gives_no_merit")
	## 这是双资源博弈的根：英雄很强，但不能靠玩英雄绕过功勋。
	## 规则不靠文档提醒 —— MeritSystem 只读 TDTower.kills，英雄一行都不碰。
	var sph: TDWaveSpawner = TDWaveSpawner.new()
	sph.auto_tick = false
	sph.configure(content)
	root.add_child(sph)
	var ms: MeritSystem = MeritSystem.new()
	var mob: TDEnemy = TDEnemy.new()
	mob.setup(PATH, 4.0, 0.0, 5)
	sph.add_child(mob)
	sph.enemies.append(mob)
	mob.killed.connect(sph._on_killed)
	var gold0: int = sph.economy.gold
	var hunter: HeroUnit = HeroUnit.new()
	hunter.reset(Vector2.ZERO)
	hunter.tick(5.0, sph.enemies)
	for i: int in range(3):
		ms.sync_kills(sph.towers, content, sph.economy)
	check(mob.done, "英雄打死了怪")
	check(sph.economy.gold > gold0, "英雄击杀给金币（%d -> %d）" % [gold0, sph.economy.gold])
	check(ms.merit == 0, "英雄击杀不给功勋，实际 %d" % ms.merit)

	section("boss_phases")
	## BOSS 的两档转换必须按血量跨、不能跳、不能重复触发。
	var bsph: TDWaveSpawner = TDWaveSpawner.new()
	bsph.auto_tick = false
	bsph.configure(content)
	root.add_child(bsph)
	var bp: BossPhases = BossPhases.new()
	bp.setup(bsph, content)
	var phases: Array[int] = []
	var summons: Array = []
	var on_phase := func(p: int, _t: String, _d: String) -> void: phases.append(p)
	var on_summon := func(into: StringName, a_hp: float, a_sp: float, a_b: int,
			path: PackedVector2Array, count: int) -> void:
		summons.append({"into": into, "hp": a_hp, "path": path, "count": count})
	bp.phase_changed.connect(on_phase)
	bp.summon_requested.connect(on_summon)

	var big: TDEnemy = TDEnemy.new()
	big.id = &"boss"
	big.setup(PATH, 1000.0, 30.0, 130)
	bsph.add_child(big)
	bsph.enemies.append(big)

	check(bp.phase_of(big) == 1, "出场是第一阶段")
	bp.tick(0.016)
	check(phases.is_empty(), "满血不触发任何转换")

	big.hp = 690.0  # 69%
	bp.tick(0.016)
	check(phases.size() == 1 and phases[0] == 2, "掉到 70% 以下进入第二阶段")
	check(summons.size() == 1, "第二阶段要求召唤援军")
	if summons.size() == 1:
		check(int(summons[0]["count"]) == 3, "召 3 只，实际 %d" % int(summons[0]["count"]))
		var spath: PackedVector2Array = summons[0]["path"]
		## 和分裂同一个坑：路径必须从当前位置起，否则援军会被传回出生点
		check(spath.size() >= 2, "召唤路径至少两个点")
		check(spath[0].distance_to(big.position) < 1.0, "召唤路径从 BOSS 当前位置开始")

	bp.tick(0.016)
	check(phases.size() == 1, "同一阶段不重复触发")

	var speed_before: float = big.speed
	big.hp = 350.0  # 35%
	bp.tick(0.016)
	check(phases.size() == 2 and phases[1] == 3, "掉到 40% 以下进入第三阶段")
	check(bp.is_enraged(big), "第三阶段进入狂暴")
	check(big.speed > speed_before * 1.4, "狂暴后移速明显变快 (%.1f -> %.1f)" % [
		speed_before, big.speed])

	## 眩晕期间 speed 被压成 0。如果只在这一帧乘一次，乘 0 还是 0 —— BOSS 会永远站着。
	## 所以狂暴必须每帧对账，而不是「进入阶段的那一刻改一次」。
	big.speed = 0.0
	bp.tick(0.016)
	check(big.speed == 0.0, "眩晕中不去抢 speed")
	big.speed = speed_before
	bp.tick(0.016)
	check(absf(big.speed - speed_before * BossPhases.ENRAGE_SPEED) < 0.1,
		"眩晕结束后狂暴重新生效，实际 %.1f" % big.speed)

	## 一次性打掉 40% 会同时跨两档，必须两档都记到，不能只触发最后一档。
	## 用一个新的 spawner：同一个 spawner 里还有上面那只 BOSS，
	## 新实例的 BossPhases 会把它也当成「第一次看见」，凭空多触发两次。
	var bsph2: TDWaveSpawner = TDWaveSpawner.new()
	bsph2.auto_tick = false
	bsph2.configure(content)
	root.add_child(bsph2)
	var bp2: BossPhases = BossPhases.new()
	bp2.setup(bsph2, content)
	var seen2: Array[int] = []
	bp2.phase_changed.connect(func(p: int, _t: String, _d: String) -> void: seen2.append(p))
	var quick: TDEnemy = TDEnemy.new()
	quick.id = &"boss"
	quick.setup(PATH, 1000.0, 30.0, 130)
	bsph2.add_child(quick)
	bsph2.enemies.append(quick)
	bp2.tick(0.016)
	quick.hp = 300.0
	bp2.tick(0.016)
	check(seen2.size() == 2, "一次跨两档会依次触发两次，实际 %d 次" % seen2.size())
	check(bp2.phase_of(quick) == 3, "跨档后停在第三阶段")

	section("run_report")
	## 归因必须按「掉了多少血」排，不能按只数。
	## 3 只重装（2 血）比 4 只斥候（1 血）更致命，但按只数会把斥候排第一。
	var rr: RunReport = RunReport.new()
	rr.setup(content)
	rr.total_waves = content.waves.size()
	rr.waves_cleared = 11
	rr.max_lives = 16
	rr.lives_left = 0
	for i: int in range(3):
		var b: TDEnemy = _enemy(10.0, 10.0)
		b.id = &"brute"
		b.leak_damage = 2
		rr.record_leak(b)
	for i: int in range(4):
		var s: TDEnemy = _enemy(10.0, 10.0)
		s.id = &"scout"
		s.leak_damage = 1
		rr.record_leak(s)
	for i: int in range(20):
		var k: TDEnemy = _enemy(10.0, 10.0)
		k.id = &"soldier"
		rr.record_kill(k)

	check(rr.leak_count() == 7, "漏 7 只，实际 %d" % rr.leak_count())
	check(rr.leak_damage_total() == 10, "共掉 10 血，实际 %d" % rr.leak_damage_total())
	var bl: Dictionary = rr.blame()
	check(str(bl.get("id", "")) == "brute",
		"主因判给掉血最多的重装，实际 %s" % str(bl.get("id", "")))
	check(int(bl.get("damage", 0)) == 6, "重装占 6 点，实际 %d" % int(bl.get("damage", 0)))
	var v: Dictionary = rr.verdict()
	check(str(v["title"]) == "基地失守", "失败标题正确")
	check(not str(v["blame"]).is_empty(), "结算页有主因行")
	## 建议必须提到「毒」—— 主因是重装，那就得给对付护甲的具体办法
	check(str(v["advice"]).contains("毒"), "重装主因的建议提到毒: %s" % str(v["advice"]))
	check((v["breakdown"] as Array).size() > 0, "构成非空")
	check(str((v["breakdown"] as Array)[0]["id"]) == "brute", "构成第一条是重装")

	## 早期崩盘：建议必须转向开局经济，而不是讲某个怪的机制
	var early: RunReport = RunReport.new()
	early.setup(content)
	early.total_waves = content.waves.size()
	early.waves_cleared = 2
	var e2: TDEnemy = _enemy(10.0, 10.0)
	e2.id = &"brute"
	e2.leak_damage = 2
	early.record_leak(e2)
	check(early.advice().contains("开局"), "第 2 波崩，建议讲开局经济: %s" % early.advice())

	## 一只没漏也输？不该出现，但 blame() 必须安全返回空而不是崩溃
	var clean: RunReport = RunReport.new()
	clean.setup(content)
	check(clean.blame().is_empty(), "没有漏怪时 blame 返回空字典")
	check(not clean.advice().is_empty(), "没有漏怪时也有建议")

	check(RunReport.clock(204.0) == "3:24", "时长格式化，实际 %s" % RunReport.clock(204.0))

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
