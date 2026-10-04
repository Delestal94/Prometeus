extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_root.gd
##
## Root scene of the Modo Empresa (expansion D-0214, company_root.gd,
## scenes/gameplay/company_root.tscn, main_menu.gd --mode=company):
## - it loads and builds with no errors, switching the company on (CompanyState);
## - there is one slab per data/zones/*.tres (nine) and a shed with its floor and
##   three walls, all with collision;
## - the local player stands inside the shed, on the floor;
## - it has a CompanyNet child (D-2003); solo is the host, so it switches the company on
##   and holds its stock (a client would wait for the host's snapshot instead); it hands
##   CompanyNet the CompanyState node, whose to_dict() the snapshot carries (D-2004);
## - on a client (a session that isn't the host) it waits for the snapshot without touching
##   CompanyState; the snapshot loads the host's company there, and leaving the root puts back
##   what the client had (switched off when it had none, its own company when it had one);
## - the main menu knows the scene, the --mode=company flag and has the button.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"
const STATE_SCRIPT: String = "res://scripts/core/company/company_state.gd"
## Nobody listens here: the client stays connecting, which is enough not to be the host.
const CLOSED_PORT: int = 24639

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var state: Node = root.get_node(^"/root/CompanyState")
	state.call(&"reset")
	var level: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	_expect(bool(state.call(&"is_active")), "Entering the root switches the company on")
	var net: CompanyNet = level.get_node_or_null(^"CompanyNet") as CompanyNet
	_expect(net != null and net == level.get(&"net"), "The root has its CompanyNet child (D-2003)")
	if net != null:
		var stock: Inventory = state.call(&"stock")
		_expect(net.inventory.to_dict() == stock.to_dict() and not net.awaiting_snapshot(),
			"Solo counts as host: CompanyNet starts from the company's stock, not waiting for a snapshot")
		_expect(net.company == state, "CompanyNet gets the CompanyState node for the snapshot")

	var zone_files: int = 0
	for file: String in DirAccess.get_files_at("res://data/zones/"):
		if file.ends_with(".tres"):
			zone_files += 1
	var slabs: int = 0
	for child: Node in level.get_node(^"World").get_children():
		if child.name.begins_with("Zone_"):
			slabs += 1
			_expect(child.get_child_count() >= 2, "%s has collision, mesh and name" % child.name)
	_expect(slabs == zone_files and slabs == 9, "One slab per zone .tres (%d slabs, %d files)" % [slabs, zone_files])

	var shed: Node = level.get_node(^"World/Shed")
	for part: String in ["Floor", "WallBack", "WallLeft", "WallRight"]:
		_expect(shed.get_node_or_null(NodePath(part)) is StaticBody3D, "The shed has %s" % part)

	var player: Node3D = level.get(&"player")
	_expect(player != null and player.is_inside_tree(), "The local player is in the scene")
	if player != null:
		var half: Vector2 = CompanyRoot.SHED_SIZE * 0.5
		_expect(absf(player.global_position.x) < half.x and absf(player.global_position.z) < half.y,
			"The player starts inside the shed (%s)" % player.global_position)
		for _i: int in range(90):
			await physics_frame
		var height: float = player.global_position.y
		_expect(height > -1.0, "The player stands on the floor, not falling (y=%.2f)" % height)

	var menu_source: String = FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_expect(menu_source.contains(SCENE) and menu_source.contains("--mode=company"),
		"The main menu opens this scene with --mode=company")
	_expect(menu_source.contains("pressed.connect(_play_company)"), "The Play page has a Modo Empresa button")

	level.queue_free()
	await process_frame
	await _check_client_restores(state)
	state.call(&"reset")
	if _failures == 0:
		print("PASS: company root builds the shed and nine zones, company on, player inside, menu flag")
	quit(_failures)


## A client loads the host's company from the snapshot; leaving the root puts its own back.
func _check_client_restores(state: Node) -> void:
	var host_state: Node = (load(STATE_SCRIPT) as GDScript).new()
	host_state.call(&"new_company", "Host SRL")
	host_state.call(&"earn", 900, &"order_paid")
	host_state.call(&"open_gate", &"gate_campo")
	var host := CompanyNet.new()
	host.company = host_state
	host.inventory.receive(&"hen", 5, &"dock")
	host.seq = 7
	var snapshot: Dictionary = host.snapshot()
	for own_name: String in ["", "Mine"]:
		state.call(&"reset")
		if own_name != "":
			state.call(&"new_company", own_name)
			state.call(&"earn", 15, &"order_paid")
		var before: Dictionary = state.call(&"to_dict")
		var was_active: bool = state.call(&"is_active")
		var side := Node.new()
		side.name = "ClientSide"
		root.add_child(side)
		set_multiplayer(SceneMultiplayer.new(), side.get_path())
		var peer := ENetMultiplayerPeer.new()
		_expect(peer.create_client("127.0.0.1", CLOSED_PORT) == OK, "A client session starts")
		side.multiplayer.multiplayer_peer = peer
		var level: Node = (load(SCENE) as PackedScene).instantiate()
		side.add_child(level)
		await process_frame
		var net: CompanyNet = level.get(&"net")
		var label: String = "with no company" if own_name == "" else "with its own company"
		_expect(net != null and not net.is_host() and net.awaiting_snapshot()
			and state.call(&"to_dict") == before,
			"A client %s waits for the snapshot and leaves CompanyState as it was" % label)
		if net != null:
			_expect(net.apply_snapshot(snapshot) and state.get(&"company_name") == "Host SRL"
				and bool(state.call(&"is_active")),
				"The snapshot loads the host's company into the client's CompanyState (%s)" % label)
		level.queue_free()
		await process_frame
		_expect(bool(state.call(&"is_active")) == was_active and state.call(&"to_dict") == before,
			"Leaving the root puts back what the client had %s (active %s, name '%s')"
			% [label, state.call(&"is_active"), state.get(&"company_name")])
		peer.close()
		set_multiplayer(null, side.get_path())
		side.free()
	host.free()
	host_state.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
