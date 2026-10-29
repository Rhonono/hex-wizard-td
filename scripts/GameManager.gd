extends Control

# Références UI créées dynamiquement pour garantir zéro dépendance externe fragile
var board_view: HexBoardView
var spell_stack_view: SpellStackView
var hand_container: HBoxContainer
var lbl_top_status: Label
var lbl_step_prompt: Label
var lbl_spell_summary: Label
var lbl_combat_log: Label
var btn_rotate_left: Button
var btn_rotate_right: Button
var btn_cast_spell: Button
var btn_undo_card: Button
var btn_end_turn: Button
var btn_open_market: Button
var btn_view_deck: Button
var btn_view_draw: Button
var btn_view_discard: Button
var btn_toggle_audio: Button
var btn_options: Button
var sound_manager: SoundManager

# Fenêtre modale des Options Audio (Volume Général, Musique, Effets)
var options_overlay: ColorRect
var slider_master: HSlider
var slider_music: HSlider
var slider_sfx: HSlider
var lbl_val_master: Label
var lbl_val_music: Label
var lbl_val_sfx: Label
var chk_mute_audio: CheckButton

# Fenêtre modale du Marché (3 emplacements + retrait de carte)
var market_overlay: ColorRect
var market_cards_box: HBoxContainer
var market_title_lbl: Label
var market_status_lbl: Label
var btn_market_remove_card: Button

# Fenêtre modale de consultation de cartes (Deck / Pioche / Défausse / Retrait de carte)
var card_viewer_overlay: ColorRect
var card_viewer_title_lbl: Label
var card_viewer_grid: GridContainer
var card_viewer_close_btn: Button
var is_removing_card_mode: bool = false

# Fenêtre Fin de partie
var game_over_overlay: ColorRect
var game_over_lbl: Label

# État de la partie
var rng := RandomNumberGenerator.new()
var next_card_uid: int = 1
var next_monster_id: int = 1

var wave_number: int = 1
var turn_in_wave: int = 1
var spawns_remaining_in_wave: int = 0
var spawned_in_current_wave: int = 0
var total_monsters_spawned: int = 0
var tower_hp: int = 50
var tower_max_hp: int = 50

# Économie d'Or & Marché (3 emplacements)
var gold: int = 0
var market_buys_available: int = 0 # Perdu à la fin du tour !
var market_slots: Array = [null, null, null] # 3 emplacements de SpellData.CardItem (ou null si acheté/supprimé ce tour)
var remove_card_cost: int = 2 # 2 Or la 1re fois, puis double à chaque achat (2, 4, 8, 16...)

# Deck & Cartes
var full_deck: Array[SpellData.CardItem] = []
var draw_pile: Array[SpellData.CardItem] = []
var discard_pile: Array[SpellData.CardItem] = []
var hand: Array[SpellData.CardItem] = []
var current_spell_cards: Array[SpellData.CardItem] = [] # Max 3 cartes : [0]=Element, [1]=Shape, [2]=Bonus

const HAND_SIZE: int = 6

# État de visée du sort et offset aléatoire pré-calculé pour le bonus "+1 Hexa"
var current_rotation: int = 0
var has_weak_extra_offset: bool = false
var current_weak_extra_offset: Vector2i = Vector2i.ZERO

func _ready() -> void:
	rng.randomize()
	sound_manager = SoundManager.new()
	add_child(sound_manager)
	_build_ui()
	_start_new_run()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if options_overlay.visible and event.keycode == KEY_ESCAPE:
			options_overlay.visible = false
			return
		if card_viewer_overlay.visible and event.keycode == KEY_ESCAPE:
			card_viewer_overlay.visible = false
			is_removing_card_mode = false
			return
		if market_overlay.visible and event.keycode == KEY_ESCAPE:
			market_overlay.visible = false
			return
		if current_spell_cards.size() >= 2 and not market_overlay.visible and not card_viewer_overlay.visible and not options_overlay.visible:
			if event.keycode == KEY_R or event.keycode == KEY_E:
				_rotate_spell(1)
			elif event.keycode == KEY_Q:
				_rotate_spell(-1)
			elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
				if current_spell_cards.size() == 3:
					_cast_ready_spell()

func _build_ui() -> void:
	# Fond général sombre arcanique
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)

	# --- BARRE SUPÉRIEURE ---
	var top_bar := PanelContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 48)
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.11, 0.13, 0.20)
	top_style.border_width_bottom = 2
	top_style.border_color = Color(0.32, 0.38, 0.54)
	top_style.content_margin_left = 16
	top_style.content_margin_right = 16
	top_bar.add_theme_stylebox_override("panel", top_style)
	main_vbox.add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_Bar_setup(top_bar, top_hbox)

	# --- ZONE CENTRALE (Plateau Hexagonal à gauche + Forge de Sort à droite) ---
	var middle_hbox := HBoxContainer.new()
	middle_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(middle_hbox)

	# Plateau Hexagonal (Côté 7 tuiles)
	board_view = HexBoardView.new()
	board_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_view.rotation_changed.connect(_on_board_rotation_changed)
	board_view.cast_confirmed.connect(_cast_ready_spell)
	middle_hbox.add_child(board_view)

	# Panneau Droit : Création du Sort (Éventail des 3 cartes)
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(360, 0)
	var right_style := StyleBoxFlat.new()
	right_style.bg_color = Color(0.10, 0.12, 0.18)
	right_style.border_width_left = 2
	right_style.border_color = Color(0.30, 0.35, 0.48)
	right_style.content_margin_left = 14
	right_style.content_margin_right = 14
	right_style.content_margin_top = 10
	right_style.content_margin_bottom = 10
	right_panel.add_theme_stylebox_override("panel", right_style)
	middle_hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(right_vbox)

	var forge_title := Label.new()
	forge_title.text = "GRIMOIRE D'INCANTATION (3 CARTES)"
	forge_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forge_title.add_theme_font_size_override("font_size", 15)
	forge_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.48))
	right_vbox.add_child(forge_title)

	lbl_step_prompt = Label.new()
	lbl_step_prompt.text = "Étape 1 : Choisissez une carte ÉLÉMENT"
	lbl_step_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_step_prompt.add_theme_font_size_override("font_size", 13)
	lbl_step_prompt.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	right_vbox.add_child(lbl_step_prompt)

	spell_stack_view = SpellStackView.new()
	spell_stack_view.undo_top_card.connect(_undo_last_spell_card)
	right_vbox.add_child(spell_stack_view)

	lbl_spell_summary = Label.new()
	lbl_spell_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_spell_summary.custom_minimum_size = Vector2(320, 62)
	lbl_spell_summary.add_theme_font_size_override("font_size", 12)
	lbl_spell_summary.add_theme_color_override("font_color", Color(0.88, 0.88, 0.94))
	right_vbox.add_child(lbl_spell_summary)

	# Boutons de contrôle de rotation et lancement du sort
	var rot_hbox := HBoxContainer.new()
	rot_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	rot_hbox.add_theme_constant_override("separation", 8)
	right_vbox.add_child(rot_hbox)

	btn_rotate_left = Button.new()
	btn_rotate_left.text = "↺ Pivoter -60° (Q)"
	btn_rotate_left.pressed.connect(func(): _rotate_spell(-1))
	rot_hbox.add_child(btn_rotate_left)

	btn_rotate_right = Button.new()
	btn_rotate_right.text = "↻ Pivoter +60° (R)"
	btn_rotate_right.pressed.connect(func(): _rotate_spell(1))
	rot_hbox.add_child(btn_rotate_right)

	var action_hbox := HBoxContainer.new()
	action_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	action_hbox.add_theme_constant_override("separation", 10)
	right_vbox.add_child(action_hbox)

	btn_undo_card = Button.new()
	btn_undo_card.text = "↩ Retirer carte"
	btn_undo_card.pressed.connect(_undo_last_spell_card)
	action_hbox.add_child(btn_undo_card)

	btn_cast_spell = Button.new()
	btn_cast_spell.text = "⚡ LANCER LE SORT !"
	btn_cast_spell.custom_minimum_size = Vector2(175, 38)
	btn_cast_spell.pressed.connect(_cast_ready_spell)
	action_hbox.add_child(btn_cast_spell)

	# --- BARRE INFÉRIEURE : Consultation Deck/Pioche/Défausse + Main + Marché/Fin de tour ---
	var bottom_panel := PanelContainer.new()
	bottom_panel.custom_minimum_size = Vector2(0, 226)
	var bot_style := StyleBoxFlat.new()
	bot_style.bg_color = Color(0.10, 0.11, 0.16)
	bot_style.border_width_top = 2
	bot_style.border_color = Color(0.32, 0.38, 0.54)
	bot_style.content_margin_left = 14
	bot_style.content_margin_right = 14
	bot_style.content_margin_top = 8
	bot_style.content_margin_bottom = 8
	bottom_panel.add_theme_stylebox_override("panel", bot_style)
	main_vbox.add_child(bottom_panel)

	var bot_hbox := HBoxContainer.new()
	bot_hbox.add_theme_constant_override("separation", 14)
	bottom_panel.add_child(bot_hbox)

	# Boutons de consultation (Deck complet, Pioche mélangée, Défausse) + Journal à gauche
	var deck_vbox := VBoxContainer.new()
	deck_vbox.custom_minimum_size = Vector2(185, 0)
	deck_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	deck_vbox.add_theme_constant_override("separation", 5)
	bot_hbox.add_child(deck_vbox)

	btn_view_deck = Button.new()
	btn_view_deck.text = "🃏 Voir Deck (9)"
	btn_view_deck.custom_minimum_size = Vector2(180, 28)
	btn_view_deck.pressed.connect(func(): _open_card_viewer("DECK"))
	deck_vbox.add_child(btn_view_deck)

	var piles_hbox := HBoxContainer.new()
	piles_hbox.add_theme_constant_override("separation", 6)
	deck_vbox.add_child(piles_hbox)

	btn_view_draw = Button.new()
	btn_view_draw.text = "📚 Pioche (0)"
	btn_view_draw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_view_draw.custom_minimum_size = Vector2(86, 28)
	btn_view_draw.pressed.connect(func(): _open_card_viewer("DRAW"))
	piles_hbox.add_child(btn_view_draw)

	btn_view_discard = Button.new()
	btn_view_discard.text = "♻️ Défausse (0)"
	btn_view_discard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_view_discard.custom_minimum_size = Vector2(86, 28)
	btn_view_discard.pressed.connect(func(): _open_card_viewer("DISCARD"))
	piles_hbox.add_child(btn_view_discard)

	lbl_combat_log = Label.new()
	lbl_combat_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_combat_log.custom_minimum_size = Vector2(180, 118)
	lbl_combat_log.add_theme_font_size_override("font_size", 11)
	lbl_combat_log.add_theme_color_override("font_color", Color(0.78, 0.84, 0.95))
	deck_vbox.add_child(lbl_combat_log)

	# Conteneur de la Main au centre
	var hand_scroll := ScrollContainer.new()
	hand_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bot_hbox.add_child(hand_scroll)

	hand_container = HBoxContainer.new()
	hand_container.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hand_container.add_theme_constant_override("separation", 12)
	hand_scroll.add_child(hand_container)

	# Boutons Marché + Fin du Tour à droite
	var end_vbox := VBoxContainer.new()
	end_vbox.custom_minimum_size = Vector2(175, 0)
	end_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	end_vbox.add_theme_constant_override("separation", 8)
	bot_hbox.add_child(end_vbox)

	btn_open_market = Button.new()
	btn_open_market.text = "🛒 MARCHÉ (3 cartes)"
	btn_open_market.custom_minimum_size = Vector2(165, 42)
	btn_open_market.pressed.connect(_open_market_modal)
	end_vbox.add_child(btn_open_market)

	btn_end_turn = Button.new()
	btn_end_turn.text = "FIN DU TOUR ⏭\n(Phase Monstres)"
	btn_end_turn.custom_minimum_size = Vector2(165, 58)
	btn_end_turn.pressed.connect(_on_end_turn_pressed)
	end_vbox.add_child(btn_end_turn)

	var help_lbl := Label.new()
	help_lbl.text = "Les actions d'achat non utilisées sont perdues en fin de tour !"
	help_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_lbl.add_theme_font_size_override("font_size", 10)
	help_lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 0.65))
	end_vbox.add_child(help_lbl)

	_build_overlays()

func top_Bar_setup(top_bar: PanelContainer, top_hbox: HBoxContainer) -> void:
	top_bar.add_child(top_hbox)
	var title := Label.new()
	title.text = "🧙 HEX WIZARD TD — Deckbuilding & Marché"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.50))
	top_hbox.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)

	lbl_top_status = Label.new()
	lbl_top_status.add_theme_font_size_override("font_size", 15)
	top_hbox.add_child(lbl_top_status)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(16, 0)
	top_hbox.add_child(spacer2)

	btn_toggle_audio = Button.new()
	btn_toggle_audio.text = "🔇 Muet" if sound_manager.is_muted else "🔊 Son"
	btn_toggle_audio.pressed.connect(func():
		sound_manager.toggle_audio()
		_sync_audio_ui()
	)
	top_hbox.add_child(btn_toggle_audio)

	btn_options = Button.new()
	btn_options.text = "⚙️ Options"
	btn_options.pressed.connect(_open_options_modal)
	top_hbox.add_child(btn_options)

	var btn_restart := Button.new()
	btn_restart.text = "Nouvelle Partie"
	btn_restart.pressed.connect(_start_new_run)
	top_hbox.add_child(btn_restart)

func _build_overlays() -> void:
	# 1. Overlay du Marché de 3 cartes + Retrait de carte + Suppression du marché
	market_overlay = ColorRect.new()
	market_overlay.color = Color(0.03, 0.04, 0.08, 0.92)
	market_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	market_overlay.visible = false
	add_child(market_overlay)

	var market_vbox := VBoxContainer.new()
	market_vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	market_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	market_vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	market_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	market_vbox.add_theme_constant_override("separation", 14)
	market_overlay.add_child(market_vbox)

	market_title_lbl = Label.new()
	market_title_lbl.text = "🛒 MARCHÉ ARCANIQUE (1 comp. puissant ★ = 3 Or  |  2 comp. puissants ★★ = 8 Or)"
	market_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	market_title_lbl.add_theme_font_size_override("font_size", 20)
	market_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
	market_vbox.add_child(market_title_lbl)

	market_status_lbl = Label.new()
	market_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	market_status_lbl.add_theme_font_size_override("font_size", 15)
	market_status_lbl.add_theme_color_override("font_color", Color(0.82, 0.94, 1.0))
	market_vbox.add_child(market_status_lbl)

	market_cards_box = HBoxContainer.new()
	market_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	market_cards_box.add_theme_constant_override("separation", 30)
	market_vbox.add_child(market_cards_box)

	var bottom_market_hbox := HBoxContainer.new()
	bottom_market_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_market_hbox.add_theme_constant_override("separation", 24)
	market_vbox.add_child(bottom_market_hbox)

	btn_market_remove_card = Button.new()
	btn_market_remove_card.custom_minimum_size = Vector2(340, 42)
	btn_market_remove_card.pressed.connect(_on_market_remove_deck_card_pressed)
	bottom_market_hbox.add_child(btn_market_remove_card)

	var btn_close_market := Button.new()
	btn_close_market.text = "Fermer le Marché (Retour au combat)"
	btn_close_market.custom_minimum_size = Vector2(260, 42)
	btn_close_market.pressed.connect(func():
		market_overlay.visible = false
		_refresh_all_ui()
	)
	bottom_market_hbox.add_child(btn_close_market)

	# 2. Overlay de consultation de cartes (Deck complet / Pioche mélangée / Défausse / Suppression)
	card_viewer_overlay = ColorRect.new()
	card_viewer_overlay.color = Color(0.02, 0.03, 0.06, 0.94)
	card_viewer_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_viewer_overlay.visible = false
	add_child(card_viewer_overlay)

	var viewer_vbox := VBoxContainer.new()
	viewer_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewer_vbox.offset_left = 40
	viewer_vbox.offset_right = -40
	viewer_vbox.offset_top = 30
	viewer_vbox.offset_bottom = -30
	viewer_vbox.add_theme_constant_override("separation", 14)
	card_viewer_overlay.add_child(viewer_vbox)

	card_viewer_title_lbl = Label.new()
	card_viewer_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_viewer_title_lbl.add_theme_font_size_override("font_size", 22)
	card_viewer_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
	viewer_vbox.add_child(card_viewer_title_lbl)

	var viewer_scroll := ScrollContainer.new()
	viewer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewer_vbox.add_child(viewer_scroll)

	var center_box := CenterContainer.new()
	center_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewer_scroll.add_child(center_box)

	card_viewer_grid = GridContainer.new()
	card_viewer_grid.columns = 6
	card_viewer_grid.add_theme_constant_override("h_separation", 18)
	card_viewer_grid.add_theme_constant_override("v_separation", 18)
	center_box.add_child(card_viewer_grid)

	card_viewer_close_btn = Button.new()
	card_viewer_close_btn.text = "Fermer"
	card_viewer_close_btn.custom_minimum_size = Vector2(220, 42)
	card_viewer_close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card_viewer_close_btn.pressed.connect(func():
		card_viewer_overlay.visible = false
		is_removing_card_mode = false
		_refresh_all_ui()
	)
	viewer_vbox.add_child(card_viewer_close_btn)

	# 3. Overlay Game Over / Victoire
	game_over_overlay = ColorRect.new()
	game_over_overlay.color = Color(0.04, 0.02, 0.05, 0.90)
	game_over_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_overlay.visible = false
	add_child(game_over_overlay)

	var go_vbox := VBoxContainer.new()
	go_vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	go_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	go_vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	go_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	go_vbox.add_theme_constant_override("separation", 18)
	game_over_overlay.add_child(go_vbox)

	game_over_lbl = Label.new()
	game_over_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_lbl.add_theme_font_size_override("font_size", 26)
	go_vbox.add_child(game_over_lbl)

	var btn_retry := Button.new()
	btn_retry.text = "Rejouer une Partie"
	btn_retry.custom_minimum_size = Vector2(220, 46)
	btn_retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_retry.pressed.connect(_start_new_run)
	go_vbox.add_child(btn_retry)

	# 4. Overlay du Menu Options (Volume Général, Volume Musique, Volume Effets)
	options_overlay = ColorRect.new()
	options_overlay.color = Color(0.02, 0.03, 0.07, 0.92)
	options_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	options_overlay.visible = false
	add_child(options_overlay)

	var opt_panel := PanelContainer.new()
	opt_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	opt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	opt_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	opt_panel.custom_minimum_size = Vector2(520, 360)
	var opt_style := StyleBoxFlat.new()
	opt_style.bg_color = Color(0.10, 0.13, 0.21)
	opt_style.border_width_left = 2
	opt_style.border_width_right = 2
	opt_style.border_width_top = 2
	opt_style.border_width_bottom = 2
	opt_style.border_color = Color(0.45, 0.56, 0.78)
	opt_style.corner_radius_top_left = 10
	opt_style.corner_radius_top_right = 10
	opt_style.corner_radius_bottom_left = 10
	opt_style.corner_radius_bottom_right = 10
	opt_style.content_margin_left = 28
	opt_style.content_margin_right = 28
	opt_style.content_margin_top = 24
	opt_style.content_margin_bottom = 24
	opt_panel.add_theme_stylebox_override("panel", opt_style)
	options_overlay.add_child(opt_panel)

	var opt_vbox := VBoxContainer.new()
	opt_vbox.add_theme_constant_override("separation", 18)
	opt_panel.add_child(opt_vbox)

	var opt_title := Label.new()
	opt_title.text = "⚙️ OPTIONS AUDIO"
	opt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opt_title.add_theme_font_size_override("font_size", 22)
	opt_title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.45))
	opt_vbox.add_child(opt_title)

	# Ligne 1 : Volume Général
	var row_master := HBoxContainer.new()
	row_master.add_theme_constant_override("separation", 12)
	opt_vbox.add_child(row_master)

	var lbl_m := Label.new()
	lbl_m.text = "🔊 Volume Général :"
	lbl_m.custom_minimum_size = Vector2(185, 0)
	lbl_m.add_theme_font_size_override("font_size", 15)
	row_master.add_child(lbl_m)

	slider_master = HSlider.new()
	slider_master.min_value = 0.0
	slider_master.max_value = 100.0
	slider_master.step = 1.0
	slider_master.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_master.custom_minimum_size = Vector2(180, 26)
	slider_master.value_changed.connect(func(v: float):
		sound_manager.set_master_volume(v / 100.0)
		lbl_val_master.text = "%d %%" % roundi(v)
	)
	row_master.add_child(slider_master)

	lbl_val_master = Label.new()
	lbl_val_master.custom_minimum_size = Vector2(56, 0)
	lbl_val_master.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_val_master.add_theme_font_size_override("font_size", 15)
	row_master.add_child(lbl_val_master)

	# Ligne 2 : Volume de la Musique
	var row_music := HBoxContainer.new()
	row_music.add_theme_constant_override("separation", 12)
	opt_vbox.add_child(row_music)

	var lbl_mu := Label.new()
	lbl_mu.text = "🎵 Volume Musique :"
	lbl_mu.custom_minimum_size = Vector2(185, 0)
	lbl_mu.add_theme_font_size_override("font_size", 15)
	row_music.add_child(lbl_mu)

	slider_music = HSlider.new()
	slider_music.min_value = 0.0
	slider_music.max_value = 100.0
	slider_music.step = 1.0
	slider_music.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_music.custom_minimum_size = Vector2(180, 26)
	slider_music.value_changed.connect(func(v: float):
		sound_manager.set_music_volume(v / 100.0)
		lbl_val_music.text = "%d %%" % roundi(v)
	)
	row_music.add_child(slider_music)

	lbl_val_music = Label.new()
	lbl_val_music.custom_minimum_size = Vector2(56, 0)
	lbl_val_music.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_val_music.add_theme_font_size_override("font_size", 15)
	row_music.add_child(lbl_val_music)

	# Ligne 3 : Volume des Effets Sonores (SFX)
	var row_sfx := HBoxContainer.new()
	row_sfx.add_theme_constant_override("separation", 12)
	opt_vbox.add_child(row_sfx)

	var lbl_sf := Label.new()
	lbl_sf.text = "✨ Volume Effets :"
	lbl_sf.custom_minimum_size = Vector2(185, 0)
	lbl_sf.add_theme_font_size_override("font_size", 15)
	row_sfx.add_child(lbl_sf)

	slider_sfx = HSlider.new()
	slider_sfx.min_value = 0.0
	slider_sfx.max_value = 100.0
	slider_sfx.step = 1.0
	slider_sfx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_sfx.custom_minimum_size = Vector2(180, 26)
	slider_sfx.value_changed.connect(func(v: float):
		sound_manager.set_sfx_volume(v / 100.0)
		lbl_val_sfx.text = "%d %%" % roundi(v)
	)
	row_sfx.add_child(slider_sfx)

	lbl_val_sfx = Label.new()
	lbl_val_sfx.custom_minimum_size = Vector2(56, 0)
	lbl_val_sfx.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_val_sfx.add_theme_font_size_override("font_size", 15)
	row_sfx.add_child(lbl_val_sfx)

	# Ligne 4 : Bouton Tester Effet + Case Couper le son
	var row_extra := HBoxContainer.new()
	row_extra.alignment = BoxContainer.ALIGNMENT_CENTER
	row_extra.add_theme_constant_override("separation", 24)
	opt_vbox.add_child(row_extra)

	chk_mute_audio = CheckButton.new()
	chk_mute_audio.text = "🔇 Couper tout le son"
	chk_mute_audio.toggled.connect(func(pressed: bool):
		sound_manager.set_muted(pressed)
		_sync_audio_ui()
	)
	row_extra.add_child(chk_mute_audio)

	var btn_test_sfx := Button.new()
	btn_test_sfx.text = "🔔 Tester un effet sonore"
	btn_test_sfx.custom_minimum_size = Vector2(190, 34)
	btn_test_sfx.pressed.connect(func():
		sound_manager.play_sfx("market_buy")
	)
	row_extra.add_child(btn_test_sfx)

	# Bouton Fermer
	var btn_close_opt := Button.new()
	btn_close_opt.text = "Fermer (Échap)"
	btn_close_opt.custom_minimum_size = Vector2(200, 42)
	btn_close_opt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_close_opt.pressed.connect(func():
		options_overlay.visible = false
	)
	opt_vbox.add_child(btn_close_opt)

	_sync_audio_ui()

func _open_options_modal() -> void:
	_sync_audio_ui()
	options_overlay.visible = true

func _sync_audio_ui() -> void:
	if sound_manager == null:
		return
	var m_pct: float = roundf(sound_manager.master_volume * 100.0)
	var mu_pct: float = roundf(sound_manager.music_volume * 100.0)
	var sf_pct: float = roundf(sound_manager.sfx_volume * 100.0)

	if slider_master != null:
		slider_master.set_value_no_signal(m_pct)
		lbl_val_master.text = "%d %%" % roundi(m_pct)
	if slider_music != null:
		slider_music.set_value_no_signal(mu_pct)
		lbl_val_music.text = "%d %%" % roundi(mu_pct)
	if slider_sfx != null:
		slider_sfx.set_value_no_signal(sf_pct)
		lbl_val_sfx.text = "%d %%" % roundi(sf_pct)
	if chk_mute_audio != null:
		chk_mute_audio.set_pressed_no_signal(sound_manager.is_muted)
	if btn_toggle_audio != null:
		btn_toggle_audio.text = "🔇 Muet" if sound_manager.is_muted else "🔊 Son"

# ============================================================================
# INITIALISATION D'UNE PARTIE & DECK DE DÉPART (9 CARTES FAIBLES)
# ============================================================================

func _start_new_run() -> void:
	game_over_overlay.visible = false
	market_overlay.visible = false
	card_viewer_overlay.visible = false
	options_overlay.visible = false
	is_removing_card_mode = false
	tower_max_hp = 50
	tower_hp = 50
	wave_number = 1
	total_monsters_spawned = 0
	spawned_in_current_wave = 0
	gold = 0
	market_buys_available = 0
	remove_card_cost = 2
	board_view.monsters.clear()
	board_view.lingering_zones.clear()
	board_view.active_projectiles.clear()
	board_view.projectile_particles.clear()
	board_view.dying_monsters.clear()
	current_spell_cards.clear()

	_build_starter_deck()
	market_slots = [null, null, null]
	_refill_empty_market_slots()
	_start_wave(1)

func _create_card(c1_cat: int, c1_val: int, c2_cat: int, c2_val: int) -> SpellData.CardItem:
	var card := SpellData.CardItem.new(next_card_uid, c1_cat, c1_val, c2_cat, c2_val)
	next_card_uid += 1
	return card

func _build_starter_deck() -> void:
	full_deck.clear()
	# Deck de départ de 9 cartes faibles :
	# - Élément : Neutre (pas de bonus/malus aux dégâts, pas d'effet)
	# - Gabarits de 3 hexa : Ligne (3), Forme V (3), Triangle (3)
	# - Bonus faibles : +1 Hexa aléatoire en contact, +10% Dégâts, Acheter 1 carte

	# 3 cartes (Élément Neutre / Gabarit 3 hexa)
	full_deck.append(_create_card(SpellData.CompCategory.ELEMENT, SpellData.Element.NEUTRAL, SpellData.CompCategory.SHAPE, SpellData.Shape.SMALL_LINE))
	full_deck.append(_create_card(SpellData.CompCategory.ELEMENT, SpellData.Element.NEUTRAL, SpellData.CompCategory.SHAPE, SpellData.Shape.SMALL_V))
	full_deck.append(_create_card(SpellData.CompCategory.ELEMENT, SpellData.Element.NEUTRAL, SpellData.Shape.SMALL_TRIANGLE if false else SpellData.CompCategory.SHAPE, SpellData.Shape.SMALL_TRIANGLE))

	# 3 cartes (Élément Neutre / Bonus faible)
	full_deck.append(_create_card(SpellData.CompCategory.ELEMENT, SpellData.Element.NEUTRAL, SpellData.CompCategory.BONUS, SpellData.BonusType.WEAK_EXPAND_1))
	full_deck.append(_create_card(SpellData.CompCategory.ELEMENT, SpellData.Element.NEUTRAL, SpellData.CompCategory.BONUS, SpellData.BonusType.WEAK_DAMAGE_10))
	full_deck.append(_create_card(SpellData.CompCategory.ELEMENT, SpellData.Element.NEUTRAL, SpellData.CompCategory.BONUS, SpellData.BonusType.BUY_MARKET_CARD))

	# 3 cartes (Gabarit 3 hexa / Bonus faible)
	full_deck.append(_create_card(SpellData.CompCategory.SHAPE, SpellData.Shape.SMALL_LINE, SpellData.CompCategory.BONUS, SpellData.BonusType.GAIN_1_GOLD))
	full_deck.append(_create_card(SpellData.CompCategory.SHAPE, SpellData.Shape.SMALL_V, SpellData.CompCategory.BONUS, SpellData.BonusType.WEAK_DAMAGE_10))
	full_deck.append(_create_card(SpellData.CompCategory.SHAPE, SpellData.Shape.SMALL_TRIANGLE, SpellData.CompCategory.BONUS, SpellData.BonusType.WEAK_EXPAND_1))

func _start_wave(p_wave: int) -> void:
	wave_number = p_wave
	turn_in_wave = 1
	spawned_in_current_wave = 0
	# Plus de monstres par vague (13 en vague 1, 17 en vague 2, 21 en vague 3...)
	spawns_remaining_in_wave = 9 + wave_number * 4

	# Réinitialise et mélange la pioche à chaque début de vague
	draw_pile.clear()
	discard_pile.clear()
	hand.clear()
	current_spell_cards.clear()
	board_view.lingering_zones.clear()

	for c in full_deck:
		draw_pile.append(c)
	_shuffle_cards(draw_pile)

	# Fait apparaître un groupe plus nombreux de monstres en bordure dès le début de la vague
	_spawn_wave_monsters(4 + mini(3, wave_number))
	_start_player_turn()

func _shuffle_cards(arr: Array[SpellData.CardItem]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: SpellData.CardItem = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# ============================================================================
# GESTION DU MARCHÉ (ACHAT, SUPPRESSION D'OFFRE 1 OR, RETRAIT DU DECK 2/4/8 OR)
# ============================================================================

func _refill_empty_market_slots() -> void:
	for i in range(3):
		if market_slots[i] == null:
			# 80% de chance d'avoir 1 composant puissant (3 Or), 20% de chance d'en avoir 2 (8 Or)
			var is_two_strong: bool = (rng.randf() < 0.20)
			market_slots[i] = _generate_market_card(2 if is_two_strong else 1)

func _generate_market_card(strong_count: int) -> SpellData.CardItem:
	var pairs: Array[Vector2i] = [
		Vector2i(SpellData.CompCategory.ELEMENT, SpellData.CompCategory.SHAPE),
		Vector2i(SpellData.CompCategory.ELEMENT, SpellData.CompCategory.BONUS),
		Vector2i(SpellData.CompCategory.SHAPE, SpellData.CompCategory.BONUS)
	]
	var pair: Vector2i = pairs[rng.randi_range(0, pairs.size() - 1)]
	var c1_strong: bool = true
	var c2_strong: bool = true
	if strong_count == 1:
		if rng.randf() < 0.5:
			c2_strong = false
		else:
			c1_strong = false

	var val1: int = _get_random_component_value(pair.x, c1_strong)
	var val2: int = _get_random_component_value(pair.y, c2_strong)
	return _create_card(pair.x, val1, pair.y, val2)

func _get_random_component_value(cat: int, is_strong: bool) -> int:
	match cat:
		SpellData.CompCategory.ELEMENT:
			if is_strong:
				return rng.randi_range(0, 3) # FIRE, ICE, POISON, EARTH
			return SpellData.Element.NEUTRAL
		SpellData.CompCategory.SHAPE:
			if is_strong:
				return rng.randi_range(0, 3) # LINE(7), HEX(7), TRIANGLE(7), ZIGZAG(7)
			return rng.randi_range(4, 6) # SMALL_LINE(3), SMALL_V(3), SMALL_TRIANGLE(3)
		SpellData.CompCategory.BONUS:
			if is_strong:
				return rng.randi_range(0, 6) # Bonus puissants (0..6)
			return rng.randi_range(7, 10) # Bonus faibles (7..10)
	return 0

func _open_market_modal() -> void:
	market_overlay.visible = true
	_rebuild_market_ui()

func _rebuild_market_ui() -> void:
	market_status_lbl.text = "💰 Votre Or : %d   |   🛒 Actions d'achat ce tour : %d (perdues en fin de tour)" % [
		gold, market_buys_available
	]

	for child in market_cards_box.get_children():
		child.queue_free()

	for i in range(3):
		var slot_vbox := VBoxContainer.new()
		slot_vbox.custom_minimum_size = Vector2(190, 320)
		slot_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		slot_vbox.add_theme_constant_override("separation", 8)
		market_cards_box.add_child(slot_vbox)

		var card: SpellData.CardItem = market_slots[i]
		if card == null:
			var sold_lbl := Label.new()
			sold_lbl.text = "📦 EMPLACEMENT VIDE\n\nNouvel arrivage\nau prochain tour"
			sold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sold_lbl.add_theme_font_size_override("font_size", 14)
			sold_lbl.add_theme_color_override("font_color", Color(0.65, 0.70, 0.80))
			slot_vbox.add_child(sold_lbl)
			continue

		var cost: int = SpellData.get_card_market_cost(card)
		var strong_cnt: int = SpellData.get_card_strong_count(card)
		var can_buy: bool = (market_buys_available > 0) and (gold >= cost)
		var can_trash: bool = (market_buys_available > 0) and (gold >= 1)

		var tier_lbl := Label.new()
		if strong_cnt >= 2:
			tier_lbl.text = "★★ 2 Comp. Puissants — 8 Or"
			tier_lbl.add_theme_color_override("font_color", Color(1.0, 0.78, 0.25))
		else:
			tier_lbl.text = "★ 1 Comp. Puissant — 3 Or"
			tier_lbl.add_theme_color_override("font_color", Color(0.65, 0.90, 1.0))
		tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tier_lbl.add_theme_font_size_override("font_size", 13)
		slot_vbox.add_child(tier_lbl)

		var cv := CardView.new()
		cv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.setup(card, can_buy, -1, false)
		var slot_index: int = i
		cv.card_clicked.connect(func(_c): _try_buy_market_slot(slot_index))
		slot_vbox.add_child(cv)

		var desc_lbl := Label.new()
		desc_lbl.text = "%s + %s" % [
			SpellData.get_component_title(card.comp1_cat, card.comp1_val),
			SpellData.get_component_title(card.comp2_cat, card.comp2_val)
		]
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.add_theme_font_size_override("font_size", 12)
		slot_vbox.add_child(desc_lbl)

		var btn_buy := Button.new()
		if market_buys_available <= 0:
			btn_buy.text = "Acheter (%d Or) [0 Achat]" % cost
			btn_buy.disabled = true
		elif gold < cost:
			btn_buy.text = "Or insuffisant (%d/%d Or)" % [gold, cost]
			btn_buy.disabled = true
		else:
			btn_buy.text = "💰 Acheter (%d Or + 1 Achat)" % cost
			btn_buy.disabled = false
		btn_buy.pressed.connect(func(): _try_buy_market_slot(slot_index))
		slot_vbox.add_child(btn_buy)

		var btn_trash := Button.new()
		btn_trash.text = "🗑️ Supprimer offre (1 Or + 1 Achat)"
		btn_trash.disabled = not can_trash
		btn_trash.pressed.connect(func(): _try_trash_market_slot(slot_index))
		slot_vbox.add_child(btn_trash)

	# Bouton pour retirer une carte de son Deck (2 Or, puis double à chaque fois)
	var can_remove_deck_card: bool = (market_buys_available > 0) and (gold >= remove_card_cost) and (full_deck.size() > 3)
	btn_market_remove_card.text = "🔥 Retirer 1 carte de mon Deck (%d Or + 1 Achat)" % remove_card_cost
	btn_market_remove_card.disabled = not can_remove_deck_card

func _try_buy_market_slot(slot_idx: int) -> void:
	var card: SpellData.CardItem = market_slots[slot_idx]
	if card == null:
		return
	var cost: int = SpellData.get_card_market_cost(card)
	if market_buys_available <= 0 or gold < cost:
		return

	gold -= cost
	market_buys_available -= 1
	full_deck.append(card)
	discard_pile.append(card) # Mise dans la défausse
	market_slots[slot_idx] = null # Sera rempli au prochain tour
	sound_manager.play_sfx("market_buy")

	lbl_combat_log.text = "Carte achetée pour %d Or et placée dans votre Défausse !" % cost
	_rebuild_market_ui()
	_refresh_all_ui()

func _try_trash_market_slot(slot_idx: int) -> void:
	var card: SpellData.CardItem = market_slots[slot_idx]
	if card == null:
		return
	if market_buys_available <= 0 or gold < 1:
		return

	gold -= 1
	market_buys_available -= 1
	market_slots[slot_idx] = null # Sera remplacé au prochain tour
	sound_manager.play_sfx("market_trash")

	lbl_combat_log.text = "Offre du marché supprimée pour 1 Or (remplacée au prochain tour)."
	_rebuild_market_ui()
	_refresh_all_ui()

func _on_market_remove_deck_card_pressed() -> void:
	if market_buys_available <= 0 or gold < remove_card_cost or full_deck.size() <= 3:
		return
	market_overlay.visible = false
	_open_card_viewer("REMOVE_FROM_DECK")

# ============================================================================
# CONSULTATION DU DECK, DE LA PIOCHE (SANS ORDRE) ET DE LA DÉFAUSSE
# ============================================================================

func _open_card_viewer(mode: String) -> void:
	card_viewer_overlay.visible = true
	is_removing_card_mode = (mode == "REMOVE_FROM_DECK")

	for child in card_viewer_grid.get_children():
		child.queue_free()

	var cards_to_show: Array[SpellData.CardItem] = []
	match mode:
		"DECK":
			card_viewer_title_lbl.text = "🃏 ENSEMBLE DE VOTRE DECK (%d cartes)" % full_deck.size()
			cards_to_show = full_deck.duplicate()
		"DRAW":
			card_viewer_title_lbl.text = "📚 VOTRE PIOCHE (%d cartes — ordre mélangé)" % draw_pile.size()
			cards_to_show = draw_pile.duplicate()
			# Mélange l'affichage pour ne pas révéler l'ordre exact de tirage
			_shuffle_cards(cards_to_show)
		"DISCARD":
			card_viewer_title_lbl.text = "♻️ VOTRE DÉFAUSSE (%d cartes)" % discard_pile.size()
			cards_to_show = discard_pile.duplicate()
		"REMOVE_FROM_DECK":
			card_viewer_title_lbl.text = "🔥 CHOISISSEZ 1 CARTE À RETIRER DÉFINITIVEMENT DU DECK (Coût : %d Or)" % remove_card_cost
			cards_to_show = full_deck.duplicate()

	if cards_to_show.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Aucune carte dans cette pile."
		empty_lbl.add_theme_font_size_override("font_size", 16)
		card_viewer_grid.add_child(empty_lbl)
		return

	for c in cards_to_show:
		var item_vbox := VBoxContainer.new()
		item_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		item_vbox.add_theme_constant_override("separation", 6)
		card_viewer_grid.add_child(item_vbox)

		var cv := CardView.new()
		cv.setup(c, true, -1, false)
		var target_card: SpellData.CardItem = c
		if is_removing_card_mode:
			cv.card_clicked.connect(func(_v): _confirm_remove_card_from_deck(target_card))
		item_vbox.add_child(cv)

		if is_removing_card_mode:
			var btn_del := Button.new()
			btn_del.text = "🔥 Retirer (%d Or)" % remove_card_cost
			btn_del.pressed.connect(func(): _confirm_remove_card_from_deck(target_card))
			item_vbox.add_child(btn_del)

func _confirm_remove_card_from_deck(card: SpellData.CardItem) -> void:
	if not is_removing_card_mode:
		return
	if market_buys_available <= 0 or gold < remove_card_cost or full_deck.size() <= 3:
		return

	gold -= remove_card_cost
	market_buys_available -= 1
	var paid_cost: int = remove_card_cost
	remove_card_cost *= 2 # Double le prix à chaque nouvelle sélection de cet achat

	full_deck.erase(card)
	draw_pile.erase(card)
	discard_pile.erase(card)
	if hand.has(card):
		hand.erase(card)
	if current_spell_cards.has(card):
		current_spell_cards.erase(card)

	is_removing_card_mode = false
	card_viewer_overlay.visible = false
	sound_manager.play_sfx("market_trash")
	lbl_combat_log.text = "Carte retirée définitivement du Deck pour %d Or (prochain retrait : %d Or) !" % [
		paid_cost, remove_card_cost
	]
	_update_spell_preview()
	_refresh_all_ui()

# ============================================================================
# TOUR DU JOUEUR & SYSTÈME DE CARTES (ÉLÉMENT -> FORME -> BONUS)
# ============================================================================

func _start_player_turn() -> void:
	_return_incomplete_spell_to_discard()
	# L'action d'achat est réinitialisée à chaque début de tour
	market_buys_available = 0
	# Remplit les emplacements du marché achetés ou supprimés au tour précédent
	_refill_empty_market_slots()
	_draw_cards(HAND_SIZE)
	lbl_combat_log.text = "Tour %d (Vague %d) : Assemblez 3 cartes (Élément -> Forme -> Bonus)." % [turn_in_wave, wave_number]
	_refresh_all_ui()

func _draw_cards(count: int) -> void:
	for _i in range(count):
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			draw_pile.append_array(discard_pile)
			discard_pile.clear()
			_shuffle_cards(draw_pile)
		hand.append(draw_pile.pop_back())

func get_required_step_category() -> int:
	match current_spell_cards.size():
		0: return SpellData.CompCategory.ELEMENT
		1: return SpellData.CompCategory.SHAPE
		_: return SpellData.CompCategory.BONUS

func _on_hand_card_clicked(cv: CardView) -> void:
	if current_spell_cards.size() >= 3:
		lbl_combat_log.text = "Le sort est déjà complet ! Visez une tuile sur le plateau et cliquez pour lancer."
		return

	var req_cat: int = get_required_step_category()
	var card: SpellData.CardItem = cv.card_data
	var has_type: bool = card.has_category(req_cat)

	hand.erase(card)
	current_spell_cards.append(card)
	sound_manager.play_sfx("card_pick", 0.95 + float(current_spell_cards.size()) * 0.08)

	if not has_type:
		match req_cat:
			SpellData.CompCategory.ELEMENT:
				lbl_combat_log.text = "Carte sans Élément jouée : dégâts diminués à 5."
			SpellData.CompCategory.SHAPE:
				lbl_combat_log.text = "Carte sans Gabarit jouée : gabarit réduit à 1 hexagone."
			SpellData.CompCategory.BONUS:
				lbl_combat_log.text = "Carte sans Bonus jouée : aucun effet bonus."

	# Si la 3e carte posée possède le bonus "+1 Hexa aléatoire", on tire tout de suite cet hexagone
	# pour qu'il soit visible dans l'aperçu du gabarit avant même de le placer !
	if current_spell_cards.size() == 3:
		var sh_val: int = current_spell_cards[1].get_value_for_category(SpellData.CompCategory.SHAPE)
		var bn_val: int = current_spell_cards[2].get_value_for_category(SpellData.CompCategory.BONUS)
		if bn_val == SpellData.BonusType.WEAK_EXPAND_1:
			var base_offsets: Array[Vector2i] = SpellData.get_shape_offsets(sh_val, false)
			current_weak_extra_offset = SpellData.pick_random_contact_local_offset(base_offsets, rng)
			has_weak_extra_offset = true
		else:
			has_weak_extra_offset = false
	else:
		has_weak_extra_offset = false

	_update_spell_preview()
	_refresh_all_ui()

func _undo_last_spell_card() -> void:
	if current_spell_cards.is_empty():
		return
	var last_card: SpellData.CardItem = current_spell_cards.pop_back()
	hand.append(last_card)
	has_weak_extra_offset = false
	sound_manager.play_sfx("card_undo")
	_update_spell_preview()
	_refresh_all_ui()

func _update_spell_preview() -> void:
	if current_spell_cards.size() < 2:
		board_view.preview_active = false
		board_view.preview_extra_offsets.clear()
		board_view.queue_redraw()
		return

	var el_val: int = current_spell_cards[0].get_value_for_category(SpellData.CompCategory.ELEMENT)
	var sh_val: int = current_spell_cards[1].get_value_for_category(SpellData.CompCategory.SHAPE)
	var expand_sz: bool = false
	board_view.preview_extra_offsets.clear()

	if current_spell_cards.size() == 3:
		var bn_val: int = current_spell_cards[2].get_value_for_category(SpellData.CompCategory.BONUS)
		expand_sz = (bn_val == SpellData.BonusType.EXPAND_SIZE)
		if bn_val == SpellData.BonusType.WEAK_EXPAND_1 and has_weak_extra_offset:
			board_view.preview_extra_offsets.append(current_weak_extra_offset)

	if not board_view.preview_active:
		if HexMath.is_in_board(board_view.hovered_hex):
			board_view.preview_origin_hex = board_view.hovered_hex
		elif not board_view.monsters.is_empty():
			board_view.preview_origin_hex = board_view.monsters[0]["hex"]
		else:
			board_view.preview_origin_hex = Vector2i(2, 0)

	board_view.preview_active = true
	board_view.preview_element = el_val
	board_view.preview_shape = sh_val
	board_view.preview_double_size = expand_sz
	board_view.preview_rotation = current_rotation
	board_view.queue_redraw()

func _rotate_spell(delta_steps: int) -> void:
	if current_spell_cards.size() < 2:
		return
	current_rotation = ((current_rotation + delta_steps) % 6 + 6) % 6
	board_view.preview_rotation = current_rotation
	sound_manager.play_sfx("rotate")
	board_view.queue_redraw()
	_refresh_all_ui()

func _on_board_rotation_changed(new_rot: int) -> void:
	current_rotation = new_rot
	sound_manager.play_sfx("rotate")
	_refresh_all_ui()

# ============================================================================
# RÉSOLUTION DU SORT SUR LA TUILE VISÉE PAR LE JOUEUR
# ============================================================================

func _award_kill_gold(hex: Vector2i) -> void:
	gold += 1
	sound_manager.play_sfx("monster_death", randf_range(0.95, 1.06))
	board_view.add_floating_text(hex, "+1 Or 💰", Color(1.0, 0.88, 0.25))

func _cast_ready_spell() -> void:
	if board_view.is_busy_animating():
		return
	if current_spell_cards.size() < 3:
		lbl_combat_log.text = "Ajoutez d'abord la 3e carte (3. BONUS) pour lancer le sort !"
		return

	var el: int = current_spell_cards[0].get_value_for_category(SpellData.CompCategory.ELEMENT)
	var sh: int = current_spell_cards[1].get_value_for_category(SpellData.CompCategory.SHAPE)
	var bn: int = current_spell_cards[2].get_value_for_category(SpellData.CompCategory.BONUS)
	var is_expand_size: bool = (bn == SpellData.BonusType.EXPAND_SIZE)
	var is_linger: bool = (bn == SpellData.BonusType.LINGER)

	var origin_hex: Vector2i = board_view.preview_origin_hex
	var offsets: Array[Vector2i] = SpellData.get_shape_offsets(sh, is_expand_size).duplicate()

	# Utilise exactement l'hexagone aléatoire qui était affiché dans l'aperçu du gabarit
	if bn == SpellData.BonusType.WEAK_EXPAND_1 and has_weak_extra_offset:
		if not offsets.has(current_weak_extra_offset):
			offsets.append(current_weak_extra_offset)

	var affected_hexes: Array[Vector2i] = HexMath.get_transformed_shape(offsets, origin_hex, current_rotation)

	var base_dmg: int = SpellData.get_element_base_damage(el)
	if bn == SpellData.BonusType.DAMAGE_BOOST:
		base_dmg = roundi(float(base_dmg) * 1.25)
	elif bn == SpellData.BonusType.WEAK_DAMAGE_10:
		base_dmg = roundi(float(base_dmg) * 1.10)

	# Les 3 cartes du sort vont dans la défausse dès le lancement
	for c in current_spell_cards:
		discard_pile.append(c)
	current_spell_cards.clear()
	has_weak_extra_offset = false
	board_view.preview_active = false
	board_view.preview_extra_offsets.clear()

	lbl_combat_log.text = "Incantation en cours : projectile %s lancé vers (%d, %d)..." % [
		SpellData.get_element_name(el), origin_hex.x, origin_hex.y
	]
	_refresh_all_ui()

	# Lance l'animation du Sorcier + le projectile de la Tour vers l'hexagone ciblé,
	# puis déploie l'effet sur le gabarit et résout les dégâts à l'impact !
	sound_manager.play_spell_cast()
	board_view.launch_spell_projectile(
		origin_hex,
		affected_hexes,
		el,
		is_linger,
		base_dmg,
		func(): _resolve_spell_impact(el, bn, affected_hexes, base_dmg)
	)

func _resolve_spell_impact(el: int, bn: int, affected_hexes: Array[Vector2i], base_dmg: int) -> void:
	sound_manager.play_spell_impact(el)
	var el_col: Color = SpellData.get_element_color(el)

	# Identifie tous les monstres touchés sur les tuiles de la forme
	var hit_monsters: Array[Dictionary] = []
	for m in board_view.monsters:
		if affected_hexes.has(m["hex"]):
			hit_monsters.append(m)

	var occupied: Dictionary = _get_occupied_map()
	var total_hits: int = hit_monsters.size()

	for m in hit_monsters:
		var mult: float = 1.0
		var tag: String = ""
		if el not in [SpellData.Element.NEUTRAL, SpellData.Element.FALLBACK_WEAK]:
			if m["weakness"] == el:
				mult *= 2.0
				tag = " (FAIBLESSE x2!)"
			elif m["resistance"] == el:
				mult *= 0.5
				tag = " (Résist. x0.5)"

		if int(m.get("vulnerable_turns", 0)) > 0:
			mult *= 1.5
			tag += " (Fragile +50%)"

		var final_dmg: int = maxi(1, roundi(float(base_dmg) * mult))
		m["hp"] -= final_dmg
		board_view.add_floating_text(m["hex"], "-%d%s" % [final_dmg, tag], el_col.lightened(0.25))

		# Effets élémentaires (sauf Neutre) + Bonus sur les survivants
		if m["hp"] > 0:
			match el:
				SpellData.Element.ICE:
					m["slow_turns"] = maxi(int(m.get("slow_turns", 0)), 2)
				SpellData.Element.POISON:
					m["poison_turns"] = int(m.get("poison_turns", 0)) + 3
				SpellData.Element.EARTH:
					occupied.erase(m["hex"])
					var pushed_hex: Vector2i = HexMath.get_knockback_hex(m["hex"], occupied)
					m["hex"] = pushed_hex
					occupied[pushed_hex] = true

			if bn == SpellData.BonusType.KNOCKBACK:
				for _k in range(2):
					occupied.erase(m["hex"])
					var kb_hex: Vector2i = HexMath.get_knockback_hex(m["hex"], occupied)
					m["hex"] = kb_hex
					occupied[kb_hex] = true
			elif bn == SpellData.BonusType.VULNERABLE:
				m["vulnerable_turns"] = maxi(int(m.get("vulnerable_turns", 0)), 2)

	# Bonus de soin de la tour (Soin Tour : +2 PV par monstre touché)
	if bn == SpellData.BonusType.LEECH and total_hits > 0:
		var heal_amount: int = total_hits * 2
		tower_hp = mini(tower_max_hp, tower_hp + heal_amount)
		board_view.add_floating_text(Vector2i.ZERO, "+%d PV Tour" % heal_amount, Color(0.35, 1.0, 0.55))

	# Retire les monstres vaincus (avec animation de mort !) et donne +1 Or par ennemi tué
	for i in range(board_view.monsters.size() - 1, -1, -1):
		if board_view.monsters[i]["hp"] <= 0:
			var dead_m: Dictionary = board_view.monsters[i]
			board_view.add_monster_death_anim(dead_m, el)
			_award_kill_gold(dead_m["hex"])
			board_view.monsters.remove_at(i)

	# Bonus Piocher 1 carte
	if bn == SpellData.BonusType.DRAW_CARD:
		_draw_cards(1)

	# Bonus +1 Pièce d'Or
	if bn == SpellData.BonusType.GAIN_1_GOLD:
		gold += 1
		sound_manager.play_sfx("market_buy", 1.12)
		board_view.add_floating_text(Vector2i.ZERO, "+1 Or 💰 (Bonus)", Color(1.0, 0.88, 0.25))

	# Bonus Acheter 1 carte du marché (valable uniquement pendant ce tour !)
	if bn == SpellData.BonusType.BUY_MARKET_CARD:
		market_buys_available += 1
		lbl_combat_log.text = "Sort lancé ! +1 Action d'achat débloquée pour ce tour (Or: %d)." % gold
		_refresh_all_ui()
		if gold >= 1:
			_open_market_modal()
	else:
		lbl_combat_log.text = "Sort %s [%s] lancé (%d monstre(s) touché(s)) !" % [
			SpellData.get_element_name(el), SpellData.get_bonus_name(bn), total_hits
		]
		_refresh_all_ui()

	_check_wave_cleared()

# ============================================================================
# FIN DU TOUR & PHASE DES MONSTRES (AVANCÉE + APPARITION EN BORDURE)
# ============================================================================

func _return_incomplete_spell_to_discard() -> void:
	for c in current_spell_cards:
		discard_pile.append(c)
	current_spell_cards.clear()
	has_weak_extra_offset = false
	board_view.preview_active = false
	board_view.preview_extra_offsets.clear()

func _on_end_turn_pressed() -> void:
	if board_view.is_busy_animating():
		return
	if market_overlay.visible or card_viewer_overlay.visible or game_over_overlay.visible or options_overlay.visible:
		return

	sound_manager.play_sfx("end_turn")

	# Les actions d'achat non utilisées sont perdues à la fin du tour
	market_buys_available = 0

	# Défausse les cartes restantes
	_return_incomplete_spell_to_discard()
	for c in hand:
		discard_pile.append(c)
	hand.clear()

	# 1. Application du Poison et décrément des états
	for i in range(board_view.monsters.size() - 1, -1, -1):
		var m: Dictionary = board_view.monsters[i]
		if int(m.get("vulnerable_turns", 0)) > 0:
			m["vulnerable_turns"] = int(m["vulnerable_turns"]) - 1
		if int(m.get("poison_turns", 0)) > 0:
			var p_dmg: int = 7
			if m["weakness"] == SpellData.Element.POISON:
				p_dmg = 12
			elif m["resistance"] == SpellData.Element.POISON:
				p_dmg = 4
			m["hp"] -= p_dmg
			m["poison_turns"] = int(m["poison_turns"]) - 1
			board_view.add_floating_text(m["hex"], "-%d Poison" % p_dmg, Color(0.6, 0.95, 0.25))
			if m["hp"] <= 0:
				board_view.add_monster_death_anim(m, SpellData.Element.POISON)
				_award_kill_gold(m["hex"])
				board_view.monsters.remove_at(i)
				continue

	# 2. Avancée des monstres vers la tour (du plus proche au plus éloigné)
	board_view.monsters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return HexMath.distance(Vector2i.ZERO, a["hex"]) < HexMath.distance(Vector2i.ZERO, b["hex"])
	)

	var occupied: Dictionary = _get_occupied_map()
	for i in range(board_view.monsters.size()):
		var m: Dictionary = board_view.monsters[i]
		var steps: int = int(m["speed"])
		if int(m.get("slow_turns", 0)) > 0:
			steps = maxi(0, steps - 1)
			m["slow_turns"] = int(m["slow_turns"]) - 1

		for _s in range(steps):
			occupied.erase(m["hex"])
			var next_hex: Vector2i = HexMath.get_step_toward_center(m["hex"], occupied)
			m["hex"] = next_hex
			if m["hex"] == Vector2i.ZERO:
				break
			occupied[m["hex"]] = true

	# 2b. Déclenchement des zones élémentaires persistantes ("Reste 1 Tour") et nettoyage des effets de tour
	_process_lingering_zones_at_turn_end()

	# 3. Monstres qui touchent la Tour centrale (0, 0)
	for i in range(board_view.monsters.size() - 1, -1, -1):
		var m: Dictionary = board_view.monsters[i]
		if m["hex"] == Vector2i.ZERO:
			var dmg: int = int(m["damage"])
			tower_hp = maxi(0, tower_hp - dmg)
			sound_manager.play_sfx("tower_hit")
			board_view.add_floating_text(Vector2i.ZERO, "-%d TOUR !" % dmg, Color(1.0, 0.25, 0.25))
			board_view.monsters.remove_at(i)

	board_view.tower_hp = tower_hp
	if tower_hp <= 0:
		_trigger_game_over(false)
		return

	# 4. Apparition de nouveaux monstres en bordure (distance == 6)
	if spawns_remaining_in_wave > 0:
		var max_turn_spawn: int = 4 + mini(2, wave_number / 2)
		var count_to_spawn: int = mini(spawns_remaining_in_wave, rng.randi_range(3, max_turn_spawn))
		_spawn_wave_monsters(count_to_spawn)

	if _check_wave_cleared():
		return

	turn_in_wave += 1
	_start_player_turn()

func _process_lingering_zones_at_turn_end() -> void:
	var occupied: Dictionary = _get_occupied_map()
	for i in range(board_view.lingering_zones.size() - 1, -1, -1):
		var lz: Dictionary = board_view.lingering_zones[i]
		if bool(lz.get("is_lingering", false)):
			var z_hex: Vector2i = lz["hex"]
			var el: int = int(lz["element"])
			var base_dmg: int = maxi(1, roundi(float(lz["damage"]) * 0.65))
			var el_col: Color = SpellData.get_element_color(el)

			for m in board_view.monsters:
				if m["hex"] == z_hex and m["hp"] > 0:
					var mult: float = 1.0
					if el not in [SpellData.Element.NEUTRAL, SpellData.Element.FALLBACK_WEAK]:
						if m["weakness"] == el:
							mult *= 2.0
						elif m["resistance"] == el:
							mult *= 0.5
					if int(m.get("vulnerable_turns", 0)) > 0:
						mult *= 1.5
					var dmg: int = maxi(1, roundi(float(base_dmg) * mult))
					m["hp"] -= dmg
					board_view.add_floating_text(z_hex, "-%d Zone" % dmg, el_col.lightened(0.3))
					if m["hp"] > 0:
						match el:
							SpellData.Element.ICE:
								m["slow_turns"] = maxi(int(m.get("slow_turns", 0)), 2)
							SpellData.Element.POISON:
								m["poison_turns"] = int(m.get("poison_turns", 0)) + 2
							SpellData.Element.EARTH:
								occupied.erase(m["hex"])
								var pushed: Vector2i = HexMath.get_knockback_hex(m["hex"], occupied)
								m["hex"] = pushed
								occupied[pushed] = true

		lz["turns_left"] = int(lz["turns_left"]) - 1
		if int(lz["turns_left"]) <= 0:
			board_view.lingering_zones.remove_at(i)

	# Retire les monstres éliminés par les zones persistantes et donne +1 Or
	for i in range(board_view.monsters.size() - 1, -1, -1):
		if board_view.monsters[i]["hp"] <= 0:
			var dead_m: Dictionary = board_view.monsters[i]
			board_view.add_monster_death_anim(dead_m, SpellData.Element.NEUTRAL)
			_award_kill_gold(dead_m["hex"])
			board_view.monsters.remove_at(i)

func _spawn_wave_monsters(count: int) -> void:
	var border_tiles: Array[Vector2i] = HexMath.get_border_tiles()
	var occupied: Dictionary = _get_occupied_map()
	var free_border: Array[Vector2i] = []
	for t in border_tiles:
		if not occupied.has(t):
			free_border.append(t)

	for _i in range(count):
		if free_border.is_empty() or spawns_remaining_in_wave <= 0:
			break
		var idx: int = rng.randi_range(0, free_border.size() - 1)
		var spawn_hex: Vector2i = free_border[idx]
		free_border.remove_at(idx)

		var monster: Dictionary = _generate_monster(spawn_hex)
		board_view.monsters.append(monster)
		spawns_remaining_in_wave -= 1

func _generate_monster(spawn_hex: Vector2i) -> Dictionary:
	total_monsters_spawned += 1
	spawned_in_current_wave += 1

	# Progression douce : +1 rang par vague et +1 rang tous les 6 monstres apparus dans la vague
	var power_rank: int = (wave_number - 1) + int((spawned_in_current_wave - 1) / 6)

	# Sélection d'archétype : au début surtout des monstres rapides/légers, puis de plus en plus de colosses
	var max_archetype: int = 1 if total_monsters_spawned <= 4 else (2 if total_monsters_spawned <= 9 else 3)
	var roll: int = rng.randi_range(0, max_archetype)

	var m_name: String
	var hp: int
	var speed: int
	var dmg: int
	var col: Color

	match roll:
		0:
			m_name = "Diablotin Véloce"
			hp = 4 + power_rank + rng.randi_range(0, 1)
			speed = 2
			dmg = 3 + int(wave_number / 2) + int(power_rank / 3)
			col = Color(0.85, 0.32, 0.24)
		1:
			m_name = "Rôdeur des Brumes"
			hp = 5 + power_rank + rng.randi_range(0, 2)
			speed = 2 if (rng.randf() < 0.30 + float(power_rank) * 0.03) else 1
			dmg = 4 + int(wave_number / 2) + int(power_rank / 3)
			col = Color(0.52, 0.34, 0.78)
		2:
			m_name = "Carapace de Roc"
			hp = 8 + roundi(float(power_rank) * 1.5) + rng.randi_range(0, 2)
			speed = 1
			dmg = 5 + wave_number + int(power_rank / 2)
			col = Color(0.42, 0.56, 0.46)
		_:
			m_name = "Exécuteur Abyssal"
			hp = 7 + roundi(float(power_rank) * 1.5) + rng.randi_range(0, 2)
			speed = 1 if power_rank < 6 else (2 if rng.randf() < 0.25 else 1)
			dmg = 7 + wave_number + int(power_rank / 2)
			col = Color(0.76, 0.20, 0.48)

	if power_rank >= 1:
		m_name += " +%d" % power_rank

	var weak_el: int = rng.randi_range(0, 3)
	var res_el: int = (weak_el + rng.randi_range(1, 3)) % 4

	var m_id: int = next_monster_id
	next_monster_id += 1

	return {
		"id": m_id,
		"archetype": roll,
		"name": m_name,
		"hex": spawn_hex,
		"hp": hp,
		"max_hp": hp,
		"speed": speed,
		"damage": dmg,
		"weakness": weak_el,
		"resistance": res_el,
		"color": col,
		"poison_turns": 0,
		"slow_turns": 0,
		"vulnerable_turns": 0
	}

func _get_occupied_map() -> Dictionary:
	var occ := {}
	for m in board_view.monsters:
		occ[m["hex"]] = true
	return occ

func _check_wave_cleared() -> bool:
	if board_view.monsters.is_empty() and spawns_remaining_in_wave <= 0:
		sound_manager.play_sfx("wave_clear")
		tower_hp = mini(tower_max_hp, tower_hp + 5)
		board_view.add_floating_text(Vector2i.ZERO, "Vague %d Vaincue ! (+5 PV)" % wave_number, Color(0.4, 1.0, 0.6))
		_start_wave(wave_number + 1)
		return true
	return false

func _trigger_game_over(victory: bool) -> void:
	game_over_overlay.visible = true
	if victory:
		game_over_lbl.text = "🏆 VICTOIRE ! Vous avez défendu la Tour !"
	else:
		game_over_lbl.text = "💥 LA TOUR EST TOMBÉE (Vague %d, Tour %d)" % [wave_number, turn_in_wave]

# ============================================================================
# MISE À JOUR DE L'INTERFACE GRAPHIQUE
# ============================================================================

func _refresh_all_ui() -> void:
	board_view.tower_hp = tower_hp
	board_view.tower_max_hp = tower_max_hp
	board_view.queue_redraw()

	lbl_top_status.text = "🏰 Tour : %d/%d PV  |  💰 Or : %d  |  🛒 Achats (ce tour) : %d  |  🌊 Vague : %d (T%d)  |  👾 Monstres : %d (+%d)" % [
		tower_hp, tower_max_hp, gold, market_buys_available, wave_number, turn_in_wave, board_view.monsters.size(), spawns_remaining_in_wave
	]

	btn_view_deck.text = "🃏 Voir Deck (%d)" % full_deck.size()
	btn_view_draw.text = "📚 Pioche (%d)" % draw_pile.size()
	btn_view_discard.text = "♻️ Défausse (%d)" % discard_pile.size()

	if market_buys_available > 0:
		btn_open_market.text = "🛒 MARCHÉ (%d Achat !)" % market_buys_available
	else:
		btn_open_market.text = "🛒 MARCHÉ (Voir 3 cartes)"

	# Mise à jour de la pile de sort (superposition des 3 cartes en éventail)
	spell_stack_view.set_stack(current_spell_cards)

	var step: int = current_spell_cards.size()
	if step == 0:
		lbl_step_prompt.text = "Étape 1/3 : Jouez une carte ÉLÉMENT (ou autre = 5 DG)"
		lbl_spell_summary.text = "Choisissez une carte Élément (sinon toute autre carte donnera 5 Dégâts par défaut)."
	elif step == 1:
		var el: int = current_spell_cards[0].get_value_for_category(SpellData.CompCategory.ELEMENT)
		lbl_step_prompt.text = "Étape 2/3 : Jouez une carte FORME (ou autre = 1 Hexa)"
		lbl_spell_summary.text = "Élément actif : %s (%s).\nChoisissez la Forme (sinon toute autre carte donnera 1 Hexa)." % [
			SpellData.get_element_name(el), SpellData.get_element_desc(el)
		]
	elif step == 2:
		var el: int = current_spell_cards[0].get_value_for_category(SpellData.CompCategory.ELEMENT)
		var sh: int = current_spell_cards[1].get_value_for_category(SpellData.CompCategory.SHAPE)
		lbl_step_prompt.text = "Étape 3/3 : Jouez une carte BONUS (ou autre = Sans Bonus)"
		lbl_spell_summary.text = "Élément : %s | Forme : %s.\nChoisissez un Bonus (sinon toute autre carte ne donnera aucun bonus)." % [
			SpellData.get_element_name(el), SpellData.get_shape_name(sh)
		]
	else:
		var el: int = current_spell_cards[0].get_value_for_category(SpellData.CompCategory.ELEMENT)
		var sh: int = current_spell_cards[1].get_value_for_category(SpellData.CompCategory.SHAPE)
		var bn: int = current_spell_cards[2].get_value_for_category(SpellData.CompCategory.BONUS)
		lbl_step_prompt.text = "✨ SORT PRÊT ! Visez une tuile (Rot: 60° x %d)" % current_rotation
		lbl_spell_summary.text = "%s + %s + [%s]\n%s\n👉 Survolez la tuile de votre choix, Molette/Q/R pour tourner, Clic Gauche pour lancer !" % [
			SpellData.get_element_name(el), SpellData.get_shape_name(sh), SpellData.get_bonus_name(bn),
			SpellData.get_bonus_desc(bn)
		]

	btn_undo_card.disabled = (step == 0)
	btn_rotate_left.disabled = (step < 2)
	btn_rotate_right.disabled = (step < 2)
	btn_cast_spell.disabled = (step < 3)

	# Reconstruction des cartes en main (toutes les cartes sont jouables, même sans le bon composant !)
	for child in hand_container.get_children():
		child.queue_free()

	var req_cat: int = int(get_required_step_category()) if step < 3 else -1
	for c in hand:
		var cv := CardView.new()
		var playable: bool = (step < 3)
		cv.setup(c, playable, req_cat, false)
		cv.card_clicked.connect(_on_hand_card_clicked)
		hand_container.add_child(cv)
