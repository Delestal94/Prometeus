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

const _HOUSE := preload("res://scripts/gameplay/route/delivery_house.gd")

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

	if _failures == 0:
		print("PASS: HUD node keeps hud.gd in a --script run; care card EDGE_MARGIN matches the HUD's")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
