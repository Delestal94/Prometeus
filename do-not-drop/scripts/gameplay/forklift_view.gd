class_name ForkliftView
extends Node3D
## The forklift of the shed as the players see and drive it (expansion D-0606.b, "Modo Empresa"), a child of
## PalletYardView.
##
## It only DRAWS state: who drives, where it stands when nobody does, the height of the forks and the pallet on
## them are CompanyPallets.forklift and the book, the host's and equal on every peer. Nothing travels per frame:
## while somebody drives, the forklift is wherever their Player is (every peer reads that player's own replicated
## pose), facing where the player faces, so "driving" is walking with the normal movement. The driver's peer sends
## the few requests of CompanyForklift (mast up and down, work, leave); the host judges them.
##
## Grey-box stand-in made of boxes (docs/expansion-distritos/arte-pendiente/D-0606.md), built facing -Z with its
## origin on the floor under the driver: chassis, wheels, a mast and a carriage with two forks that rides up it. A
## pallet on the forks (PalletBox) lies CompanyTuning.FORKLIFT_TIP_M ahead of the origin.
##
## Controls of the local driver: the interact key takes / leaves a pallet (PlayerInteraction's
## `interact_override`), forklift_mast_up / forklift_mast_down raise and lower the forks, package_drop gets off.
## The host also lets the forklift go when its driver's player is gone for good.

signal used(action: StringName, peer_id: int, from: Vector3)

const FRAME_COLOR: Color = Color(0.58, 0.59, 0.61)
const DARK_COLOR: Color = Color(0.30, 0.31, 0.33)
const FORK_THICKNESS: float = 0.05
const MAST_HEIGHT: float = 2.7
## Seconds between two mast requests while the key is held (under CompanyTuning.FORKLIFT_MAST_BURST_S).
const MAST_RESEND_S: float = 0.35
## How long a refusal stays in the prompt, and how long the host waits for a vanished driver's player.
const REFUSAL_SECONDS: float = 3.0
const GONE_SECONDS: float = 1.5
## The text a refusal shows (default: WORLD_FORKLIFT_REFUSED).
const REFUSAL_KEYS: Dictionary = {
	CompanyForklift.REASON_NO_PALLET: "WORLD_FORKLIFT_NO_PALLET",
	CompanyForklift.REASON_NO_ROOM: "WORLD_FORKLIFT_NO_ROOM",
	CompanyForklift.REASON_NO_RACK: "WORLD_FORKLIFT_NO_RACK",
	CompanyForklift.REASON_JACK_FULL: "WORLD_FORKLIFT_HANDS_FULL",
	CompanyForklift.REASON_TRUCK_AWAY: "WORLD_FORKLIFT_TRUCK_AWAY",
}

## The seat: a point to get on when nobody drives.
var seat_point: PalletJackPoint
## The mast keys count only with the mouse captured (no menu open); a test turns it off.
var keys_need_capture: bool = true
## The CompanyNet the requests go to (CompanyShed sets it); null draws and nothing else.
var net: CompanyNet:
	set(value):
		net = value
		if net != null and not net.request_rejected.is_connected(_on_rejected):
			net.request_rejected.connect(_on_rejected)

var _pallets: CompanyPallets
var _home: Vector2 = Vector2.ZERO
var _carriage: Node3D
var _carried: Node3D
var _carried_id: StringName = &""
var _driver_node: Node3D
var _override_node: Node
var _next_lookup_msec: int = 0
var _gone_since_msec: int = -1
var _local_driving: bool = false
var _sent_dir: int = 0
var _sent_msec: int = 0
var _work_rids: Dictionary = {}
var _refusal: String = ""
var _refusal_until_msec: int = 0


## A forklift parked at `home` (the shed's frame, metres), facing `heading`.
static func make(home: Vector2, heading: float) -> ForkliftView:
	var view := ForkliftView.new()
	view.name = "Forklift"
	view._home = home
	view.position = Vector3(home.x, 0.0, home.y)
	view.rotation.y = heading
	view._build()
	view.set_process(false)
	view.set_process_unhandled_input(false)
	return view


## Draws `pallets` (the book and the forklift's state): who drives, where it stands, the forks and their pallet.
func refresh(pallets: CompanyPallets) -> void:
	_pallets = pallets
	var state: CompanyForklift = pallets.forklift
	seat_point.taken = state.driver != 0
	var book: PalletJack = pallets.book
	if book.carrying != &"" and state.holds:
		_show_carried(book.places[book.carrying]["pallet"])
	else:
		_show_carried({})
	if state.driver == 0 or not _follow_driver():
		var parked: Vector2 = state.at if state.at is Vector2 else _home
		position = Vector3(parked.x, 0.0, parked.y)
		rotation.y = state.yaw if state.at is Vector2 else rotation.y
	_carriage.position.y = state.height_at(Time.get_ticks_msec())
	_gone_since_msec = -1
	_sync_local_driving()
	set_process(state.driver != 0 or state.moving_at(Time.get_ticks_msec()))


## Where it stands now and which way it faces, in the shed's frame: where the driver's player is while somebody
## drives (the host judges a request by this), else where it was left. {body: Vector2, yaw: float}.
func pose() -> Dictionary:
	if _pallets != null and _pallets.forklift.driver != 0 and _driver() != null:
		var local: Vector3 = _shed_frame().to_local(_driver().global_position)
		return {"body": Vector2(local.x, local.z), "yaw": _yaw_of(_driver())}
	return {"body": Vector2(position.x, position.z), "yaw": rotation.y}


## The id of the pallet drawn on the forks, &"" for none.
func carried_id() -> StringName:
	return _carried_id


## The height of the forks as drawn now.
func fork_height() -> float:
	return _carriage.position.y


## Whether this peer's own player drives it (and so the keys are theirs).
func is_local_driving() -> bool:
	return _local_driving


func _process(_delta: float) -> void:
	if _pallets == null:
		return
	var state: CompanyForklift = _pallets.forklift
	var now: int = Time.get_ticks_msec()
	if state.driver != 0:
		_follow_driver()
		_release_if_gone(state, now)
		if _local_driving:
			_steer_mast(now)
	_carriage.position.y = state.height_at(now)
	if state.driver == 0 and not state.moving_at(now):
		set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if _local_driving and event.is_action_pressed(&"package_drop"):
		_ask({"act": CompanyForklift.ACT_LEAVE})
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_set_override(null)


## The driver's player, found among the players by the peer that drives (null when there is none here yet).
func _driver() -> Node3D:
	if _pallets == null or not is_inside_tree():
		return null
	if is_instance_valid(_driver_node) and _driver_node.get_multiplayer_authority() == _pallets.forklift.driver:
		return _driver_node
	_driver_node = null
	var now: int = Time.get_ticks_msec()
	if now < _next_lookup_msec:
		return null
	_next_lookup_msec = now + 500
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		if node is Node3D and node.get_multiplayer_authority() == _pallets.forklift.driver:
			_driver_node = node as Node3D
			return _driver_node
	return null


## Puts the forklift under the driver's player, facing where it faces. False while that player is not here.
func _follow_driver() -> bool:
	var driver: Node3D = _driver()
	if driver == null:
		return false
	var local: Vector3 = _shed_frame().to_local(driver.global_position)
	position = Vector3(local.x, 0.0, local.z)
	rotation.y = _yaw_of(driver)
	return true


## Host: the driver's player is gone (the peer left): after GONE_SECONDS the forklift is let go where it stood.
func _release_if_gone(state: CompanyForklift, now: int) -> void:
	if net == null or not net.is_host() or _driver() != null:
		_gone_since_msec = -1
		return
	if _gone_since_msec < 0:
		_gone_since_msec = now
	elif float(now - _gone_since_msec) / 1000.0 >= GONE_SECONDS:
		_gone_since_msec = -1
		net.publish(CompanyPallets.FORK, CompanyForklift.state_event(0, Vector2(position.x, position.z),
			rotation.y, 0, state.height_at(now)))


func _shed_frame() -> Node3D:
	return get_parent_node_3d() if get_parent_node_3d() != null else self


## The heading of a body as Node3D rotation.y: it faces -Z at 0.
static func _yaw_of(body: Node3D) -> float:
	var back: Vector3 = body.global_basis.z
	return atan2(back.x, back.z)


# --- The local driver ---


## This peer's own player takes the interact key and the prompt while it drives (and gives them back after).
func _sync_local_driving() -> void:
	var mine: bool = false
	if _pallets != null and is_inside_tree() and _pallets.forklift.driver != 0:
		mine = _pallets.forklift.driver == multiplayer.get_unique_id() and _driver() != null
	var target: Node = _driver() if mine else null
	if mine == _local_driving and target == _override_node:
		return
	_local_driving = mine
	set_process_unhandled_input(mine)
	_set_override(target)
	_sent_dir = 0


func _set_override(player: Node) -> void:
	if is_instance_valid(_override_node) and _override_node.has_meta(&"interact_override"):
		_override_node.remove_meta(&"interact_override")
	_override_node = player
	if player != null:
		player.set_meta(&"interact_override", {"use": _work, "prompt": _prompt})


## The mast keys: a request when the direction changes, and again while it is held.
func _steer_mast(now: int) -> void:
	var dir: int = 0
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not keys_need_capture:
		dir = int(signf(Input.get_axis(&"forklift_mast_down", &"forklift_mast_up")))
	if dir == _sent_dir and (dir == 0 or float(now - _sent_msec) / 1000.0 < MAST_RESEND_S):
		return
	_sent_dir = dir
	_sent_msec = now
	_ask({"act": CompanyForklift.ACT_MAST, "dir": dir})


func _work() -> void:
	var rid: int = _ask({"act": CompanyForklift.ACT_WORK})
	if rid != 0:
		_work_rids[rid] = true


func _ask(data: Dictionary) -> int:
	return net.request(CompanyPallets.FORK_ACT, data) if net != null and is_instance_valid(net) else 0


func _on_rejected(rid: int, reason: StringName) -> void:
	if not _work_rids.has(rid):
		return
	_work_rids.erase(rid)
	_refusal = String(REFUSAL_KEYS.get(reason, "WORLD_FORKLIFT_REFUSED"))
	_refusal_until_msec = Time.get_ticks_msec() + int(REFUSAL_SECONDS * 1000.0)


## What the prompt says while driving: the last refusal for a moment, else the keys.
func _prompt() -> String:
	if _refusal != "" and Time.get_ticks_msec() < _refusal_until_msec:
		return tr(_refusal)
	return tr("WORLD_FORKLIFT_DRIVING")


# --- Drawing ---


func _show_carried(pallet: Dictionary) -> void:
	var id := StringName(pallet.get("id", &""))
	if id == _carried_id:
		return
	_carried_id = id
	if _carried != null:
		_carriage.remove_child(_carried)
		_carried.queue_free()
		_carried = null
	if id == &"":
		return
	_carried = PalletBox.build(pallet, true)
	_carried.position = Vector3(0.0, FORK_THICKNESS, -CompanyTuning.FORKLIFT_TIP_M)
	_carriage.add_child(_carried)


func _build() -> void:
	var frame: Material = DepotKit.flat(FRAME_COLOR)
	var dark: Material = DepotKit.flat(DARK_COLOR)
	_part(self, "Chassis", Vector3(1.0, 0.5, 1.5), Vector3(0.0, 0.45, 0.45), frame)
	_part(self, "Counterweight", Vector3(1.0, 0.45, 0.4), Vector3(0.0, 0.95, 1.0), dark)
	for side: float in [-1.0, 1.0]:
		_part(self, "FrontWheel", Vector3(0.2, 0.5, 0.5), Vector3(side * 0.5, 0.25, -0.05), dark)
		_part(self, "RearWheel", Vector3(0.2, 0.4, 0.4), Vector3(side * 0.5, 0.2, 0.95), dark)
		_part(self, "Upright", Vector3(0.07, MAST_HEIGHT, 0.1), Vector3(side * 0.36, MAST_HEIGHT * 0.5, -0.45), dark)
	_carriage = Node3D.new()
	_carriage.name = "Carriage"
	add_child(_carriage)
	_part(_carriage, "Backrest", Vector3(0.9, 0.8, 0.05), Vector3(0.0, 0.4, -0.6), frame)
	for side: float in [-1.0, 1.0]:
		_part(_carriage, "Fork", Vector3(0.1, FORK_THICKNESS, 1.2),
			Vector3(side * 0.3, FORK_THICKNESS * 0.5, -1.2), dark)
	seat_point = PalletJackPoint.make(PalletJackPoint.ACTION_BOARD, Vector3(0.0, 0.9, 0.3), 1.0)
	seat_point.used.connect(func(how: StringName, peer_id: int, origin: Vector3) -> void:
		used.emit(how, peer_id, origin))
	add_child(seat_point)


func _part(parent: Node3D, part_name: String, size: Vector3, at: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	part.mesh = mesh
	part.position = at
	parent.add_child(part)
