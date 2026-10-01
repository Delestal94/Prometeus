class_name LoadingScreen
extends SceneLoader
## The cover between the menu and a level (N-407). Pressing "¡JUGAR!" used to
## freeze the menu on its last frame for the seconds the level took to load
## and build; now its own key art comes up with the logo where the menu had
## it, a "shipping label" card with a box riding a bumpy road, a bar and
## what's happening ("Cargando el camión…", "Armando la ruta…"), and a tip.
##
## The mechanism (threaded load, swap behind the cover, first frames drawn
## before it lifts) is the scene_loader module; this file is only the look.

## Its own key art (ComfyUI, art/concept/loading/): the van heading out at
## sunrise, boxes already flying off the roof.
const ART: Texture2D = preload("res://assets/ui/backgrounds/tx_ui_loading_background_1920.png")
const LOGO: Texture2D = preload("res://assets/ui/logo/tx_ui_logo_wordmark_2048.png")
const TIPS: Array[String] = [
	"UI_LOADING_TIP_FRAGILE", "UI_LOADING_TIP_RUN", "UI_LOADING_TIP_EXPLOSIVE",
	"UI_LOADING_TIP_LIQUID", "UI_LOADING_TIP_NOISY", "UI_LOADING_TIP_HOSTILE",
	"UI_LOADING_TIP_PARK", "UI_LOADING_TIP_BOARD", "UI_LOADING_TIP_MERIT",
]
const STAGE_TEXT: Dictionary = {
	Stage.LOADING: "UI_LOADING_STAGE_LOAD",
	Stage.BUILDING: "UI_LOADING_STAGE_BUILD",
	Stage.SETTLING: "UI_LOADING_STAGE_SETTLE",
	Stage.DONE: "UI_LOADING_STAGE_READY",
}
## The art creeps in this much over a load: the screen never looks frozen.
const ART_ZOOM: float = 1.06
## Every model a level may load() while it builds: fetched on threads while
## the scene loads, so the depot kit, the roadside and the houses find them
## cached (~220 ms of main-thread load() in the delivery level otherwise).
const MODELS_DIR: String = "res://assets/models"
## The synthesized sounds a level asks for in its _ready() (measured,
## N-408): ~0.4 s of synthesis that moves to a worker thread.
const LEVEL_SOUNDS: Array[StringName] = [
	&"ambient_birds", &"ambient_wind", &"distant_road", &"river_flow_loop", &"tension_pulse",
	&"doorbell_ding_dong", &"wood_creak", &"engine_idle_loop", &"dog_bark", &"care_success", &"train_horn",
	&"engine_high_loop", &"comic_boom", &"forklift_motor_loop", &"comic_ruin_stinger", &"creature_groan",
	&"roller_door", &"engine_loop", &"train_chug_loop", &"sheep_bleat", &"reverse_beep", &"glass_chime",
	&"crossing_bell", &"honk_horn", &"care_error", &"tire_screech", &"hostile_hiss", &"liquid_slosh",
	&"care_whoosh", &"impact_thud", &"camera_shutter", &"care_step", &"care_tick", &"explosive_tick",
]
## Hidden at the swap and shown one per frame once the level is built: the
## depot's first draw (~180 ms of shader compiles) gets a frame of its own,
## and the road isn't drawn while it builds (tens of thousands of pieces
## before they are batched), so the build's frames stay short. Paths that a
## level doesn't have are skipped.
const REVEALS: Array[NodePath] = [^"World/Depot", ^"World/Route"]

## Not the same tip twice in a row.
static var _last_tip: String = ""

## The tape over the card: what is starting ("JUGAR SOLO", "CREAR SALA"...).
var mode_text: String = ""
## A translation key from TIPS; picked at random when left empty.
var tip_key: String = ""

var _bar: ProgressBar
var _stage_label: Label
var _shown_stage: int = -1


## The menu's way into a level: the loader with this look, already on its way.
static func go(tree: SceneTree, path: String, mode: String = "") -> LoadingScreen:
	var screen := LoadingScreen.new()
	screen.mode_text = mode
	# Not headless: the dummy renderer crashes on meshes loaded on threads
	# (blend shapes on uninitialized RIDs), and there's nothing to show anyway.
	if DisplayServer.get_name() != "headless":
		screen.prefetch_paths = model_paths()
	screen.reveal_paths = REVEALS
	SceneLoader.change_scene(tree, path, screen)
	return screen


## Every .glb under MODELS_DIR, as an exported build lists them too.
static func model_paths() -> PackedStringArray:
	var found := PackedStringArray()
	_collect_models(MODELS_DIR, found)
	return found


static func _collect_models(directory: String, found: PackedStringArray) -> void:
	for entry: String in ResourceLoader.list_directory(directory):
		if entry.ends_with("/"):
			_collect_models(directory.path_join(entry.trim_suffix("/")), found)
		elif entry.get_extension() == "glb":
			found.append(directory.path_join(entry))


func _start_warm() -> void:
	SynthAudio.warm(LEVEL_SOUNDS)


func _warm_done() -> bool:
	return SynthAudio.warm_done()


## The cover stays until this peer's own player is in the level: a client
## waits for the host to answer its ready report and spawn it. A session
## that dropped meanwhile doesn't keep it waiting (the level shows why).
func _scene_ready(scene: Node) -> bool:
	if scene == null or scene.get_node_or_null(^"World/PlayerSpawner") == null:
		return true
	# By path, not the autoload's name: this class compiles on its own too.
	var session: Node = get_node_or_null(^"/root/NetworkManager")
	if session == null or not bool(session.call(&"is_online")):
		return true
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if player.is_multiplayer_authority():
			return true
	return false


static func pick_tip() -> String:
	var choices: Array[String] = []
	for key: String in TIPS:
		if key != _last_tip:
			choices.append(key)
	_last_tip = choices[randi() % choices.size()]
	return _last_tip


func _build_cover(root: Control) -> void:
	UiTheme.apply(root)
	var backdrop := ColorRect.new()
	backdrop.color = UiTheme.BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	_build_art(root)
	_build_logo(root)
	_build_cards(root)


## The key art, slowly creeping in; ink pooled at the bottom so the cards
## read over the road.
func _build_art(root: Control) -> void:
	var art := TextureRect.new()
	art.name = "Art"
	art.texture = ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(art)
	art.resized.connect(func() -> void: art.pivot_offset = art.size * 0.5)
	art.create_tween().tween_property(art, "scale", Vector2.ONE * ART_ZOOM, 8.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(UiTheme.INK, 0.0))
	gradient.set_color(1, Color(UiTheme.INK, 0.78))
	gradient.add_point(0.55, Color(UiTheme.INK, 0.12))
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.fill_from = Vector2(0.5, 0.0)
	fill.fill_to = Vector2(0.5, 1.0)
	var shade := TextureRect.new()
	shade.texture = fill
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)


## Same size and place as on the menu (main_menu.gd _build_brand()).
func _build_logo(root: Control) -> void:
	var logo := TextureRect.new()
	logo.name = "BrandLogo"
	logo.texture = LOGO
	# Ignore the texture's 2048 px before sizing it, or that becomes its minimum size.
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(420, 210)
	logo.position = Vector2(64, 48)
	logo.size = Vector2(420, 210)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(logo)


## Progress card bottom left, tip card bottom right.
func _build_cards(root: Control) -> void:
	var band := MarginContainer.new()
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.grow_vertical = Control.GROW_DIRECTION_BEGIN
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["margin_left", "margin_right"]:
		band.add_theme_constant_override(side, 64)
	band.add_theme_constant_override("margin_bottom", 56)
	root.add_child(band)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	band.add_child(row)

	var progress: VBoxContainer = UiTheme.panel(row, Vector2(520, 0))
	progress.add_theme_constant_override("separation", 12)
	(progress.get_parent() as Control).size_flags_vertical = Control.SIZE_SHRINK_END
	var tag_text: String = mode_text if not mode_text.is_empty() else tr("UI_LOADING_TAG")
	UiTheme.tag(progress, tag_text.to_upper(), UiTheme.MINT, -2.0, 15)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 16)
	progress.add_child(heading)
	var box := BumpyBox.new()
	box.name = "BumpyBox"
	box.custom_minimum_size = Vector2(64, 56)
	heading.add_child(box)
	_stage_label = UiTheme.title(heading, tr(STAGE_TEXT[Stage.LOADING]), 32)
	_stage_label.name = "StageLabel"
	_stage_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar = UiTheme.bar(progress, UiTheme.MINT, 20)
	_bar.name = "LoadingBar"
	_bar.max_value = 1.0
	_bar.step = 0.0

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	var tip: VBoxContainer = UiTheme.panel(row, Vector2(420, 0))
	(tip.get_parent() as Control).size_flags_vertical = Control.SIZE_SHRINK_END
	UiTheme.tag(tip, tr("UI_LOADING_TIP_TAG"), UiTheme.YELLOW, 2.0, 14)
	if tip_key.is_empty():
		tip_key = pick_tip()
	var tip_label: Label = UiTheme.label(tip, tr(tip_key), 18)
	tip_label.name = "TipLabel"
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size.x = 376


func _show_progress(ratio: float, current: Stage) -> void:
	if _bar == null:
		return
	_bar.value = ratio
	if int(current) != _shown_stage:
		_shown_stage = int(current)
		_stage_label.text = tr(STAGE_TEXT[current])


## A cardboard box riding a bumpy road: it hops, lands a little crooked and
## the road dashes slide under it. Drawn, not a texture: two rects and tape.
class BumpyBox extends Control:
	const HOP_RATE: float = 5.0
	const DASH: float = 14.0
	var _time: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var road_y: float = size.y - 3.0
		var offset: float = fmod(_time * 90.0, DASH * 2.0)
		var x: float = -offset
		while x < size.x:
			draw_line(Vector2(maxf(x, 0.0), road_y), Vector2(clampf(x + DASH, 0.0, size.x), road_y), UiTheme.INK, 3.0)
			x += DASH * 2.0
		var phase: float = _time * HOP_RATE
		var hop: float = absf(sin(phase))
		var box_size := Vector2(size.x * 0.62, size.y * 0.58)
		var lift: float = hop * hop * size.y * 0.2
		var tilt: float = sin(phase * 0.5) * 0.12 * hop
		var center := Vector2(size.x * 0.5, road_y - 4.0 - box_size.y * 0.5 - lift)
		draw_set_transform(center, tilt, Vector2.ONE)
		var body := Rect2(-box_size * 0.5, box_size)
		draw_rect(Rect2(body.position + Vector2(0, 4), body.size), UiTheme.INK)
		draw_rect(body, UiTheme.CARDBOARD)
		var tape_width: float = box_size.x * 0.2
		draw_rect(Rect2(-tape_width * 0.5, body.position.y, tape_width, box_size.y), UiTheme.YELLOW)
		draw_line(Vector2(body.position.x, body.position.y + box_size.y * 0.3),
			Vector2(body.end.x, body.position.y + box_size.y * 0.3), UiTheme.INK, 2.0)
		draw_rect(body, UiTheme.INK, false, 3.0)
		draw_set_transform_matrix(Transform2D.IDENTITY)
