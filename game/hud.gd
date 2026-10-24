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
	var t: TDTower = main.selected_tower
	if t == null or not is_instance_valid(t):
		return
	var r := Rect2(16, ACTION_Y, W - 32, ACTION_H)
	_panel(r, 14.0, Color("#1B2A37"), Color("#131E28"), LINE)

	text(Vector2(34, ACTION_Y + 8), "%s  Lv.%d" % [t.display_name, t.level], 21, TEXT)
	text(Vector2(34, ACTION_Y + 38),
		"伤害 %.0f · 射程 %d · 击杀 %d" % [t.damage, int(t.range_px), t.kills], 14, DIM)

	# 升级
	var uc: int = t.upgrade_cost()
	var can_up: bool = t.can_upgrade()
	var up_rect := Rect2(W - 320, ACTION_Y + 12, 140, 54)
	if can_up:
		_panel(up_rect, 12.0, Color("#1F4A47"), Color("#153230"), TEAL)
		TDArt.glow(self, up_rect.get_center(), 70.0, Color(0.12, 0.62, 0.56, 0.22))
	else:
		_panel(up_rect, 12.0, Color("#1A2430"), Color("#141C24"), LINE)
	text_c(up_rect.get_center().x, up_rect.position.y + 9, "升级", 17, TEXT if can_up else DIM)
	text_c(up_rect.get_center().x, up_rect.position.y + 30,
		("%d 金币" % uc) if can_up else "已满级", 13, AMBER if can_up else DIM)

	# 出售
	var sell_rect := Rect2(W - 168, ACTION_Y + 12, 136, 54)
	_panel(sell_rect, 12.0, Color("#33201F"), Color("#221616"), Color("#6B3030"))
	text_c(sell_rect.get_center().x, sell_rect.position.y + 9, "出售", 17, TEXT)
	text_c(sell_rect.get_center().x, sell_rect.position.y + 30,
		"+%d 金币" % t.sell_value(), 13, Color("#E0A0A0"))


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
	var t: TDTower = main.selected_tower
	if t == null or not is_instance_valid(t):
		return false
	if p.y < ACTION_Y or p.y > ACTION_Y + ACTION_H:
		return false
	if Rect2(W - 320, ACTION_Y + 12, 140, 54).has_point(p):
		main.try_upgrade(t)
	elif Rect2(W - 168, ACTION_Y + 12, 136, 54).has_point(p):
		main.try_sell(t)
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
