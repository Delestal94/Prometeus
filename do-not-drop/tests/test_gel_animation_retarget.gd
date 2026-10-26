extends SceneTree
## S-311.85: every gel preset reuses the complete clip library through named
## bones, and depot workers plus the forklift operator use that same contract.

const GEL_SCENE: PackedScene = preload("res://assets/models/characters/gel/gel_body_lod0.glb")
const PRESETS: Array[StringName] = [
	&"delgada", &"flaca", &"rellena", &"petisa", &"cabezona", &"larguirucha",
]
const CLIPS: Array[StringName] = [
	&"Idle", &"Walk", &"Stroll", &"Run", &"Jump", &"PickUpPackage", &"PickUpHigh",
	&"Sit", &"TurnInPlace", &"CarryWalk", &"ThrowPackage", &"DropPackage", &"Drive",
	&"EnterTruck", &"ExitTruck", &"RingDoorbell", &"Stumble", &"Slip", &"Pushed",
	&"BoxHit", &"Scared", &"Dizzy", &"ShakeOffWater",
	&"Wave", &"Clap", &"Facepalm", &"Shrug", &"Point", &"ThumbsUp",
	&"MeltAndReturn", &"ShakeLikeDog",
	&"Pancake", &"GumStretch", &"BallBounce", &"SplitAndJoin", &"ColdShiver",
	&"Inflate", &"SimpleStep", &"Robot", &"Disco", &"FloorWorm", &"Headbang",
	&"VictoryDance", &"Flan", &"Conga",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gel: Node3D = GEL_SCENE.instantiate()
	root.add_child(gel)
	await process_frame
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(gel)
	var player: AnimationPlayer = PlayerAppearance.find_animation_player(gel)
	var shaper := GelBodyShaper.new()
	_expect(skeleton != null and player != null and shaper.setup(gel),
		"the shared gel model exposes its named rig, shaper and clip library")
	if skeleton != null and player != null:
		_check_named_track_targets(player, skeleton)
		_check_every_preset(player, skeleton, shaper)
	gel.free()
	await _check_depot_characters()
	if _failures == 0:
		print("PASS: all gel presets and depot NPCs reuse the 45 named-bone clips")
	quit(_failures)


func _check_named_track_targets(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	var unresolved: Array[String] = []
	for clip: StringName in CLIPS:
		if not player.has_animation(clip):
			continue
		var animation: Animation = player.get_animation(clip)
		for track: int in animation.get_track_count():
			if animation.track_get_type(track) not in [
				Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D,
			]:
				continue
			var path: NodePath = animation.track_get_path(track)
			if path.get_subname_count() == 0:
				unresolved.append("%s:%s" % [clip, path])
				continue
			var bone_name: StringName = path.get_subname(path.get_subname_count() - 1)
			if skeleton.find_bone(bone_name) < 0:
				unresolved.append("%s:%s" % [clip, path])
	_expect(unresolved.is_empty(),
		"every transform track resolves by bone name (unresolved: %s)" % [unresolved.slice(0, 5)])


func _check_every_preset(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	shaper: GelBodyShaper
) -> void:
	for preset_id: StringName in PRESETS:
		var proportions: GelBodyProportions = GelProportionPresets.load_preset(preset_id)
		_expect(proportions != null and shaper.apply(proportions), "%s applies to the shared rig" % preset_id)
		if proportions == null:
			continue
		for clip: StringName in CLIPS:
			_expect(player.has_animation(clip), "%s keeps clip %s" % [preset_id, clip])
			if not player.has_animation(clip):
				continue
			var animation: Animation = player.get_animation(clip)
			var finite: bool = true
			for at: float in [0.0, animation.length * 0.5, maxf(animation.length - 0.001, 0.0)]:
				player.play(clip)
				player.seek(at, true)
				player.advance(0.0)
				skeleton.force_update_all_bone_transforms()
				for bone: int in skeleton.get_bone_count():
					finite = finite and skeleton.get_bone_global_pose(bone).is_finite()
			_expect(finite, "%s plays %s with finite bone poses" % [preset_id, clip])


func _check_depot_characters() -> void:
	for preset_id: StringName in PRESETS:
		var worker := DepotWorker.new()
		worker.proportion_preset = preset_id
		root.add_child(worker)
		await process_frame
		var body := worker.get_node_or_null(^"Body") as Node3D
		var player: AnimationPlayer = PlayerAppearance.find_animation_player(body)
		_expect(body != null and body.get_meta(&"gel_proportion_preset", &"") == preset_id,
			"depot worker uses gel preset %s" % preset_id)
		_expect(player != null and CLIPS.all(func(clip: StringName) -> bool: return player.has_animation(clip)),
			"depot worker %s exposes the complete shared clip library" % preset_id)
		worker.free()

	var forklift := DepotForklift.new()
	root.add_child(forklift)
	forklift.set_physics_process(false)
	await process_frame
	var operator := forklift.get_node_or_null(^"Operator") as Node3D
	var operator_player: AnimationPlayer = PlayerAppearance.find_animation_player(operator)
	_expect(operator != null and operator.get_meta(&"gel_proportion_preset", &"") == DepotForklift.OPERATOR_PRESET,
		"the forklift operator uses its named gel preset")
	_expect(operator_player != null and operator_player.has_animation(&"Idle"),
		"the forklift operator reuses the shared Idle clip")
	forklift.free()
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
