extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_company_root.gd
##
## Root scene of the Modo Empresa (expansion D-0214, company_root.gd,
## scenes/gameplay/company_root.tscn, main_menu.gd --mode=company):
## - it loads and builds with no errors, switching the company on (CompanyState);
## - there is one slab per data/zones/*.tres (nine) and a shed with its floor and
##   three walls, all with collision;
## - the local player stands inside the shed, on the floor;
## - it has a CompanyNet child (D-2003) holding the company's stock;
## - the main menu knows the scene, the --mode=company flag and has the button.

const SCENE: String = "res://scenes/gameplay/company_root.tscn"

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
		_expect(net.inventory.to_dict() == stock.to_dict(), "CompanyNet starts from the company's stock")

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
	state.call(&"reset")
	if _failures == 0:
		print("PASS: company root builds the shed and nine zones, company on, player inside, menu flag")
	quit(_failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
