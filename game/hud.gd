extends Control
## 竖屏 HUD —— 全部自绘 + 手动命中测试，不用 Control 节点树。
## 理由：塔防的 HUD 元素数量少、布局固定，自绘能保证视觉统一，
## 也避免手机端嵌套容器带来的点击穿透与布局抖动。

const W := 720.0
const H := 1280.0
const TOP_H := 150.0
const CARD_Y := 1100.0
const CARD_H := 96.0
const SKILL_Y := 1200.0
const SKILL_H := 72.0
const CARD_W := 92.0
const CARD_GAP := 8.0
const ACTION_Y := 1012.0
const ACTION_H := 78.0

## 战场控制条拆成三块，职责单一：
##   左 = 开波（唯一一个「主动承担风险换收益」的按钮）
##   中 = 情报（常态）/ 塔操作（选中塔时）
##   右 = 英雄
## 之前这一条只放塔的升级/出售，不选塔的时候整条是空的 —— 是屏幕上最贵的一段空白。
const WAVE_BTN := Rect2(20, 1018, 218, 72)
const INTEL_BOX := Rect2(248, 1018, 244, 72)
const HERO_BOX := Rect2(502, 1018, 198, 72)

## 结算页。宽高留够，是因为这里要放下「你死于什么」+ 构成 + 一句建议，
## 挤成三行小字等于没写 —— 玩家不会读，只会点掉。
const RESULT_PANEL := Rect2(40, 210, 640, 740)

const BG := Color("#0B1420")
const PANEL := Color("#16232F")
const PANEL_HI := Color("#20323F")
const LINE := Color("#2A4052")
const AMBER := Color("#E0A83C")
const TEAL := Color("#1E9E8F")
const TEXT := Color("#E8EFF5")
const DIM := Color("#7C8FA0")
const BAD := Color("#E15555")

## 表示「这次输入不是按下」的哨兵坐标
const NO_POS := Vector2(-9999, -9999)

## 中文必须显式给字体：Godot 内置 fallback 不含 CJK，会显示方块。
## 桌面端用系统字体（雅黑/苹方），Web 端拿不到系统字体，必须用打包的中文子集，
## 否则整屏都是豆腐块。子集由 tools/subset_font.py 生成，只留游戏里用到的字。
const FONT_BUNDLED := "res://assets/fonts/game_cjk.ttf"
const FONT_NAMES := [
	"Microsoft YaHei", "微软雅黑", "PingFang SC", "Noto Sans CJK SC",
	"Source Han Sans SC", "WenQuanYi Micro Hei", "sans-serif",
]

var main: Node2D
var _font: Font
var _drag_target: String = ""


func setup(m: Node2D) -> void:
	main = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bundled: Font = null
	if ResourceLoader.exists(FONT_BUNDLED):
		bundled = load(FONT_BUNDLED) as Font

	if OS.has_feature("web") and bundled != null:
		# Web 里没有系统字体可查，直接用打包子集，最确定
		_font = bundled
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(FONT_NAMES)
		sf.font_weight = 400
		if bundled != null:
			# 桌面上万一系统缺字，也有兜底
			sf.fallbacks = [bundled]
		_font = sf


func _process(_d: float) -> void:
	if main != null:
		queue_redraw()


## 主场景画飘字（+金币之类）时要用同一套字体，否则中英文混排会跳字。
func font() -> Font:
	return _font


# ------------------------------------------------------------------ 绘制

func _draw() -> void:
	if main == null or main.merit == null:
		return
	if main.run_over:
		_draw_result()
		return
	_draw_top()
	_draw_actions()
	_draw_cards()
	_draw_skills()


func text(p: Vector2, s: String, size: int, col: Color) -> void:
	draw_string(_font, p + Vector2(0, float(size) * 0.78), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func text_r(right_x: float, p_y: float, s: String, size: int, col: Color) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(Vector2(right_x - w, p_y), s, size, col)


func text_c(center_x: float, p_y: float, s: String, size: int, col: Color) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(Vector2(center_x - w * 0.5, p_y), s, size, col)


func _draw_top() -> void:
	var econ: TDEconomy = main.spawner.economy

	# 顶栏：竖向渐变 + 底部一条亮线。纯色面板会让整个 HUD 看起来像没上色的线框图。
	TDArt.fill_vgrad(self, TDArt.round_rect(Rect2(0, 0, W, TOP_H), 0.0, 1),
		Color("#182735"), Color("#0E1822"), 0.0, TOP_H)
	draw_line(Vector2(0, TOP_H - 1), Vector2(W, TOP_H - 1), Color("#2E4759"), 1.0)
	draw_line(Vector2(0, TOP_H - 2), Vector2(W, TOP_H - 2), Color(1, 1, 1, 0.05), 1.0)

	# 金币 —— 主资源，字号最大，配一个amber圆章
	text(Vector2(26, 10), "金币", 15, DIM)
	_resource_coin(Vector2(34, 52), 10.0, AMBER)
	text(Vector2(50, 26), str(econ.gold), 38, AMBER)

	# 功勋 —— 第二资源，与金币并列同高：它是本作的核心差异，不能画成附属品
	text(Vector2(198, 10), "功勋", 15, DIM)
	_resource_star(Vector2(206, 52), 10.0, TEAL)
	text(Vector2(222, 26), str(main.merit.merit), 38, TEAL)

	# 生命 / 波次 —— 右上
	text_r(W - 24, 10, "生命", 15, DIM)
	text_r(W - 24, 26, str(econ.lives), 34, BAD if econ.lives <= 5 else TEXT)
	text_r(W - 122, 10, "波次", 15, DIM)
	text_r(W - 122, 30, "%d/%d" % [maxi(main.spawner.wave_index + 1, 0),
		main.spawner.waves.size()], 22, TEXT)

	# 人口
	var used: int = main.pop_used()
	var cap: int = main.merit.pop_cap()
	text(Vector2(26, 72), "人口 %d/%d" % [used, cap], 17, BAD if used >= cap else TEXT)

	# 下一档解锁进度：一条带渐变的圆角进度条，快到的时候发光
	var nxt: int = main.merit.next_locked_tier()
	if nxt > 0:
		var req: int = main.merit.required_merit(nxt)
		var ratio: float = clampf(float(main.merit.merit) / float(maxi(req, 1)), 0.0, 1.0)
		var bar := Rect2(150, 76, 220, 11)
		TDArt.fill(self, TDArt.round_rect(bar, bar.size.y * 0.5, 6), Color(0, 0, 0, 0.45))
		if ratio > 0.02:
			var fr := Rect2(bar.position, Vector2(maxf(bar.size.x * ratio, bar.size.y), bar.size.y))
			TDArt.fill_vgrad(self, TDArt.round_rect(fr, fr.size.y * 0.5, 6),
				Color("#5BE0C8"), Color("#1B8D7E"), bar.position.y, fr.end.y)
			if ratio > 0.85:
				TDArt.glow(self, Vector2(bar.position.x + fr.size.x, bar.get_center().y),
					26.0, Color(0.42, 0.95, 0.86, 0.35))
		text(Vector2(150, 90), "第 %d 档 %d/%d 功勋 · 点此解锁" % [nxt, main.merit.merit, req],
			12, DIM)
	else:
		text(Vector2(150, 84), "全部档位已解锁", 14, TEAL)

	# 部族 chip：左边一条部族色，右上角给「点击换部族」的行内提示
	var p: Dictionary = main.current_profession()
	var chip := Rect2(W - 216, 72, 192, 48)
	var pcol := Color(str(p.get("color", "#5BD1A6")))
	_panel(chip, 12.0, Color("#213240"), Color("#17242E"), Color(0.18, 0.28, 0.36, 1.0))
	TDArt.fill(self, TDArt.round_rect(Rect2(chip.position.x, chip.position.y, 5, chip.size.y), 2.5, 4),
		pcol)
	text(Vector2(chip.position.x + 16, chip.position.y + 6), str(p.get("name", "部族")), 18, TEXT)
	text(Vector2(chip.position.x + 16, chip.position.y + 28), "点击换部族", 11, DIM)


func _draw_actions() -> void:
	_draw_wave_button()
	_draw_intel()
	_draw_hero_box()


## 左块：开波。准备阶段给「提前开波能多拿多少金币」，进行中给「第几波 / 场上几只」。
func _draw_wave_button() -> void:
	var sp: TDWaveSpawner = main.spawner
	if sp == null:
		return
	var next_no: int = sp.wave_index + 2
	var cleared: bool = sp.wave_index + 1 >= sp.waves.size() and sp.enemies_left_in_wave() <= 0

	if cleared:
		_panel(WAVE_BTN, 14.0, Color("#1C3A2C"), Color("#14281F"), Color("#2E5A44"))
		text_c(WAVE_BTN.get_center().x, WAVE_BTN.position.y + 18, "已通关", 22, Color("#8BE0A8"))
		return

	if main.is_prep_phase():
		var bonus: int = main.early_wave_bonus()
		_panel(WAVE_BTN, 14.0, Color("#4A3A16"), Color("#2A2110"), AMBER)
		text_c(WAVE_BTN.get_center().x, WAVE_BTN.position.y + 8, "开波", 23, AMBER)
		text_c(WAVE_BTN.get_center().x, WAVE_BTN.position.y + 38,
			"第 %d 波 · 提前 +%d 金币" % [next_no, bonus], 12, Color("#E8D3A0"))
		var bar := Rect2(WAVE_BTN.position.x + 14, WAVE_BTN.end.y - 13, WAVE_BTN.size.x - 28, 5)
		TDArt.fill(self, TDArt.round_rect(bar, 2.5, 3), Color(0, 0, 0, 0.45))
		var ratio: float = main.prep_progress()
		if ratio > 0.01:
			TDArt.fill(self, TDArt.round_rect(
				Rect2(bar.position, Vector2(maxf(bar.size.x * ratio, 6.0), bar.size.y)), 2.5, 3), AMBER)
	else:
		_panel(WAVE_BTN, 14.0, Color("#1B2A37"), Color("#131E28"), LINE)
		text_c(WAVE_BTN.get_center().x, WAVE_BTN.position.y + 12,
			"第 %d 波 进行中" % maxi(sp.wave_index + 1, 1), 17, TEXT)
		text_c(WAVE_BTN.get_center().x, WAVE_BTN.position.y + 40,
			"场上 %d 只" % sp.enemies_left_in_wave(), 12, DIM)


## 中块：没选塔时是下一波情报，选了塔时是塔操作。
## 情报只给「下一波」，不给下两波 —— 手机上一屏塞两波等于两波都没看。
func _draw_intel() -> void:
	var t: TDTower = main.selected_tower
	if t != null and is_instance_valid(t):
		_draw_tower_actions(t)
		return

	_panel(INTEL_BOX, 14.0, Color("#1B2A37"), Color("#131E28"), LINE)
	var rows: Array = main.next_wave_hint()
	var px: float = INTEL_BOX.position.x + 12
	text(Vector2(px, INTEL_BOX.position.y + 5), "下一波", 12, DIM)
	if rows.is_empty():
		text(Vector2(px, INTEL_BOX.position.y + 32), "没有更多波次了", 15, TEAL)
		return

	var x: float = px
	var y: float = INTEL_BOX.position.y + 26
	for i: int in range(mini(rows.size(), 3)):
		var r: Dictionary = rows[i]
		var col: Color = r["color"]
		draw_circle(Vector2(x + 5, y + 7), 5.0, col, true, -1.0, true)
		var line: String = "%d %s" % [int(r["count"]), str(r["name"])]
		var w: float = _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if x + 16.0 + w > INTEL_BOX.end.x - 8:
			break
		text(Vector2(x + 15, y), line, 13, TEXT)
		x += 22.0 + w

	var hint: String = WaveIntel.hint(rows)
	if hint != "":
		text(Vector2(px, INTEL_BOX.end.y - 22), hint, 12, Color("#E8B45C"))


func _up_rect() -> Rect2:
	return Rect2(INTEL_BOX.position.x + 8, INTEL_BOX.position.y + 38, 108, 30)


func _sell_rect() -> Rect2:
	return Rect2(INTEL_BOX.position.x + 124, INTEL_BOX.position.y + 38, 108, 30)


func _draw_tower_actions(t: TDTower) -> void:
	_panel(INTEL_BOX, 14.0, Color("#1B2A37"), Color("#131E28"), LINE)
	text(Vector2(INTEL_BOX.position.x + 12, INTEL_BOX.position.y + 3),
		"%s Lv.%d" % [t.display_name, t.level], 17, TEXT)
	text(Vector2(INTEL_BOX.position.x + 12, INTEL_BOX.position.y + 23),
		"伤害 %.0f · 射程 %d · 击杀 %d" % [t.damage, int(t.range_px), t.kills], 12, DIM)

	var up: Rect2 = _up_rect()
	var can_up: bool = t.can_upgrade()
	if can_up:
		_panel(up, 9.0, Color("#1F4A47"), Color("#153230"), TEAL)
	else:
		_panel(up, 9.0, Color("#1A2430"), Color("#141C24"), LINE)
	text_c(up.get_center().x, up.position.y + 4, "升级", 14, TEXT if can_up else DIM)
	text_c(up.get_center().x, up.position.y + 20,
		(str(t.upgrade_cost()) + " 金币") if can_up else "已满级", 11, AMBER if can_up else DIM)

	var sell: Rect2 = _sell_rect()
	_panel(sell, 9.0, Color("#33201F"), Color("#221616"), Color("#6B3030"))
	text_c(sell.get_center().x, sell.position.y + 4, "出售", 14, TEXT)
	text_c(sell.get_center().x, sell.position.y + 20, "+%d 金币" % t.sell_value(), 11, Color("#E0A0A0"))


## 右块：英雄。三个装备格不是装饰 —— 「剑/护符/靴」三色对应
## 攻击力 / 攻速 / 移速+射程，玩家扫一眼就知道自己这套装备在往哪个方向长。
func _draw_hero_box() -> void:
	var h: HeroUnit = main.hero
	if h == null:
		return
	_panel(HERO_BOX, 14.0, Color("#2E2716"), Color("#1A170E"), Color("#5A4A22"))

	var c := Vector2(HERO_BOX.position.x + 26, HERO_BOX.get_center().y)
	TDArt.glow(self, c, 26.0, Color(0.92, 0.74, 0.32, 0.35))
	draw_circle(c, 15.0, Color("#E8BC62"), true, -1.0, true)
	draw_circle(c, 15.0, Color(0.10, 0.07, 0.03, 0.92), false, 2.0, true)
	# 头像是把剑，不是一个「英雄」二字 —— 10px 的中文在圆圈里读不出来
	draw_line(c + Vector2(0, 6), c + Vector2(0, -7), Color("#2A2110"), 2.4, true)
	draw_line(c + Vector2(-4, 2), c + Vector2(4, 2), Color("#2A2110"), 2.0, true)

	text(Vector2(HERO_BOX.position.x + 48, HERO_BOX.position.y + 2),
		"Lv.%d  攻 %.0f" % [h.level, h.attack()], 13, Color("#E8D3A0"))

	var sx: float = HERO_BOX.position.x + 48
	var sy: float = HERO_BOX.position.y + 26
	for i: int in range(HeroUnit.SLOTS.size()):
		var kind: String = HeroUnit.SLOTS[i]
		var lvl: int = h.slot_level(kind)
		var r := Rect2(sx + float(i) * 34.0, sy, 28, 30)
		var col: Color = HeroUnit.SLOT_COLORS.get(kind, Color.WHITE)
		var shape: PackedVector2Array = TDArt.round_rect(r, 7.0, 4)
		if lvl > 0:
			TDArt.fill(self, shape, Color(col.r * 0.30, col.g * 0.30, col.b * 0.30, 1.0))
			draw_polyline(TDArt.closed(shape), col, 1.6, true)
			text_c(r.get_center().x, r.position.y + 3, "★%d" % lvl, 12, col)
		else:
			TDArt.fill(self, shape, Color(0, 0, 0, 0.35))
			draw_polyline(TDArt.closed(shape), Color(0.34, 0.31, 0.21, 1.0), 1.0, true)
			text_c(r.get_center().x, r.position.y + 5, str(HeroUnit.SLOT_NAMES.get(kind, "?")), 11, DIM)


func _draw_cards() -> void:
	var p: Dictionary = main.current_profession()
	var ids: Array = p.get("towers", [])
	if ids.is_empty():
		return
	var n: int = ids.size()
	var total: float = float(n) * CARD_W + float(n - 1) * CARD_GAP
	var x0: float = (W - total) * 0.5

	for i: int in range(n):
		var id := StringName(str(ids[i]))
		var def: Dictionary = main.content.tower_def(id)
		if def.is_empty():
			continue
		var x: float = x0 + float(i) * (CARD_W + CARD_GAP)
		var r := Rect2(x, CARD_Y, CARD_W, CARD_H)
		var locked: bool = not main.merit.is_unlocked(int(def.get("tier", 1)))
		var selected: bool = main.build_id == id
		var col := Color(str(def.get("color", "#8899AA")))

		if locked:
			_panel(r, 12.0, Color("#182430"), Color("#121B24"), Color("#243543"))
		else:
			# 卡面染一层部族色，六张卡才有「六支部队」的差异感
			_panel(r, 12.0, Color("#20303E").lerp(col, 0.14),
				Color("#16232D").lerp(col, 0.06), Color("#2C4052").lerp(col, 0.18))
		if selected:
			TDArt.glow(self, r.get_center(), 74.0, Color(0.88, 0.66, 0.24, 0.30))
			draw_polyline(TDArt.closed(TDArt.round_rect(r.grow(-1.0), 12.0, 6)), AMBER, 2.5, true)

		# 档位角标：圆角小chip，锁着的时候只给暗底
		var badge := Rect2(x + 6, CARD_Y + 5, 26, 18)
		TDArt.fill(self, TDArt.round_rect(badge, 6.0, 3),
			Color(0.10, 0.14, 0.18, 1.0) if locked else col)
		text_c(badge.get_center().x, badge.position.y + 1, "T%d" % int(def.get("tier", 1)), 11,
			DIM if locked else Color("#0B1420"))

		var label: String = str(def.get("name", "?"))
		text_c(x + CARD_W * 0.5, CARD_Y + 28, label, 15, DIM if locked else TEXT)

		if locked:
			var req: int = main.merit.required_merit(int(def.get("tier", 1)))
			text_c(x + CARD_W * 0.5, CARD_Y + 50, "需要", 11, DIM)
			text_c(x + CARD_W * 0.5, CARD_Y + 64, "%d 功勋" % req, 12, TEAL)
		else:
			# JSON 里的数字都是 float，直接 str() 会显示成 "40.0"，先转 int
			text_c(x + CARD_W * 0.5, CARD_Y + 50, str(int(def.get("cost", 0))), 18, AMBER)
			text_c(x + CARD_W * 0.5, CARD_Y + 72,
				"伤害 %d" % int(def.get("damage", 0)), 11, DIM)


func _draw_skills() -> void:
	var skills: Array = main.merit.SKILLS
	var n: int = skills.size()
	var w := 150.0
	var gap := 14.0
	var total: float = float(n) * w + float(n - 1) * gap
	var x0: float = (W - total) * 0.5 + 40.0

	for i: int in range(n):
		var s: Dictionary = skills[i]
		var x: float = x0 + float(i) * (w + gap)
		var r := Rect2(x, SKILL_Y, w, SKILL_H)
		var ok: bool = main.merit.can_afford(int(s["cost"]))
		if ok:
			_panel(r, 12.0, Color("#1C3A44"), Color("#142831"), TEAL)
		else:
			_panel(r, 12.0, Color("#182430"), Color("#121B24"), LINE)
		text_c(r.get_center().x, SKILL_Y + 8, str(s["name"]), 19, TEXT if ok else DIM)
		text_c(r.get_center().x, SKILL_Y + 34, "%d 功勋" % int(s["cost"]), 13,
			TEAL if ok else DIM)
		# 热键角标
		text(Vector2(x + 7, SKILL_Y + 2), str(s.get("hotkey", i + 1)), 11, DIM)


# ------------------------------------------------------------------ 绘制小工具

## 玻璃面板：竖向渐变 + 一圈描边 + 顶边一条内高光。
## 三条都要有，少一条就会退回「没上色的线框图」。
func _panel(r: Rect2, rad: float, top_c: Color, bot_c: Color, border: Color) -> void:
	var shape: PackedVector2Array = TDArt.round_rect(r, rad, 6)
	TDArt.fill_vgrad(self, shape, top_c, bot_c, r.position.y, r.end.y)
	draw_polyline(TDArt.closed(shape), border, 1.0, true)
	draw_line(Vector2(r.position.x + rad, r.position.y + 1.2),
		Vector2(r.end.x - rad, r.position.y + 1.2), Color(1, 1, 1, 0.07), 1.0)


func _resource_coin(c: Vector2, r: float, col: Color) -> void:
	TDArt.glow(self, c, r * 2.4, Color(col, 0.30))
	draw_circle(c, r, col, true, -1.0, true)
	draw_circle(c, r * 0.52, Color(0.06, 0.10, 0.14, 1.0), true, -1.0, true)
	draw_circle(c, r * 0.52, Color(col, 0.9), false, 1.2, true)


func _resource_star(c: Vector2, r: float, col: Color) -> void:
	TDArt.glow(self, c, r * 2.4, Color(col, 0.30))
	TDArt.fill(self, TDArt.star(c, r * 1.15, r * 0.44, 4), col)


# ------------------------------------------------------------------ 命中测试

func _top_unlock_rect() -> Rect2:
	return Rect2(146, 80, 230, 32)


func _prof_rect() -> Rect2:
	return Rect2(W - 216, 78, 192, 40)


func _card_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var p: Dictionary = main.current_profession()
	var ids: Array = p.get("towers", [])
	var n: int = ids.size()
	if n == 0:
		return out
	var total: float = float(n) * CARD_W + float(n - 1) * CARD_GAP
	var x0: float = (W - total) * 0.5
	for i: int in range(n):
		out.append(Rect2(x0 + float(i) * (CARD_W + CARD_GAP), CARD_Y, CARD_W, CARD_H))
	return out


func _skill_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var n: int = main.merit.SKILLS.size()
	var w := 150.0
	var gap := 14.0
	var total: float = float(n) * w + float(n - 1) * gap
	var x0: float = (W - total) * 0.5 + 40.0
	for i: int in range(n):
		out.append(Rect2(x0 + float(i) * (w + gap), SKILL_Y, w, SKILL_H))
	return out


## 返回 true 表示这次输入被 HUD 吃掉，地图不再处理。
func handle_input(event: InputEvent) -> bool:
	var p: Vector2 = _press_pos(event)
	if p == NO_POS:
		return false
	if _hit_top(p):
		return true
	if _hit_actions(p):
		return true
	if _hit_cards(p):
		return true
	if _hit_skills(p):
		return true
	# 底部区域兜底：点在空白处也不该穿透到地图去造塔
	return p.y > CARD_Y


func _press_pos(event: InputEvent) -> Vector2:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and touch.pressed:
		return touch.position
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		return mb.position
	return NO_POS


func _hit_top(p: Vector2) -> bool:
	if p.y >= TOP_H:
		return false
	if _prof_rect().has_point(p):
		main.switch_profession(1)
	elif _top_unlock_rect().has_point(p):
		main.try_unlock_tier()
	return true


func _hit_actions(p: Vector2) -> bool:
	# 整条控制带一律吞掉输入：宁可点了没反应，也不能穿透到棋盘上造出一座塔。
	if p.y < ACTION_Y or p.y > ACTION_Y + ACTION_H:
		return false
	if WAVE_BTN.has_point(p):
		main.start_wave_early()
		return true
	var t: TDTower = main.selected_tower
	if t != null and is_instance_valid(t):
		if _up_rect().has_point(p):
			main.try_upgrade(t)
			return true
		if _sell_rect().has_point(p):
			main.try_sell(t)
			return true
	return true


func _hit_cards(p: Vector2) -> bool:
	var cards: Array[Rect2] = _card_rects()
	for i: int in range(cards.size()):
		if not cards[i].has_point(p):
			continue
		var ids: Array = main.current_profession().get("towers", [])
		if i < ids.size():
			main.build_id = StringName(str(ids[i]))
			main.selected_tower = null
			main.toast("%s（%d 金币）" % [
				main.content.tower_def(main.build_id).get("name", ""),
				main.content.tower_cost(main.build_id)])
		return true
	return false


func _hit_skills(p: Vector2) -> bool:
	var skills: Array[Rect2] = _skill_rects()
	for i: int in range(skills.size()):
		if not skills[i].has_point(p):
			continue
		main.use_skill(main.merit.SKILLS[i]["id"])
		return true
	return false


# ------------------------------------------------------------------ 结算页
#
# 这一页只回答一个问题：我是怎么输的。
# 所以版面的权重是「主因 → 构成 → 建议」，而不是把一堆数字平铺上去。
# 数据全部来自 RunReport，这里不做任何判断，只排版。

func _draw_result() -> void:
	var rep: RunReport = main.report
	if rep == null:
		return
	var v: Dictionary = rep.verdict()
	var won: bool = bool(v["won"])
	var accent: Color = Color("#E8C36A") if won else BAD

	# 全屏压暗。用一层带蓝的深色而不是纯黑：纯黑会让棋盘看起来「关机了」，
	# 玩家会以为自己把游戏点崩了。
	draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.04, 0.06, 0.84))

	var x: float = RESULT_PANEL.position.x + 30.0
	var iw: float = RESULT_PANEL.size.x - 60.0
	var blame_txt: String = str(v["blame"])
	var rows: Array = v["breakdown"]
	var advice_lines: Array[String] = _wrap(str(v["advice"]), 16, iw - 32.0)
	var foot1: String = str((v["lines"] as Array)[1])
	var foot2: String = str((v["lines"] as Array)[2])

	# 先量后画。面板高度跟着内容走 —— 固定高度在「一只没漏」和「建议很长」
	# 这两种极端下都会留一大片空白或者直接溢出，而这两件事都会发生。
	var body: float = 34.0 + 54.0 + 26.0 + 26.0 + 22.0  # 上边距·标题·副标题·时长·分割线
	body += 60.0 if not blame_txt.is_empty() else 36.0
	if not rows.is_empty():
		body += 22.0 + float(rows.size()) * 34.0 + 10.0
	body += 18.0 + 22.0 + float(advice_lines.size()) * 26.0 + 14.0
	## 底部那块：两条数据 + 重开提示 + 内边距。
	## 这三个数必须比实际行距宽松一点 —— 紧贴建议框会让整页看起来「糊在一起」，
	## 而结算页最怕的就是玩家一眼扫过去什么都没记住。
	body += 40.0 + 26.0 + 40.0

	# 垂直位置按内容高度换算，视觉重心落在棋盘中部而不是屏幕正中 ——
	# 正中会贴着底部卡片，看起来像被 HUD 挤上去的。
	var r := Rect2(RESULT_PANEL.position.x,
		clampf(150.0 + (940.0 - body) * 0.45, 160.0, 420.0),
		RESULT_PANEL.size.x, body)
	_panel(r, 18.0, Color("#1A2A38"), Color("#0E1A24"), Color("#33506A"))
	# 顶部强调条 + 一条同色辉光，让「赢 / 输」在两米外就能分辨
	draw_rect(Rect2(r.position, Vector2(r.size.x, 5.0)), accent)
	TDArt.fill_vgrad(self, TDArt.round_rect(
		Rect2(r.position, Vector2(r.size.x, 26.0)), 13.0, 3), accent, Color(0, 0, 0, 0),
		r.position.y, r.position.y + 26.0)

	var y: float = r.position.y + 34.0
	text(Vector2(x, y), str(v["title"]), 38, accent if won else Color("#FF8C8C"))
	y += 54.0
	text(Vector2(x, y), str(v["headline"]), 17, DIM)
	y += 26.0
	text(Vector2(x, y), "本局用时 %s" % RunReport.clock(rep.duration), 15, DIM)
	y += 26.0
	draw_line(Vector2(x, y), Vector2(x + iw, y), LINE, 1.0)
	y += 22.0

	# 主因：整页最重要的一行，字号给到最大。
	if not blame_txt.is_empty():
		text(Vector2(x, y), "主要漏怪", 14, DIM)
		y += 24.0
		text(Vector2(x, y), blame_txt, 19, Color("#FFB4B4"))
		y += 40.0
	else:
		text(Vector2(x, y), "一只都没漏出去", 19, Color("#8CE0B0"))
		y += 40.0

	# 构成：按掉血量排序，配一条相对长度的条。
	# 按掉血量而不是只数排，是因为重装一只掉 2 血、斥候一只掉 1 血 ——
	# 按只数排会把真正致命的那类藏到第二行。
	if not rows.is_empty():
		text(Vector2(x, y), "漏怪构成", 14, DIM)
		y += 22.0
		var worst: int = 1
		for row: Dictionary in rows:
			worst = maxi(worst, int(row["damage"]))
		for row: Dictionary in rows:
			text(Vector2(x, y), str(row["name"]), 16, TEXT)
			text_r(x + iw, y, "×%d　-%d 血" % [int(row["count"]), int(row["damage"])],
				15, DIM)
			draw_rect(Rect2(x, y + 21.0, iw, 4.0), Color(0, 0, 0, 0.45))
			draw_rect(Rect2(x, y + 21.0, iw * float(row["damage"]) / float(worst), 4.0),
				Color(0.88, 0.34, 0.38, 0.85))
			y += 34.0
		y += 10.0

	# 建议：写在独立的浅色盒子里。和上面的数字分开，是为了让它被读到 ——
	# 这一句是整页唯一「下次能改」的东西。
	y += 18.0
	var box_h: float = 22.0 + float(advice_lines.size()) * 26.0 + 14.0
	_panel(Rect2(x, y, iw, box_h), 10.0, Color("#20323F"), Color("#16232F"), Color("#2F4A5E"))
	draw_rect(Rect2(x, y, 3.0, box_h), TEAL)
	var ty: float = y + 16.0
	for ln: String in advice_lines:
		text(Vector2(x + 18.0, ty), ln, 16, Color("#CFE3EE"))
		ty += 26.0

	# 底部：一行数据 + 一行重开提示
	var by2: float = r.position.y + r.size.y - 30.0
	text(Vector2(x, by2 - 46.0), foot1, 14, DIM)
	text(Vector2(x, by2 - 26.0), foot2, 14, DIM)
	# 提示文字只在 0.55~1.0 之间呼吸。用 sin 直接当 alpha 会掉到 0 附近，
	# 截屏或恰好抬头的那一瞬就是一片看不见 —— 玩家会以为卡住了。
	var blink: float = 0.55 + 0.45 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006))
	text_c(W * 0.5, by2 + 4.0, "点击任意处再来一局", 17,
		Color(TEXT.r, TEXT.g, TEXT.b, blink))


## 逐字折行。中文没有空格，按字符宽度切就够；
## 顺手把句号/逗号/问号这类不能出现在行首的标点往回拉一格。
func _wrap(s: String, size: int, max_w: float) -> Array[String]:
	const NO_LINE_START := "，。！？、；：）】」』…"
	var out: Array[String] = []
	var line: String = ""
	for i: int in s.length():
		var ch: String = s[i]
		var trial: String = line + ch
		if _font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w \
				and not line.is_empty():
			if NO_LINE_START.contains(ch) and line.length() > 1:
				out.append(line.substr(0, line.length() - 1))
				line = line[line.length() - 1] + ch
			else:
				out.append(line)
				line = ch
		else:
			line = trial
	if not line.is_empty():
		out.append(line)
	return out
