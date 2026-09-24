extends Node3D
class_name ChasingDog
## A village dog that chases the truck (tareas de Nacho N-106): it waits by
## the road, and when the truck goes past it runs alongside on the shoulder,
## barking, for up to CHASE_LENGTH metres -- or until the truck leaves it
## behind, or a honk sends it home. It never touches the truck and costs
## nothing: it's a distraction, and a moment for the clips.
##
## Multiplayer: every peer runs it off its own copy of the (replicated)
## truck and the relayed horn; nothing about it is decided by the host.
##
## Space: this node sits on the road's centre line where the dog lives,
## the road running along Z; the dog itself runs in world space.

const DOG_MODEL: String = "res://assets/models/environment/wildlife/sm_env_animal_dog.glb"
const ANIMAL_SCRIPT: Script = preload("res://scripts/presentation/wildlife_animal.gd")

enum State { WAITING, CHASING, GIVING_UP, DONE }

const HOME_LATERAL: float = 9.5
## The truck this close (flat) wakes the dog up.
const NOTICE_DISTANCE: float = 22.0
## Where it runs: off the truck's side, clear of its wheels.
const CHASE_LATERAL: float = 5.5
const CHASE_LENGTH: float = 150.0
const RUN_SPEED: float = 11.0
const TROT_SPEED: float = 3.0
## Left this far behind, it gives up.
const LEFT_BEHIND: float = 30.0
const GIVE_UP_SECONDS: float = 3.0
const BARK_SECONDS: float = 0.7

@export var side: float = 1.0

var state: State = State.WAITING
var dog: Node3D
var run_distance: float = 0.0
var barks: int = 0
var _home: Vector3
var _bark_timer: float = 0.0
var _give_up_timer: float = 0.0
var _bark: AudioStreamPlayer3D


func _ready() -> void:
	if ResourceLoader.exists(DOG_MODEL):
		dog = (load(DOG_MODEL) as PackedScene).instantiate() as Node3D
	else:
		dog = Node3D.new()
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 0.45, 0.75)
		body.mesh = box
		body.position.y = 0.45
		dog.add_child(body)
	dog.name = "Dog"
	dog.set_script(ANIMAL_SCRIPT)
	dog.set(&"steered", true)
	add_child(dog)
	# It runs beside a moving truck, well past this segment: world space.
	dog.top_level = true
	_home = to_global(Vector3(side * HOME_LATERAL, 0.0, 0.0))
	dog.global_position = _home
	dog.rotation.y = side * PI * 0.5  # Sitting, facing the road.
	_bark = AudioStreamPlayer3D.new()
	_bark.name = "Bark"
	_bark.bus = &"SFX"
	_bark.stream = SynthAudio.dog_bark()
	_bark.unit_size = 6.0
	_bark.max_distance = 45.0
	dog.add_child(_bark)
	var bus: Node = get_node_or_null(^"/root/EventBus")
	if bus != null:
		bus.connect(&"horn_honked", _on_horn_honked)


func _physics_process(delta: float) -> void:
	if state == State.DONE:
		return
	var vehicle := get_tree().get_first_node_in_group(&"vehicle") as Node3D
	match state:
		State.WAITING:
			if vehicle != null and _flat(vehicle.global_position - dog.global_position).length() < NOTICE_DISTANCE:
				state = State.CHASING
				dog.call(&"run")
		State.CHASING:
			if vehicle == null:
				_give_up()
				return
			# Beside the truck, on this dog's side of it, just ahead of the
			# rear wheels: keeps pace when it can, falls back when it can't.
			var target: Vector3 = vehicle.global_position + vehicle.global_basis.x * side * CHASE_LATERAL + vehicle.global_basis.z * 1.5
			var step: Vector3 = _flat(target - dog.global_position)
			var move: Vector3 = step.limit_length(RUN_SPEED * delta)
			_move(move)
			run_distance += move.length()
			_bark_timer -= delta
			if _bark_timer <= 0.0:
				_bark_timer = BARK_SECONDS
				barks += 1
				_bark.pitch_scale = 0.95 + 0.1 * float(barks % 3)
				_bark.play()
			if run_distance >= CHASE_LENGTH or step.length() > LEFT_BEHIND:
				_give_up()
		State.GIVING_UP:
			_give_up_timer -= delta
			var home: Vector3 = _flat(_home - dog.global_position)
			_move(home.limit_length(TROT_SPEED * delta))
			if _give_up_timer <= 0.0:
				state = State.DONE
				dog.call(&"idle")


func _on_horn_honked(_peer_id: int) -> void:
	var vehicle := get_tree().get_first_node_in_group(&"vehicle") as Node3D
	if state == State.CHASING and vehicle != null and _flat(vehicle.global_position - dog.global_position).length() < WildlifeCrossing.HORN_SCARE_DISTANCE:
		_give_up()


func _give_up() -> void:
	state = State.GIVING_UP
	_give_up_timer = GIVE_UP_SECONDS
	dog.call(&"run")


## Moves the dog across the ground, facing where it goes.
func _move(offset: Vector3) -> void:
	if offset.length() < 0.001:
		return
	var to: Vector3 = dog.global_position + offset
	to.y = _ground_height(to)
	dog.look_at(Vector3(to.x, dog.global_position.y, to.z), Vector3.UP)
	dog.global_position = to


static func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


func _ground_height(world_point: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(world_point + Vector3.UP * 6.0, world_point + Vector3.DOWN * 12.0, 1)
	var hit_info: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return (hit_info["position"] as Vector3).y if not hit_info.is_empty() else world_point.y
