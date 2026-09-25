extends Node3D
class_name FlockCrossing
## A flock of sheep crossing the road in open country (tareas de Nacho
## N-106): six to ten of them graze on one shoulder; when the truck comes
## close they amble across, slowly and not all at once, blocking the lane
## for a while. The driver waits, or honks: the flock scatters off the road
## to whichever side each sheep is nearest. Running one over costs a fine,
## like the deer, and jolts the truck (less: a sheep is smaller).
##
## Multiplayer: the same as WildlifeCrossing. The flock comes from the
## crossing's own seed, every peer runs the same timeline off the replicated
## truck and the relayed horn, and only the host decides a hit's
## consequences.
##
## Space: this node sits on the road's centre line, the road running along
## Z (the truck comes from +Z), lateral offsets on X.

const WorldMix = preload("res://scripts/presentation/world_mix.gd")
const SHEEP_MODEL: String = "res://assets/models/environment/wildlife/sm_env_animal_sheep.glb"
const ANIMAL_SCRIPT: Script = preload("res://scripts/presentation/wildlife_animal.gd")
const SIGN_MODEL: PackedScene = preload("res://assets/models/environment/signs/sm_env_sign_animal_crossing.glb")

enum State { WAITING, CROSSING, SCATTERED, DONE }

const MIN_SHEEP: int = 6
const MAX_SHEEP: int = 10
## The truck this far before the crossing sets the flock off: sheep amble
## (~1.7 m/s), so they have to start early to be on the road when a truck at
## cruising speed (~14 m/s, eight seconds away) gets there. Wide sideways,
## so a bend just before the straight doesn't hide the truck from it.
const TRIGGER_DISTANCE: float = 110.0
const TRIGGER_LATERAL: float = 45.0
const WAIT_LATERAL_MIN: float = 8.5
const WAIT_LATERAL_MAX: float = 14.0
const EXIT_LATERAL: float = 11.0
## Where scattered sheep stop, well clear of the asphalt.
const SCATTER_LATERAL: float = 13.0
const WALK_SPEED_MIN: float = 1.4
const WALK_SPEED_MAX: float = 2.1
const SCATTER_SPEED: float = 5.0
## Sheep don't all set off together: up to this many seconds apart.
const START_SPREAD_SECONDS: float = 3.0
const ROAD_HALF_WIDTH: float = 6.2
const MIN_HIT_SPEED_KMH: float = 6.0
const IMPACT_SPEED_LOSS: float = 2.0
const FINE: int = 20
const SIGN_LEAD: float = 50.0
const SIGN_LATERAL: float = 7.8

@export var side: float = 1.0
## Picks the flock (how many, where each grazes, its pace): the same on
## every peer, set by whoever places the crossing from the session seed.
@export var flock_seed: int = 0
## Endless has no RouteDresser to put up the sign.
@export var with_sign: bool = false

var state: State = State.WAITING
var hit: bool = false
var sheep: Array[Node3D] = []
## Per sheep: {"lateral", "z", "speed", "delay", "hit", "tumble"}.
var _flock: Array[Dictionary] = []
var _clock: float = 0.0
var _bleat: AudioStreamPlayer3D


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = flock_seed
	var count: int = rng.randi_range(MIN_SHEEP, MAX_SHEEP)
	for index: int in range(count):
		var animal: Node3D = _make_sheep()
		animal.name = "Sheep%d" % index
		add_child(animal)
		sheep.append(animal)
		_flock.append({
			"lateral": side * rng.randf_range(WAIT_LATERAL_MIN, WAIT_LATERAL_MAX),
			"z": rng.randf_range(-7.0, 7.0),
			"speed": rng.randf_range(WALK_SPEED_MIN, WALK_SPEED_MAX),
			"delay": rng.randf_range(0.0, START_SPREAD_SECONDS),
			"hit": false,
			"tumble": 0.0,
		})
		_place(index, -side)
	if with_sign:
		var warning := SIGN_MODEL.instantiate() as Node3D
		warning.name = "CrossingSign"
		warning.rotation.y = PI
		warning.position = Vector3(SIGN_LATERAL, 0.0, SIGN_LEAD)
		add_child(warning)
	_bleat = AudioStreamPlayer3D.new()
	_bleat.name = "Bleat"
	_bleat.bus = &"SFX"
	_bleat.stream = SynthAudio.sheep_bleat()
	_bleat.unit_size = 7.0
	_bleat.volume_db = WorldMix.SHEEP_BLEAT_DB
	_bleat.max_distance = 60.0
	add_child(_bleat)
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"horn_honked", _on_horn_honked)


func _physics_process(delta: float) -> void:
	if state == State.DONE:
		return
	var vehicle := get_tree().get_first_node_in_group(&"vehicle") as VehicleBody3D
	if state == State.WAITING:
		if vehicle != null and _approaching(vehicle):
			state = State.CROSSING
			_clock = 0.0
			_baa(0)
		return
	_clock += delta
	var settled: int = 0
	for index: int in range(_flock.size()):
		var member: Dictionary = _flock[index]
		var animal: Node3D = sheep[index]
		if float(member.tumble) > 0.0:
			member.tumble = float(member.tumble) - delta
			continue
		var goal: float
		var speed: float
		if state == State.SCATTERED or bool(member.hit):
			var away: float = signf(member.lateral) if absf(member.lateral) > 0.5 else side
			goal = away * SCATTER_LATERAL
			speed = SCATTER_SPEED
		else:
			if _clock < float(member.delay):
				continue
			goal = -side * EXIT_LATERAL
			speed = member.speed
		var before: float = member.lateral
		member.lateral = move_toward(member.lateral, goal, speed * delta)
		var moving: bool = not is_equal_approx(member.lateral, goal)
		animal.call(&"run" if moving else &"idle")
		_place(index, signf(member.lateral - before) if moving else -side)
		if not moving:
			settled += 1
		if vehicle != null and absf(member.lateral) < ROAD_HALF_WIDTH and not bool(member.hit):
			_check_hit(vehicle, index)
	if settled == _flock.size():
		state = State.DONE


## The truck is on this stretch, coming toward the flock, within range.
func _approaching(vehicle: Node3D) -> bool:
	var local: Vector3 = to_local(vehicle.global_position)
	return local.z > 4.0 and local.z < TRIGGER_DISTANCE and absf(local.x) < TRIGGER_LATERAL


func _check_hit(vehicle: VehicleBody3D, index: int) -> void:
	if vehicle.linear_velocity.length() * 3.6 < MIN_HIT_SPEED_KMH:
		return
	var in_truck: Vector3 = vehicle.to_local(sheep[index].global_position + Vector3.UP * 0.5)
	if absf(in_truck.x) > WildlifeCrossing.TRUCK_HALF_WIDTH or in_truck.z < WildlifeCrossing.TRUCK_FRONT_Z or in_truck.z > WildlifeCrossing.TRUCK_BACK_Z:
		return
	var member: Dictionary = _flock[index]
	member.hit = true
	member.tumble = 0.8
	sheep[index].call(&"tumble")
	_baa(index)
	if hit:
		return  # One fine per flock: a second sheep in the same second is the same accident.
	hit = true
	if vehicle.is_multiplayer_authority():
		var velocity: Vector3 = vehicle.linear_velocity
		if velocity.length() > 0.1:
			vehicle.apply_central_impulse(-velocity.normalized() * vehicle.mass * minf(IMPACT_SPEED_LOSS, velocity.length() * 0.5))
		var fine: int = FINE
		var crew: Node = get_node_or_null(^"/root/CrewProgression")
		if crew != null:
			fine = mini(FINE, int(crew.get(&"team_money")))
			if fine > 0:
				crew.call(&"spend", fine)
		WildlifeCrossing.report_incident(get_tree(), &"sheep_hit", "¡Atropellaste una oveja!",
			("Se levantó ofendida. El dueño cobra $%d." % fine) if fine > 0 else "Se levantó ofendida. El dueño no te pudo cobrar nada.")


## A honk close enough ahead scatters the flock off the road.
func _on_horn_honked(_peer_id: int) -> void:
	if state not in [State.WAITING, State.CROSSING]:
		return
	var vehicle := get_tree().get_first_node_in_group(&"vehicle") as Node3D
	if vehicle == null or not horn_reaches(vehicle):
		return
	state = State.SCATTERED
	_baa(_flock.size() / 2)


## Whether a honk from this truck reaches the flock: its middle ahead of the
## nose within WildlifeCrossing.HORN_SCARE_DISTANCE (plus the flock's spread).
func horn_reaches(vehicle: Node3D) -> bool:
	var in_truck: Vector3 = vehicle.to_local(global_position)
	var ahead: float = -in_truck.z + WildlifeCrossing.TRUCK_FRONT_Z
	return ahead > -8.0 and ahead <= WildlifeCrossing.HORN_SCARE_DISTANCE + 7.0 and absf(in_truck.x) <= WildlifeCrossing.HORN_SCARE_LATERAL


## A bleat from sheep `index`'s spot.
func _baa(index: int) -> void:
	_bleat.position = sheep[index].position + Vector3.UP * 0.7
	_bleat.pitch_scale = 0.9 + 0.05 * float(index % 4)
	_bleat.play()


## Whether any sheep stands on the asphalt right now.
func blocking_road() -> bool:
	for member: Dictionary in _flock:
		if absf(member.lateral) < ROAD_HALF_WIDTH:
			return true
	return false


func _place(index: int, facing: float) -> void:
	var member: Dictionary = _flock[index]
	var spot := Vector3(member.lateral, 0.0, member.z)
	spot.y = _ground_height(spot)
	sheep[index].position = spot
	sheep[index].rotation = Vector3(0.0, facing * -PI * 0.5, 0.0)


func _make_sheep() -> Node3D:
	var animal: Node3D
	if ResourceLoader.exists(SHEEP_MODEL):
		animal = (load(SHEEP_MODEL) as PackedScene).instantiate() as Node3D
	else:
		# Until the model exists: a woolly box, so the hazard still works.
		animal = Node3D.new()
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.55, 0.95)
		body.mesh = box
		body.position.y = 0.55
		animal.add_child(body)
	animal.set_script(ANIMAL_SCRIPT)
	animal.set(&"steered", true)
	return animal


func _ground_height(local_point: Vector3) -> float:
	if not is_inside_tree():
		return local_point.y
	var world_point: Vector3 = to_global(local_point)
	var query := PhysicsRayQueryParameters3D.create(world_point + Vector3.UP * 6.0, world_point + Vector3.DOWN * 12.0, 1)
	var hit_info: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit_info.is_empty():
		return local_point.y
	return to_local(hit_info["position"] as Vector3).y
