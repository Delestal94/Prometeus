extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_player_colors.gd
## Covers the per-peer body/hand coloring added in docs/direccion-visual.md's
## "identificación visual entre jugadores" decision: until this, there was no
## visible body mesh at all (only viewmodel hands attached to each player's
## own camera, so a teammate literally had nothing to look at) -- this checks
## the body actually gets built, colored, and that different peers get
## different colors instead of everyone looking identical.

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

	var body: MeshInstance3D = _find_body(first)
	_expect(body != null, "A body mesh actually exists now, not just the viewmodel hands")
	_expect(body.mesh is CapsuleMesh, "Placeholder body is a capsule, matching the collision shape")

	var left_hand: MeshInstance3D = first.get_node(^"Head/Camera3D/LeftHand")
	var right_hand: MeshInstance3D = first.get_node(^"Head/Camera3D/RightHand")
	_expect(left_hand.material_override != null and right_hand.material_override != null,
		"Both hands get their own colored material, not the shared default skin tone")

	var second: Node = player_scene.instantiate()
	second.set_multiplayer_authority(2)
	root.add_child(second)
	await process_frame

	var first_color: Color = (body.material_override as StandardMaterial3D).albedo_color
	var second_color: Color = (_find_body(second).material_override as StandardMaterial3D).albedo_color
	_expect(first_color != second_color, "Different peers get visibly different colors (got the same one for both)")

	# Same peer id always resolves to the same color -- no randomness, no
	# dependency on join order, so it stays consistent across a whole session
	# (and across every other client's own view of the same player).
	var third: Node = player_scene.instantiate()
	third.set_multiplayer_authority(1)
	root.add_child(third)
	await process_frame
	var third_color: Color = (_find_body(third).material_override as StandardMaterial3D).albedo_color
	_expect(third_color == first_color, "The same peer id deterministically gets the same color every time")

	first.free()
	second.free()
	third.free()
	if _failures == 0:
		print("PASS: every player has a visible, distinctly-colored body, deterministic by peer id")
	quit(_failures)


func _find_body(player: Node) -> MeshInstance3D:
	for child: Node in player.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is CapsuleMesh:
			return child
	return null


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
