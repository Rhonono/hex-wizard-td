class_name CardView
extends Control

signal card_clicked(card_view: CardView)

var card_data: SpellData.CardItem
var is_playable: bool = true
var is_hovered: bool = false
var is_in_spell_slot: bool = false
var active_slot_category: int = -1 # -1 = en main, sinon SpellData.CompCategory (0, 1, 2)
var grey_out_bottom_right: bool = false
var hide_bottom_right: bool = false

func _init() -> void:
	custom_minimum_size = Vector2(144, 192)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func setup(
	p_card: SpellData.CardItem,
	p_playable: bool = true,
	p_slot_cat: int = -1,
	p_grey_br: bool = false,
	p_hide_br: bool = false,
	p_in_spell_slot: bool = false
) -> void:
	card_data = p_card
	is_playable = p_playable
	active_slot_category = p_slot_cat
	is_in_spell_slot = p_in_spell_slot
	grey_out_bottom_right = p_grey_br
	hide_bottom_right = p_hide_br
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_playable else Control.CURSOR_FORBIDDEN
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		is_hovered = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		is_hovered = false
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		card_clicked.emit(self)

func _draw() -> void:
	if card_data == null:
		return

	var w: float = size.x
	var h: float = size.y

	# Détermine quel composant est en Haut-Gauche (actif quand posé dans le sort)
	# et quel composant est en Bas-Droite (recouvert par la carte suivante ou grisé sur la 3e carte)
	var tl_cat: int = card_data.comp1_cat
	var tl_val: int = card_data.comp1_val
	var br_cat: int = card_data.comp2_cat
	var br_val: int = card_data.comp2_val

	if is_in_spell_slot:
		if card_data.has_category(active_slot_category):
			if card_data.comp2_cat == active_slot_category:
				# On oriente la carte pour que le composant actif soit dans le triangle Haut-Gauche visible
				tl_cat = card_data.comp2_cat
				tl_val = card_data.comp2_val
				br_cat = card_data.comp1_cat
				br_val = card_data.comp1_val
		else:
			# La carte n'a pas le bon type de composant : elle fournit le composant diminué par défaut !
			tl_cat = active_slot_category
			tl_val = card_data.get_value_for_category(active_slot_category)
	elif not is_in_spell_slot and active_slot_category != -1 and card_data.has_category(active_slot_category):
		# En main : met en Haut-Gauche le composant correspondant à l'étape actuelle du sort
		if card_data.comp2_cat == active_slot_category:
			tl_cat = card_data.comp2_cat
			tl_val = card_data.comp2_val
			br_cat = card_data.comp1_cat
			br_val = card_data.comp1_val

	var shadow_offset := Vector2(5, 7) if not is_hovered else Vector2(8, 12)

	# Triangle Haut-Gauche : (0,0) -> (w,0) -> (0,h)
	var tri_tl := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(0, h)])
	var col_tl: Color = SpellData.get_component_bg_color(tl_cat, tl_val)
	if not is_playable and not is_in_spell_slot:
		col_tl = col_tl.darkened(0.45)

	if hide_bottom_right:
		# Quand la carte est recouverte en éventail par la carte suivante :
		# Seul le triangle Haut-Gauche (composant actif) est visible, le composant inutile est 100% recouvert
		var shadow_tri := PackedVector2Array([
			 shadow_offset,
			 Vector2(w, 0) + shadow_offset,
			 Vector2(0, h) + shadow_offset
		])
		draw_colored_polygon(shadow_tri, Color(0, 0, 0, 0.45))
		draw_colored_polygon(tri_tl, col_tl)
		_draw_half_content(tl_cat, tl_val, Vector2(w * 0.34, h * 0.27), false)

		var border_tl := Color(1.0, 0.9, 0.5)
		draw_polyline(
			PackedVector2Array([Vector2(0, h), Vector2(0, 0), Vector2(w, 0), Vector2(0, h)]),
			border_tl,
			2.5,
			true
		)
		return

	# Ombre portée complète
	draw_rect(Rect2(shadow_offset, size), Color(0, 0, 0, 0.48), true)

	# Triangle Bas-Droite : (w,0) -> (w,h) -> (0,h)
	var tri_br := PackedVector2Array([Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	var col_br: Color = SpellData.get_component_bg_color(br_cat, br_val)
	if grey_out_bottom_right:
		col_br = Color(0.16, 0.16, 0.19)
	elif not is_playable and not is_in_spell_slot:
		col_br = col_br.darkened(0.45)

	draw_colored_polygon(tri_tl, col_tl)
	draw_colored_polygon(tri_br, col_br)

	# Ligne diagonale de séparation (0, h) -> (w, 0)
	draw_line(Vector2(2, h - 2), Vector2(w - 2, 2), Color(0.95, 0.88, 0.68, 0.9), 3.0, true)

	# Contenu du triangle Haut-Gauche (centre vers (0.34*w, 0.27*h))
	_draw_half_content(tl_cat, tl_val, Vector2(w * 0.34, h * 0.27), false)

	# Contenu du triangle Bas-Droite (centre vers (0.66*w, 0.73*h))
	_draw_half_content(br_cat, br_val, Vector2(w * 0.66, h * 0.73), grey_out_bottom_right)

	# Bordure extérieure de la carte
	var has_matching_cat: bool = (active_slot_category == -1) or card_data.has_category(active_slot_category)
	var border_col := Color(0.95, 0.84, 0.45) if (is_hovered and is_playable) else Color(0.75, 0.72, 0.68)
	if is_in_spell_slot:
		border_col = Color(1.0, 0.9, 0.5) if has_matching_cat else Color(0.85, 0.62, 0.35)
	elif not is_playable:
		border_col = Color(0.35, 0.35, 0.4)
	draw_rect(Rect2(Vector2.ZERO, size), border_col, false, 3.0 if is_hovered else 2.0)

func _draw_half_content(cat: int, val: int, center: Vector2, is_greyed: bool) -> void:
	var font: Font = ThemeDB.fallback_font
	var text_col: Color = Color(0.48, 0.48, 0.52) if is_greyed else Color.WHITE
	var sub_col: Color = Color(0.40, 0.40, 0.44) if is_greyed else Color(0.92, 0.90, 0.78)

	# Badge de catégorie ("1. ÉLÉMENT", "2. FORME", "3. BONUS") + étoile si composant puissant
	var is_strong: bool = SpellData.is_component_strong(cat, val)
	var cat_label: String = SpellData.get_category_name(cat) + (" ★" if is_strong else "")
	var cat_col: Color = sub_col if not is_strong or is_greyed else Color(1.0, 0.88, 0.35)
	draw_string(font, center + Vector2(-46, -24), cat_label, HORIZONTAL_ALIGNMENT_CENTER, 92, 10, cat_col)

	# Icône / Mini-visuel au centre du triangle
	match cat:
		SpellData.CompCategory.ELEMENT:
			var el_col: Color = Color(0.45, 0.45, 0.48) if is_greyed else SpellData.get_element_color(val)
			draw_circle(center + Vector2(0, -5), 12.0, el_col)
			draw_arc(center + Vector2(0, -5), 12.0, 0, TAU, 24, Color.WHITE if not is_greyed else Color.DIM_GRAY, 1.8)
		SpellData.CompCategory.SHAPE:
			_draw_mini_shape(val, center + Vector2(-5, -6), is_greyed)
		SpellData.CompCategory.BONUS:
			var r_col: Color = Color(0.45, 0.45, 0.48) if is_greyed else Color(1.0, 0.84, 0.35)
			var c_pos: Vector2 = center + Vector2(0, -5)
			var diamond := PackedVector2Array([
				c_pos + Vector2(0, -12),
				c_pos + Vector2(12, 0),
				c_pos + Vector2(0, 12),
				c_pos + Vector2(-12, 0),
				c_pos + Vector2(0, -12)
			])
			draw_colored_polygon(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3]]), r_col.darkened(0.55))
			draw_polyline(diamond, r_col, 2.0, true)
			var badge: String = SpellData.get_bonus_short_badge(val)
			draw_string(font, c_pos + Vector2(-16, 4), badge, HORIZONTAL_ALIGNMENT_CENTER, 32, 9, Color.WHITE if not is_greyed else Color.GRAY)

	# Titre du composant
	var title: String = SpellData.get_component_title(cat, val)
	draw_string(font, center + Vector2(-46, 17), title, HORIZONTAL_ALIGNMENT_CENTER, 92, 12, text_col)

	if is_greyed:
		draw_string(font, center + Vector2(-44, 29), "(Inactif)", HORIZONTAL_ALIGNMENT_CENTER, 88, 10, Color(0.65, 0.65, 0.7))
	elif cat == SpellData.CompCategory.ELEMENT:
		var dmg_txt: String = "%d DG" % SpellData.get_element_base_damage(val)
		draw_string(font, center + Vector2(-44, 29), dmg_txt, HORIZONTAL_ALIGNMENT_CENTER, 88, 10, sub_col)

func _draw_mini_shape(sh: int, center: Vector2, is_greyed: bool) -> void:
	var offsets: Array[Vector2i] = SpellData.get_shape_offsets(sh)
	var mini_size: float = 4.0
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for off in offsets:
		var px: Vector2 = HexMath.hex_to_pixel(off, mini_size)
		min_v.x = min(min_v.x, px.x)
		min_v.y = min(min_v.y, px.y)
		max_v.x = max(max_v.x, px.x)
		max_v.y = max(max_v.y, px.y)
	var mid: Vector2 = (min_v + max_v) * 0.5

	for off in offsets:
		var px: Vector2 = center + HexMath.hex_to_pixel(off, mini_size) - mid
		var is_origin: bool = (off == Vector2i.ZERO)
		var col: Color
		if is_greyed:
			col = Color(0.6, 0.6, 0.65) if is_origin else Color(0.4, 0.4, 0.45)
		else:
			col = Color(1.0, 0.88, 0.25) if is_origin else Color(0.55, 0.85, 1.0)
		draw_circle(px, 3.0 if is_origin else 2.4, col)
