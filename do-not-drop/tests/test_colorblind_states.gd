extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_colorblind_states.gd
##
## Colour-blind safety of the expansion's requirements and states (D-1918, with D-0447 and D-0846), checked on the
## numbers instead of a capture with filters:
## - the colour-safe palette (UiTheme.OKABE_STATE_COLORS: ok, warning, danger) stays apart under simulated
##   deuteranopia and protanopia (Machado et al. 2009, full severity): every pair at least MIN_DISTANCE apart
##   (0-255 RGB, after the simulation), and so do ok and danger in the default palette under both;
## - with GameSettings.colorblind_palette on, the expansion's states take it (UiTheme.status): the day's HUD (money
##   in the red, late orders), the closing screen (income, costs, profit), the dispatch board (load bars, picked
##   rows), the arrows over the stations (supplies, late) and the packing table's marks (done, error); with it off
##   they keep the default palette. Every state also has a mark or a word besides its colour (tested where each
##   screen is: ✓ ○ ✗, ▼ with its line, "Pausa"...).
## The option is flipped with the settings' own save held (SettingsStore._loading), so the player's file is not
## touched, and put back as it was.

const MIN_DISTANCE: float = 60.0
## Machado, Oliveira & Fernandes (2009), severity 1.0, on linear RGB.
const DEUTERANOPIA: Array = [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413],
	[-0.011820, 0.042940, 0.968881]]
const PROTANOPIA: Array = [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216],
	[-0.003882, -0.048116, 1.051998]]

var _failures: int = 0
var _settings: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings = root.get_node_or_null(^"/root/GameSettings")
	_test_palette()
	if _settings == null:
		_expect(false, "GameSettings autoload present")
		quit(_failures)
		return
	var was: bool = bool(_settings.get(&"colorblind_palette"))
	for on: bool in [true, false]:
		_set_palette(on)
		await _test_screens(on)
	_set_palette(was)
	if _failures == 0:
		print("PASS: the colour-safe palette stays apart for red-green blindness and reaches every expansion state")
	quit(_failures)


func _set_palette(on: bool) -> void:
	_settings.set(&"_loading", true)
	_settings.set(&"colorblind_palette", on)
	_settings.set(&"_loading", false)


func _test_palette() -> void:
	var safe: Array[Color] = UiTheme.OKABE_STATE_COLORS
	for matrix: Array in [DEUTERANOPIA, PROTANOPIA]:
		for a: int in safe.size():
			for b: int in range(a + 1, safe.size()):
				var apart: float = _distance(_simulate(safe[a], matrix), _simulate(safe[b], matrix))
				_expect(apart >= MIN_DISTANCE, "safe states %d and %d stay %.0f apart (min %.0f)" % [a, b, apart,
					MIN_DISTANCE])
		var plain_ok: Color = _simulate(UiTheme.STATE_COLORS[0], matrix)
		var plain: float = _distance(plain_ok, _simulate(UiTheme.STATE_COLORS[2], matrix))
		_expect(plain >= MIN_DISTANCE, "default ok and danger stay %.0f apart" % plain)


func _test_screens(on: bool) -> void:
	var ok: Color = UiTheme.state_color(0, on)
	var warn: Color = UiTheme.state_color(1, on)
	var bad: Color = UiTheme.state_color(2, on)
	var tag: String = "palette %s" % ("on" if on else "off")
	var hud := CompanyDayHud.new()
	hud.money_of = func() -> int: return -10
	hud.orders_of = func() -> Array: return [{"due_min": 0}]
	hud.minute_of = func() -> float: return 600.0
	root.add_child(hud)
	await process_frame
	hud.refresh()
	_expect(_font(hud, "Money") == bad and _font(hud, "Orders") == warn, "%s: the HUD's red and late" % tag)
	hud.queue_free()
	var summary := DaySummaryPanel.new()
	root.add_child(summary)
	await process_frame
	summary.open({"day": 2, "income": 10, "costs": 50, "profit": -40, "income_by_reason": {"order_paid": 10},
		"cost_by_reason": {"rent": 50}})
	var totals: Array[Node] = summary.find_children("Total", "Label", true, false)
	_expect(totals.size() >= 2 and _color(totals[0]) == ok and _color(totals[1]) == bad,
		"%s: income ok, costs danger" % tag)
	_expect(_font(summary, "Profit") == bad, "%s: a loss is danger" % tag)
	summary.queue_free()
	var picked: Color = DispatchBoardPanel.row_color(DispatchBoardPanel.PICKED, on)
	_expect(DispatchBoardPanel.fill_color(0.9, on) == warn and picked == ok,
		"%s: the dispatch board's bars and picked rows" % tag)
	var marks := ShedIndicators.new()
	marks.pieces_of = func() -> Array: return [{"uid": &"d", "id": &"zone"}]
	marks.role_of = func(_id: StringName) -> StringName: return &"dispatch"
	marks.orders_of = func() -> Array: return [{"due_min": 0}]
	marks.minute_of = func() -> float: return 10.0
	root.add_child(marks)
	await process_frame
	marks.set_process(false)
	marks.refresh()
	var arrow := marks.get_node_or_null(^"Need_d") as Label3D
	_expect(arrow != null and arrow.modulate == bad, "%s: a late arrow is danger" % tag)
	marks.queue_free()
	var vfx := PackingVfx.new()
	root.add_child(vfx)
	await process_frame
	var done: Node3D = vfx.play(PackingVfx.KIND_DONE, Vector3.ZERO)
	var error: Node3D = vfx.play(PackingVfx.KIND_ERROR, Vector3.ZERO)
	_expect((done.get_node(^"Mark") as Label3D).modulate.is_equal_approx(ok)
		and (error.get_node(^"Mark") as Label3D).modulate.is_equal_approx(bad), "%s: the packing marks" % tag)
	vfx.queue_free()
	await process_frame


func _font(screen: Node, node_name: String) -> Color:
	return _color(screen.find_child(node_name, true, false))


func _color(node: Node) -> Color:
	return (node as Control).get_theme_color(&"font_color") if node is Control else Color.TRANSPARENT


static func _simulate(color: Color, matrix: Array) -> Color:
	var linear: Color = color.srgb_to_linear()
	var rgb: Array[float] = [linear.r, linear.g, linear.b]
	var out: Array[float] = []
	for row: Array in matrix:
		out.append(clampf(row[0] * rgb[0] + row[1] * rgb[1] + row[2] * rgb[2], 0.0, 1.0))
	return Color(out[0], out[1], out[2]).linear_to_srgb()


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() * 255.0


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error("FAIL: " + description)
		_failures += 1
