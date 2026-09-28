extends Control
## The care panel's "what do I press" card: animated, and every change it
## shows also sounds (playtest 2026-09-28: a bare "←" beside the tool read as
## decoration, and nobody found the bomb's keys). Two modes:
##   work     -- hold a button and a direction: the mouse's right button (LT
##               on a gamepad) plus a keycap for the arrow (the stick), the
##               arrow sliding its way and a ring filling with the progress.
##   sequence -- tap directions one at a time (the bomb's module, Peso
##               Creciente): a row of keycaps, the next one bouncing.
## Pure presentation: player_cargo_care.gd feeds it the replicated care
## state every frame, and events come from comparing a frame with the last.

const SynthAudioScript = preload("res://scripts/presentation/synth_audio.gd")
const UiThemeScript = preload("res://scripts/ui/ui_theme.gd")
const KEYS: Dictionary = {Vector2.LEFT: "A", Vector2.UP: "W", Vector2.RIGHT: "D", Vector2.DOWN: "S"}
const STEP_VECTORS: Dictionary = {&"left": Vector2.LEFT, &"up": Vector2.UP, &"right": Vector2.RIGHT,
	&"down": Vector2.DOWN}
const CARD_SIZE := Vector2(330, 160)
## A finished sequence stays on screen, celebrated, this long before the
## card goes back to the tool.
const DONE_HOLD: float = 1.3
## Tool progress clicks once per this much of the job.
const TICK_EVERY: float = 0.1
## Two wrong-key buzzes closer than this would just be noise.
const ERROR_COOLDOWN: float = 0.6
const CUES: Dictionary = {&"step": -12.0, &"error": -11.0, &"success": -9.0, &"whoosh": -15.0, &"tick": -19.0}

enum Mode { NONE, WORK, SEQUENCE }

var mode: int = Mode.NONE
var gamepad: bool = false
var caption: String = ""
# Work mode.
var direction: Vector2 = Vector2.LEFT
var progress: float = 0.0
var holding_button: bool = false
var holding_direction: bool = false
var can_work: bool = true
# Sequence mode.
var steps: Array = []
var step_index: int = 0
var seconds_left: float = -1.0
## Every cue played, newest last: what the tests read.
var played: Array[StringName] = []

var _time: float = 0.0
var _pop: float = 0.0
var _shake: float = 0.0
var _flash: float = 0.0
var _error_flash: float = 0.0
var _done_left: float = 0.0
var _last_error_time: float = -INF
var _wrong_text: String = ""
var _sparks: Array = []
var _baseline: Dictionary = {}
var _players: Dictionary = {}
var _style := StyleBoxFlat.new()


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
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


## A different box (or none): forget what the last frame looked like, so
## the new one's state doesn't read as a burst of events.
func reset() -> void:
	_baseline.clear()
	_done_left = 0.0
	mode = Mode.NONE


func hide_prompt() -> void:
	mode = Mode.NONE


## Hold-to-work: `direction` is the arrow to hold, `work` the replicated
## progress, `fixes` a count that grows each time a tool job completes.
func show_work(work_direction: Vector2, work: float, button: bool, direction_held: bool, fixes: int,
		usable: bool, pad: bool, text: String) -> void:
	var fresh: bool = mode != Mode.WORK or not _baseline.has("fixes")
	mode = Mode.WORK
	gamepad = pad
	caption = text
	can_work = usable
	holding_button = button
	holding_direction = direction_held
	if not fresh:
		if fixes > int(_baseline["fixes"]):
			_celebrate(false)
		elif work_direction != direction:
			_play(&"whoosh")
			_pop = 1.0
		if work > progress and floorf(work / TICK_EVERY) > floorf(progress / TICK_EVERY) and work < 1.0:
			_play(&"tick", 0.85 + work * 0.6)
		var wrong: bool = button and (not usable or not direction_held)
		if wrong and not bool(_baseline.get("wrong", false)):
			_fail("AHORA NO SE PUEDE" if not usable else "TECLA EQUIVOCADA")
		_baseline["wrong"] = wrong
	else:
		_baseline["wrong"] = false
	_baseline["fixes"] = fixes
	direction = work_direction
	progress = clampf(work, 0.0, 1.0)


## Tap-to-solve, from a trap's sequence_state(). Returns false once there's
## nothing left to show (solved and celebrated), so the caller can fall back
## to the tool.
func show_sequence(state: Dictionary, pad: bool, text: String) -> bool:
	var new_steps: Array = state.get("steps", [])
	var index: int = int(state.get("index", 0))
	var mistakes: int = int(state.get("mistakes", 0))
	var solved: int = int(state.get("solved", 0))
	var complete: bool = index >= new_steps.size()
	if not _baseline.has("solved"):
		# First look: whatever already happened isn't news.
		_baseline["solved"] = solved
		_baseline["mistakes"] = mistakes
		_baseline["index"] = index
		if complete:
			return false
	if solved > int(_baseline["solved"]):
		_celebrate(complete)
	elif mistakes > int(_baseline["mistakes"]):
		_fail("TECLA EQUIVOCADA")
	elif index > int(_baseline["index"]):
		_play(&"step", 1.0 + 0.12 * (index - 1))
		_pop = 1.0
	_baseline["solved"] = solved
	_baseline["mistakes"] = mistakes
	_baseline["index"] = index
	if complete and _done_left <= 0.0:
		return false
	mode = Mode.SEQUENCE
	gamepad = pad
	caption = text
	steps = new_steps
	step_index = index
	seconds_left = float(state.get("seconds", -1.0))
	return true


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


func _fail(text: String) -> void:
	_wrong_text = text
	_shake = 1.0
	_error_flash = 1.0
	if _time - _last_error_time >= ERROR_COOLDOWN:
		_last_error_time = _time
		_play(&"error")


func _celebrate(hold: bool) -> void:
	_play(&"success")
	_flash = 1.0
	_pop = 1.0
	if hold:
		_done_left = DONE_HOLD
	# Bursting up from above the keys, so the letters stay readable.
	var origin := Vector2(size.x * 0.5, 30.0)
	for i: int in 18:
		var angle: float = -PI * (0.1 + 0.8 * i / 17.0) + randf_range(-0.1, 0.1)
		_sparks.append({"pos": origin, "vel": Vector2.from_angle(angle) * randf_range(70.0, 150.0),
			"life": randf_range(0.5, 0.9), "color": UiThemeScript.YELLOW if i % 2 == 0 else UiThemeScript.WHITE})


func _process(delta: float) -> void:
	_time += delta
	_pop = maxf(0.0, _pop - delta * 2.5)
	_shake = maxf(0.0, _shake - delta * 3.0)
	_flash = maxf(0.0, _flash - delta * 2.0)
	_error_flash = maxf(0.0, _error_flash - delta * 1.1)
	_done_left = maxf(0.0, _done_left - delta)
	for spark: Dictionary in _sparks:
		spark["life"] = float(spark["life"]) - delta
		spark["vel"] = (spark["vel"] as Vector2) * (1.0 - delta * 2.5) + Vector2(0, 140.0 * delta)
		spark["pos"] = (spark["pos"] as Vector2) + (spark["vel"] as Vector2) * delta
	# Confined to the card: whatever sits under it in the panel stays clean.
	var inside := Rect2(Vector2(4, 4), size - Vector2(8, 30))
	_sparks = _sparks.filter(func(spark: Dictionary) -> bool:
		return float(spark["life"]) > 0.0 and inside.has_point(spark["pos"]))
	modulate.a = 1.0 if mode != Mode.WORK or can_work else 0.55
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	match mode:
		Mode.WORK:
			_draw_work()
		Mode.SEQUENCE:
			_draw_sequence()
	for spark: Dictionary in _sparks:
		var alpha: float = clampf(float(spark["life"]) / 0.4, 0.0, 1.0)
		var color: Color = spark["color"]
		draw_rect(Rect2((spark["pos"] as Vector2) - Vector2(3, 3), Vector2(6, 6)), Color(color, alpha))
	if _error_flash > 0.0 and mode != Mode.NONE:
		_draw_wrong_banner()
	if not caption.is_empty():
		var font: Font = UiThemeScript.body_font(800)
		draw_string_outline(font, Vector2(0, size.y - 8), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, 6,
			UiThemeScript.INK)
		draw_string(font, Vector2(0, size.y - 8), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16,
			UiThemeScript.PAPER)


# --- Work: hold the button and the direction ---------------------------------

func _draw_work() -> void:
	var working: bool = holding_button and holding_direction and can_work
	var y: float = 64.0
	var wiggle := Vector2(sin(_time * 55.0) * 7.0 * _shake, 0.0)
	if gamepad:
		_draw_trigger(Vector2(size.x * 0.15, y), holding_button)
	else:
		_draw_mouse(Vector2(size.x * 0.15, y), holding_button)
	_draw_text("+", Vector2(size.x * 0.31, y + 10), 30, UiThemeScript.PAPER)
	var key_center := Vector2(size.x * 0.5, y) + wiggle
	# Progress ring around the key: the job filling up as it's held.
	draw_arc(key_center, 46.0, 0.0, TAU, 48, Color(UiThemeScript.PAPER, 0.18), 7.0, true)
	if progress > 0.0:
		draw_arc(key_center, 46.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, UiThemeScript.MINT, 7.0, true)
	var border: Color = UiThemeScript.RED if _error_flash > 0.25 else UiThemeScript.INK
	if gamepad:
		_draw_stick(key_center, direction, holding_direction, border)
	else:
		_draw_key(key_center, String(KEYS.get(direction, "?")), direction,
			holding_direction, working, border, 1.0 + 0.3 * _ease(_pop), not holding_direction)
	_draw_chevrons(Vector2(size.x * 0.82, y), direction, working)


func _draw_mouse(center: Vector2, pressed: bool) -> void:
	var body := Rect2(center - Vector2(21, 30), Vector2(42, 60))
	_box(body, UiThemeScript.PAPER, UiThemeScript.INK, 20, 3)
	var pulse: float = 0.45 + 0.55 * absf(sin(_time * 5.0))
	var fill: Color = UiThemeScript.MINT if pressed else Color(UiThemeScript.YELLOW, pulse)
	# Right button, the one that works: a quarter of the body, lit.
	var button := Rect2(center + Vector2(1, -28), Vector2(18, 24))
	_box(button, fill, UiThemeScript.INK, 10, 0)
	draw_line(center + Vector2(0, -30), center + Vector2(0, -4), UiThemeScript.INK, 3.0)
	draw_line(center + Vector2(-21, -4), center + Vector2(21, -4), UiThemeScript.INK, 3.0)
	if not pressed:
		_draw_ripple(center + Vector2(10, -16), 1.1)


func _draw_trigger(center: Vector2, pressed: bool) -> void:
	var sink: float = 4.0 if pressed else 0.0
	var pulse: float = 0.45 + 0.55 * absf(sin(_time * 5.0))
	_box(Rect2(center - Vector2(26, 16) + Vector2(0, 5), Vector2(52, 36)), UiThemeScript.INK, UiThemeScript.INK, 12, 0)
	_box(Rect2(center - Vector2(26, 16) + Vector2(0, sink), Vector2(52, 36)),
		UiThemeScript.MINT if pressed else Color(UiThemeScript.YELLOW, pulse), UiThemeScript.INK, 12, 3)
	_draw_text("LT", center + Vector2(0, 10 + sink), 22, UiThemeScript.INK)
	if not pressed:
		_draw_ripple(center, 1.1)


func _draw_stick(center: Vector2, toward: Vector2, held: bool, border: Color) -> void:
	draw_circle(center, 30.0, UiThemeScript.PAPER)
	draw_arc(center, 30.0, 0.0, TAU, 40, border, 3.0, true)
	# The nub leans toward the arrow over and over until it's held there.
	var reach: float = 14.0 if held else 14.0 * _ease(fmod(_time * 1.4, 1.0))
	var nub: Vector2 = center + toward * reach
	draw_circle(nub, 13.0, UiThemeScript.MINT if held else UiThemeScript.INK)
	_draw_arrow(nub, toward, 9.0, UiThemeScript.INK if held else UiThemeScript.PAPER, 3.0)


## Arrows sliding the way to push, three at a time, fading in and out.
func _draw_chevrons(center: Vector2, toward: Vector2, working: bool) -> void:
	var side := Vector2(-toward.y, toward.x)
	var speed: float = 2.4 if working else 1.4
	for i: int in 3:
		var t: float = fmod(_time * speed + i / 3.0, 1.0)
		var at: Vector2 = center + toward * (t - 0.5) * 38.0
		var color := Color(UiThemeScript.MINT if working else UiThemeScript.YELLOW, sin(PI * t))
		var tip: Vector2 = at + toward * 8.0
		draw_polyline(PackedVector2Array([at - toward * 5.0 + side * 10.0, tip, at - toward * 5.0 - side * 10.0]),
			color, 6.0, true)


# --- Sequence: tap each direction once, in order ------------------------------

func _draw_sequence() -> void:
	var count: int = steps.size()
	if count == 0:
		return
	var cap: float = 52.0
	var gap: float = 14.0 if count <= 4 else 6.0
	var total: float = count * cap + (count - 1) * gap
	var x0: float = (size.x - total) * 0.5 + sin(_time * 60.0) * 10.0 * _shake
	var y: float = 72.0
	var done_all: bool = step_index >= count
	if seconds_left >= 0.0 and not done_all:
		var urgent: bool = seconds_left <= 6.0  # Top right, clear of the centred banner.
		var pulse: float = 1.0 + (0.12 * absf(sin(_time * 8.0)) if urgent else 0.0)
		_draw_text("%d s" % ceili(seconds_left), Vector2(size.x - 30, 22), roundi(20 * pulse),
			UiThemeScript.RED if urgent else UiThemeScript.YELLOW)
	for i: int in count:
		var step_direction: Vector2 = STEP_VECTORS.get(StringName(steps[i]), Vector2.ZERO)
		var center := Vector2(x0 + cap * 0.5 + i * (cap + gap), y)
		var glyph: String = "" if gamepad else String(KEYS.get(step_direction, "?"))
		var corner: Vector2 = step_direction
		var border: Color = UiThemeScript.RED if _error_flash > 0.25 and i == step_index else UiThemeScript.INK
		if done_all or i < step_index:
			var grow: float = 1.0 + 0.18 * _ease(_pop) if i == step_index - 1 or done_all else 1.0
			_draw_key(center, glyph, corner, true, true, border, grow, false)
			_draw_check(center + Vector2(cap * 0.38, -cap * 0.4))
		elif i == step_index:
			var bounce: float = -absf(sin(_time * 6.0)) * 8.0
			_draw_ripple(center, 0.9)
			_draw_key(center + Vector2(0, bounce), glyph, corner, false, false, border, 1.0, true)
			_draw_text("TOCÁ", center + Vector2(0, cap * 0.5 + 26), 17, UiThemeScript.YELLOW)
		else:
			_draw_key(center, glyph, corner, false, false, border, 0.86, false, 0.45)
	if done_all:
		_draw_text("¡LISTO!", Vector2(size.x * 0.5, 22), 24, UiThemeScript.MINT)


# --- Shared pieces ----------------------------------------------------------

## A keycap: ink base for depth, a face that sinks when held, a big glyph and
## (keyboard) the arrow it stands for in the corner.
func _draw_key(center: Vector2, glyph: String, corner: Vector2, pressed: bool, lit: bool, border: Color,
		grow: float = 1.0, beckon: bool = false, alpha: float = 1.0) -> void:
	var side: float = 52.0 * grow
	var sink: float = 5.0 if pressed else 0.0
	var face := Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side))
	_box(Rect2(face.position + Vector2(0, 6), face.size), Color(UiThemeScript.INK, alpha), UiThemeScript.INK, 10, 0)
	var fill: Color = UiThemeScript.MINT if lit else UiThemeScript.PAPER
	if _flash > 0.0:
		fill = fill.lerp(UiThemeScript.MINT, _flash)
	var edge: Color = border
	if beckon:
		edge = UiThemeScript.YELLOW.lerp(border, 0.5 + 0.5 * sin(_time * 7.0))
	_box(Rect2(face.position + Vector2(0, sink), face.size), Color(fill, alpha), Color(edge, alpha), 10,
		4 if beckon else 3)
	if glyph.is_empty():
		# A gamepad cap is just its direction, drawn big.
		_draw_arrow(center + Vector2(0, sink), corner, 12.0 * grow, Color(UiThemeScript.INK, alpha), 4.0)
		return
	if corner == Vector2.ZERO:
		_draw_text(glyph, center + Vector2(0, 11 + sink), roundi(30 * grow), Color(UiThemeScript.INK, alpha))
		return
	# Letter a little left, its arrow drawn beside it: "A ←" on one cap.
	_draw_text(glyph, center + Vector2(-side * 0.14, 11 + sink), roundi(28 * grow), Color(UiThemeScript.INK, alpha))
	_draw_arrow(center + Vector2(side * 0.27, sink), corner, 7.0 * grow, Color(UiThemeScript.INK, alpha), 3.0)


## An arrow as lines (shaft and head): the fonts' arrow glyphs came out as
## smudges at HUD size.
func _draw_arrow(center: Vector2, toward: Vector2, half: float, color: Color, width: float) -> void:
	var side := Vector2(-toward.y, toward.x)
	var tip: Vector2 = center + toward * half
	draw_line(center - toward * half, tip, color, width, true)
	draw_polyline(PackedVector2Array([tip - toward * half * 0.7 + side * half * 0.7, tip,
		tip - toward * half * 0.7 - side * half * 0.7]), color, width, true)


## Over the card for a moment after a wrong key: unmistakably "no".
func _draw_wrong_banner() -> void:
	var alpha: float = clampf(_error_flash * 1.6, 0.0, 1.0)
	var rect := Rect2(Vector2(size.x * 0.5 - 96, 0), Vector2(192, 24))
	_box(rect, Color(UiThemeScript.RED, alpha), Color(UiThemeScript.INK, alpha), 8, 2)
	_draw_text("¡%s!" % _wrong_text, rect.get_center() + Vector2(0, 7), 17, Color(UiThemeScript.WHITE, alpha))


## A ring spreading from a point, over and over: "press here".
func _draw_ripple(center: Vector2, period: float) -> void:
	var t: float = fmod(_time / period, 1.0)
	draw_arc(center, 16.0 + t * 26.0, 0.0, TAU, 32, Color(UiThemeScript.YELLOW, (1.0 - t) * 0.8), 3.0, true)


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
