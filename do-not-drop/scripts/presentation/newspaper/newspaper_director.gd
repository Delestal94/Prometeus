class_name NewspaperDirector
extends Control
## The next-day newspaper as a scene (N-606.3, docs/diario-final.md): the
## morning after, the Boss reads the paper the host wrote for this run, and
## the camera reads it over his shoulder, one close-up per story. Full screen,
## in its own World3D (a SubViewport with NewspaperSet), ~30 s, and the player
## can skip it by holding Interact or Jump (or Back) for a moment.
##
## Everything about time and framing is data (data/newspaper/shots.json): the
## shots in order, each one a rail of camera poses (CameraRail, the format of
## TrailerCamera's rails), the close-up numbers and the total length. The one
## shot that is not written out is "stories": it opens into one close-up per
## story printed on the page (NewspaperSpread.blocks), framed so the whole
## block fits on screen, and the reading pause is shared out so the scene
## lasts `length_seconds`.
##
## Sound (N-606.4a) is data too: a shot lists its `sounds` ({at, sound, when?},
## seconds into the shot; `when` "news" or "clean" keeps a cue for that kind of
## paper only) and `story.sounds` says which cue each close-up opens with (by
## block id, else "default"). The rooster and the little birds open the scene,
## paper rustles as he unfolds and lowers it, the front page gets its "extra!"
## hit, every other page a page turn, and with bad news the Boss spits his
## mate (a cheer instead if the run was clean). Plain 2D players on the SFX bus:
## the scene has no place in the run's world and nothing here touches it.
##
## It only draws: what the paper says is the host's (NewsDesk), what comes
## after is whoever listens to `finished` (HudNewspaper -> HudResults).

signal finished

const SHOTS_PATH: String = "res://data/newspaper/shots.json"
const NEWS_DESK = preload("res://scripts/presentation/newspaper/news_desk.gd")
const SPREAD = preload("res://scripts/presentation/newspaper/newspaper_spread.gd")
const SET = preload("res://scripts/presentation/newspaper/newspaper_set.gd")
const WorldMix = preload("res://scripts/presentation/world_mix.gd")
## Held for skip_hold_seconds, any of these skips; pressed before the scene
## began, it doesn't count until let go.
const SKIP_ACTIONS: Array[StringName] = [&"interact", &"jump", &"ui_accept", &"ui_cancel", &"ui_pause"]
const FADE_IN_SECONDS: float = 0.6
const TITLE_FADE_SECONDS: float = 0.4
const BAND_SPEED: float = 2.5

static var _shots: Dictionary = {}

var paper: Dictionary = {}
var spread: NewspaperSpread
var stage: NewspaperSet
var viewport: SubViewport
var camera: Camera3D
## [{id, start, seconds, rail, ease, title, bands, lower, react_at, handheld}], in order.
var timeline: Array[Dictionary] = []
## The cues that have played, in order (for the tests: headless plays nothing).
var played: Array[StringName] = []
var duration: float = 0.0
var time: float = 0.0
var skip_held: float = 0.0
var done: bool = false
var _held: Dictionary = {}
var _reacted: bool = false
var _fired: Dictionary = {}
var _sound_players: Dictionary = {}
var _band_amount: float = 0.0
var _shot_index: int = 0
var _container: SubViewportContainer
var _bands: Array[ColorRect] = []
var _title: Label
var _fade: ColorRect
var _skip_box: PanelContainer
var _skip_row: HBoxContainer
var _skip_ring: SkipRing


## The arc that fills while the skip button is held.
class SkipRing extends Control:
	var progress: float = 0.0:
		set(value):
			progress = value
			queue_redraw()

	func _draw() -> void:
		var centre: Vector2 = size * 0.5
		var radius: float = minf(size.x, size.y) * 0.5 - 4.0
		draw_arc(centre, radius, 0.0, TAU, 40, Color(UiTheme.PAPER, 0.35), 4.0, true)
		if progress > 0.0:
			draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 40, UiTheme.YELLOW, 5.0, true)


static func shots() -> Dictionary:
	if _shots.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHOTS_PATH))
		_shots = parsed if parsed is Dictionary else {}
	return _shots


func _ready() -> void:
	name = "NewspaperDirector"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_layout_bands)


## Builds the set with this paper printed and starts the scene. False (and
## nothing shown) when the paper can't be read.
func play(new_paper: Dictionary) -> bool:
	if not NEWS_DESK.is_valid(new_paper) or shots().is_empty():
		return false
	paper = new_paper
	spread = SPREAD.new()
	add_child(spread)
	# This peer's own photos of the run, if the level took any (N-606.5).
	var photographer: NewsPhotographer = NewsPhotographer.find(get_tree()) if is_inside_tree() else null
	if not spread.print_paper(paper, photographer.photos_for(paper) if photographer != null else {}):
		return false
	_container = SubViewportContainer.new()
	_container.name = "Screen"
	_container.stretch = true
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	viewport = SubViewport.new()
	viewport.name = "Stage"
	viewport.own_world_3d = true
	viewport.audio_listener_enable_3d = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.size = Vector2i(maxi(int(size.x), 64), maxi(int(size.y), 64))
	_container.add_child(viewport)
	stage = SET.new()
	viewport.add_child(stage)
	stage.build(spread.inner.get_texture(), spread.outer.get_texture())
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.04
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(camera)
	camera.make_current()
	_build_overlay()
	build_timeline()
	for shot: Dictionary in timeline:
		for cue: Dictionary in shot["sounds"]:
			_sound_player(StringName(cue.get("sound", "")))
	_apply(0.0, 0.0)
	_bake_prints.call_deferred()
	for action: StringName in SKIP_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			_held[action] = false
	return true


## The shots with their rails in world space, from shots.json and the
## printed page. Public for the tests: the scene is deterministic.
func build_timeline() -> void:
	timeline.clear()
	var data: Dictionary = shots()
	var story: Dictionary = data.get("story", {})
	var fixed: float = 0.0
	for shot: Dictionary in data.get("shots", []):
		fixed += float(shot.get("seconds", 0.0))
	var count: int = maxi(spread.blocks.size(), 1)
	var move: float = float(story.get("move", 0.7))
	var hold: float = clampf((float(data.get("length_seconds", 30.0)) - fixed) / count - move,
			float(story.get("hold_min", 2.8)), float(story.get("hold_max", 5.5)))
	var current: Dictionary = _reading_pose()
	var start: float = 0.0
	for shot: Dictionary in data.get("shots", []):
		if String(shot.get("id", "")) == "stories":
			for block: Dictionary in spread.blocks:
				var entry: Dictionary = _story_shot(block, current, story, move, hold)
				entry["start"] = start
				timeline.append(entry)
				start += float(entry["seconds"])
				current = CameraRail.pose_at(entry["rail"], INF)
			continue
		var rail: Array = []
		for point: Dictionary in shot.get("rail", []):
			rail.append(_resolve(point, current))
		var entry: Dictionary = {
			"id": String(shot.get("id", "")),
			"start": start,
			"seconds": float(shot.get("seconds", 1.0)),
			"rail": rail,
			"ease": String(shot.get("ease", "smooth")),
			"title": String(shot.get("title", "")),
			"bands": bool(shot.get("bands", false)),
			"lower": shot.get("lower", []),
			"react_at": float(shot.get("react_at", -1.0)),
			"handheld": float(shot.get("handheld", 0.0)),
			"sounds": shot.get("sounds", []),
		}
		timeline.append(entry)
		start += float(entry["seconds"])
		if not rail.is_empty():
			current = CameraRail.pose_at(rail, INF)
	duration = start


## The shot playing now.
func shot_id() -> String:
	return String(timeline[_shot_index]["id"]) if _shot_index < timeline.size() else ""


func skip() -> void:
	finish()


func finish() -> void:
	if done:
		return
	done = true
	for player: AudioStreamPlayer in _sound_players.values():
		player.stop()
	set_process(false)
	finished.emit()


func _process(delta: float) -> void:
	if done or timeline.is_empty():
		return
	time += delta
	_update_skip(delta)
	if done:
		return
	if time >= duration:
		finish()
		return
	_apply(time, delta)


## Puts everything where it is at `at` seconds: camera, paper, face, overlay.
func _apply(at: float, delta: float) -> void:
	while _shot_index < timeline.size() - 1 and at >= float(timeline[_shot_index + 1]["start"]):
		_shot_index += 1
	var shot: Dictionary = timeline[_shot_index]
	var local: float = at - float(shot["start"])
	_fire_sounds(shot, local)
	var pose: Dictionary = CameraRail.pose_at(shot["rail"], local, shot["ease"])
	var position_now: Vector3 = pose["at"]
	var amplitude: float = float(shot["handheld"])
	if amplitude > 0.0:
		position_now += Vector3(sin(at * 1.7) + sin(at * 4.1) * 0.4, sin(at * 2.3 + 1.0) + sin(at * 3.7) * 0.3, 0.0) \
				* amplitude
	camera.global_position = position_now
	var look: Vector3 = pose["look"]
	if not look.is_equal_approx(position_now):
		camera.look_at(look, pose["up"])
	camera.fov = float(pose["fov"])
	var lower: Array = shot["lower"]
	if lower.size() == 2:
		stage.set_lowered(inverse_lerp(float(lower[0]), float(lower[1]), local))
	if float(shot["react_at"]) >= 0.0 and local >= float(shot["react_at"]) and not _reacted:
		_reacted = true
		var reactions: Dictionary = shots().get("reactions", {})
		var face: Array = reactions.get("clean" if _is_clean() else "news", ["worried", "surprised"])
		stage.set_reaction(StringName(face[0]), StringName(face[1]))
	var title: String = String(shot["title"])
	_title.visible = not title.is_empty()
	if _title.visible:
		_title.text = tr(title)
		var seconds: float = float(shot["seconds"])
		_title.modulate.a = minf(clampf((local - 0.2) / TITLE_FADE_SECONDS, 0.0, 1.0),
				clampf((seconds - local) / TITLE_FADE_SECONDS, 0.0, 1.0))
	var bands_target: float = 1.0 if bool(shot["bands"]) else 0.0
	_band_amount = bands_target if delta <= 0.0 else move_toward(_band_amount, bands_target, delta * BAND_SPEED)
	_layout_bands()
	_fade.modulate.a = 1.0 - clampf(at / FADE_IN_SECONDS, 0.0, 1.0)


## The "everything arrived" scandal: the one paper the Boss is pleased with.
func _is_clean() -> bool:
	return String((paper.get("front", {}) as Dictionary).get("id", "")) == "clean_run"


## Plays the cues of this shot whose time has come, once each.
func _fire_sounds(shot: Dictionary, local: float) -> void:
	var cues: Array = shot["sounds"]
	for index: int in cues.size():
		var cue: Dictionary = cues[index]
		var token: String = "%d:%d" % [_shot_index, index]
		if _fired.has(token) or local < float(cue.get("at", 0.0)):
			continue
		_fired[token] = true
		var only: String = String(cue.get("when", ""))
		if (only == "news" and _is_clean()) or (only == "clean" and not _is_clean()):
			continue
		play_sound(StringName(cue.get("sound", "")))


## One cue of this scene by name (rooster, chirps, paper, page, extra, spit,
## cheer); an unknown name plays nothing.
func play_sound(key: StringName) -> void:
	var player: AudioStreamPlayer = _sound_player(key)
	if player == null:
		return
	played.append(key)
	player.pitch_scale = 1.0 + randf_range(-0.04, 0.04) * float(player.get_meta(&"variation", 0.0))
	player.play()


## The player of a cue, made on first use: [stream, WorldMix level, how much its pitch may vary].
func _sound_player(key: StringName) -> AudioStreamPlayer:
	if _sound_players.has(key):
		return _sound_players[key]
	var spec: Array = _sound_spec(key)
	if spec.is_empty():
		return null
	var player := AudioStreamPlayer.new()
	player.name = "Sound_%s" % key
	player.stream = spec[0]
	player.volume_db = float(spec[1])
	player.bus = &"SFX"
	player.set_meta(&"variation", float(spec[2]))
	add_child(player)
	_sound_players[key] = player
	return player


static func _sound_spec(key: StringName) -> Array:
	match key:
		&"rooster":
			return [SynthAudio.rooster_crow(), WorldMix.NEWSPAPER_ROOSTER_DB, 0.0]
		&"chirps":
			return [SynthAudio.morning_chirps(), WorldMix.NEWSPAPER_CHIRPS_DB, 0.0]
		&"extra":
			return [SynthAudio.extra_stinger(), WorldMix.NEWSPAPER_EXTRA_DB, 0.0]
		&"paper":
			return [SynthAudio.paper_rustle(), WorldMix.NEWSPAPER_PAPER_DB, 1.0]
		&"page":
			return [SynthAudio.page_turn(), WorldMix.NEWSPAPER_PAGE_DB, 1.0]
		&"spit":
			return [SynthAudio.mate_spit(), WorldMix.NEWSPAPER_SPIT_DB, 0.5]
		&"cheer":
			return [SynthAudio.neighbor_cheer(), WorldMix.RESIDENT_CHEER_DB, 0.0]
	return []


func _update_skip(delta: float) -> void:
	var holding: bool = false
	for action: StringName in _held:
		holding = holding or bool(_held[action])
	var hold_seconds: float = float(shots().get("skip_hold_seconds", 0.6))
	skip_held = minf(skip_held + delta, hold_seconds) if holding else maxf(skip_held - delta * 2.0, 0.0)
	_skip_box.visible = time >= float(shots().get("skip_hint_after", 1.0)) or holding
	_skip_ring.progress = skip_held / maxf(hold_seconds, 0.01)
	if holding and skip_held >= hold_seconds:
		skip()


## Holding a skip button. A button already down when the scene began is
## ignored until it is let go (the jump that ended the run doesn't skip it).
func _input(event: InputEvent) -> void:
	if done:
		return
	for action: StringName in SKIP_ACTIONS:
		if not InputMap.has_action(action) or not event.is_action(action):
			continue
		if event.is_action_pressed(action, false, true):
			if not _held.has(action) or bool(_held[action]):
				_held[action] = true
		elif event.is_action_released(action, true):
			_held.erase(action)
		get_viewport().set_input_as_handled()
		return


func _resolve(point: Dictionary, current: Dictionary) -> Dictionary:
	var resolved: Dictionary
	match String(point.get("space", "set")):
		"current":
			resolved = current.duplicate()
		"reading":
			resolved = _reading_pose()
		"paper":
			var centre: Vector3 = stage.paper.global_position
			resolved = {"at": centre + _vector(point.get("at", [0, 0, 1])),
					"look": centre + _vector(point.get("look", [0, 0, 0])),
					"up": stage.paper_up() if String(point.get("up", "paper")) == "paper" else Vector3.UP,
					"fov": float(point.get("fov", current.get("fov", 42.0)))}
		_:
			resolved = {"at": _vector(point.get("at", [0, 1, 0])), "look": _vector(point.get("look", [0, 1, -1])),
					"up": Vector3.UP, "fov": float(point.get("fov", current.get("fov", 42.0)))}
	resolved["t"] = float(point.get("t", 0.0))
	return resolved


## The whole spread in view, square to it, with both hands at the corners.
func _reading_pose() -> Dictionary:
	var reading: Dictionary = shots().get("reading", {})
	var centre: Vector3 = stage.paper.global_position
	return {"at": centre + _vector(reading.get("at", [0.0, 1.16, 0.18])), "look": centre, "up": stage.paper_up(),
			"fov": float(reading.get("fov", 42.0))}


## A close-up of one story: nearly square to the sheet, leaning past its far
## edge so the Boss's head stays out of the lens, framed to fit the block.
func _story_shot(block: Dictionary, current: Dictionary, story: Dictionary, move: float, hold: float) -> Dictionary:
	var rect: Rect2 = block["rect"]
	var page: Vector2 = Vector2(SPREAD.PAGE_SIZE)
	var target: Vector3 = stage.paper_point(rect.get_center() / page)
	var distance: float = float(story.get("distance", 1.6))
	var away: Vector3 = stage.paper_normal().rotated(stage.paper_right(),
			-deg_to_rad(float(story.get("tilt_degrees", 28.0))))
	var aspect: float = size.x / size.y if size.x > 0.0 and size.y > 0.0 else 16.0 / 9.0
	var width: float = rect.size.x / page.x * SET.SHEET_WIDTH
	var height: float = rect.size.y / page.y * SET.SHEET_HEIGHT
	var half: float = maxf(height, width / aspect) * 0.5 * float(story.get("margin", 1.14))
	var close: Dictionary = {"at": target + away * distance, "look": target, "up": stage.paper_up(),
			"fov": rad_to_deg(2.0 * atan(half / distance)), "t": move}
	var from: Dictionary = current.duplicate()
	from["t"] = 0.0
	var cues: Dictionary = story.get("sounds", {})
	return {"id": String(block["id"]), "seconds": move + hold, "rail": [from, close],
			"ease": String(story.get("ease", "smooth")), "title": "", "bands": false, "lower": [], "react_at": -1.0,
			"handheld": 0.0, "sounds": cues.get(String(block["id"]), cues.get("default", []))}


## Mipmapped prints once the pages have been drawn (sharper small type).
func _bake_prints() -> void:
	if not is_inside_tree():
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or done or spread == null:
		return
	stage.set_prints(spread.baked(spread.inner), spread.baked(spread.outer))


func _build_overlay() -> void:
	for index: int in 2:
		var band := ColorRect.new()
		band.name = "Band%d" % index
		band.color = Color.BLACK
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(band)
		_bands.append(band)
	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_font_override("font", UiTheme.display_font())
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", UiTheme.PAPER)
	_title.add_theme_color_override("font_outline_color", UiTheme.INK)
	_title.add_theme_constant_override("outline_size", 8)
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_title.position = Vector2(72, 64)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	# A dark pill: the hint sits over bright newsprint in the close-ups.
	_skip_box = PanelContainer.new()
	_skip_box.name = "Skip"
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(UiTheme.INK, 0.62)
	pill.set_corner_radius_all(22)
	pill.content_margin_left = 12
	pill.content_margin_right = 18
	pill.content_margin_top = 6
	pill.content_margin_bottom = 6
	_skip_box.add_theme_stylebox_override("panel", pill)
	_skip_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skip_box.offset_right = -28
	_skip_box.offset_bottom = -24
	_skip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_box.visible = false
	add_child(_skip_box)
	_skip_row = HBoxContainer.new()
	_skip_row.add_theme_constant_override("separation", 10)
	_skip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_box.add_child(_skip_row)
	_skip_ring = SkipRing.new()
	_skip_ring.custom_minimum_size = Vector2(34, 34)
	_skip_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skip_row.add_child(_skip_ring)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = tr("HUD_NEWS_SKIP") % GameSettings.binding_label(&"interact")
	hint.add_theme_font_override("font", UiTheme.body_font(700))
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", UiTheme.PAPER)
	hint.add_theme_color_override("font_outline_color", UiTheme.INK)
	hint.add_theme_constant_override("outline_size", 6)
	_skip_row.add_child(hint)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


## Letterbox bands toward 2.35:1 on the shots that ask for them.
func _layout_bands() -> void:
	if _bands.is_empty():
		return
	var ratio: float = float(shots().get("band_ratio", 2.35))
	var height: float = maxf((size.y - size.x / ratio) * 0.5, 0.0) * _band_amount
	_bands[0].position = Vector2.ZERO
	_bands[0].size = Vector2(size.x, height)
	_bands[1].position = Vector2(0.0, size.y - height)
	_bands[1].size = Vector2(size.x, height)


static func _vector(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
