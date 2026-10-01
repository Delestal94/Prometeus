class_name CargoAnimalView
extends Node3D
## What the crew sees and hears of the animals that go for the cargo (N-109),
## on every peer: the gull swooping in through the rear doors, the dog running
## up to an open box, the bees rounding the cake -- each with its cry, bark or
## buzz and an icon over the box that counts down, so nothing bites without
## warning (RV There Yet?'s main complaint about its fauna).
##
## Presentation only. It follows EventBus.cargo_animal_alert / _ended, which the
## host relays (cargo_animals.gd), and never decides anything about the box:
## the timeline is the alert's own seconds, counted locally, and the animal
## sits wherever the box is, which the network already places on every peer.
## Models: a gull of primitives (cargo_gull.gd: white, grey wings, yellow beak;
## the roadside bird is a brown blob at this size), the rigged village dog
## animated by wildlife_animal.gd and scaled up to be read, and the bees, one
## MultiMesh of striped, winged bees (cargo_bee_mesh.gd) orbiting the cake.
##
## Cost: nothing while no animal is out (process is off). With one: a handful
## of transforms a frame, and one raycast when the dog arrives.

const DOG_MODEL: String = "res://assets/models/environment/wildlife/sm_env_animal_dog_rigged.glb"
const ANIMAL_SCRIPT: Script = preload("res://scripts/presentation/wildlife_animal.gd")
const WorldMix = preload("res://scripts/presentation/world_mix.gd")

signal dog_thrown(peer_id: int)

enum State { NONE, WARN, ACT, LEAVE }

const GULL_SCALE: float = 1.15
## The village dog stands ~0.55 m; on a box it has to be read from across the bay.
const DOG_SCALE: float = 1.3
## Where the gull starts its swoop, in the truck's space: behind it and high.
const GULL_START: Vector3 = Vector3(0.0, 4.2, 15.0)
## Where the dog starts running from, in the truck's space, and the rear doors
## it heads for; and where it trots off to (or to the stick).
const DOG_START: Vector3 = Vector3(2.4, 0.0, 15.0)
const DOG_AT_DOORS: Vector3 = Vector3(0.0, 0.0, 5.8)
const DOG_AWAY: Vector3 = Vector3(3.0, 0.0, 26.0)
const DOG_HOP_SECONDS: float = 0.45
const DOG_RUN_SPEED: float = 8.0
const STICK_TARGET: Vector3 = Vector3(-3.0, 0.0, 14.0)
const STICK_FLIGHT_SECONDS: float = 0.7
const BEE_COUNT: int = 64
const BEE_RADIUS: float = 0.8
const LEAVE_SECONDS: Dictionary = {
	CargoAnimalPlan.GULL: 2.2, CargoAnimalPlan.DOG: 3.0, CargoAnimalPlan.BEES: 1.6}
## Icon text by kind (keys written out in full, see test_world_translations).
const ICON_KEYS: Dictionary = {
	CargoAnimalPlan.GULL: "WORLD_GULL_ICON",
	CargoAnimalPlan.DOG: "WORLD_DOG_ICON",
	CargoAnimalPlan.BEES: "WORLD_BEES_ICON",
}
const ICON_WARN_COLOR := Color("ffd23f")
const ICON_ACT_COLOR := Color("ff4a3a")
const ICON_HEIGHT: float = 1.0

var state: State = State.NONE
var kind: StringName = &""
var package_id: StringName = &""
## The last outcome the host announced for the animal that just left.
var outcome: StringName = &""
var animal: Node3D
var bees: MultiMeshInstance3D
var icon: Label3D
var dog_point: DogDistractPoint

var _box: Node3D
var _warn_left: float = 0.0
var _warn_total: float = 1.0
var _act_left: float = 0.0
var _leave_left: float = 0.0
var _age: float = 0.0
var _phase_age: float = 0.0
var _ground_y: float = 0.0
var _hop_from: Vector3 = Vector3.ZERO
var _leave_target: Vector3 = Vector3.ZERO
var _voice: AudioStreamPlayer3D
var _buzz: AudioStreamPlayer3D
var _voice_clock: float = 0.0
var _voice_rng := RandomNumberGenerator.new()
var _stick: MeshInstance3D
var _stick_from: Vector3 = Vector3.ZERO
var _stick_age: float = 0.0
var _bee_seeds: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	set_process(false)
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"cargo_animal_alert", _on_alert)
		bus.connect(&"cargo_animal_ended", _on_ended)


func _exit_tree() -> void:
	_clear()


# --- Events ------------------------------------------------------------------

func _on_alert(animal_kind: StringName, id: StringName, warn_seconds: float, act_seconds: float) -> void:
	# Not while it is leaving: the ended and the next alert can land in the same frame
	# (the director's cooldown is longer than the exit, but not by much), and that one
	# is a new attack, not a repeat.
	if state != State.NONE and state != State.LEAVE and animal_kind == kind and id == package_id:
		# The host repeating itself for a peer that just joined: adjust, don't restart.
		if state == State.WARN:
			_warn_left = warn_seconds
			if warn_seconds <= 0.0:
				_begin_act()
		_act_left = act_seconds
		return
	# Detached, so a new "Dog" keeps its name (and the path of its DistractPoint, which
	# the host's stick throw uses) even when the old one is only queued to be freed.
	_clear(true)
	var found: Node3D = _find_box(id)
	if found == null or _vehicle() == null:
		return
	kind = animal_kind
	package_id = id
	outcome = &""
	_box = found
	_warn_total = maxf(warn_seconds, 0.01)
	_warn_left = warn_seconds
	_act_left = act_seconds
	_age = 0.0
	_phase_age = 0.0
	_voice_clock = 0.0
	_voice_rng.seed = hash([String(id), String(animal_kind)])
	_ground_y = _ground_height()
	_build_animal()
	_build_icon()
	state = State.WARN
	if warn_seconds <= 0.0:
		_begin_act()
	set_process(true)


func _on_ended(animal_kind: StringName, id: StringName, result: StringName, peer_id: int) -> void:
	if state == State.NONE or animal_kind != kind or id != package_id:
		return
	outcome = result
	state = State.LEAVE
	_phase_age = 0.0
	_leave_left = float(LEAVE_SECONDS[kind])
	_leave_target = _vehicle().to_global(DOG_AWAY) if _vehicle() != null else Vector3.ZERO
	if is_instance_valid(icon):
		icon.visible = false
	if is_instance_valid(dog_point):
		dog_point.active = false
	if result == &"distracted":
		_throw_stick(peer_id)
	if is_instance_valid(_buzz):
		_buzz.stop()


func _begin_act() -> void:
	state = State.ACT
	_phase_age = 0.0
	_hop_from = animal.global_position if is_instance_valid(animal) else Vector3.ZERO


# --- Frame -------------------------------------------------------------------

func _process(delta: float) -> void:
	var vehicle: Node3D = _vehicle()
	if state == State.NONE or vehicle == null:
		return
	if not is_instance_valid(_box):
		_box = _find_box(package_id)
		if _box == null:
			_clear()
			return
	_age += delta
	_phase_age += delta
	match state:
		State.WARN:
			_warn_left -= delta
			if _warn_left <= 0.0:
				_begin_act()
		State.ACT:
			_act_left = maxf(0.0, _act_left - delta)
		State.LEAVE:
			_leave_left -= delta
			if _leave_left <= 0.0:
				_clear()
				return
	match kind:
		CargoAnimalPlan.GULL:
			_pose_gull(delta, vehicle)
		CargoAnimalPlan.DOG:
			_pose_dog(delta, vehicle)
		CargoAnimalPlan.BEES:
			_pose_bees(vehicle)
	_update_icon()
	_update_voice(delta)
	_update_stick(delta)


func _pose_gull(delta: float, vehicle: Node3D) -> void:
	var gull := animal as CargoGull
	var top: Vector3 = _box_top()
	var here: Vector3 = animal.global_position
	match state:
		State.WARN:
			var k: float = clampf(1.0 - _warn_left / _warn_total, 0.0, 1.0)
			var eased: float = k * k * (3.0 - 2.0 * k)
			here = vehicle.to_global(GULL_START.lerp(vehicle.to_local(top), eased)) + Vector3.UP * sin(k * PI) * 0.5
			_turn_toward(here)
			gull.pose(true, _age)
		State.ACT:
			here = top + Vector3.UP * 0.02
			# Facing forward and a little toward the aisle, into the open of the rack: in
			# profile from the crew's side, where head, beak and back can be told apart.
			animal.global_rotation = Vector3(0.0, vehicle.global_rotation.y - 0.35, 0.0)
			gull.pose(false, _age)
		State.LEAVE:
			var away: Vector3 = (vehicle.global_basis * Vector3(0.5, 0.5, 1.0)).normalized()
			here += away * 9.0 * delta
			_turn_toward(here)
			gull.pose(true, _age)
	animal.global_position = here


func _pose_dog(delta: float, vehicle: Node3D) -> void:
	var here: Vector3 = animal.global_position
	var speed: float = 0.0
	match state:
		State.WARN:
			var start: Vector3 = _on_ground(vehicle.to_global(DOG_START))
			var stop: Vector3 = _dog_stop(vehicle)
			var k: float = clampf(1.0 - _warn_left / _warn_total, 0.0, 1.0)
			here = start.lerp(stop, k)
			speed = start.distance_to(stop) / _warn_total
			_turn_toward(here)
			animal.call(&"run")
		State.ACT:
			# Front paws up on the box, the dog standing beside it (a shelf above a
			# box leaves no room to stand on it).
			var hop: float = clampf(_phase_age / DOG_HOP_SECONDS, 0.0, 1.0)
			here = _hop_from.lerp(_dog_beside(vehicle), hop) + Vector3.UP * sin(hop * PI) * 0.4
			var toward: Vector3 = _box.global_position - here
			animal.global_rotation = Vector3(0.0, atan2(-toward.x, -toward.z), 0.0)
			animal.call(&"idle")
		State.LEAVE:
			var goal: Vector3 = _on_ground(_leave_target)
			var flat: Vector3 = Vector3(goal.x - here.x, 0.0, goal.z - here.z)
			var step: Vector3 = flat.limit_length(DOG_RUN_SPEED * delta)
			here += step
			here.y = move_toward(here.y, _ground_y, 6.0 * delta)
			speed = DOG_RUN_SPEED if flat.length() > 0.2 else 0.0
			_turn_toward(here)
			animal.call(&"run")
	# The clips are paced to the dog at its own size.
	animal.set(&"ground_speed", lerpf(float(animal.get(&"ground_speed")), speed / DOG_SCALE, 0.25))
	animal.global_position = here


func _pose_bees(vehicle: Node3D) -> void:
	if not is_instance_valid(bees):
		return
	var centre: Vector3 = _box.global_position
	var radius: float = BEE_RADIUS
	var lift: float = 0.0
	match state:
		State.WARN:
			var k: float = clampf(1.0 - _warn_left / _warn_total, 0.0, 1.0)
			centre += (vehicle.global_basis * Vector3(0.0, 1.5, 9.0)) * (1.0 - k)
			radius = lerpf(3.0, BEE_RADIUS, k)
		State.LEAVE:
			var spread: float = clampf(_phase_age / float(LEAVE_SECONDS[kind]), 0.0, 1.0)
			radius = lerpf(BEE_RADIUS, 4.0, spread)
			lift = spread * 6.0
	centre += Vector3.UP * lift
	var multi: MultiMesh = bees.multimesh
	for index: int in range(multi.instance_count):
		var seed_value: float = _bee_seeds[index]
		# Each bee has its own orbit speed, direction, tilt and height: a cloud that
		# churns round the cake instead of a ring.
		var turn: float = (2.6 + fmod(seed_value * 7.0, 2.2)) * (1.0 if index % 3 != 0 else -1.0)
		var angle: float = seed_value * TAU + _age * turn
		var reach: float = radius * (0.45 + fmod(seed_value * 13.0, 0.55))
		var height: float = (fmod(seed_value * 29.0, 1.0) - 0.15) * radius * 1.3 + sin(_age * 3.1 + seed_value * 20.0) * 0.12
		var offset := Vector3(cos(angle) * reach, height, sin(angle) * reach)
		# Nose along the orbit, so they read as flying insects, not floating dots.
		var heading := Vector3(-sin(angle), 0.1 * sin(_age * 5.0 + seed_value * 9.0), cos(angle)) * signf(turn)
		var forward: Vector3 = heading.normalized()
		var side: Vector3 = Vector3.UP.cross(forward).normalized()
		var basis := Basis(side, forward, side.cross(forward))
		# The wings are too fast to draw: the whole bee shivers about its heading.
		basis = Basis(forward, sin(_age * 70.0 + seed_value * 40.0) * 0.45) * basis
		multi.set_instance_transform(index, Transform3D(basis, centre + offset))
	if is_instance_valid(_buzz):
		_buzz.global_position = centre


# --- Pieces ------------------------------------------------------------------

func _build_animal() -> void:
	if kind == CargoAnimalPlan.BEES:
		_build_bees()
		return
	if kind == CargoAnimalPlan.GULL:
		animal = CargoGull.new()
		animal.scale = Vector3.ONE * GULL_SCALE
	else:
		animal = _load_dog()
		animal.name = "Dog"
		animal.set_script(ANIMAL_SCRIPT)
		animal.set(&"steered", true)
		animal.set(&"standing_clip", &"Idle")
		animal.scale = Vector3.ONE * DOG_SCALE
	add_child(animal)
	animal.global_position = _vehicle().to_global(GULL_START if kind == CargoAnimalPlan.GULL else DOG_START)
	_voice = _make_voice(animal)
	if kind == CargoAnimalPlan.DOG:
		_build_dog_point()


func _load_dog() -> Node3D:
	if ResourceLoader.exists(DOG_MODEL):
		return (load(DOG_MODEL) as PackedScene).instantiate() as Node3D
	# No model (a stripped build): a box, so the warning still has a face.
	var stand_in := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.3, 0.5)
	body.mesh = box
	stand_in.add_child(body)
	return stand_in


func _build_dog_point() -> void:
	dog_point = DogDistractPoint.new()
	dog_point.name = "DistractPoint"
	dog_point.active = true
	dog_point.position = Vector3(0.0, 0.5 / DOG_SCALE, 0.0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.3 / DOG_SCALE
	shape.shape = sphere
	dog_point.add_child(shape)
	animal.add_child(dog_point)
	dog_point.thrown.connect(func(peer_id: int) -> void: dog_thrown.emit(peer_id))


func _build_bees() -> void:
	var count: int = maxi(12, roundi(BEE_COUNT * WorldQuality.setting("particle_scale")))
	# One striped bee with wings per instance (CargoBeeMesh).
	var mesh: ArrayMesh = CargoBeeMesh.mesh()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count
	_bee_seeds.resize(count)
	for index: int in range(count):
		# Every peer draws the same swarm: the seeds come from the index.
		_bee_seeds[index] = fmod(float(index) * 0.6180339, 1.0)
	bees = MultiMeshInstance3D.new()
	bees.name = "Bees"
	bees.multimesh = multi
	bees.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bees)
	_buzz = AudioStreamPlayer3D.new()
	_buzz.name = "Buzz"
	_buzz.bus = &"SFX"
	_buzz.stream = CargoAnimalSounds.bee_buzz()
	_buzz.unit_size = 5.0
	_buzz.volume_db = WorldMix.BEE_BUZZ_DB
	_buzz.max_distance = 40.0
	add_child(_buzz)
	_buzz.play()


func _make_voice(parent: Node3D) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = "Voice"
	voice.bus = &"SFX"
	voice.stream = CargoAnimalSounds.gull_cry() if kind == CargoAnimalPlan.GULL else SynthAudio.dog_bark()
	voice.unit_size = 6.0
	voice.volume_db = WorldMix.GULL_CRY_DB if kind == CargoAnimalPlan.GULL else WorldMix.DOG_BARK_DB
	voice.max_distance = 45.0
	parent.add_child(voice)
	return voice


func _build_icon() -> void:
	icon = Label3D.new()
	icon.name = "AlertIcon"
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	icon.fixed_size = true
	icon.pixel_size = 0.0011
	icon.font_size = 40
	icon.outline_size = 10
	add_child(icon)
	_update_icon()


func _update_icon() -> void:
	if not is_instance_valid(icon) or not is_instance_valid(_box):
		return
	var left: float = _warn_left if state == State.WARN else _act_left
	var text: String = tr(ICON_KEYS[kind])
	# The seconds left to stop it: to arrive, and (the gull) to snatch.
	if state == State.WARN or (state == State.ACT and kind == CargoAnimalPlan.GULL):
		text += "  %d" % ceili(left)
	icon.text = text + "
▼"
	icon.modulate = ICON_WARN_COLOR if state == State.WARN else ICON_ACT_COLOR
	icon.global_position = _box.global_position + Vector3.UP * (ICON_HEIGHT + _box_half_height())


func _update_voice(delta: float) -> void:
	if state == State.LEAVE or kind == CargoAnimalPlan.BEES or not is_instance_valid(_voice):
		return
	_voice_clock -= delta
	if _voice_clock > 0.0:
		return
	_voice.pitch_scale = _voice_rng.randf_range(0.92, 1.1)
	_voice.play()
	if kind == CargoAnimalPlan.GULL:
		_voice_clock = _voice_rng.randf_range(1.2, 1.9)
	else:
		_voice_clock = _voice_rng.randf_range(0.6, 1.2)


func _throw_stick(peer_id: int) -> void:
	_stick = MeshInstance3D.new()
	_stick.name = "Stick"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.07, 0.07, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("7a5230")
	mesh.material = material
	_stick.mesh = mesh
	add_child(_stick)
	var thrower: Node3D = _player_of(peer_id)
	_stick_from = (thrower.global_position + Vector3.UP * 1.4) if thrower != null else _box_top()
	_stick_age = 0.0
	_stick.global_position = _stick_from
	_leave_target = _vehicle().to_global(STICK_TARGET)


func _update_stick(delta: float) -> void:
	if not is_instance_valid(_stick):
		return
	_stick_age += delta
	var k: float = clampf(_stick_age / STICK_FLIGHT_SECONDS, 0.0, 1.0)
	var landing: Vector3 = _on_ground(_leave_target)
	_stick.global_position = _stick_from.lerp(landing, k) + Vector3.UP * sin(k * PI) * 2.0
	_stick.rotate_x(delta * 14.0)


## Frees everything the animal made. `detach` also takes the pieces out of the tree
## right away, so their names are free again this same frame (queue_free alone
## leaves them in until the frame ends); not wanted when the view itself is leaving.
func _clear(detach: bool = false) -> void:
	state = State.NONE
	set_process(false)
	for node: Node in [animal, bees, icon, _buzz, _stick]:
		if is_instance_valid(node):
			if detach and node.get_parent() == self:
				remove_child(node)
			node.queue_free()
	animal = null
	bees = null
	icon = null
	dog_point = null
	_voice = null
	_buzz = null
	_stick = null
	_box = null
	kind = &""
	package_id = &""


# --- Where things are --------------------------------------------------------

func _vehicle() -> Node3D:
	var parent: Node = get_parent()
	return parent.get(&"vehicle") as Node3D if parent != null else null


func _find_box(id: StringName) -> Node3D:
	var parent: Node = get_parent()
	if parent == null:
		return null
	for candidate: Variant in parent.get(&"packages"):
		if is_instance_valid(candidate) and StringName((candidate as Node).get(&"package_id")) == id:
			return candidate as Node3D
	return null


func _player_of(peer_id: int) -> Node3D:
	for candidate: Node in get_tree().get_nodes_in_group(&"player"):
		if candidate.get_multiplayer_authority() == peer_id:
			return candidate as Node3D
	return null


func _box_half_height() -> float:
	if _box == null or not _box.has_method(&"get_half_extents"):
		return 0.33
	return float((_box.call(&"get_half_extents") as Vector3).y)


func _box_top() -> Vector3:
	return _box.global_position + Vector3.UP * _box_half_height()


## Where the dog runs to: the rear doors when the box is in the bay, else the
## foot of the box.
func _dog_stop(vehicle: Node3D) -> Vector3:
	if bool(vehicle.call(&"carries", _box.global_position, 0.6)):
		return _on_ground(vehicle.to_global(DOG_AT_DOORS))
	return _on_ground(_box.global_position)


## Where the dog stands to work at the box: out in the aisle of the bay (the
## rack opens onto it) at the floor under the box; by the box on the ground.
func _dog_beside(vehicle: Node3D) -> Vector3:
	var box_at: Vector3 = _box.global_position
	var in_bay: bool = bool(vehicle.call(&"carries", box_at, 0.6))
	var aside: Vector3 = vehicle.global_basis * Vector3(0.95 if in_bay else 0.7, 0.0, 0.0)
	var spot: Vector3 = box_at + aside
	if not in_bay:
		return _on_ground(spot)
	# The floor of the bay: the truck's shell (Vehicle.SHELL_LAYER), found with
	# a ray down from the height of the box. A ray at the world layer would fall
	# through to the ground under the truck.
	var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 0.3, spot + Vector3.DOWN * 1.6, 64)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3(spot.x, box_at.y - _box_half_height() - 0.4, spot.z)
	return Vector3(spot.x, (hit["position"] as Vector3).y, spot.z)


func _on_ground(point: Vector3) -> Vector3:
	return Vector3(point.x, _ground_y, point.z)


func _ground_height() -> float:
	var vehicle: Node3D = _vehicle()
	if vehicle == null or not is_inside_tree():
		return 0.0
	var origin: Vector3 = vehicle.global_position
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 2.0, origin + Vector3.DOWN * 6.0, 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else origin.y - 0.7


## Faces where it is going (front is -Z), yaw only.
func _turn_toward(next_position: Vector3) -> void:
	var heading: Vector3 = next_position - animal.global_position
	if Vector2(heading.x, heading.z).length() > 0.001:
		animal.global_rotation = Vector3(0.0, atan2(-heading.x, -heading.z), 0.0)
