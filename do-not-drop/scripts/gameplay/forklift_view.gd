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
## On every peer the driver's player carries the meta `driving` (DRIVING_META) while it drives: nobody hands it a box.
## The host lets the forklift go when its driver leaves (CompanyNet, on peer_removed); here there is only a safety net
## for a driver's player that is gone without that (GONE_SECONDS).

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
## How often the driver's player is looked for among the players while it is not found (ms).
const LOOKUP_MSEC: int = 500
const PlayerSprint = preload("res://scripts/gameplay/player/player_sprint.gd")
## The meta the driver's player carries while it drives (PackageHandling.transfer(), PlayerCarry.transfer_target()).
const DRIVING_META: StringName = &"driving"
## The text a refusal of work shows (default: WORLD_FORKLIFT_REFUSED).
const REFUSAL_KEYS: Dictionary = {
	CompanyForklift.REASON_NO_PALLET: "WORLD_FORKLIFT_NO_PALLET",
	CompanyForklift.REASON_NO_ROOM: "WORLD_FORKLIFT_NO_ROOM",
	CompanyForklift.REASON_NO_RACK: "WORLD_FORKLIFT_NO_RACK",
	CompanyForklift.REASON_JACK_FULL: "WORLD_FORKLIFT_HANDS_FULL",
	CompanyForklift.REASON_TRUCK_AWAY: "WORLD_FORKLIFT_TRUCK_AWAY",
}
## ... and of getting off.
const LEAVE_REFUSAL_KEYS: Dictionary = {CompanyForklift.REASON_NO_ROOM: "WORLD_FORKLIFT_NO_PARK"}

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
## The driver the last refresh() drew (a change restarts the lookup and the wait for a gone player).
var _drawn_driver: int = 0
var _local_driving: bool = false
var _sent_dir: int = 0
var _sent_msec: int = 0
## The last request whose refusal the prompt shows (work, leave) and its act; -1 while it is being asked.
var _shown_rid: int = 0
var _shown_act: StringName = &""
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
	if state.driver != _drawn_driver:
		# Another driver: their player is looked for now, not at the next spaced lookup, and the wait for a gone
		# one starts over (only here: any pallet or stock event redraws, and must not put it off).
		_drawn_driver = state.driver
		_next_lookup_msec = 0
		_gone_since_msec = -1
		_set_driver_node(null)
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
		# This peer drives but its player was not found yet (spaced lookups): the keys are taken once it is.
		if state.driver == _my_id() and not _local_driving:
			_sync_local_driving()
		if _local_driving:
			_steer_mast(now)
	_carriage.position.y = state.height_at(now)
	if state.driver == 0 and not state.moving_at(now):
		set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if _local_driving and event.is_action_pressed(&"package_drop"):
		_ask_shown(CompanyForklift.ACT_LEAVE)
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_set_override(null)
	_set_driver_node(null)


## The driver's player, found among the players by the peer that drives (null when there is none here yet).
func _driver() -> Node3D:
	if _pallets == null or not is_inside_tree():
		return null
	var peer: int = _pallets.forklift.driver
	if is_instance_valid(_driver_node) and peer != 0 and _driver_node.get_multiplayer_authority() == peer:
		return _driver_node
	_set_driver_node(null)
	var now: int = Time.get_ticks_msec()
	if peer == 0 or now < _next_lookup_msec:
		return null
	_next_lookup_msec = now + LOOKUP_MSEC
	for node: Node in get_tree().get_nodes_in_group(Interactable.player_group):
		if node is Node3D and node.get_multiplayer_authority() == peer:
			_set_driver_node(node as Node3D)
			return _driver_node
	return null


## The driver's player carries DRIVING_META while it drives, on every peer (and loses it after).
func _set_driver_node(node: Node3D) -> void:
	if node == _driver_node:
		return
	if is_instance_valid(_driver_node) and _driver_node.has_meta(DRIVING_META):
		_driver_node.remove_meta(DRIVING_META)
		_driver_node.remove_meta(PlayerSprint.PACE_CAP_META)
	_driver_node = node
	if node != null:
		node.set_meta(DRIVING_META, true)
		node.set_meta(PlayerSprint.PACE_CAP_META, CompanyTuning.FORKLIFT_DRIVE_SPEED_MPS)


## Puts the forklift under the driver's player, facing where it faces. False while that player is not here.
func _follow_driver() -> bool:
	var driver: Node3D = _driver()
	if driver == null:
		return false
	var local: Vector3 = _shed_frame().to_local(driver.global_position)
	position = Vector3(local.x, 0.0, local.z)
	rotation.y = _yaw_of(driver)
	return true


## Host, a safety net: the driver's player is gone and CompanyNet did not let the forklift go (a leave it never
## heard of): after GONE_SECONDS without that player the forklift is let go where it stood. Only a new driver
## (refresh()) or the player found again restarts the wait.
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
		mine = _pallets.forklift.driver == _my_id() and _driver() != null
	var target: Node = _driver() if mine else null
	if mine == _local_driving and target == _override_node:
		return
	_local_driving = mine
	set_process_unhandled_input(mine)
	_set_override(target)
	_sent_dir = 0


## This peer's id; 0 while its connection is not up (a closed ENet peer refuses to say, with an error).
func _my_id() -> int:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer \
			or peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return multiplayer.get_unique_id()
	return 0


func _set_override(player: Node) -> void:
	if is_instance_valid(_override_node) and _override_node.has_meta(&"interact_override"):
		_override_node.remove_meta(&"interact_override")
	_override_node = player
	if player != null:
		player.set_meta(&"interact_override", {"use": _work, "prompt": _prompt})


## The mast keys: a request when the direction changes, and again while it is held; none while it is held against
## the end of the mast the forks reached, nor a stop for forks that are still already (this peer's burst is over, so
## the host's is too). A stop says the height drawn here (`at_height`): the host leaves the forks where the driver
## let go of the key, not a round trip further.
func _steer_mast(now: int) -> void:
	var dir: int = 0
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not keys_need_capture:
		dir = int(signf(Input.get_axis(&"forklift_mast_down", &"forklift_mast_up")))
	var drawn: float = fork_height()
	if dir == 0 and _sent_dir != 0 and not _pallets.forklift.moving_at(now):
		_sent_dir = 0
		return
	var at_end: bool = (dir > 0 and drawn >= CompanyTuning.FORKLIFT_MAX_LIFT_M - CompanyForklift.END_M) \
		or (dir < 0 and drawn <= CompanyForklift.END_M)
	if at_end or (dir == _sent_dir and (dir == 0 or float(now - _sent_msec) / 1000.0 < MAST_RESEND_S)):
		return
	_sent_dir = dir
	_sent_msec = now
	var ask: Dictionary = {"act": CompanyForklift.ACT_MAST, "dir": dir}
	if dir == 0:
		ask["at_height"] = drawn
	_ask(ask)


func _work() -> void:
	_ask_shown(CompanyForklift.ACT_WORK)


func _ask(data: Dictionary) -> int:
	return net.request(CompanyPallets.FORK_ACT, data) if net != null and is_instance_valid(net) else 0


## A request whose refusal the prompt shows (work, leave). The host's own is refused before request() returns, so
## the act is noted first and the rid after.
func _ask_shown(act: StringName) -> void:
	_shown_act = act
	_shown_rid = -1
	var rid: int = _ask({"act": act})
	if _shown_rid == -1:
		_shown_rid = rid
		# Nobody to ask: a refusal with rid 0 (the host's request_for) is not this one's.
		_shown_act = _shown_act if rid != 0 else &""


func _on_rejected(rid: int, reason: StringName) -> void:
	if _shown_act == &"" or (rid != _shown_rid and _shown_rid != -1):
		return
	var keys: Dictionary = LEAVE_REFUSAL_KEYS if _shown_act == CompanyForklift.ACT_LEAVE else REFUSAL_KEYS
	_refusal = String(keys.get(reason, "WORLD_FORKLIFT_REFUSED"))
	_refusal_until_msec = Time.get_ticks_msec() + int(REFUSAL_SECONDS * 1000.0)
	_shown_act = &""
	_shown_rid = 0


## What the prompt says while driving: the last refusal for a moment, else the keys.
func _prompt() -> String:
	if _refusal != "" and Time.get_ticks_msec() < _refusal_until_msec:
		return tr(_refusal)
	# Looked up at run time: tests preload this script before the autoloads exist as identifiers.
	var settings: Node = get_node_or_null(^"/root/GameSettings")
	var labels: Array = []
	for action: StringName in [&"interact", &"forklift_mast_up", &"forklift_mast_down", &"package_drop"]:
		labels.append(settings.binding_label(action) if settings != null else "?")
	return tr("WORLD_FORKLIFT_DRIVING") % labels


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
