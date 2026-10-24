class_name TDEconomy
extends RefCounted
## Gold + lives. Lose when lives reach 0.

signal gold_changed(gold: int)
signal lives_changed(lives: int)
signal defeated()

var gold: int
var lives: int
var max_lives: int

func _init(p_gold: int = 100, p_lives: int = 20) -> void:
	gold = p_gold
	lives = p_lives
	max_lives = p_lives

func can_afford(cost: int) -> bool:
	return gold >= cost

func spend(cost: int) -> bool:
	if cost < 0 or gold < cost:
		return false
	gold -= cost
	gold_changed.emit(gold)
	return true

func earn(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)

func leak(damage: int) -> void:
	if lives <= 0:
		return
	lives = maxi(0, lives - damage)
	lives_changed.emit(lives)
	if lives == 0:
		defeated.emit()

func is_defeated() -> bool:
	return lives <= 0
