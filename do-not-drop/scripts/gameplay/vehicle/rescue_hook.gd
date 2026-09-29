extends Interactable
class_name RescueHook
## Rescue hook (tareas de Nacho N-213.3): a depot supply of the Survival
## branch. While the run that took it lasts, a pole hangs by the open rear
## doors and a passenger standing there can snag a box lying on the road
## close behind the van and have it in their hands without anybody braking.
##
## Hung on the van from outside (vehicle.gd is frozen) by LevelCommon, so its
## node path is the same on every peer. The client only sends the intent
## (Interactable.request_interact); the host picks the box and hands it over
## with DeliveryPackage.take_by(), the same pickup that closes the overboard
## window as rescued (N-213.2).

## Where it hangs, in the van's frame: on the left post of the rear doors,
## clear of the door control in the middle so looking at one never picks
## the other.
const LOCAL_POSITION: Vector3 = Vector3(-0.85, 1.6, 4.3)
## How far from the hook a box can lie and still be snagged. The overboard
## window opens 8 m from the van's middle (LevelCommon.LOST_CARGO_DISTANCE),
## about 3.5 m behind the doors, so this leaves a few meters to aim for at
## speed -- a skill shot, not a free recall.
const REACH: float = 7.0
## After a throw, the hook needs this long to be ready again (host-side).
const COOLDOWN_SECONDS: float = 3.0

## Every peer: the crew brought the hook on this run.
var armed: bool = false
var _cooldown_left: float = 0.0
var _pole: MeshInstance3D


func _ready() -> void:
	super._ready()
	prompt = "WORLD_HOOK_PROMPT"
	position = LOCAL_POSITION
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.35
	shape.shape = sphere
	add_child(shape)
	_pole = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.025
	mesh.bottom_radius = 0.025
	mesh.height = 1.3
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("e0a526")
	mesh.material = paint
	_pole.mesh = mesh
	_pole.visible = false
	add_child(_pole)
	EventBus.run_ended.connect(_on_run_ended)


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)


## Host-only: the run leaving the depot took the hook (depot.gd begin_run).
func arm() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	_set_armed(true)
	if _is_online():
		_set_armed.rpc(true)


@rpc("authority", "call_remote", "reliable")
func _set_armed(value: bool) -> void:
	armed = value
	_cooldown_left = 0.0
	if _pole != null:
		_pole.visible = value


func get_prompt() -> String:
	return tr(prompt)


func can_interact(player: Node) -> bool:
	if not armed or _cooldown_left > 0.0 or player.get(&"carried_package") != null:
		return false
	if not _rear_open():
		return false
	return target_package() != null


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	var package: DeliveryPackage = target_package()
	_cooldown_left = COOLDOWN_SECONDS
	package.take_by(player)
	interacted.emit(player)


## The closest box within reach that fell out of the van: it rode on a rack
## this run (is_loaded stays set until someone picks it up, the same test
## LevelCommon._check_lost_cargo() uses), it isn't in anybody's hands, isn't
## ruined and isn't inside the cargo bay any more.
func target_package() -> DeliveryPackage:
	var vehicle: Node3D = get_parent() as Node3D
	var best: DeliveryPackage = null
	var best_distance: float = REACH
	for node: Node in get_tree().get_nodes_in_group(&"cargo"):
		var package := node as DeliveryPackage
		if package == null or not package.is_inside_tree() or package.is_held or not package.is_loaded:
			continue
		if package.trap_state == ITrapBehavior.TrapState.RUINED:
			continue
		if vehicle != null and vehicle.has_method(&"carries") and bool(vehicle.call(&"carries", package.global_position)):
			continue
		var distance: float = package.global_position.distance_to(global_position)
		if distance <= best_distance:
			best_distance = distance
			best = package
	return best


func _rear_open() -> bool:
	var vehicle: Node = get_parent()
	return vehicle == null or not vehicle.has_method(&"is_door_open") or bool(vehicle.call(&"is_door_open", &"rear"))


func _on_run_ended(_score: int, _results: Dictionary) -> void:
	_set_armed(false)


func _is_online() -> bool:
	return multiplayer.multiplayer_peer != null \
			and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
