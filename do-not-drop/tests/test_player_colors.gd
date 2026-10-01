extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_player_colors.gd
## Covers the per-peer body coloring added in docs/direccion-visual.md's
## "identificación visual entre jugadores" decision: until this, there was no
## visible body mesh at all (only viewmodel hands attached to each player's
## own camera, so a teammate literally had nothing to look at) -- this checks
## the body actually gets built, colored, and that different peers get
## different colors instead of everyone looking identical.
##
## Rewritten 2026-09-22: BodyVisual is the rigged low-poly character now
## (assets/models/characters/sm_char_player_lowpoly.glb), not a bare capsule
## -- color lives on a per-instance surface override of the suit material
## nested inside it, found by walking the tree instead of assumed to be a
## direct child.
##
## N-228.3: the palette has one colour per seat of a full room (>= MAX_PLAYERS),
## so slots 5..7 stop repeating 0..2. Checked here: the palette is as big as the
## room; its colours differ in CIE Lab by a margin, also after a deuteranopia and
## a protanopia simulation (Machado 2009, full severity) -- the first five were
## chosen before that check, so the old pairs only need a floor and the new
## slots a real margin; the results screen reuses the same colours; every colour
## has a key and a translated name (es and en) in CrewProgression; and every
## colour slot has its own callout voice pitch, all different.

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	# load() at runtime, not preload() at parse time: player.gd references the
	# NetworkManager autoload as a bare global, which isn't resolvable yet
	# while this script itself is still being compiled (see test_interaction.gd).
	var player_scene: PackedScene = load("res://scenes/gameplay/player/player.tscn")

	var first: Node = player_scene.instantiate()
	first.set_multiplayer_authority(1)
	root.add_child(first)
	await process_frame

	var body: Node3D = first.get_node(^"BodyVisual")
	_expect(body != null, "A body actually exists now, not just the viewmodel hands")
	var mesh_instance: MeshInstance3D = _find_mesh_instance(body)
	_expect(mesh_instance != null, "The rigged character's mesh is present inside BodyVisual")
	_expect(_find_skeleton(body) != null, "The rigged character's Skeleton3D is present inside BodyVisual")

	# The only hands on screen are a character's: nothing hangs off the
	# first-person camera, and the seat cameras carry none either.
	var camera: Camera3D = first.get_node(^"Head/Camera3D")
	_expect(camera.find_children("*", "VisualInstance3D", true, false).is_empty(),
		"No stand-in hands (or any mesh) float in front of the first-person camera")
	var seat_camera: Node = load("res://scenes/presentation/first_person_camera.tscn").instantiate()
	_expect(seat_camera.find_children("*", "VisualInstance3D", true, false).is_empty(),
		"No stand-in hands float in front of the seat cameras")
	seat_camera.free()

	var second: Node = player_scene.instantiate()
	second.set_multiplayer_authority(2)
	root.add_child(second)
	await process_frame

	var first_color: Color = _suit_color(first)
	var second_color: Color = _suit_color(second)
	_expect(first_color != second_color, "Different peers get visibly different colors (got the same one for both)")

	# Same peer id always resolves to the same color -- no randomness, no
	# dependency on join order, so it stays consistent across a whole session
	# (and across every other client's own view of the same player).
	var third: Node = player_scene.instantiate()
	third.set_multiplayer_authority(1)
	root.add_child(third)
	await process_frame
	var third_color: Color = _suit_color(third)
	_expect(third_color == first_color, "The same peer id deterministically gets the same color every time")

	# Recoloring one instance must not have mutated the shared glTF material
	# resource -- otherwise every player (and every future non-player use of
	# this asset) would silently end up sharing whichever peer built last.
	var fresh: Node = player_scene.instantiate()
	fresh.set_multiplayer_authority(3)
	root.add_child(fresh)
	await process_frame
	var expected_third_color: Color = _suit_color_for_peer(3)
	_expect(_suit_color(fresh) == expected_third_color,
		"A brand-new instance still gets its own peer's color, not a leaked one from an earlier instance")

	first.free()
	second.free()
	third.free()
	fresh.free()
	_check_palette()
	if _failures == 0:
		print("PASS: every player has a visible, distinctly-colored rigged body, deterministic by peer id; "
				+ "the palette has a distinguishable colour, name and voice for every seat")
	quit(_failures)


func _suit_color(player: Node) -> Color:
	var mesh_instance: MeshInstance3D = _find_mesh_instance(player.get_node(^"BodyVisual"))
	return (mesh_instance.get_surface_override_material(0) as StandardMaterial3D).albedo_color


## Mirrors Player.PLAYER_COLORS' indexing without importing player.gd's
## constant directly, so this genuinely checks the observable result instead
## of just echoing the same lookup back at itself.
func _suit_color_for_peer(peer_id: int) -> Color:
	var colors: Array[Color] = [
		Color("83e2ba"), Color("f4c562"), Color("f47e6d"), Color("6db3d6"), Color("c9a0e0"),
		Color("e8eaf0"), Color("5f7fd0"), Color("4f9a8f"),
	]
	return colors[peer_id % colors.size()]


## N-228.3: one distinguishable colour, name and voice per seat.
func _check_palette() -> void:
	var player_script: GDScript = load("res://scripts/gameplay/player/player.gd")
	var palette: Array = player_script.get_script_constant_map()["PLAYER_COLORS"]
	var max_players: int = int(load("res://scripts/core/network_manager.gd").get_script_constant_map()["MAX_PLAYERS"])
	_expect(palette.size() >= max_players,
		"A colour for every seat: %d colours for %d players" % [palette.size(), max_players])

	# The first five keep their order: saves and tests index by it.
	var original: Array[Color] = [
		Color("83e2ba"), Color("f4c562"), Color("f47e6d"), Color("6db3d6"), Color("c9a0e0"),
	]
	for i: int in original.size():
		_expect(palette[i] == original[i], "Slot %d keeps its original colour" % i)

	var views: Dictionary = {&"normal": 25.0, &"deuteranopia": 12.0, &"protanopia": 12.0}
	var floors: Dictionary = {&"normal": 25.0, &"deuteranopia": 4.0, &"protanopia": 4.0}
	for i: int in palette.size():
		for j: int in range(i + 1, palette.size()):
			_expect(palette[i] != palette[j], "Slots %d and %d have different colours" % [i, j])
			for view: StringName in views:
				var gap: float = _lab_distance(_seen(palette[i], view), _seen(palette[j], view))
				# Pairs among the original five: a floor (deuteranopia merges sky and violet a
				# little, a known limit of the old colours; names and the crew panel still
				# tell them apart). Any pair with a new slot: the real margin.
				var needed: float = float(views[view]) if j >= original.size() else float(floors[view])
				_expect(gap >= needed, "Slots %d and %d are told apart in %s (distance %.1f, needs %.1f)"
						% [i, j, view, gap, needed])

	# The results screen paints from the same palette, not a copy.
	var results: GDScript = load("res://scripts/ui/hud/hud_results.gd")
	_expect(results.get_script_constant_map()["RESULT_PLAYER_COLORS"] == palette,
		"The results screen uses the player colours")

	# Names: a key and a translated es/en name per colour.
	var crew: Dictionary = load("res://scripts/core/crew_progression.gd").get_script_constant_map()
	var keys: Array = crew["PLAYER_COLOR_KEYS"]
	var names: Array = crew["PLAYER_COLOR_NAMES"]
	_expect(keys.size() == palette.size() and names.size() == palette.size(),
		"Every colour has a key and a name (%d keys, %d names, %d colours)"
		% [keys.size(), names.size(), palette.size()])
	var distinct_keys: Dictionary = {}
	for key: Variant in keys:
		distinct_keys[key] = true
	_expect(distinct_keys.size() == keys.size(), "The colour keys are all different")
	var strings: Dictionary = _read_translations("res://translations/strings_ui.csv")
	for name_key: Variant in names:
		var row: Array = strings.get(String(name_key), [])
		_expect(row.size() >= 2 and String(row[0]) != "" and String(row[1]) != "",
			"%s has a Spanish and an English name in strings_ui.csv" % name_key)
	var spanish: Dictionary = {}
	for name_key: Variant in names:
		var row: Array = strings.get(String(name_key), ["", ""])
		spanish[row[0]] = true
	_expect(spanish.size() == names.size(), "The colour names are all different")

	# Voices: one pitch per slot, all different.
	var pitches: Array = load("res://modules/synth_audio/synth_audio_scenes.gd") \
			.get_script_constant_map()["CALLOUT_VOICE_PITCHES"]
	_expect(pitches.size() >= palette.size(), "A callout voice for every colour (%d pitches)" % pitches.size())
	for i: int in range(1, pitches.size()):
		_expect(float(pitches[i]) >= float(pitches[i - 1]) * 1.15,
			"Voice %d is at least 15%% above voice %d (%s Hz vs %s Hz)" % [i, i - 1, pitches[i], pitches[i - 1]])


## {key: [es, en]} from a translations CSV (header: keys,es,en).
func _read_translations(path: String) -> Dictionary:
	var result: Dictionary = {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_expect(false, "%s opens" % path)
		return result
	file.get_csv_line() # header
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() >= 3:
			result[line[0]] = [line[1], line[2]]
	return result


## The colour as someone with that vision sees it (Machado 2009, severity 1.0).
func _seen(color: Color, view: StringName) -> Color:
	var matrix: Array = []
	match view:
		&"deuteranopia":
			matrix = [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413],
					[-0.011820, 0.042940, 0.968881]]
		&"protanopia":
			matrix = [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216],
					[-0.003882, -0.048116, 1.051998]]
		_:
			return color
	var linear: Color = color.srgb_to_linear()
	var channels: Array[float] = []
	for row: Array in matrix:
		channels.append(clampf(row[0] * linear.r + row[1] * linear.g + row[2] * linear.b, 0.0, 1.0))
	return Color(channels[0], channels[1], channels[2]).linear_to_srgb()


## CIE76 distance in Lab (D65): ~2.3 is a just-noticeable difference.
func _lab_distance(a: Color, b: Color) -> float:
	var lab_a: Vector3 = _lab(a)
	var lab_b: Vector3 = _lab(b)
	return lab_a.distance_to(lab_b)


func _lab(color: Color) -> Vector3:
	var linear: Color = color.srgb_to_linear()
	var x: float = (0.4124 * linear.r + 0.3576 * linear.g + 0.1805 * linear.b) / 0.95047
	var y: float = 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b
	var z: float = (0.0193 * linear.r + 0.1192 * linear.g + 0.9505 * linear.b) / 1.08883
	var fx: float = _lab_f(x)
	var fy: float = _lab_f(y)
	var fz: float = _lab_f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
