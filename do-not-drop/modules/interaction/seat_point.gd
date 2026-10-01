class_name SeatPoint
extends Interactable
## Lets a player board this seat: hides them, switches to its first-person
## camera, and -- for the driver's seat -- enables driving input. Whoever
## reaches a seat first takes that role; nothing assigns roles in advance.
## Portable module (docs/modulos.md): what a game's seat does besides
## seating (a passenger taking charge of the cargo beside them) goes in the
## hooks at the end.
##
## interact() only ever runs on the host (see Interactable), so it's the
## right place to touch the vehicle directly. The camera swap is the
## player's own local, visual state, though, so it goes out as an RPC
## targeted at that specific peer.
##
## Contracts: the player answers `seat_node_path` (replicated: the seat
## anchor it sits in, empty when on foot), `is_local()`, and takes the RPC
## `board_seat(camera_path, seat_path)`; the vehicle at `vehicle_path` has
## `driver_peer_id` and `controls_enabled`, optionally `is_door_open(name)`
## and `set_controls(throttle, steer, brake)`.

@export var role: StringName = &"driver"  ## "driver" or "passenger"
@export var seat_camera_path: NodePath
@export var vehicle_path: NodePath
## A seat behind one of the vehicle's doors (the driver's, behind the cab
## door) can only be reached with that door open.
@export var required_door: StringName = &""
## Translation keys of the prompts (tr()).
@export var drive_prompt_key: String = "Drive"
@export var sit_prompt_key: String = "Sit"

## The marker's colours while free and once someone's seated.
static var free_color: Color = Color("83e2ba")
static var taken_color: Color = Color("f47e6d")

## Host-only: interact() (and so this) only ever runs on the host, so other
## clients' copies of this same node never see it change. Fine for the
## can_interact()/interact() logic below (host-authoritative anyway), but
## no use for a visual indicator everyone needs to see -- see is_occupied().
var occupant: Node = null
var _own_seat_path: NodePath = NodePath()
var _indicator: MeshInstance3D
var _indicator_material: StandardMaterial3D
var _indicator_occupied: Variant = null

## Who sits where, worked out once per frame for every seat's marker instead
## of once per seat: seat path -> true, and the seat this client's own player
## is in (empty when none).
static var _seating_frame: int = -1
static var _seated_paths: Dictionary = {}
static var _local_seat_path: NodePath = NodePath()


func _ready() -> void:
	super._ready()
	_own_seat_path = get_parent().get_path()
	_build_indicator()


## A small glowing marker instead of only the prompt text: green while
## free, red once someone's seated -- readable from across the cabin, not
## just when close enough to trigger the interact prompt. Derived from every
## player's own replicated seat_node_path rather than `occupant`, so it
## updates correctly on every client, not just the host's.
func _build_indicator() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	_indicator_material = StandardMaterial3D.new()
	_indicator_material.emission_enabled = true
	_indicator_material.emission_energy_multiplier = 1.4
	_indicator = MeshInstance3D.new()
	_indicator.mesh = sphere
	_indicator.material_override = _indicator_material
	_indicator.position = Vector3(0.0, 0.3, 0.0)
	add_child(_indicator)
	_update_indicator()


func _process(_delta: float) -> void:
	_update_indicator(false)


func _refresh_seating(tree: SceneTree, force: bool) -> void:
	var frame: int = Engine.get_process_frames()
	if not force and frame == _seating_frame:
		return
	_seating_frame = frame
	_seated_paths.clear()
	_local_seat_path = NodePath()
	var found_local: bool = false
	for player: Node in tree.get_nodes_in_group(player_group):
		var seat: NodePath = NodePath(player.get(&"seat_node_path"))
		_seated_paths[seat] = true
		if not found_local and player.has_method(&"is_local") and bool(player.call(&"is_local")):
			found_local = true
			_local_seat_path = seat


## `force` looks at the players again even if this frame already did.
func _update_indicator(force: bool = true) -> void:
	_refresh_seating(get_tree(), force)
	var occupied: bool = _seated_paths.has(_own_seat_path)
	# The marker is for everyone else: whoever sits here would see it glowing
	# at their shoulder whenever they turn their head.
	_indicator.visible = _local_seat_path != _own_seat_path
	# Rewriting the material every frame re-uploaded it for nothing; the
	# colour only changes when someone sits down or gets up.
	if occupied == _indicator_occupied:
		return
	_indicator_occupied = occupied
	var color: Color = taken_color if occupied else free_color
	_indicator_material.albedo_color = color
	_indicator_material.emission = color


## Whether any player's replicated seat is this one (true on every peer).
func is_occupied() -> bool:
	for player: Node in get_tree().get_nodes_in_group(player_group):
		if NodePath(player.get(&"seat_node_path")) == _own_seat_path:
			return true
	return false


func get_prompt() -> String:
	if is_occupied():
		return ""
	return _free_prompt()


func can_interact(player: Node) -> bool:
	if is_instance_valid(occupant) or is_occupied():
		return false
	if required_door != &"":
		var door_vehicle: Node = get_node_or_null(vehicle_path)
		if door_vehicle != null and door_vehicle.has_method(&"is_door_open") \
				and not bool(door_vehicle.call(&"is_door_open", required_door)):
			return false
	return _can_board(player)


func interact(player: Node) -> void:
	if not can_interact(player) or not _accept_boarding(player):
		return
	occupant = player
	var peer_id: int = int(player.get_multiplayer_authority())
	var camera: Node = get_node_or_null(seat_camera_path)
	var vehicle: Node = get_node_or_null(vehicle_path)
	if role == &"driver" and vehicle != null:
		# The vehicle is host-authoritative, and interact() only ever runs on
		# the host -- this is the real state, not a copy.
		vehicle.set(&"controls_enabled", true)
		vehicle.set(&"driver_peer_id", peer_id)
	if player.has_method(&"board_seat"):
		var camera_path: NodePath = camera.get_path() if camera != null else NodePath()
		# The seat anchor itself (this Area3D's parent) -- an absolute path so
		# it resolves the same way from the player's own position in the
		# tree, which is a sibling of the vehicle, not a child.
		var seat_path: NodePath = get_parent().get_path()
		player.rpc_id(peer_id, &"board_seat", camera_path, seat_path)
	_on_boarded(player, peer_id)
	interacted.emit(player)


## The player owns the local "leave seat" gesture, but driving state is host
## authoritative. Clearing it here prevents the same input from being read
## by both the on-foot controller and the vehicle after the driver exits.
@rpc("any_peer", "call_local", "reliable")
func release_occupant(peer_id: int) -> void:
	if not multiplayer.is_server() or not RpcGuard.allow_request(self):
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != peer_id:
		return
	if is_instance_valid(occupant) and int(occupant.get_multiplayer_authority()) == peer_id:
		occupant = null
	_on_released(peer_id)
	if role != &"driver":
		return
	var vehicle: Node = get_node_or_null(vehicle_path)
	if vehicle == null or int(vehicle.get(&"driver_peer_id")) != peer_id:
		return
	vehicle.set(&"driver_peer_id", 0)
	vehicle.set(&"controls_enabled", false)
	if vehicle.has_method(&"set_controls"):
		vehicle.call(&"set_controls", 0.0, 0.0, true)


# --- Hooks the game fills in ---------------------------------------------------

## The prompt while the seat is free.
func _free_prompt() -> String:
	return tr(drive_prompt_key) if role == &"driver" else tr(sit_prompt_key)


## Whether `player` may target this seat at all (beyond it being free and
## its door open). A seat that answers true but refuses in _accept_boarding
## still shows its prompt, which can say why.
func _can_board(_player: Node) -> bool:
	return true


## The last word before seating: false leaves the player where they are.
func _accept_boarding(_player: Node) -> bool:
	return true


## The player is seated (host). What else this seat gives them goes here.
func _on_boarded(_player: Node, _peer_id: int) -> void:
	pass


## The player left (host), before the driving state is cleared.
func _on_released(_peer_id: int) -> void:
	pass
