extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_skin_profile.gd
## S-311.70: selection, persistence, live preview and the active player contract.

const Profile := preload("res://scripts/core/unlock_manager.gd")
const Catalog := preload("res://scripts/gameplay/player/gel/gel_skin_catalog.gd")
const PROFILE_PATH: String = "user://gel_skin_profile_test.json"

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_profile()
	await _check_players()
	await _check_preview()
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	if _failures == 0:
		print("PASS: gel skin preview, profile and per-player replication contract")
	quit(_failures)


func _check_profile() -> void:
	var profile := Profile.new()
	profile.storage_path = PROFILE_PATH
	profile.reset_profile()
	_expect(profile.selected_gel_skin == Catalog.DEFAULT_ID, "a new profile starts with milk")
	_expect(profile.select_gel_skin(&"night_neon"), "a catalog skin can be selected")
	_expect(not profile.select_gel_skin(&"missing"), "an unknown skin ID is rejected")
	var restored := Profile.new()
	restored.storage_path = PROFILE_PATH
	restored.load_profile()
	_expect(restored.selected_gel_skin == &"night_neon", "the selected skin survives save/load")
	profile.free()
	restored.free()


func _check_players() -> void:
	var scene: PackedScene = load("res://scenes/gameplay/player/player.tscn")
	var first: Player = scene.instantiate()
	first.name = "Player_1"
	root.add_child(first)
	var second: Player = scene.instantiate()
	second.name = "Player_2"
	root.add_child(second)
	await process_frame
	var first_state: Node = first.get_node(^"GelProportions")
	var second_state: Node = second.get_node(^"GelProportions")
	first_state.set(&"skin_id", &"layered_gummy")
	second_state.set(&"skin_id", &"holographic")
	await process_frame
	_expect(_applied_skin(first) == &"layered_gummy", "the local body applies its selected skin")
	_expect(_applied_skin(second) == &"holographic", "another body keeps its own skin instance")
	var sync := first_state.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var path := NodePath(".:skin_id")
	_expect(sync.replication_config.has_property(path), "skin ID is in the replication contract")
	_expect(sync.replication_config.property_get_spawn(path), "late joiners receive the skin at spawn")
	_expect(sync.replication_config.property_get_replication_mode(path) \
			== SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE, "skin travels only when changed")
	first.free()
	second.free()


func _check_preview() -> void:
	var profile: Node = root.get_node(^"/root/UnlockManager")
	profile.call(&"reset_profile")
	var panel: Control = load("res://scripts/ui/cosmetics_panel.gd").new()
	root.add_child(panel)
	await process_frame
	var cards: Array[Node] = panel.find_children("Skin_*", "Button", true, false)
	_expect(cards.size() == Catalog.all_skins().size(), "every catalog skin has a preview card")
	var card := panel.find_child("Skin_slow_lava", true, false) as Button
	_expect(card != null, "animated skins are present in customization")
	if card != null:
		card.pressed.emit()
		await process_frame
		_expect(profile.get(&"selected_gel_skin") == &"slow_lava", "picking a card saves the skin")
		var preview: Control = panel.find_child("CharacterPreview", true, false)
		_expect(_applied_skin(preview.get(&"gel_mannequin")) == &"slow_lava",
			"the real gel preview updates immediately")
	panel.free()
	profile.call(&"reset_profile")


func _applied_skin(owner: Node) -> StringName:
	var body: Node = owner.get_node_or_null(^"BodyVisual")
	if body == null and owner is Node3D:
		body = owner
	var mesh := PlayerAppearance.find_mesh_instance(body)
	if mesh == null:
		return &""
	var color: Color = mesh.get_instance_shader_parameter(&"gel_color")
	var surface: Vector4 = mesh.get_instance_shader_parameter(&"gel_skin_surface")
	for definition: Resource in Catalog.all_skins():
		var mode := float(definition.get(&"interior_mode"))
		if int(definition.get(&"animation_mode")) != 0:
			mode = 5.0 + float(definition.get(&"animation_mode"))
		if color == definition.get(&"color") and is_equal_approx(surface.z, mode):
			return definition.get(&"id")
	return &""


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
