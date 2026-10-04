extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_hud_script_loads.gd
##
## The HUD keeps its script in a --script run (N-919, regression of #208). A
## --script run compiles the test's static dependency tree before the autoloads
## exist; #208 made DeliveryHouse -> ... -> Player -> player_cargo_care.gd -> Hud
## a static chain, and hud.gd names the NetworkManager autoload, so it failed to
## compile and the HUD node of level_base.tscn loaded as a bare CanvasLayer with
## no script (CI missed it: the runner judges by exit code).
## - This script reaches DeliveryHouse statically on purpose (the _HOUSE const),
##   like a test that touches the route does, then instances level_base.tscn and
##   expects its "HUD" node to run hud.gd.
## - player_cargo_care.gd keeps a local EDGE_MARGIN instead of naming Hud; this
##   checks it equals Hud.EDGE_MARGIN (hud.gd is load()ed at runtime here so the
##   test does not create the static edge itself).
## - It also reaches Depot statically (the _DEPOT const): depot.gd used to type
##   RunManager, CrewProgression, RescueHook and VehicleFaults, which name the
##   EventBus autoload, so they failed to compile and /root/RunManager ran with
##   no script (N-919.2). Those scripts must still compile here.
## - It reaches CompanyState statically too (the _COMPANY const, D-0202.3): the
##   company autoload sits after UnlockManager and must not drag a UI class or
##   another autoload into a --script tree, so the autoloads survive it.

const _HOUSE := preload("res://scripts/gameplay/route/delivery_house.gd")
const _DEPOT := preload("res://scripts/gameplay/depot/depot.gd")
const _COMPANY := preload("res://scripts/core/company/company_state.gd")
const EVENT_BUS_USERS: Array[String] = [
	"res://scripts/core/run_manager.gd",
	"res://scripts/core/crew_progression.gd",
	"res://scripts/gameplay/vehicle/rescue_hook.gd",
	"res://scripts/gameplay/vehicle/vehicle_faults.gd",
]

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# --- local EDGE_MARGIN matches the HUD's ---
	var hud_script: Script = load("res://scripts/ui/hud/hud.gd")
	_expect(hud_script != null and hud_script.can_instantiate(),
		"hud.gd compiles in a --script run (got %s)" % hud_script)
	var care_script: Script = load("res://scripts/gameplay/player/player_cargo_care.gd")
	_expect(care_script != null, "player_cargo_care.gd loads (got %s)" % care_script)
	if hud_script != null and care_script != null:
		var hud_consts: Dictionary = hud_script.get_script_constant_map()
		var care_consts: Dictionary = care_script.get_script_constant_map()
		_expect(hud_consts.has("EDGE_MARGIN") and care_consts.has("EDGE_MARGIN"),
			"Both scripts define EDGE_MARGIN")
		_expect(hud_consts.get("EDGE_MARGIN") == care_consts.get("EDGE_MARGIN"),
			"Care card EDGE_MARGIN matches Hud.EDGE_MARGIN (got %s vs %s)"
			% [care_consts.get("EDGE_MARGIN"), hud_consts.get("EDGE_MARGIN")])

	# --- the level's HUD node keeps its script ---
	_expect(_HOUSE != null, "DeliveryHouse is reached statically (got %s)" % _HOUSE)
	var scene: PackedScene = load("res://scenes/gameplay/level_base.tscn")
	var level: Node = scene.instantiate()
	var hud: Node = level.get_node_or_null(^"HUD")
	_expect(hud != null, "level_base.tscn has a HUD node")
	if hud != null:
		var script: Script = hud.get_script()
		_expect(script != null, "HUD node keeps its script (got %s)" % script)
		_expect(script != null and script.resource_path.ends_with("hud.gd"),
			"HUD node runs hud.gd (got %s)" % (script.resource_path if script else "null"))
	# Never added to the tree: free it directly.
	level.free()

	# --- the Depot chain leaves the autoload scripts compilable ---
	_expect(_DEPOT != null, "Depot is reached statically (got %s)" % _DEPOT)
	for path: String in EVENT_BUS_USERS:
		var script: Script = load(path)
		_expect(script != null and script.can_instantiate(),
			"%s compiles in a --script run that names Depot" % path.get_file())
	var run_manager: Node = root.get_node_or_null(^"RunManager")
	_expect(run_manager != null and run_manager.get_script() != null,
		"The RunManager autoload keeps its script (got %s)"
		% (run_manager.get_script() if run_manager != null else "no node"))

	# --- the company autoload keeps its script and the others survive it ---
	var company_script: Script = _COMPANY
	_expect(company_script != null and company_script.can_instantiate(),
		"company_state.gd compiles in a --script run that names it")
	for autoload_name: StringName in [&"EventBus", &"NetworkManager", &"UnlockManager",
			&"CompanyState", &"ProximityVoice", &"RunTelemetry"]:
		var autoload: Node = root.get_node_or_null(NodePath(autoload_name))
		_expect(autoload != null and autoload.get_script() != null,
			"The %s autoload keeps its script when CompanyState is named" % autoload_name)
	var company: Node = root.get_node_or_null(^"CompanyState")
	_expect(company != null and not company.is_active(),
		"CompanyState is inactive in a plain --script run")

	if _failures == 0:
		print("PASS: HUD, RunManager and CompanyState keep their scripts in a --script run; "
			+ "care card EDGE_MARGIN matches the HUD's")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
