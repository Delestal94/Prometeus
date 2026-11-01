extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_gel_character.gd
## S-311.99 integration gate: one saved/customized look drives the real rig,
## materials and cosmetics, stays inside its budgets and exposes the complete
## spawn/on-change contract used by the two-process network check.

const PLAYER_SCENE := preload("res://scenes/gameplay/player/player.tscn")
const Profile := preload("res://scripts/core/unlock_manager.gd")
const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Presets := preload("res://scripts/gameplay/player/gel/gel_proportion_presets.gd")
const Ragdoll := preload("res://scripts/gameplay/player/gel/gel_active_ragdoll.gd")
const CostumeLibrary := preload("res://scripts/gameplay/player/gel/gel_costume_library.gd")
const AccessoryLibrary := preload("res://scripts/gameplay/player/gel/gel_accessory_library.gd")
const Bench := preload("res://tests/bench_gel_character.gd")
const PROFILE_PATH: String = "user://gel_character_integration_test.json"
const REQUIRED_CLIPS: Array[StringName] = [
	&"Idle", &"Walk", &"Run", &"Jump", &"PickUpPackage", &"Sit",
	&"Pancake", &"MeltAndReturn", &"VictoryDance", &"Conga",
]
const APPEARANCE_PATHS: Array[NodePath] = [
	^".:packet", ^".:skin_id", ^".:hair_id", ^".:eyebrows_id",
	^".:moustache_id", ^".:costume_id", ^".:accessory_id",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_cleanup_profile()
	_check_profile_round_trip()
	var player: Player = PLAYER_SCENE.instantiate()
	player.set_multiplayer_authority(2)
	root.add_child(player)
	await process_frame
	await process_frame
	player.set(&"cosmetic_id", &"mint_uniform")
	var state: Node = player.get_node(^"GelProportions")
	state.set(&"packet", Proportions.packet_from_dictionary({
		&"total_height": 1.14, &"head_size": 0.87, &"general_thickness": -0.45,
	}))
	state.set(&"skin_id", &"holographic")
	state.set(&"hair_id", &"braid")
	state.set(&"eyebrows_id", &"arched")
	state.set(&"moustache_id", &"pencil")
	state.set(&"costume_id", &"pirate")
	state.set(&"accessory_id", &"scarf")
	await process_frame
	await process_frame
	var body: Node3D = player.get_node(^"BodyVisual")
	_check_asset_contract(body)
	_check_live_look(player, body)
	_check_network_contract(player)
	await _check_ragdoll(body, state.get(&"proportions") as GelBodyProportions)
	await _check_vest_fit(body, state)
	player.free()
	_cleanup_profile()
	if _failures == 0:
		print("PASS: complete gel customization persists, renders, fits budgets and replicates")
	quit(_failures)


## S-305: the replicated vest id mounts the shell accessory and the live proportions fit it.
func _check_vest_fit(body: Node3D, state: Node) -> void:
	state.set(&"accessory_id", &"reflective_vest")
	await process_frame
	await process_frame
	var vest: Node = body.find_child("GelAccessory_reflective_vest", false, false)
	_expect(vest != null, "the replicated vest id mounts the vest on the live body")
	if vest == null:
		return
	var back: Node3D = vest.find_child("VestBack", true, false) as Node3D
	var proportions: GelBodyProportions = state.get(&"proportions") as GelBodyProportions
	_expect(back != null and absf(back.position.y - 1.13 * proportions.total_height) < 0.001,
		"the live vest is fitted to the replicated body proportions")


func _check_profile_round_trip() -> void:
	var profile := Profile.new()
	profile.storage_path = PROFILE_PATH
	profile.reset_profile()
	profile.set(&"selected_cosmetic", &"mint_uniform")
	profile.set(&"selected_gel_face", &"happy")
	profile.set(&"selected_gel_skin", &"holographic")
	profile.set(&"selected_gel_hair", &"quiff")
	profile.set(&"selected_gel_eyebrows", &"soft")
	profile.set(&"selected_gel_moustache", &"pencil")
	profile.set(&"selected_gel_costume", &"courier")
	profile.set(&"selected_gel_accessory", &"glasses")
	var preset: GelBodyProportions = Presets.load_preset(&"flaca")
	preset.head_size = 0.87
	profile.set_gel_proportions(preset.as_dictionary())
	profile.save_profile()
	var restored := Profile.new()
	restored.storage_path = PROFILE_PATH
	restored.load_profile()
	for field: StringName in [
		&"selected_cosmetic", &"selected_gel_face", &"selected_gel_skin", &"selected_gel_hair",
		&"selected_gel_eyebrows", &"selected_gel_moustache",
		&"selected_gel_costume", &"selected_gel_accessory",
	]:
		_expect(restored.get(field) == profile.get(field), "%s survives profile save/load" % field)
	_expect(restored.gel_proportions == profile.gel_proportions,
		"all gel proportions survive beside the cosmetic IDs")
	profile.free()
	restored.free()


func _check_asset_contract(body: Node3D) -> void:
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(body)
	var animations: AnimationPlayer = PlayerAppearance.find_animation_player(body)
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(body)
	_expect(skeleton != null and skeleton.get_bone_count() == 26,
		"the active player uses the twenty-six-bone gel rig")
	_expect(animations != null, "the active player exposes its animation library")
	if animations != null:
		for clip: StringName in REQUIRED_CLIPS:
			_expect(animations.has_animation(clip), "the integrated rig retains %s" % clip)
	_expect(mesh != null and mesh.mesh != null, "the integrated body has renderable geometry")
	if mesh == null or mesh.mesh == null:
		return
	_expect(mesh.mesh.get_blend_shape_count() == 11, "the active body retains all eleven morphs")
	_expect(mesh.material_override is ShaderMaterial,
		"the active body uses the shared gel shader material")
	var body_triangles: int = _triangle_count(mesh.mesh)
	_expect(body_triangles <= 20_000, "LOD0 stays inside its 20k-triangle body budget")
	_expect(is_equal_approx(Bench.GPU_BUDGET_MS, 0.5),
		"the rendered four-character gate keeps the +0.5 ms GPU budget")


func _check_live_look(player: Player, body: Node3D) -> void:
	var state: Node = player.get_node(^"GelProportions")
	var mesh: MeshInstance3D = PlayerAppearance.find_mesh_instance(body)
	var hair: Node = body.find_child("GelHair", true, false)
	var costume: Node = body.find_child("GelCostume_*", false, false)
	var accessory: Node = body.find_child("GelAccessory_*", false, false)
	_expect(hair != null and StringName(hair.get(&"style_id")) == state.get(&"hair_id"),
		"the selected hairstyle is mounted on the live skeleton")
	_expect(body.find_child("GelEyebrows_*", true, false) != null,
		"the selected eyebrows are mounted on the live face")
	_expect(body.find_child("GelMoustache_*", true, false) != null,
		"the selected moustache is mounted on the live face")
	_expect(costume != null and costume.get_meta(&"gel_costume_id", &"") == state.get(&"costume_id"),
		"the selected fitted costume is present")
	_expect(accessory != null and accessory.get_meta(&"gel_accessory_id", &"") == state.get(&"accessory_id"),
		"the selected accessory is present")
	if costume != null and accessory != null:
		var cosmetic_triangles: int = CostumeLibrary.triangle_count(costume) \
			+ AccessoryLibrary.triangle_count(accessory)
		_expect(cosmetic_triangles <= 10_000,
			"the combined costume and accessory stay within their authored budgets")
	_expect(mesh != null and mesh.get_instance_shader_parameter(&"gel_skin_surface") != null,
		"the selected skin reaches the live material uniforms")
	if mesh != null:
		var packed: float = float(mesh.get_instance_shader_parameter(&"gel_brightness"))
		var expected_accent: Color = PlayerAppearance.unpack_gel_team_color(
			PlayerAppearance.pack_gel_team_color(1.0, Color("83e2ba")))
		_expect(PlayerAppearance.unpack_gel_team_color(packed) == expected_accent,
			"the saved uniform colour reaches the live gel accent")


func _check_network_contract(player: Player) -> void:
	var state: Node = player.get_node(^"GelProportions")
	var sync := state.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	for path: NodePath in APPEARANCE_PATHS:
		_expect(sync.replication_config.has_property(path), "%s is in the appearance wire contract" % path)
		_expect(sync.replication_config.property_get_spawn(path), "%s reaches late joiners" % path)
		_expect(sync.replication_config.property_get_replication_mode(path) \
			== SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE, "%s travels only on change" % path)
	var player_sync := player.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	var face_path := NodePath("GelFaceReactions:base_face_id")
	_expect(player_sync.replication_config.has_property(face_path)
		and player_sync.replication_config.property_get_spawn(face_path),
		"the chosen face remains in the spawn replication contract")


func _check_ragdoll(body: Node3D, proportions: GelBodyProportions) -> void:
	var ragdoll: GelActiveRagdoll = Ragdoll.new()
	body.add_child(ragdoll)
	_expect(ragdoll.setup(body, proportions, 31199),
		"the integrated body builds its active-ragdoll rig")
	_expect(ragdoll.start_ragdoll(Vector3(4.0, 5.0, -3.0), Vector3.ZERO, 31199),
		"the integrated ragdoll accepts a deterministic impact")
	await physics_frame
	await physics_frame
	var state: Dictionary = ragdoll.stability_state()
	_expect(bool(state[&"finite"]), "the integrated ragdoll remains finite")
	_expect(float(state[&"stretch_ratio"]) <= GelActiveRagdoll.MAX_JOINT_STRETCH_RATIO + 0.001,
		"the integrated ragdoll respects its joint-stretch cap")
	ragdoll.stop_ragdoll()
	_expect(bool(ragdoll.stability_state()[&"settled"]), "the integrated ragdoll settles cleanly")


func _triangle_count(mesh: Mesh) -> int:
	var total: int = 0
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	return total


func _cleanup_profile() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
