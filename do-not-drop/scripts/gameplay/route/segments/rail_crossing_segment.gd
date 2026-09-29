extends RouteSegment
class_name RailCrossingSegment
## A level crossing (docs/tareas-nacho.md #63): tracks across the road, red
## lights and a crossbuck, and every so often the barriers come down and a
## short train goes by -- a forced stop in the middle of a delivery.
##
## Whether this crossing closes is drawn from the world seed and where the
## segment sits, so every peer agrees. *When* it closes is the host's call:
## each peer used to trigger it off its own copy of the truck, which on a
## client arrives late through interpolation, and a client loading in mid-
## crossing started from scratch -- so the barrier and train a client saw
## weren't the ones the host's physics was running. Now the host starts the
## cycle for everyone (_begin_cycle), a client that builds the segment asks
## for the phase it's in (_request_state), and every peer runs the same
## timers from there. Only the host's physics decides anything, and there the
## barrier arms and train cars are solid.
##
## What you see is imported art (assets/tools/build_rail_crossing.py, N-129 /
## N-130): track, signal, barrier arm and a cartoon steam train. What you hit
## is still the boxes this script always used -- post, arm, one per car -- so
## the models can change without touching the driving or the network sync.
##
## The track runs into a tunnel at each end (playtest 2026-09-28: the train
## used to pop into existence in the open, 42 m down the line). The portals
## are rigid models (sm_env_rail_tunnel_portal.glb) at +-PORTAL_X; route.gd
## hands their mouths to RouteTerrain, which raises a hill behind each one and
## leaves a hole where the bore runs through it (tunnel_mouths()). The train
## starts inside one bore and ends inside the other, and a car is drawn only
## while some of it is short of a bore's black end (_place_train()).

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const APPROACH_TRIGGER: float = 55.0
const CLOSE_CHANCE: float = 0.6
const ARM_SECONDS: float = 1.3
const WARNING_SECONDS: float = 1.2
const TRAIN_SPEED: float = 17.0
const TRAIN_SPAN: float = 42.0
const GAUGE: float = 1.435
const LAMP_OFF := Color("5a1210")
const LAMP_ON := Color("ff2a1f")
const MODELS: String = "res://assets/models/environment/rail/"
const TRACK_MODEL: String = MODELS + "sm_env_rail_track.glb"
const SIGNAL_MODEL: String = MODELS + "sm_env_rail_crossing_signal.glb"
const ARM_MODEL: String = MODELS + "sm_env_rail_barrier_arm.glb"
const PORTAL_MODEL: String = MODELS + "sm_env_rail_tunnel_portal.glb"
## Where each portal's facade stands (local x), right where the track model's
## rails end, and the size of the tunnel behind it -- the same numbers as
## build_rail_crossing.py's PORTAL_* and BORE_LENGTH, which RouteTerrain needs
## to shape the hill and cut the bore out of it.
const PORTAL_X: float = TRAIN_SPAN
const BORE_LENGTH: float = 12.0
const BORE_HALF_WIDTH: float = 2.35
const BORE_CROWN: float = 6.05
const PORTAL_HALF_WIDTH: float = 5.6
const PORTAL_HEIGHT: float = 8.4
## How far into the bore the train waits, and goes, out of sight.
const TRAIN_HIDE_DEPTH: float = 6.0
## Half a car, couplers and cowcatcher included.
const CAR_HALF_LENGTH: float = 4.1
const CAR_SPACING: float = 8.0
## Front to back: the locomotive leads (+X, the way the train runs).
const TRAIN_MODELS: Array[String] = [
	MODELS + "sm_env_rail_locomotive.glb",
	MODELS + "sm_env_rail_wagon_boxcar.glb",
	MODELS + "sm_env_rail_wagon_tanker.glb",
	MODELS + "sm_env_rail_wagon_boxcar.glb",
]
## The lenses the signal model names; each gets its own glow material.
const LAMP_NODES: Array[StringName] = [&"LampLeft", &"LampRight"]
const CAR_SIZE := Vector3(7.5, 3.0, 2.6)

enum State { WAITING, WARNING, CLOSING, TRAIN, OPENING, DONE }

var will_close: bool = false
var state: int = State.WAITING
var track_z: float = 0.0
var _timer: float = 0.0
var _arms: Array[Node3D] = []
var _lamps: Array[StandardMaterial3D] = []
var _train: Array[AnimatableBody3D] = []
var _train_x: float = 0.0
var _bell: AudioStreamPlayer3D
## The cartoon steam train's own voice (playtest polish 2026-09-27): a
## "toot, tooooot" as it starts across, and a chugging loop for as long as
## it's actually on the tracks. Both hang on the locomotive (_train[0]) so
## they move with it for free.
var _train_horn: AudioStreamPlayer3D
var _train_chug: AudioStreamPlayer3D


func _init() -> void:
	length = 32.0


func _build() -> void:
	track_z = -length * 0.5
	_box("Ground", Vector3(24.0, 1.0, length), Vector3(0.0, -0.8, -length * 0.5), SHOULDER, true)
	_box("Road", Vector3(12.0, 0.4, length), Vector3(0.0, -0.2, -length * 0.5), ROAD, true)
	# Tracks: rails, sleepers and ballast across the road and well beyond
	# (TRAIN_SPAN each way, into the tunnels), a plank deck where they cross
	# it. No collision.
	# Rigid, not bent over the terrain: the ground along it is levelled anyway
	# (track_pads()), and its ends meet the portals' own rails, which sit on
	# that level while the hill rises behind them.
	var track: Node3D = _dress(_model("RailTrack", TRACK_MODEL, Vector3(0.0, 0.0, track_z)))
	if track != null:
		track.set_meta(&"rigid", true)
	for side: float in [-1.0, 1.0]:
		var portal: Node3D = _dress(_model("TunnelPortal" + ("Far" if side > 0.0 else "Near"), PORTAL_MODEL,
			Vector3(side * PORTAL_X, 0.0, track_z), 0.0 if side > 0.0 else PI))
		if portal != null:
			portal.set_meta(&"rigid", true)
	_box("CrossingStopLine", Vector3(6.0, 0.02, 0.35), Vector3(1.5, 0.03, track_z + 5.5), MARKING)
	_box("CrossingStopLine", Vector3(6.0, 0.02, 0.35), Vector3(-1.5, 0.03, track_z - 5.5), MARKING)
	for side: float in [-1.0, 1.0]:
		_build_signal(Vector3(side * 5.6, 0.0, track_z + side * 3.2), side)
	_build_train()
	_bell = AudioStreamPlayer3D.new()
	_bell.name = "CrossingBell"
	_bell.stream = SynthAudio.crossing_bell()
	_bell.unit_size = 10.0
	_bell.volume_db = WorldMix.CROSSING_BELL_DB
	_bell.max_distance = 70.0
	_bell.bus = &"SFX"
	_bell.position = Vector3(0.0, 2.5, track_z)
	add_child(_bell)
	var seed_value: int = 0
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network != null:
		seed_value = int(network.get(&"world_seed"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, roundi(global_position.x), roundi(global_position.z), &"rail"])
	will_close = rng.randf() < CLOSE_CHANCE
	if will_close and _is_online() and not _is_host():
		# Joining mid-crossing: pick it up where the host's is.
		if multiplayer.get_peers().has(1):
			_request_state.rpc_id(1)
		else:
			multiplayer.connected_to_server.connect(
				func() -> void: _request_state.rpc_id(1), CONNECT_ONE_SHOT)


## World-space points along the tracks where the ground should be level with
## the road (route.gd turns them into terrain pads): trains don't climb hills.
func track_pads() -> Array[Vector3]:
	var pads: Array[Vector3] = []
	var x: float = -TRAIN_SPAN
	while x <= TRAIN_SPAN:
		pads.append(transform * Vector3(x, 0.0, track_z))
		x += 7.0
	return pads


## Where each tunnel starts, for RouteTerrain.tunnels: {"at": Vector2 world
## x/z of the facade on the track axis, "dir": Vector2 into the hill}, and the
## portal's size.
func tunnel_mouths() -> Array[Dictionary]:
	var mouths: Array[Dictionary] = []
	for side: float in [-1.0, 1.0]:
		var at: Vector3 = transform * Vector3(side * PORTAL_X, 0.0, track_z)
		var inward: Vector3 = transform.basis * Vector3(side, 0.0, 0.0)
		mouths.append({"at": Vector2(at.x, at.z), "dir": Vector2(inward.x, inward.z).normalized(),
			"bore_half": BORE_HALF_WIDTH, "bore_length": BORE_LENGTH, "crown": BORE_CROWN,
			"face_half": PORTAL_HALF_WIDTH, "height": PORTAL_HEIGHT + 3.0})
	return mouths


## A post with the crossbuck, twin red lamps and a barrier arm that swings
## down across the whole road on this side of the tracks.
func _build_signal(at: Vector3, side: float) -> void:
	# The post's collision stays the box it always was; the model draws it.
	_hide_box_visual(_box("CrossingPost", Vector3(0.18, 3.4, 0.18), at + Vector3(0.0, 1.7, 0.0), CONCRETE, true))
	# The model faces +Z: the side = -1 signal (past the tracks, for the
	# traffic coming the other way) turns round.
	var signal_name: String = "CrossingSignalNear" if side > 0.0 else "CrossingSignalFar"
	var signal_model: Node3D = _dress(_model(signal_name, SIGNAL_MODEL, at, 0.0 if side > 0.0 else PI))
	for lamp_name: StringName in LAMP_NODES:
		var lens := signal_model.find_child(String(lamp_name), true, false) as MeshInstance3D if signal_model != null else null
		if lens == null:
			push_warning("Crossing signal model without %s" % lamp_name)
			continue
		var glow := StandardMaterial3D.new()
		glow.albedo_color = LAMP_OFF
		glow.emission_enabled = true
		glow.emission = LAMP_ON
		glow.emission_energy_multiplier = 0.0
		lens.material_override = glow
		_lamps.append(glow)
	# The arm pivots on the post; up is vertical, down spans the road.
	var pivot := StaticBody3D.new()
	pivot.name = "BarrierArm"
	pivot.collision_layer = 1
	pivot.collision_mask = 6
	pivot.position = at + Vector3(0.0, 1.05, 0.0)
	add_child(pivot)
	var arm_length: float = 10.6
	# The model is authored along +X from its hinge (and a hand's breadth
	# behind the post); a half turn points it across the road for side = +1.
	var arm_model: Node3D = _instance(ARM_MODEL)
	if arm_model != null:
		arm_model.name = "ArmModel"
		arm_model.rotation.y = PI if side > 0.0 else 0.0
		pivot.add_child(arm_model)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(arm_length, 0.3, 0.3)
	shape.shape = box_shape
	shape.position = Vector3(-side * arm_length * 0.5, 0.0, 0.0)
	pivot.add_child(shape)
	pivot.set_meta(&"side", side)
	# A script-driven part: keeps it out of the static geometry merge.
	pivot.set_meta(&"animated", true)
	_set_arm(pivot, 0.0)
	_arms.append(pivot)


## 0 = up (vertical, out of the way), 1 = down across the road.
func _set_arm(arm: Node3D, down: float) -> void:
	var side: float = float(arm.get_meta(&"side", 1.0))
	arm.rotation.z = side * lerpf(-PI * 0.5, 0.0, down)


func _build_train() -> void:
	for index: int in range(TRAIN_MODELS.size()):
		var car := AnimatableBody3D.new()
		car.name = "TrainCar%d" % index
		car.collision_layer = 1
		car.collision_mask = 0
		car.sync_to_physics = false
		# The model sits on the car's origin (the rails); the collision is the
		# same 7.5 x 3 x 2.6 m box the cubes had, its bottom 0.35 m up.
		var model: Node3D = _instance(TRAIN_MODELS[index])
		if model != null:
			model.name = "CarModel"
			car.add_child(model)
			LowpolyMaterials.apply(model)
			# The loco's headlight lens is "lamp": lit after dark.
			LowpolyMaterials.light_up(model, ["lamp"])
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = CAR_SIZE
		shape.shape = box_shape
		shape.position.y = CAR_SIZE.y * 0.5 + 0.35
		car.add_child(shape)
		car.set_meta(&"animated", true)
		car.visible = false
		car.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(car)
		_train.append(car)
	# Children of the segment itself, not of a car -- a car's process_mode
	# toggles off between crossings, which would also stop these tracking
	# their position. _physics_process moves them by hand instead, the same
	# way it moves the cars' own visuals.
	_train_horn = AudioStreamPlayer3D.new()
	_train_horn.name = "TrainHorn"
	_train_horn.stream = SynthAudio.train_horn()
	_train_horn.bus = &"SFX"
	_train_horn.volume_db = WorldMix.TRAIN_HORN_DB
	_train_horn.unit_size = 12.0
	_train_horn.max_distance = 80.0
	add_child(_train_horn)
	_train_chug = AudioStreamPlayer3D.new()
	_train_chug.name = "TrainChug"
	_train_chug.stream = SynthAudio.train_chug_loop()
	_train_chug.bus = &"SFX"
	_train_chug.volume_db = WorldMix.TRAIN_CHUG_DB
	_train_chug.unit_size = 10.0
	_train_chug.max_distance = 70.0
	add_child(_train_chug)


## An imported model, not yet in the tree (null, with a warning, if missing).
func _instance(path: String) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("Missing rail model: " + path)
		return null
	return scene.instantiate() as Node3D


## The kit's detail textures (planks on the sleepers and the deck).
func _dress(model: Node3D) -> Node3D:
	if model != null:
		LowpolyMaterials.apply(model)
	return model


func _physics_process(delta: float) -> void:
	match state:
		State.WAITING:
			if will_close and _is_host() and _truck_approaching():
				if _is_online():
					_begin_cycle.rpc()
				else:
					_begin_cycle()
		State.WARNING:
			_timer += delta
			if _timer >= WARNING_SECONDS:
				state = State.CLOSING
				_timer = 0.0
		State.CLOSING:
			_timer += delta
			for arm: Node3D in _arms:
				_set_arm(arm, clampf(_timer / ARM_SECONDS, 0.0, 1.0))
			if _timer >= ARM_SECONDS:
				state = State.TRAIN
				# The locomotive's nose just out of sight in the near bore.
				_train_x = -PORTAL_X - TRAIN_HIDE_DEPTH
				for car: AnimatableBody3D in _train:
					car.process_mode = Node.PROCESS_MODE_INHERIT
				_place_train()
				_train_horn.play()
				_train_chug.play()
		State.TRAIN:
			_train_x += TRAIN_SPEED * delta
			_place_train()
			# Gone once the last car is as deep in the far bore.
			if _train_x - float(_train.size() - 1) * CAR_SPACING - CAR_HALF_LENGTH > PORTAL_X + TRAIN_HIDE_DEPTH:
				for car: AnimatableBody3D in _train:
					car.visible = false
					car.process_mode = Node.PROCESS_MODE_DISABLED
				_train_chug.stop()
				state = State.OPENING
				_timer = 0.0
		State.OPENING:
			_timer += delta
			for arm: Node3D in _arms:
				_set_arm(arm, 1.0 - clampf(_timer / ARM_SECONDS, 0.0, 1.0))
			if _timer >= ARM_SECONDS:
				state = State.DONE
				_bell.stop()
	var flashing: bool = state in [State.WARNING, State.CLOSING, State.TRAIN, State.OPENING]
	var phase: bool = fmod(Time.get_ticks_msec() / 450.0, 2.0) < 1.0
	for index: int in range(_lamps.size()):
		_lamps[index].emission_energy_multiplier = (2.2 if (index % 2 == 0) == phase else 0.0) if flashing else 0.0


## Every car where _train_x puts it, drawn only while some of it is short of
## either bore's black end -- beyond that it would stick out of the hill.
func _place_train() -> void:
	var hidden_past: float = PORTAL_X + BORE_LENGTH + CAR_HALF_LENGTH
	for index: int in range(_train.size()):
		var at: Vector3 = Vector3(_train_x - float(index) * CAR_SPACING, 0.0, track_z)
		_train[index].position = Vector3(at.x, _ground_offset(at), at.z)
		_train[index].visible = absf(at.x) < hidden_past
	_train_horn.position = _train[0].position
	_train_chug.position = _train[0].position


## The host saw the truck coming: the bell rings and the cycle starts, on
## every peer at once.
@rpc("authority", "call_local", "reliable")
func _begin_cycle() -> void:
	if state != State.WAITING:
		return
	state = State.WARNING
	_timer = 0.0
	_bell.play()


## A client that just built this segment asks where the host's cycle is.
@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if not _is_host() or state in [State.WAITING, State.DONE]:
		return
	_apply_state.rpc_id(multiplayer.get_remote_sender_id(), state, _timer, _train_x)


## Jumps to the host's phase: arms where they'd be by now, train on the
## tracks if it's passing, bell ringing.
@rpc("authority", "call_remote", "reliable")
func _apply_state(new_state: int, timer: float, train_x: float) -> void:
	state = new_state
	_timer = timer
	_train_x = train_x
	var train_on: bool = state == State.TRAIN
	for car: AnimatableBody3D in _train:
		car.visible = false
		car.process_mode = Node.PROCESS_MODE_INHERIT if train_on else Node.PROCESS_MODE_DISABLED
	if train_on:
		_place_train()
	var down: float = 0.0
	match state:
		State.CLOSING:
			down = clampf(_timer / ARM_SECONDS, 0.0, 1.0)
		State.TRAIN:
			down = 1.0
		State.OPENING:
			down = 1.0 - clampf(_timer / ARM_SECONDS, 0.0, 1.0)
	for arm: Node3D in _arms:
		_set_arm(arm, down)
	if state != State.DONE and not _bell.playing:
		_bell.play()
	# A client joining mid-crossing picks up the chugging already in
	# progress (the horn is a one-off "here it comes", not worth replaying
	# for someone arriving late); _physics_process's own TRAIN branch keeps
	# it positioned and stops it once the cars clear, same as the host.
	if train_on and not _train_chug.playing:
		_train_chug.play()
	elif not train_on and _train_chug.playing:
		_train_chug.stop()


func _is_online() -> bool:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	return network != null and bool(network.call(&"is_online"))


func _is_host() -> bool:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	return network == null or bool(network.call(&"is_host"))


## Height of the (levelled) ground under a point of the track, in local
## space: on a continuous-terrain route the whole segment sits on it.
func _ground_offset(_at: Vector3) -> float:
	return float(get_meta(&"track_height", 0.0))


func _truck_approaching() -> bool:
	var truck := get_tree().get_first_node_in_group(&"vehicle") as Node3D
	if truck == null:
		return false
	var local: Vector3 = to_local(truck.global_position)
	# Still before the tracks (entry is +Z), and close enough to see it happen.
	return local.z > track_z and local.z - track_z < APPROACH_TRIGGER and absf(local.x) < 12.0
