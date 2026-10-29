class_name SpellStackView
extends Control

signal undo_top_card()

var played_cards: Array[SpellData.CardItem] = []

const FAN_CARD_SIZE := Vector2(118, 162)
const BASE_PIVOT := Vector2(112, 260)

func _init() -> void:
	custom_minimum_size = Vector2(332, 335)
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_stack(cards: Array[SpellData.CardItem]) -> void:
	played_cards = cards.duplicate()
	_rebuild_children()
	queue_redraw()

## Calcule la position du coin Bas-Gauche (pivot) et la rotation de la carte i (0, 1, 2) dans l'éventail
## de sorte que le bord gauche de la carte i+1 s'aligne exactement sur la diagonale de la carte i.
func _get_fan_slot_transform(slot_idx: int) -> Dictionary:
	var w: float = FAN_CARD_SIZE.x
	var h: float = FAN_CARD_SIZE.y
	var diag_angle: float = atan2(w, h) # ~36° : angle entre le bord gauche et la diagonale (0,h)->(w,0)
	var diag_len: float = sqrt(w * w + h * h)
	var slide_along_diag: float = (diag_len - h) * 0.5

	var rot: float = float(slot_idx - 1) * diag_angle
	var pivot: Vector2 = BASE_PIVOT

	# Décale légèrement chaque carte le long de la diagonale précédente pour centrer le recouvrement
	for k in range(slot_idx):
		var prev_rot: float = float(k - 1) * diag_angle
		var diag_angle_world: float = prev_rot + diag_angle
		var diag_dir := Vector2(sin(diag_angle_world), -cos(diag_angle_world))
		pivot += diag_dir * slide_along_diag

	return {
		"pivot": pivot,
		"rotation": rot
	}

func _rebuild_children() -> void:
	for child in get_children():
		child.queue_free()

	var count: int = played_cards.size()
	for i in range(count):
		var cv := CardView.new()
		cv.custom_minimum_size = FAN_CARD_SIZE
		cv.size = FAN_CARD_SIZE
		cv.pivot_offset = Vector2(0, FAN_CARD_SIZE.y) # Pivot sur le coin Bas-Gauche (0, H)

		var is_last_step: bool = (i == 2)
		var is_covered_by_next: bool = (i < count - 1)
		cv.setup(played_cards[i], true, i, is_last_step, is_covered_by_next, true)

		var tf: Dictionary = _get_fan_slot_transform(i)
		cv.position = tf["pivot"] - Vector2(0, FAN_CARD_SIZE.y)
		cv.rotation = tf["rotation"]
		cv.card_clicked.connect(_on_stack_card_clicked)
		add_child(cv)

func _on_stack_card_clicked(_cv: CardView) -> void:
	if played_cards.size() > 0:
		undo_top_card.emit()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if played_cards.size() > 0:
			undo_top_card.emit()

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var step_names: Array[String] = ["1. ÉLÉMENT", "2. FORME", "3. BONUS"]
	var w: float = FAN_CARD_SIZE.x
	var h: float = FAN_CARD_SIZE.y

	# Dessine les emplacements fantômes en éventail pour les étapes non encore posées
	for i in range(3):
		if i < played_cards.size():
			continue

		var tf: Dictionary = _get_fan_slot_transform(i)
		var pivot: Vector2 = tf["pivot"]
		var rot: float = tf["rotation"]

		# Transforme le repère local pour que (0, h) soit au pivot et tourné de rot
		var top_left_world: Vector2 = pivot + Vector2(0, -h).rotated(rot)
		draw_set_transform(top_left_world, rot, Vector2.ONE)

		var is_current_step: bool = (i == played_cards.size())
		var bg_col := Color(0.16, 0.19, 0.27, 0.78) if is_current_step else Color(0.11, 0.13, 0.18, 0.45)
		var border_col := Color(0.95, 0.82, 0.35, 0.95) if is_current_step else Color(0.35, 0.40, 0.52, 0.50)

		var rect := Rect2(Vector2.ZERO, FAN_CARD_SIZE)
		draw_rect(rect, bg_col, true)
		draw_line(Vector2(2, h - 2), Vector2(w - 2, 2), border_col.darkened(0.25), 2.0)
		draw_rect(rect, border_col, false, 2.5 if is_current_step else 1.5)

		var label_col := Color(1.0, 0.92, 0.55) if is_current_step else Color(0.55, 0.60, 0.72)
		draw_string(font, Vector2(8, 30), step_names[i], HORIZONTAL_ALIGNMENT_LEFT, 100, 12, label_col)
		if is_current_step:
			draw_string(font, Vector2(8, 48), "(À jouer)", HORIZONTAL_ALIGNMENT_LEFT, 100, 11, Color(0.85, 0.88, 0.95))

	# Réinitialise la matrice de dessin
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
