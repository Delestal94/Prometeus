extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_player_colors.gd
## Covers the per-peer body/hand coloring added in docs/direccion-visual.md's
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

	var left_hand: MeshInstance3D = first.get_node(^"Head/Camera3D/LeftHand")
	var right_hand: MeshInstance3D = first.get_node(^"Head/Camera3D/RightHand")
	_expect(left_hand.material_override != null and right_hand.material_override != null,
		"Both hands get their own colored material, not the shared default skin tone")
	_expect(left_hand.get_node_or_null(^"Glove") != null and right_hand.get_node_or_null(^"Glove") != null,
		"Both first-person anchors contain the authored glove meshes with fingers")

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
	if _failures == 0:
		print("PASS: every player has a visible, distinctly-colored rigged body, deterministic by peer id")
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
	]
	return colors[peer_id % colors.size()]


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
