extends "res://scripts/gameplay/interaction/interactable.gd"
## Lets a player board this seat: hides them, switches to its first-person
## camera, and -- for the driver's seat -- enables driving input. Whoever
## reaches a seat first takes that role; nothing assigns roles in advance.
##
## interact() only ever runs on the host (see interactable.gd), so it's the
## right place to touch the vehicle directly. The camera swap and the
## passenger's own package assignment are someone else's local, visual
## state, though, so those go out as an RPC targeted at that specific peer.

@export var role: StringName = &"driver"  ## "driver" or "passenger"
@export var seat_camera_path: NodePath
@export var vehicle_path: NodePath
@export var required_mount_path: NodePath

## Host-only: interact() (and so this) only ever runs on the host, so other
## clients' copies of this same node never see it change. Fine for the
## can_interact()/interact() logic below (host-authoritative anyway), but
## no use for a visual indicator everyone needs to see -- see _is_occupied().
var occupant: Node = null
var _own_seat_path: NodePath = NodePath()
var _indicator: MeshInstance3D
var _indicator_material: StandardMaterial3D


func _ready() -> void:
	super._ready()
	_own_seat_path = get_parent().get_path()
	_build_indicator()


## A small glowing marker (item #94) instead of only the prompt text: green
## while free, red once someone's seated -- readable from across the cabin,
## not just when close enough to trigger the interact prompt. Derived from
## every Player's own replicated seat_node_path (see player.gd's #81 work)
## rather than `occupant`, so it updates correctly on every client, not just
## the host's.
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
	_update_indicator()


func _update_indicator() -> void:
	var color: Color = Color("f47e6d") if _is_occupied() else Color("83e2ba")
	_indicator_material.albedo_color = color
	_indicator_material.emission = color


func _is_occupied() -> bool:
	for player: Node in get_tree().get_nodes_in_group(&"player"):
		if NodePath(player.get(&"seat_node_path")) == _own_seat_path:
			return true
	return false


func get_prompt() -> String:
	if occupant != null:
		return ""
	return "Subirse a manejar" if role == &"driver" else "Sentarse"


func can_interact(player: Node) -> bool:
	if occupant != null or player.get(&"carried_package") != null:
		return false
	if not required_mount_path.is_empty():
		var mount: Node = get_node_or_null(required_mount_path)
		return mount != null and is_instance_valid(mount.get(&"occupied_by"))
	return true


func interact(player: Node) -> void:
	if not can_interact(player):
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
		# The seat anchor itself (this Area3D's parent, e.g. DriverEyePoint) --
		# an absolute path so it resolves the same way from the player's own
		# position in the tree, which is a sibling of the vehicle, not a child.
		var seat_path: NodePath = get_parent().get_path()
		player.rpc_id(peer_id, &"board_seat", camera_path, seat_path)
	if role != &"driver" and not required_mount_path.is_empty():
		# A passenger takes charge of the package at their own seat: from here
		# their input is what keeps that trap under control.
		var mount: Node = get_node_or_null(required_mount_path)
		var package: Node = mount.get(&"occupied_by") if mount != null else null
		if package != null and player.has_method(&"tend_package"):
			player.rpc_id(peer_id, &"tend_package", (package as Node).get_path())
	interacted.emit(player)
