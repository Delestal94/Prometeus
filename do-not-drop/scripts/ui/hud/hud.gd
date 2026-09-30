class_name Hud
extends CanvasLayer
## The in-run HUD. It owns the widgets (built in _build_ui()) and the state
## several parts share; the behaviour lives in its child components --
## cargo (HudCargoPanel), prompts (HudPrompts), notices (HudNotices),
## results (HudResults) and pause (HudPause) -- which reach the widgets
## through `hud`. No gameplay decisions or direct physics references.

const INK: Color = UiTheme.INK
const PAPER: Color = UiTheme.PAPER
const MUTED: Color = UiTheme.MUTED
const MINT: Color = UiTheme.MINT
const YELLOW: Color = UiTheme.YELLOW
const RED: Color = UiTheme.RED
const ORANGE: Color = UiTheme.ORANGE
const STATE_FILL: Array[Color] = [UiTheme.MINT, UiTheme.ORANGE, UiTheme.RED]
const STATE_TEXT: Array[Color] = [UiTheme.INK, Color("c26a00"), Color("c73431")]
const STATE_STATUS: Array[String] = ["HUD_STATE_OK", "HUD_STATE_AT_RISK", "HUD_STATE_RUINED"]
enum Role { ON_FOOT, DRIVER, PASSENGER }
const SHORTCUT_VISIBLE_SECONDS: float = 60.0
const RESTART_HOLD_SECONDS: float = 0.9
const CAPTURE_MODE_SCRIPT: String = "res://scripts/tools/capture_mode.gd"
## The logical height the HUD is laid out for (project.godot's viewport).
const BASE_HEIGHT: float = 720.0
## Safe margin from every screen edge, in HUD units (redesign 2026-09-28:
## 24 put the cards against the bezel on a TV).
const EDGE_MARGIN: int = 40

var root: Control
var hud_layer: Control
var dashboard: VBoxContainer
var session_label: Label
var speed_label: Label
var speed_unit_label: Label
var time_label: Label
var economy_label: Label
var card_label: RichTextLabel
var distance_label: Label
var section_label: Label
var cargo_rows_box: VBoxContainer
## The bottom-left cargo card itself, hidden while it has no rows.
var cargo_card: PanelContainer
## Top-right: the metrics card with the toasts under it.
var _right_column: VBoxContainer
var cargo_hint_label: Label
var cargo_rows: Dictionary = {}
var route_bar: ProgressBar
var hint_label: RichTextLabel
var overlay: ColorRect
var card: VBoxContainer
var overlay_kicker: Label
var overlay_title: Label
var overlay_body: Label
var overlay_stats: Label
var result_details: HBoxContainer
var result_rows_box: VBoxContainer
var result_meta_box: VBoxContainer
var result_awards_label: RichTextLabel
var result_event_label: Label
var result_progress_label: Label
var result_progress_bar: ProgressBar
var score_label: Label
var record_label: Label
var action_button: Button
var second_button: Button
var options_button: Button
var menu_button: Button
var options_panel: OptionsPanel
var depot_panel: DepotPanel
var orders: Array = []
var _prep_refresh: float = 0.0
var overlay_mode: String = "start"
var interaction_label: Label
var interaction_icon: TextureRect
var interaction_prompt: String = ""
var ping_label: Label
var ping_indicator: Label
## The driver's line with the bomb's code (HudNotices.refresh_bomb_code()).
var code_label: Label
var ping_seconds_left: float = 0.0
var event_label: Label
var event_seconds_left: float = 0.0
var route_event_active_id: StringName = &""
var toast_label: Label
var toast_seconds_left: float = 0.0
var complaints_label: Label
var photo_strip: HBoxContainer
var fade_rect: ColorRect
var risk_vignette: ColorRect
var ruin_vignette: ColorRect
var shortcut_label: RichTextLabel
## Centres the start/pause/results card over the dimmed backdrop; scaled for
## the window's shape only (not the player's HUD scale), see apply_hud_scale().
var overlay_center: CenterContainer
var soft_pause: bool = false
var is_endless: bool = false
var local_merit_total: int = 0

var cargo: HudCargoPanel
var prompts: HudPrompts
var notices: HudNotices
var results: HudResults
var pause: HudPause


func _ready() -> void:
	cargo = HudCargoPanel.new()
	cargo.name = "CargoPanel"
	cargo.hud = self
	add_child(cargo)
	prompts = HudPrompts.new()
	prompts.name = "Prompts"
	prompts.hud = self
	add_child(prompts)
	notices = HudNotices.new()
	notices.name = "Notices"
	notices.hud = self
	add_child(notices)
	results = HudResults.new()
	results.name = "Results"
	results.hud = self
	add_child(results)
	pause = HudPause.new()
	pause.name = "Pause"
	pause.hud = self
	add_child(pause)
	# Store/trailer capture aid. Release builds never create it, so F10 keeps
	# its platform/default meaning outside development.
	if OS.is_debug_build() and ResourceLoader.exists(CAPTURE_MODE_SCRIPT):
		var capture_mode: Node = load(CAPTURE_MODE_SCRIPT).new()
		capture_mode.name = "CaptureMode"
		add_child(capture_mode)
	var level: Node = get_parent()
	is_endless = level != null and &"distance_traveled" in level
	local_merit_total = int(CrewProgression.merit.get(NetworkManager.local_id(), 0))
	_build_ui()
	EventBus.run_started.connect(_on_started)
	EventBus.depot_orders_posted.connect(func(posted: Array) -> void: orders = posted)
	var truck_view: Node = get_tree().get_first_node_in_group(&"vehicle")
	if truck_view != null:
		var spectator: Node = truck_view.find_child("SpectatorCamera", true, false)
		if spectator != null:
			spectator.connect(&"availability_changed", func(available: bool) -> void:
				if available:
					notices.toast(tr("HUD_SPECTATE_AVAILABLE") % key_hint("Tab", "Back")))
	EventBus.house_refused_package.connect(func(house_index: int, expected: String) -> void:
		var label: String = _house_order_label(house_index, expected)
		notices.toast(tr("HUD_HOUSE_REFUSED") % [house_index + 1, label.to_lower()]))
	NetworkManager.roster_changed.connect(_on_roster_changed)
	GameSettings.hud_scale_changed.connect(func(_scale: float) -> void: apply_hud_scale())
	GameSettings.control_help_mode_changed.connect(func(_mode: int) -> void: prompts.refresh_shortcuts())
	GameSettings.sound_subtitles_changed.connect(func(_enabled: bool) -> void: prompts.refresh_sound_subtitle())
	root.resized.connect(apply_hud_scale)
	apply_hud_scale()
	_refresh_session()
	prompts.refresh_shortcut_text()
	notices.refresh_card()
	pause.show_start()


## The HUD lays out in a logical space BASE_HEIGHT tall, whatever the
## window's shape. Under the project's "expand" stretch a window taller than
## 16:9 (4:3, 16:10) grows the logical canvas instead, which drew every
## label smaller -- 6-7 px at 4:3. Scaling back by that extra height keeps
## text the size it has at 16:9; a wider window (21:9) just gets more room.
static func layout_scale(user_scale: float, logical_size: Vector2) -> float:
	return user_scale * maxf(1.0, logical_size.y / BASE_HEIGHT)


## Team money is a chip (UiTheme.chip): the pill around the label must go too,
## or it stays behind as an empty yellow oval.
func set_economy_visible(shown: bool) -> void:
	economy_label.visible = shown
	economy_label.get_parent().visible = shown


func apply_hud_scale() -> void:
	if hud_layer == null:
		return
	var hud_scale: float = layout_scale(GameSettings.hud_scale, root.size)
	hud_layer.position = Vector2.ZERO
	hud_layer.scale = Vector2(hud_scale, hud_scale)
	hud_layer.size = root.size / hud_scale
	# The card keeps its own size -- only the window-shape correction, so a 4:3
	# screen doesn't draw it at 75% either. The dimmed backdrop stays full screen.
	if overlay_center != null:
		var shape_scale: float = layout_scale(1.0, root.size)
		overlay_center.position = Vector2.ZERO
		overlay_center.scale = Vector2(shape_scale, shape_scale)
		overlay_center.size = root.size / shape_scale


func make_rich(parent: Node, font_size: int) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.fit_content = true
	node.scroll_active = false
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("normal_font_size", font_size)
	node.add_theme_font_override("normal_font", UiTheme.body_font(700))
	node.add_theme_color_override("default_color", INK)
	parent.add_child(node)
	return node


func make_panel(parent: Node, minimum: Vector2) -> VBoxContainer:
	return UiTheme.panel(parent, minimum)


func make_label(parent: Node, value: String, font_size: int, color: Color) -> Label:
	return UiTheme.label(parent, value, font_size, color)


func make_bar(parent: Node, color: Color) -> ProgressBar:
	return UiTheme.bar(parent, color)


func make_button(parent: Node, value: String, primary: bool) -> Button:
	return UiTheme.button(parent, value, primary, Vector2(150, 52))


func key_hint(keyboard: String, gamepad: String) -> String:
	return GameSettings.prompt(keyboard, gamepad)


func _build_ui() -> void:
	_build_frame()
	_build_top_bar()
	_build_bottom_bar()
	_build_floating_labels()
	_build_overlay_card()
	_build_panels()
	_build_fade()


## The full-screen root, the risk vignette, and the scaled layer the dashboard lives in.
func _build_frame() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Menu text has its own accessibility scale; the HUD remains governed by
	# the separate HUD-scale setting.
	UiTheme.apply(root, false)
	add_child(root)
	risk_vignette = ColorRect.new()
	risk_vignette.color = Color(UiTheme.state_color(ITrapBehavior.TrapState.AT_RISK, GameSettings.colorblind_palette),
			0.0)
	risk_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	risk_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	risk_vignette.material = cargo.vignette_material()
	root.add_child(risk_vignette)
	ruin_vignette = ColorRect.new()
	ruin_vignette.color = Color(1.0, 1.0, 1.0, 0.0)
	ruin_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ruin_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ruin_vignette.material = cargo.vignette_material()
	root.add_child(ruin_vignette)
	hud_layer = Control.new()
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_layer)
	var margin := MarginContainer.new()
	hud_layer.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, EDGE_MARGIN)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard = VBoxContainer.new()
	margin.add_child(dashboard)
	dashboard.add_theme_constant_override("separation", 12)
	dashboard.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Top: where you're going (left), the van's numbers (right).
func _build_top_bar() -> void:
	var top := HBoxContainer.new()
	dashboard.add_child(top)
	top.add_theme_constant_override("separation", 16)
	# The objective owns the corner the eye checks first. It replaced a
	# permanent "TAKE MY PACKAGE" logo card (HUD redesign 2026-09-28): the
	# brand belongs to the menus; the session tape (who's playing, the LAN
	# address friends need) rides along on the same card.
	var objective := make_panel(top, Vector2(620, 0))
	objective.get_parent().size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	objective.add_theme_constant_override("separation", 8)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 10)
	objective.add_child(tags)
	section_label = UiTheme.tag(tags, tr("HUD_PREPARATION"), MINT, -1.5, 16)
	session_label = UiTheme.tag(tags, "", MINT, 1.5, 16)
	# Used to open on "220 m hasta la entrega", a leftover from the fixed
	# route: the real one is random and runs closer to 2000 m.
	distance_label = UiTheme.title(objective, "", 30)
	distance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	distance_label.custom_minimum_size.x = 576
	route_bar = UiTheme.bar(objective, MINT, 16)
	route_bar.visible = not is_endless
	var stretch := Control.new()
	stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(stretch)
	# The right column: the van's numbers, and the toasts stacked right under
	# them in the same flow -- anchored at a fixed height, a toast sat on the
	# card whenever the card grew a line (playtest 2026-09-28).
	_right_column = VBoxContainer.new()
	_right_column.add_theme_constant_override("separation", 12)
	_right_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_right_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_right_column)
	var metrics := make_panel(_right_column, Vector2(210, 0))
	metrics.get_parent().size_flags_horizontal = Control.SIZE_SHRINK_END
	metrics.add_theme_constant_override("separation", 6)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	metrics.add_child(speed_row)
	speed_label = UiTheme.title(speed_row, "00", 50)
	speed_unit_label = UiTheme.label(speed_row, "km/h", 16, MUTED)
	speed_unit_label.size_flags_vertical = Control.SIZE_SHRINK_END
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	metrics.add_child(chips)
	time_label = UiTheme.chip(chips, "00:00", UiTheme.SKY, 17)
	economy_label = UiTheme.chip(chips, "$%d" % CrewProgression.team_money, YELLOW, 17)
	set_economy_visible(false)
	card_label = make_rich(metrics, 16)
	card_label.custom_minimum_size.x = 190
	card_label.add_theme_color_override("default_color", INK)


## Bottom: the cargo card (bottom-left corner), and in the centre what you
## can do right now -- the interaction pill, the controls for your role and
## the shortcut pill. The wide objective bar that used to sit here covered
## the road ahead of the truck; its contents moved to the top-left card.
func _build_bottom_bar() -> void:
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard.add_child(space)
	# Context owns the bottom centre, right above the controls in the
	# dashboard's own flow: pinned at a fixed offset it sat on the route bar,
	# and it never competes with the critical alerts up top.
	interaction_label = UiTheme.floating_label(dashboard, "", 25, PAPER, 560, 0)
	interaction_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	interaction_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_plate(interaction_label, Color(INK, 0.88), INK)
	interaction_icon = TextureRect.new()
	interaction_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	interaction_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	interaction_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	interaction_icon.offset_left = -70
	interaction_icon.offset_right = -10
	interaction_icon.offset_top = -30
	interaction_icon.offset_bottom = 30
	interaction_icon.hide()
	interaction_label.add_child(interaction_icon)

	# The controls for what you're doing: a dark pill, the same language as
	# the shortcut pill under it (keycaps drawn for a dark background).
	var hint_pill := PanelContainer.new()
	hint_pill.add_theme_stylebox_override("panel", _pill_style())
	hint_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hint_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard.add_child(hint_pill)
	hint_label = make_rich(hint_pill, 16)
	hint_label.fit_content = true
	hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF

	# --- Bottom-left corner: the cargo, out of the centre's flow ---
	var cargo_panel := make_panel(hud_layer, Vector2(330, 0))
	cargo_card = cargo_panel.get_parent() as PanelContainer
	cargo_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	cargo_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cargo_card.offset_left = EDGE_MARGIN
	cargo_card.offset_bottom = -EDGE_MARGIN
	cargo_card.offset_top = -EDGE_MARGIN
	UiTheme.tag(cargo_panel, tr("HUD_CARGO_TITLE"), UiTheme.CARDBOARD, -2.0, 16)
	cargo_rows_box = VBoxContainer.new()
	cargo_rows_box.add_theme_constant_override("separation", 10)
	cargo_panel.add_child(cargo_rows_box)

	var shortcut_pill := PanelContainer.new()
	shortcut_pill.add_theme_stylebox_override("panel", _pill_style())
	shortcut_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shortcut_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dashboard.add_child(shortcut_pill)
	shortcut_label = make_rich(shortcut_pill, 16)
	shortcut_label.add_theme_color_override("default_color", PAPER)
	shortcut_label.fit_content = true
	shortcut_label.autowrap_mode = TextServer.AUTOWRAP_OFF


func _pill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(INK, 0.82)
	style.set_corner_radius_all(99)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 5
	style.content_margin_bottom = 6
	return style


## A dark rounded plate behind a floating message, so it reads as HUD and
## not as a sign in the world (the depot's signs are yellow on grey too).
## Label draws its "normal" stylebox; _process() hides it while empty.
func _plate(label: Label, fill: Color, border: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	style.shadow_color = Color(INK, 0.5)
	style.shadow_offset = Vector2(0, 5)
	style.shadow_size = 1
	label.add_theme_stylebox_override("normal", style)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_constant_override("shadow_outline_size", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)


## Messages that float over the view: pings, toasts, route events, interaction prompts.
func _build_floating_labels() -> void:
	ping_label = UiTheme.floating_label(hud_layer, "", 26, YELLOW, 560, 20)
	ping_indicator = UiTheme.floating_label(hud_layer, "", 34, YELLOW, 260, 0)
	ping_indicator.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ping_indicator.offset_left = -130
	ping_indicator.offset_right = 130
	ping_indicator.offset_top = -190
	ping_indicator.offset_bottom = -145
	# Big, on a plate, just under the callouts: what the driver reads out loud.
	code_label = UiTheme.floating_label(hud_layer, "", 44, YELLOW, 640, 0)
	# Upper third, not the centre: the middle of the screen is the road the
	# driver is watching (revisor-visual, N-117.2).
	code_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	code_label.offset_left = -320
	code_label.offset_right = 320
	code_label.offset_top = 104
	code_label.offset_bottom = 174
	code_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	code_label.remove_theme_font_override("font")
	_plate(code_label, Color(INK, 0.88), INK)
	# Under the van's numbers, in the same column, sized to its text.
	toast_label = UiTheme.floating_label(_right_column, "", 18, MINT, 400, 0)
	toast_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_plate(toast_label, Color(INK, 0.88), INK)
	# Top centre, sized to its text: a card, not three loose lines.
	event_label = UiTheme.floating_label(hud_layer, "", 29, YELLOW, 760, EDGE_MARGIN)
	event_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	event_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	event_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	event_label.offset_left = 0
	event_label.offset_right = 0
	_plate(event_label, Color(INK, 0.9), RED)
	# The package-at-risk hint and the route event share the critical queue,
	# never the screen. Kept as an alias for the existing cargo HUD seam.
	cargo_hint_label = event_label
## The start / pause / results card and its buttons.
func _build_overlay_card() -> void:
	overlay = ColorRect.new()
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(UiTheme.BACKDROP, 0.72)
	overlay_center = CenterContainer.new()
	overlay.add_child(overlay_center)
	card = make_panel(overlay_center, Vector2(900, 0))
	card.add_theme_constant_override("separation", 14)
	overlay_kicker = UiTheme.tag(card, "", YELLOW, -2.0, 16)
	overlay_title = UiTheme.title(card, tr("HUD_START_TITLE"), 62)
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 14)
	card.add_child(hero)
	score_label = UiTheme.chip(hero, "", YELLOW, 40)
	record_label = UiTheme.tag(hero, tr("HUD_NEW_RECORD"), UiTheme.GRAPE, 4.0, 20)
	record_label.add_theme_color_override("font_color", UiTheme.WHITE)
	record_label.get_parent().size_flags_vertical = Control.SIZE_SHRINK_CENTER
	results.set_hero(false)
	overlay_body = make_label(card, "", 21, INK)
	overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_body.custom_minimum_size.x = 835
	result_details = HBoxContainer.new()
	result_details.add_theme_constant_override("separation", 24)
	result_details.visible = false
	card.add_child(result_details)
	result_rows_box = VBoxContainer.new()
	result_rows_box.add_theme_constant_override("separation", 3)
	result_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_details.add_child(result_rows_box)
	result_meta_box = VBoxContainer.new()
	result_meta_box.custom_minimum_size.x = 320
	result_meta_box.add_theme_constant_override("separation", 6)
	result_details.add_child(result_meta_box)
	result_awards_label = RichTextLabel.new()
	result_awards_label.bbcode_enabled = true
	result_awards_label.fit_content = true
	result_awards_label.scroll_active = false
	result_awards_label.custom_minimum_size.x = 320
	result_awards_label.add_theme_font_size_override("normal_font_size", 16)
	result_meta_box.add_child(result_awards_label)
	result_event_label = make_label(result_meta_box, "", 16, MUTED)
	result_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_progress_label = make_label(result_meta_box, "", 15, MUTED)
	result_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_progress_bar = UiTheme.bar(result_meta_box, MINT, 12)
	overlay_stats = make_label(card, "", 17, MUTED)
	overlay_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_stats.custom_minimum_size.x = 835
	# What the residents had to say, and the photos that answer them. Both
	# stay hidden unless the run actually produced any.
	complaints_label = make_label(card, "", 17, STATE_TEXT[1])
	complaints_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	complaints_label.custom_minimum_size.x = 835
	complaints_label.visible = false
	photo_strip = HBoxContainer.new()
	photo_strip.add_theme_constant_override("separation", 14)
	photo_strip.visible = false
	card.add_child(photo_strip)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	card.add_child(actions)
	action_button = make_button(actions, tr("HUD_START_DELIVERY"), true)
	action_button.pressed.connect(pause.primary_action)
	second_button = make_button(actions, tr("HUD_RESTART"), false)
	second_button.pressed.connect(pause.request_restart)
	# Pausing was a dead end: continue or restart, with no way to reach the
	# options or leave the level at all
	# (docs/critica-diseno-abogado-del-diablo.md section 4).
	options_button = make_button(actions, tr("UI_OPTIONS"), false)
	options_button.pressed.connect(pause.open_options)
	menu_button = make_button(actions, tr("HUD_MENU"), false)
	menu_button.pressed.connect(pause.leave_to_menu)


func _build_panels() -> void:
	options_panel = OptionsPanel.new()
	options_panel.name = "OptionsPanel"
	root.add_child(options_panel)
	depot_panel = DepotPanel.new()
	depot_panel.name = "DepotPanel"
	root.add_child(depot_panel)
	# Back to the button that opened it: otherwise a gamepad player comes
	# back from the options with nothing focused and no way to move.
	options_panel.closed.connect(func() -> void:
		notices.refresh_card()
		if overlay.visible:
			options_button.grab_focus())


func _build_fade() -> void:
	# Added last so it paints over everything else, including the pause/
	# results overlay above -- a quick black flash to soften a hard camera
	# cut (boarding a seat) or a scene reload (restarting), not a UI panel.
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade_rect)


func _process(delta: float) -> void:
	time_label.text = "%02d:%02d" % [int(RunManager.elapsed_seconds) / 60, int(RunManager.elapsed_seconds) % 60]
	prompts.refresh_role()
	prompts.refresh_hint(delta)
	prompts.refresh_shortcuts(delta)
	pause.refresh_restart_hold(delta)
	cargo.refresh_risk_vignette(delta)
	cargo.refresh_ruin_impact(delta)
	cargo.refresh_state_pulses()
	prompts.refresh_sound_subtitle()
	notices.refresh_deadline()
	notices.refresh_bomb_code()
	notices.process_notices(delta)
	var event_pulse: float = 0.84 + sin(Time.get_ticks_msec() * 0.008) * 0.16
	event_label.modulate.a = event_pulse if not event_label.text.is_empty() else 1.0
	# The plated messages (_plate()) would show an empty plate otherwise.
	for plated: Label in [event_label, toast_label, interaction_label, code_label]:
		plated.visible = not plated.text.is_empty()
	cargo_card.visible = cargo_rows_box.get_child_count() > 0
	if overlay_mode == "pause" and not soft_pause and not get_tree().paused:
		overlay.hide()
		overlay_mode = "run" if RunManager.is_running else "preparation"
	# A panel with buttons keeps the cursor free, even if something captured
	# it after the panel opened (the local player spawns after the start
	# screen shows, and its _ready() grabs the mouse for looking around).
	if overlay.visible and overlay_mode in ["start", "pause", "results",
			"disconnected"] 			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cargo.refresh_cargo_hint()
	if overlay_mode == "preparation" and not RunManager.is_running:
		_prep_refresh -= delta
		if _prep_refresh <= 0.0:
			_prep_refresh = 0.25
			distance_label.text = pause.preparation_text()
	if is_endless and RunManager.is_running:
		distance_label.text = tr("HUD_METERS_TRAVELLED") % roundi(float(get_parent().get(&"distance_traveled")))
	if ping_seconds_left > 0.0:
		ping_seconds_left -= delta
		if ping_seconds_left <= 0.0:
			ping_label.text = ""
			ping_indicator.text = ""
	toast_seconds_left = maxf(toast_seconds_left - delta, 0.0)
	event_seconds_left = maxf(event_seconds_left - delta, 0.0)


## The order as this peer's house labels it (Route.assign_packages()
## translates it locally); the relayed one is in the host's language.
func _house_order_label(house_index: int, relayed: String) -> String:
	for house: Node in get_tree().get_nodes_in_group(&"delivery_house"):
		if house is DeliveryHouse and house.house_index == house_index and not house.assigned_label.is_empty():
			return house.assigned_label
	return relayed


func _on_roster_changed(_peer_ids: Array) -> void:
	_refresh_session()


func _refresh_session() -> void:
	if session_label == null:
		return
	var mode: String = "ENDLESS" if is_endless else tr("HUD_SESSION_MODE_DELIVERY")
	if not NetworkManager.is_online():
		session_label.text = tr("HUD_SESSION_SOLO") % mode
		_session_color(MINT)
		return
	var count: int = NetworkManager.peer_ids.size()
	var players: String = (tr("HUD_PLAYERS_ONE") if count == 1 else tr("HUD_PLAYERS_MANY")) % count
	if not NetworkManager.is_host():
		session_label.text = tr("HUD_SESSION_GUEST") % players
		_session_color(UiTheme.SKY)
	elif NetworkManager.active_transport == NetworkManager.Transport.ENET:
		var address: String = NetworkManager.lan_address()
		session_label.text = tr("HUD_SESSION_LAN") % [players,
				address if not address.is_empty() else tr("HUD_SESSION_NO_LAN")]
		_session_color(UiTheme.SKY)
	else:
		session_label.text = tr("HUD_SESSION_STEAM") % players
		_session_color(UiTheme.GRAPE)


## The session tape changes colour with the mode: mint solo, sky on LAN or
## as a guest, grape on Steam -- readable at a glance before the words are.
func _session_color(color: Color) -> void:
	var holder: PanelContainer = session_label.get_parent() as PanelContainer
	var style: StyleBoxFlat = holder.get_theme_stylebox("panel").duplicate()
	style.bg_color = color
	holder.add_theme_stylebox_override("panel", style)


func _on_started(_route: StringName, _players: Array) -> void:
	if WorldMood.active.has("description"):
		notices.toast(tr("HUD_TODAYS_ROUTE") % String(WorldMood.active["description"]).to_lower())
	overlay.hide()
	overlay_mode = "run"
	dashboard.show()
	# Who's playing matters while gathering in the depot, not on the road.
	session_label.get_parent().get_parent().hide()
	set_economy_visible(false)
	action_button.release_focus()
	interaction_prompt = ""
	interaction_label.text = ""
	if is_endless:
		section_label.text = "ENDLESS"
		distance_label.text = tr("HUD_ZERO_METERS")


## The score as a sum you can check (tareas de Slatex #89): one line per
## thing that earned or cost points, the shared-chaos multiplier, the total.
static func score_breakdown_text(results: Dictionary, score: int) -> String:
	return preload("res://scripts/ui/hud/hud_results.gd").format_score_breakdown(results, score)
