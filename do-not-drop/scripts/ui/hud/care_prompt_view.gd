extends Control
## The animated "what to press" strip of the care card (ui/hud/care_card.gd),
## one picture per CareGuide step, and a sound for every change it shows
## (playtest 2026-09-28: a bare "←" beside the tool read as decoration):
##   hold     -- the box swaying with the truck; hold the primary action and
##               two hands grip it
##   release  -- hands off: the button crossed out, red if it's still held
##   tool     -- the tool button and a ring filling with the job
##   sequence -- a row of keycaps, the next one bouncing (question marks
##               when the driver holds the code, the bomb's "Pedí el código")
##   cushion  -- Fragile: the primary button with a ring closing on it; the
##               tap counts once the ring turns green (N-117 "Amortiguá")
##   collect  -- the interact key bouncing, with how many pieces are left
## Pure presentation, drawn on the card's cream: CareCard feeds it every frame
## and events come from comparing a frame with the last.

const SynthAudioScript = preload("res://scripts/presentation/synth_audio.gd")
const UiThemeScript = preload("res://scripts/ui/ui_theme.gd")
const KEYS: Dictionary = {Vector2.LEFT: "A", Vector2.UP: "W", Vector2.RIGHT: "D", Vector2.DOWN: "S"}
const STEP_VECTORS: Dictionary = {&"left": Vector2.LEFT, &"up": Vector2.UP, &"right": Vector2.RIGHT,
	&"down": Vector2.DOWN}
const VIEW_SIZE := Vector2(300, 112)
## Tool progress clicks once per this much of the job.
const TICK_EVERY: float = 0.1
## Two "no" buzzes closer than this would just be noise.
const ERROR_COOLDOWN: float = 0.6
const CUES: Dictionary = {&"step": -12.0, &"error": -11.0, &"success": -9.0, &"whoosh": -15.0, &"tick": -19.0}
## Steps worth a swish when the card switches to them: something new to do.
const ATTENTION_STEPS: Array[StringName] = [&"collect", &"sequence", &"tool", &"release", &"cushion"]

var step: StringName = &""
var gamepad: bool = false
var holding_primary: bool = false
var holding_tool: bool = false
var progress: float = 0.0
var sway: Vector2 = Vector2.ZERO
var steps: Array = []
var step_index: int = 0
var missing: int = 0
## The code is on the driver's dashboard: the keycaps stay hidden.
var hidden_code: bool = false
## What is written under the key to press: "TAP", or "ASK" when it is a "?".
var caption: String = ""
## Fragile's cushion state as the host published it (CushionState), and when
## this frame received it, so the ring keeps closing between updates.
var cushion: Dictionary = {}
var interact_key: String = "E"
## Every cue played, newest last: what the tests read.
var played: Array[StringName] = []

var _time: float = 0.0
var _cushion_at: float = 0.0
var _pop: float = 0.0
var _shake: float = 0.0
var _flash: float = 0.0
var _error_flash: float = 0.0
var _last_error_time: float = -INF
var _sparks: Array = []
var _baseline: Dictionary = {}
var _players: Dictionary = {}
var _style := StyleBoxFlat.new()


func _ready() -> void:
	custom_minimum_size = VIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for cue: StringName in CUES:
		var player := AudioStreamPlayer.new()
		player.name = "Cue_%s" % cue
		player.stream = _cue_stream(cue)
		player.bus = &"SFX"
		player.volume_db = float(CUES[cue])
		add_child(player)
		_players[cue] = player


static func _cue_stream(cue: StringName) -> AudioStreamWAV:
	match cue:
		&"step":
			return SynthAudioScript.care_step()
		&"error":
			return SynthAudioScript.care_error()
		&"success":
			return SynthAudioScript.care_success()
		&"whoosh":
			return SynthAudioScript.care_whoosh()
	return SynthAudioScript.care_tick()


## A different box (or none): forget the last frame, so the new box's state
## doesn't read as a burst of events.
func reset() -> void:
	_baseline.clear()
	_last_error_time = -INF
	step = &""


## One frame of the card. `data`: {pad, primary, tool_held, work, fixes,
## sequence, cushion, missing, sway, interact}. Plays whatever changed since the
## last.
func show_step(new_step: StringName, data: Dictionary) -> void:
	var first: bool = _baseline.is_empty()
	gamepad = bool(data.get("pad", false))
	holding_primary = bool(data.get("primary", false))
	holding_tool = bool(data.get("tool_held", false))
	sway = data.get("sway", Vector2.ZERO)
	interact_key = String(data.get("interact", "E"))
	var work: float = clampf(float(data.get("work", 0.0)), 0.0, 1.0)
	var fixes: int = int(data.get("fixes", 0))
	var sequence: Dictionary = data.get("sequence", {})
	var new_missing: int = int(data.get("missing", 0))
	var solved: int = int(sequence.get("solved", _baseline.get("solved", 0)))
	var mistakes: int = int(sequence.get("mistakes", _baseline.get("mistakes", 0)))
	var index: int = int(sequence.get("index", 0))
	var new_cushion: Dictionary = data.get("cushion", {})
	var saved: int = int(new_cushion.get("saved", 0))
	if not first:
		if new_step != step and new_step in ATTENTION_STEPS:
			_play(&"whoosh")
			_pop = 1.0
		if fixes > int(_baseline["fixes"]) or solved > int(_baseline["solved"]) or saved > int(_baseline["saved"]):
			_celebrate()
		elif mistakes > int(_baseline["mistakes"]):
			_fail()
		elif new_step == &"sequence" and step == &"sequence" and index > int(_baseline["index"]):
			_play(&"step", 1.0 + 0.12 * (index - 1))
			_pop = 1.0
		if new_missing < int(_baseline["missing"]):
			if new_missing == 0:
				_celebrate()
			else:
				_play(&"step", 1.0 + 0.15 * maxf(0.0, 3.0 - new_missing))
				_pop = 1.0
		if new_step == &"tool" and work > progress and floorf(work / TICK_EVERY) > floorf(progress / TICK_EVERY) \
				and work < 1.0:
			_play(&"tick", 0.85 + work * 0.6)
		if new_step == &"hold" and holding_primary and not bool(_baseline["primary"]):
			_play(&"tick", 1.3)
		var wrong: bool = new_step == &"release" and holding_primary
		if wrong and not bool(_baseline["wrong"]):
			_fail()
	_baseline = {"fixes": fixes, "solved": solved, "mistakes": mistakes, "index": index, "missing": new_missing,
		"saved": saved,
		"primary": holding_primary, "wrong": new_step == &"release" and holding_primary}
	step = new_step
	progress = work
	steps = sequence.get("steps", [])
	step_index = index
	missing = new_missing
	hidden_code = StringName(sequence.get("reader", &"owner")) == &"driver"
	caption = tr("HUD_CARE_ASK") if hidden_code else tr("HUD_CARE_TAP")
	if new_cushion != cushion:
		_cushion_at = _time
	cushion = new_cushion


## For the caller's own moments (switching tools).
func play_cue(cue: StringName) -> void:
	_play(cue)


func _play(cue: StringName, pitch: float = 1.0) -> void:
	played.append(cue)
	var player := _players.get(cue) as AudioStreamPlayer
	if player == null or not player.is_inside_tree():
		return
	player.pitch_scale = pitch
	player.play()


func _fail() -> void:
	_shake = 1.0
	_error_flash = 1.0
	if _time - _last_error_time >= ERROR_COOLDOWN:
		_last_error_time = _time
		_play(&"error")


func _celebrate() -> void:
	_play(&"success")
	_flash = 1.0
	_pop = 1.0
	var origin := Vector2(size.x * 0.5, 24.0)
	for i: int in 16:
		var angle: float = -PI * (0.1 + 0.8 * i / 15.0) + randf_range(-0.1, 0.1)
		_sparks.append({"pos": origin, "vel": Vector2.from_angle(angle) * randf_range(60.0, 130.0),
			"life": randf_range(0.5, 0.8), "color": UiThemeScript.YELLOW if i % 2 == 0 else UiThemeScript.MINT})


func _process(delta: float) -> void:
	_time += delta
	_pop = maxf(0.0, _pop - delta * 2.5)
	_shake = maxf(0.0, _shake - delta * 3.0)
	_flash = maxf(0.0, _flash - delta * 2.0)
	_error_flash = maxf(0.0, _error_flash - delta * 1.1)
	for spark: Dictionary in _sparks:
		spark["life"] = float(spark["life"]) - delta
		spark["vel"] = (spark["vel"] as Vector2) * (1.0 - delta * 2.5) + Vector2(0, 140.0 * delta)
		spark["pos"] = (spark["pos"] as Vector2) + (spark["vel"] as Vector2) * delta
	# Confined to the strip: whatever sits under it on the card stays clean.
	var inside := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	_sparks = _sparks.filter(func(spark: Dictionary) -> bool:
		return float(spark["life"]) > 0.0 and inside.has_point(spark["pos"]))
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.5) + Vector2(sin(_time * 55.0) * 6.0 * _shake, 0.0)
	match step:
		&"hold":
			_draw_hold(center)
		&"idle":
			_draw_idle(center)
		&"release":
			_draw_release(center)
		&"tool":
			_draw_tool(center)
		&"sequence":
			_draw_sequence(center)
		&"cushion":
			_draw_cushion(center)
		&"collect":
			_draw_collect(center)
		&"grab":
			_draw_grab(center)
		&"load":
			_draw_load(center)
	for spark: Dictionary in _sparks:
		var alpha: float = clampf(float(spark["life"]) / 0.4, 0.0, 1.0)
		var at: Vector2 = (spark["pos"] as Vector2) - Vector2(3, 3)
		draw_rect(Rect2(at, Vector2(6, 6)), Color(spark["color"] as Color, alpha))


# --- Steps ------------------------------------------------------------------

## The box swaying with the truck; hands grip it while the button is held.
func _draw_hold(center: Vector2) -> void:
	_draw_primary_button(center + Vector2(-78, 0), holding_primary)
	var box_center: Vector2 = center + Vector2(62, 4)
	var tilt: float = clampf(sway.x, -1.0, 1.0) * (0.12 if holding_primary else 0.45) \
		+ (0.0 if holding_primary else sin(_time * 3.2) * 0.14)
	draw_set_transform(box_center, tilt, Vector2.ONE * (1.0 + 0.12 * _ease(_pop)))
	_box(Rect2(Vector2(-30, -26), Vector2(60, 52)), UiThemeScript.CARDBOARD, UiThemeScript.INK, 6, 3)
	draw_line(Vector2(-30, -8), Vector2(30, -8), Color(UiThemeScript.INK, 0.5), 3.0)
	_box(Rect2(Vector2(-8, -26), Vector2(16, 18)), UiThemeScript.YELLOW, UiThemeScript.INK, 2, 2)
	if holding_primary:
		for side: float in [-1.0, 1.0]:
			_box(Rect2(Vector2(side * 30 - 9, -6), Vector2(18, 26)), UiThemeScript.PAPER, UiThemeScript.INK, 9, 3)
	draw_set_transform(Vector2.ZERO)
	if holding_primary:
		_draw_check(box_center + Vector2(36, -30))


## The mirror of hold: the button struck out and the box on its own. Hands
## still on it show up red and crossed out.
## All good: the box sitting still with a tick, and the button quiet.
func _draw_idle(center: Vector2) -> void:
	if gamepad:
		_draw_trigger(center + Vector2(-78, 0), "RT", holding_primary, false)
	else:
		_draw_mouse(center + Vector2(-78, 0), true, holding_primary, false)
	var box_center: Vector2 = center + Vector2(62, 4)
	_draw_cardboard(box_center, clampf(sway.x, -1.0, 1.0) * 0.1)
	_draw_check(box_center + Vector2(36, -30))


func _draw_release(center: Vector2) -> void:
	_draw_primary_button(center + Vector2(-78, 0), holding_primary, true)
	var box_center: Vector2 = center + Vector2(62, 4)
	# A warning pulse around the box: this one is urgent.
	var pulse: float = fmod(_time * 1.3, 1.0)
	draw_arc(box_center, 34.0 + pulse * 18.0, 0.0, TAU, 40, Color(UiThemeScript.RED, (1.0 - pulse) * 0.6), 4.0, true)
	_draw_cardboard(box_center, 0.0)
	if holding_primary:
		var shake := Vector2(sin(_time * 40.0) * 2.0, 0.0)
		for side: float in [-1.0, 1.0]:
			var hand := Rect2(box_center + shake + Vector2(side * 30 - 9, -6), Vector2(18, 26))
			_box(hand, UiThemeScript.RED, UiThemeScript.INK, 9, 3)
			draw_line(hand.position + Vector2(-6, -6), hand.end + Vector2(6, 6), UiThemeScript.RED.darkened(0.35),
				6.0, true)
	else:
		_draw_check(box_center + Vector2(36, -30))


func _draw_tool(center: Vector2) -> void:
	var device: Vector2 = center + Vector2(0, 2)
	draw_arc(device, 46.0, 0.0, TAU, 56, Color(UiThemeScript.INK, 0.12), 8.0, true)
	if progress > 0.0:
		draw_arc(device, 46.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 56, UiThemeScript.MINT, 8.0, true)
	if gamepad:
		_draw_trigger(device, "LT", holding_tool)
	else:
		_draw_mouse(device, false, holding_tool)
	if progress > 0.0:
		_draw_text("%d%%" % roundi(progress * 100.0), device + Vector2(84, 8), 22, UiThemeScript.INK)


func _draw_sequence(center: Vector2) -> void:
	var count: int = steps.size()
	if count == 0:
		return
	var cap: float = 50.0
	var gap: float = 14.0 if count <= 4 else 6.0
	var total: float = count * cap + (count - 1) * gap
	var x0: float = center.x - total * 0.5
	var y: float = center.y - 6.0
	for i: int in count:
		var direction: Vector2 = STEP_VECTORS.get(StringName(steps[i]), Vector2.ZERO)
		var key_center := Vector2(x0 + cap * 0.5 + i * (cap + gap), y)
		var glyph: String = "" if gamepad else String(KEYS.get(direction, "?"))
		if hidden_code:
			# The driver has the code: here it is only how many are left.
			direction = Vector2.ZERO
			glyph = "" if i < step_index else "?"
		var border: Color = UiThemeScript.RED if _error_flash > 0.25 and i == step_index else UiThemeScript.INK
		if i < step_index:
			var grow: float = 1.0 + 0.18 * _ease(_pop) if i == step_index - 1 else 1.0
			_draw_key(key_center, glyph, direction, true, true, border, grow)
			_draw_check(key_center + Vector2(-cap * 0.34, -cap * 0.46))
		elif i == step_index:
			_draw_ripple(key_center, 0.9, 30.0)
			_draw_key(key_center + Vector2(0, -absf(sin(_time * 6.0)) * 7.0), glyph, direction, false, false, border,
				1.0, true)
			_draw_text(caption, key_center + Vector2(0, cap * 0.5 + 24), 16, UiThemeScript.INK)
		else:
			_draw_key(key_center, glyph, direction, false, false, border, 0.86, false, 0.4)


## Fragile: the primary button, and a ring closing on it as the bump nears.
## Green from the moment a tap would count; grey while the last one still
## makes the next one wait.
func _draw_cushion(center: Vector2) -> void:
	var lead: float = maxf(float(cushion.get("lead", 0.7)), 0.05)
	var window: float = float(cushion.get("window", 0.35))
	var eta: float = float(cushion.get("eta", -1.0)) - (_time - _cushion_at)
	var button: Vector2 = center + Vector2(-46, -6)
	_draw_primary_button(button, holding_primary)
	var closing: float = clampf(eta / lead, 0.0, 1.0)
	var ring: Color = UiThemeScript.MINT if eta <= window else UiThemeScript.ORANGE
	draw_arc(button, 32.0, 0.0, TAU, 48, Color(UiThemeScript.INK, 0.35), 3.0, true)
	draw_arc(button, 32.0 + 40.0 * closing, 0.0, TAU, 48, ring, 6.0, true)
	var shake: float = sin(_time * 45.0) * 0.06 if eta < 0.2 else 0.0
	_draw_cardboard(center + Vector2(82, 4), shake)
	_draw_text(tr("HUD_CARE_TAP"), button + Vector2(0, 62), 16, UiThemeScript.INK)


func _draw_collect(center: Vector2) -> void:
	var key_center: Vector2 = center + Vector2(-34, -absf(sin(_time * 5.0)) * 6.0)
	_draw_ripple(center + Vector2(-34, 0), 1.0, 30.0)
	_draw_key(key_center, interact_key, Vector2.ZERO, false, false, UiThemeScript.INK, 1.0 + 0.2 * _ease(_pop), true)
	_draw_text("×%d" % missing, center + Vector2(48, 12), 34, UiThemeScript.INK)


## Practice (CarePractice): the interact key beside a box, "take it".
func _draw_grab(center: Vector2) -> void:
	var key_center: Vector2 = center + Vector2(-50, -absf(sin(_time * 5.0)) * 6.0)
	_draw_ripple(center + Vector2(-50, 0), 1.0, 30.0)
	_draw_key(key_center, interact_key, Vector2.ZERO, false, false, UiThemeScript.INK, 1.0 + 0.2 * _ease(_pop), true)
	_draw_cardboard(center + Vector2(58, 6), 0.0)


## Practice: the box going down onto a shelf plank, over and over.
func _draw_load(center: Vector2) -> void:
	var drop: float = _ease(fmod(_time * 0.8, 1.0))
	var shelf_y: float = center.y + 40.0
	draw_line(Vector2(center.x - 70, shelf_y), Vector2(center.x + 70, shelf_y), UiThemeScript.ORANGE, 8.0, true)
	draw_line(Vector2(center.x - 70, shelf_y + 5), Vector2(center.x + 70, shelf_y + 5), UiThemeScript.INK, 2.0, true)
	_draw_cardboard(Vector2(center.x, lerpf(center.y - 26.0, shelf_y - 27.0, drop)), 0.0)


func _draw_cardboard(at: Vector2, tilt: float) -> void:
	draw_set_transform(at, tilt, Vector2.ONE)
	_box(Rect2(Vector2(-30, -26), Vector2(60, 52)), UiThemeScript.CARDBOARD, UiThemeScript.INK, 6, 3)
	draw_line(Vector2(-30, -8), Vector2(30, -8), Color(UiThemeScript.INK, 0.5), 3.0)
	_box(Rect2(Vector2(-8, -26), Vector2(16, 18)), UiThemeScript.YELLOW, UiThemeScript.INK, 2, 2)
	draw_set_transform(Vector2.ZERO)


# --- Pieces -----------------------------------------------------------------

## The primary action: the mouse's left button, or RT. `crossed` draws it
## struck out (hands off).
func _draw_primary_button(center: Vector2, pressed: bool, crossed: bool = false) -> void:
	if gamepad:
		_draw_trigger(center, "RT", pressed and not crossed, not crossed)
	else:
		_draw_mouse(center, true, pressed and not crossed, not crossed)
	if crossed:
		draw_line(center + Vector2(-26, -30), center + Vector2(26, 30), UiThemeScript.RED, 6.0, true)


func _draw_mouse(center: Vector2, left: bool, pressed: bool, beckon: bool = true) -> void:
	_box(Rect2(center - Vector2(22, 31) + Vector2(0, 5), Vector2(44, 62)), UiThemeScript.INK, UiThemeScript.INK, 21, 0)
	_box(Rect2(center - Vector2(22, 31), Vector2(44, 62)), UiThemeScript.WHITE, UiThemeScript.INK, 21, 3)
	var pulse: float = 0.45 + 0.55 * absf(sin(_time * 5.0))
	var fill: Color = UiThemeScript.MINT if pressed else Color(UiThemeScript.YELLOW, pulse if beckon else 0.35)
	var button := Rect2(center + Vector2(-20 if left else 1, -29), Vector2(19, 25))
	_box(button, fill, UiThemeScript.INK, 10, 0)
	draw_line(center + Vector2(0, -31), center + Vector2(0, -4), UiThemeScript.INK, 3.0)
	draw_line(center + Vector2(-22, -4), center + Vector2(22, -4), UiThemeScript.INK, 3.0)
	if not pressed and beckon:
		_draw_ripple(button.get_center(), 1.1, 12.0)


func _draw_trigger(center: Vector2, label: String, pressed: bool, beckon: bool = true) -> void:
	var sink: float = 4.0 if pressed else 0.0
	var pulse: float = 0.45 + 0.55 * absf(sin(_time * 5.0))
	_box(Rect2(center - Vector2(28, 18) + Vector2(0, 5), Vector2(56, 38)), UiThemeScript.INK, UiThemeScript.INK, 12, 0)
	_box(Rect2(center - Vector2(28, 18) + Vector2(0, sink), Vector2(56, 38)),
		UiThemeScript.MINT if pressed else Color(UiThemeScript.YELLOW, pulse), UiThemeScript.INK, 12, 3)
	_draw_text(label, center + Vector2(0, 10 + sink), 24, UiThemeScript.INK)
	if not pressed and beckon:
		_draw_ripple(center, 1.1, 22.0)


## A keycap: ink base for depth, a face that sinks when held, the letter and
## (keyboard) the arrow it stands for; on a gamepad just the arrow, big.
func _draw_key(center: Vector2, glyph: String, arrow: Vector2, pressed: bool, lit: bool, border: Color,
		grow: float = 1.0, beckon: bool = false, alpha: float = 1.0) -> void:
	var side: float = 50.0 * grow
	var sink: float = 5.0 if pressed else 0.0
	var face := Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side))
	_box(Rect2(face.position + Vector2(0, 6), face.size), Color(UiThemeScript.INK, alpha), UiThemeScript.INK, 10, 0)
	var fill: Color = UiThemeScript.MINT if lit else UiThemeScript.WHITE
	if _flash > 0.0:
		fill = fill.lerp(UiThemeScript.MINT, _flash)
	var edge: Color = UiThemeScript.ORANGE.lerp(border, 0.5 + 0.5 * sin(_time * 7.0)) if beckon else border
	_box(Rect2(face.position + Vector2(0, sink), face.size), Color(fill, alpha), Color(edge, alpha), 10,
		4 if beckon else 3)
	var ink := Color(UiThemeScript.INK, alpha)
	if glyph.is_empty():
		_draw_arrow(center + Vector2(0, sink), arrow, 12.0 * grow, ink, 4.0)
	elif arrow == Vector2.ZERO:
		_draw_text(glyph, center + Vector2(0, 11 + sink), roundi(28 * grow), ink)
	else:
		_draw_text(glyph, center + Vector2(-side * 0.14, 11 + sink), roundi(27 * grow), ink)
		_draw_arrow(center + Vector2(side * 0.27, sink), arrow, 7.0 * grow, ink, 3.0)


## An arrow as lines: the fonts' arrow glyphs came out as smudges at HUD size.
func _draw_arrow(center: Vector2, toward: Vector2, half: float, color: Color, width: float) -> void:
	var side := Vector2(-toward.y, toward.x)
	var tip: Vector2 = center + toward * half
	draw_line(center - toward * half, tip, color, width, true)
	draw_polyline(PackedVector2Array([tip - toward * half * 0.7 + side * half * 0.7, tip,
		tip - toward * half * 0.7 - side * half * 0.7]), color, width, true)


## A ring spreading from a point, over and over: "press here".
func _draw_ripple(center: Vector2, period: float, start: float) -> void:
	var t: float = fmod(_time / period, 1.0)
	draw_arc(center, start + t * 22.0, 0.0, TAU, 32, Color(UiThemeScript.ORANGE, (1.0 - t) * 0.7), 3.0, true)


func _draw_check(at: Vector2) -> void:
	draw_circle(at, 11.0, UiThemeScript.INK)
	draw_polyline(PackedVector2Array([at + Vector2(-5, 0), at + Vector2(-1, 4), at + Vector2(6, -5)]),
		UiThemeScript.MINT, 3.0, true)


func _draw_text(text: String, baseline_center: Vector2, font_size: int, color: Color) -> void:
	var font: Font = UiThemeScript.display_font()
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, baseline_center - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _box(rect: Rect2, fill: Color, border: Color, radius: int, border_width: int) -> void:
	_style.bg_color = fill
	_style.border_color = border
	_style.set_border_width_all(border_width)
	_style.set_corner_radius_all(radius)
	_style.anti_aliasing = true
	draw_style_box(_style, rect)


static func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)
