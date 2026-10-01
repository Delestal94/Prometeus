extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_dynamic_dispatch_budget.gd
##
## N-224: calls by name (`.call(&"…")`, `.callv(`, `.get(&"…")`) and
## `/root/` paths only break at runtime when something is renamed. The files
## already moved to typed references keep them low:
## - each file in BUDGETS has at most its budget of each kind (a ratchet:
##   lower the number when a file drops more, never raise it);
## - the typed autoload handles (HANDLES: crew_progression.gd's NETWORK_MANAGER,
##   RUN_MANAGER, ROUTE_EVENT_MANAGER; route_event_manager.gd's
##   CREW_PROGRESSION, NETWORK_MANAGER, RUN_MANAGER) are the scripts the
##   autoloads really run: `get_node_or_null(...) as <handle>` would quietly
##   give null if an autoload moved to another script, and the crew would stop
##   seeing the network, the route events and the delivery photos, or the route
##   events would stop paying and fining;
## - depot.gd is no autoload, so its handles (SCRIPT_HANDLES: NETWORK_MANAGER,
##   RUN_MANAGER, CREW_PROGRESSION, UNLOCK_MANAGER) are checked against the
##   script loaded from its path: each must be the script its autoload runs, or
##   `as <handle>` would give null and the depot would stop seeing the
##   network (host, seed), the crew's money and supplies, and the unlocks;
## - package.gd (the box), package_handling.gd (its hand-over) and
##   package_rescue.gd (its care simulation) reach the network through package_autoloads.gd as a NetSession (the class
##   NetworkManager extends): the NetworkManager autoload must be one, or
##   `as NetSession` would give null and the box would stop seeing the network
##   (its visibility filter, the hand-over, the seed its trap rolls from);
## - player_cargo_care.gd is no autoload either: its GAME_SETTINGS handle is
##   checked against the script GameSettings runs, or `as GAME_SETTINGS` would
##   give null and the care card would lose the HUD scale, the interact key's
##   name and the gamepad check (it would size and label itself as if on keyboard).
## - package_feedback.gd (the box's presentation) is no autoload either: its GAME_SETTINGS handle is
##   checked against the script GameSettings runs, or `as GAME_SETTINGS` would give null and the box
##   would ignore the impact-effects and colorblind-palette options.
## - cargo_animals.gd (the gull, the dog and the bees) reads the session's world_seed, is_host and
##   peer_level_ready through its NETWORK_MANAGER handle: if that stopped being the script the autoload
##   runs, `as NETWORK_MANAGER` would give null and the animals would roll from seed 0 and act on every peer.
## - trailer_shot.gd (the trailer and store-capture tool) sets the shot's seed
##   through its NETWORK_MANAGER handle: if that stopped being the script the
##   autoload runs, `as NETWORK_MANAGER` would give null and no shot (nor the
##   store stills) would set up.
## - vehicle_faults.gd (the truck's faults) holds its effects and repair spots by preload and the phone
##   holder as Player; only the van's own door API and driver_peer_id stay by name (FakeVan in the tests).
## - wildlife_crossing.gd (the deer crossing) drives its deer through the wildlife_animal.gd type; only
##   the crew's money and the incident relay stay by name.

## path -> {kind: max}. Kinds: "call", "callv", "get", "root".
const BUDGETS: Dictionary = {
	# Two .call left: one relays merit/card changes through EventBus, which a
	# test may replace with a plain Node (event_bus); the other asks the truck
	# for its pay_multiplier (N-114): vehicle.gd names the autoloads, so this
	# autoload cannot preload it as a typed reference. The .callv emits a
	# signal chosen by name. The /root/ lookups are the null-safe autoload
	# handles (EventBus x3, NetworkManager, RunManager, RouteEventManager).
	"res://scripts/core/crew_progression.gd": {"call": 2, "callv": 1, "get": 0, "root": 6},
	# The two .call left are the EventBus relays (team money and route events),
	# by name for the same reason. The /root/ lookups are the null-safe handles
	# (EventBus, NetworkManager, RunManager, CrewProgression).
	"res://scripts/core/route_event_manager.gd": {"call": 2, "callv": 0, "get": 0, "root": 4},
	# One .call left: the EventBus relay of the depot notices, by name because
	# a test may replace EventBus with a plain Node (_bus()). One .get left: the
	# seat_node_path of the players in the "player" group, because tests put
	# Node3D fakes there and `as Player` would drop them. The /root/ lookups
	# are the null-safe autoload accessors (NetworkManager, CrewProgression,
	# UnlockManager, RunManager, EventBus).
	"res://scripts/gameplay/depot/depot.gd": {"call": 1, "callv": 0, "get": 1, "root": 5},
	# The trailer tool (N-902) drives the real level: level_base.gd, route.gd,
	# vehicle.gd and package_mount_point.gd by preload (no class name), the
	# camera, segments, deer crossing, house, player and boxes by class. The one
	# /root/ lookup is the NetworkManager handle (NETWORK_MANAGER, below).
	"res://scripts/tools/trailer_shot.gd": {"call": 0, "callv": 0, "get": 0, "root": 1},
	# Three .call left, one .get and one /root/ (N-225.4 moved the rest to the files below). Two .call go to
	# the truck, found through the "vehicle" group: needs_sweep and carries. vehicle.gd has no class name,
	# and tests put plain Node fakes with those methods in the group (`as` a typed vehicle would drop them).
	# The .get reads RunManager's cargo: that autoload stays by name because preloading its script here makes
	# every script that names DeliveryPackage compile it before the autoloads exist (see
	# package_autoloads.gd). The last .call is the EventBus relay, by name because a test may replace
	# EventBus with a plain Node; the one /root/ lookup is that EventBus node. Typed now: the trap definition
	# and behavior (TrapDefinition, ITrapBehavior), the player (Player) and the network (NetSession).
	"res://scripts/gameplay/package/package.gd": {"call": 3, "callv": 0, "get": 1, "root": 1},
	# The box's autoload lookups, null-safe: NetworkManager (typed NetSession),
	# RunManager, CrewProgression and RouteEventManager.
	"res://scripts/gameplay/package/package_autoloads.gd": {"call": 0, "callv": 0, "get": 0, "root": 4},
	# Carrying, passing, dropping and handing over the box (split out of package.gd, N-225.4). Three .call go
	# to the truck, by name for the reason in package.gd: carries (x2, taking the box and riding along) and
	# point_velocity. The one .get reads RunManager's consumed_packages, by name for the compile cycle
	# package_autoloads.gd explains.
	"res://scripts/gameplay/package/package_handling.gd": {"call": 3, "callv": 0, "get": 1, "root": 0},
	# The tender, the helper and merit (split out of package.gd, N-225.4). Two .call: CrewProgression's
	# player_color_name (the helper's prompt) and award_milestone; one .get: RunManager's cargo (the state the
	# run counts for the box). All by name for the compile cycle package_autoloads.gd explains.
	"res://scripts/gameplay/package/package_tending.gd": {"call": 2, "callv": 0, "get": 1, "root": 0},
	# Hits (split out of package.gd, N-225.4). The one .call is RouteEventManager's on_package_impact, by name
	# for the compile cycle package_autoloads.gd explains.
	"res://scripts/gameplay/package/package_impacts.gd": {"call": 1, "callv": 0, "get": 0, "root": 0},
	# The rescue (host care simulation) is typed like the box: the trap (ITrapBehavior,
	# TrapDefinition, ExplosiveTrapBehavior for the defused flag), the player's seat
	# on the carrier (Player), the network and the autoload
	# lookups (PackageAutoloads). Seven .call left: carries (x2) and point_velocity go
	# to the truck, found through the "vehicle" group (vehicle.gd has no class name and
	# tests put Node fakes there); care_supply_count, consume_care_supply and
	# record_care go to RunManager, by name for the cycle package_autoloads.gd
	# explains; store goes to the lap mount (package_mount_point.gd has no class
	# name). Six .get left: the truck's driver_peer_id, RunManager's cargo, the
	# seat_node_path of the players in the "player" group (tests put Node3D fakes
	# there, `as Player` would drop them), the lap mount's occupied_by and the
	# session's world_seed (network_manager.gd declares it, NetSession does not)
	# and the radio's mode (truck_radio.gd names autoloads bare: typing it would
	# pull them into the compile graph of every script that names the box).
	"res://scripts/gameplay/package/package_rescue.gd": {"call": 7, "callv": 0, "get": 6, "root": 0},
	# Typed now: the player (Player), the box (DeliveryPackage), the settings
	# (GAME_SETTINGS, below) and the profile (UnlockProfile). The one .call and
	# the four .get left all go to RunManager (care_supply_count; is_running twice,
	# cargo, results): by name because preloading run_manager.gd here compiles it
	# before the autoloads exist (see package_autoloads.gd, whose run_manager()
	# finds the node). The two /root/ lookups are the null-safe GameSettings and
	# UnlockManager accessors.
	"res://scripts/gameplay/player/player_cargo_care.gd": {"call": 1, "callv": 0, "get": 4, "root": 2},
	# Nothing by name: the box (DeliveryPackage), the players (Player) and the
	# seats (CargoSeatPoint, seat_point.gd's class name) are typed. Group members
	# of another type (a test's stand-ins) are skipped with `as`, not called.
	# The RPC to the player stays rpc_id by name, like every RPC.
	"res://scripts/gameplay/interaction/seat_tending.gd": {"call": 0, "callv": 0, "get": 0, "root": 0},
	# Typed now: the interactables (Interactable: can_interact, interact; DogDistractPoint for the aim
	# bonus), the network (NetSession) and the box's contents view (preload, no class name). Three .call
	# left: `highlight`, asked by name because what is aimed at (the pickup point, the box's feedback,
	# the depot stations) has no common base class; EventBus's request_ping and CrewProgression's
	# request_use_card, by name (a test may replace EventBus with a plain Node, and preloading
	# crew_progression.gd builds compile cycles, see package_autoloads.gd). The three /root/ lookups
	# are the null-safe accessors (EventBus, NetworkManager, CrewProgression).
	"res://scripts/gameplay/player/player_interaction.gd": {"call": 3, "callv": 0, "get": 0, "root": 3},
	# The mud stretch (N-108) is typed: the push spot (mud_spot.gd), the crane
	# (mud_crane.gd) and the run log (mud_run_log.gd) by preload, the session as
	# NetSession and the truck's freeze as the VehicleBody3D property it is.
	# CrewProgression (team_money, spend, save_campaign) and RunManager
	# (current_mode) stay by name: preloading their scripts here breaks both
	# autoloads under --script (route.gd pulls this in, and those scripts name
	# EventBus before the autoloads exist). The other three .call and five .get
	# are on stand-ins the tests put in groups: the players of the
	# "player" group (is_local; carried_package, seat_node_path and _ragdolled,
	# twice for the first two) are FakePlayer Node3Ds, `as Player` would drop
	# them; carries goes to the truck of the "vehicle" group (vehicle.gd names
	# the autoloads, no class name). The last .call is the EventBus relay of
	# the notices, by name because a test may replace EventBus with a plain
	# Node. The four /root/ lookups are the null-safe accessors (EventBus,
	# NetworkManager, CrewProgression, RunManager).
	"res://scripts/gameplay/route/segments/mud_segment.gd": {"call": 5, "callv": 0, "get": 7, "root": 4},
	# The delivery level is typed: the route and the truck through their scripts
	# (route.gd and vehicle.gd by preload, no class name), the houses as
	# DeliveryHouse and the goal as RouteGoalLot; the route's and the houses'
	# signals are connected by the signal. Nothing left by name.
	"res://scripts/gameplay/level_base.gd": {"call": 0, "callv": 0, "get": 0, "root": 0},
	# The animals that go for the cargo (N-109) are typed: the truck through vehicle.gd by preload (no class
	# name), the session through NETWORK_MANAGER (world_seed, is_host and peer_level_ready, below), the box
	# (DeliveryPackage, its _has_previous_velocity too) and its contents (PackageContent). One .call left: the
	# EventBus relay, by name because a test may replace EventBus with a plain Node. One .get left: RunManager's
	# is_running, by name because preloading run_manager.gd here compiles it before the autoloads exist (see
	# package_autoloads.gd). The three /root/ lookups are the null-safe accessors (EventBus, NetworkManager,
	# RunManager).
	"res://scripts/gameplay/route/cargo_animals.gd": {"call": 1, "callv": 0, "get": 1, "root": 3},
	# The box's presentation (N-224.4) is typed: the box (DeliveryPackage), its trap (TrapDefinition,
	# HostileTrapBehavior, ExplosiveTrapBehavior, LiquidTrapBehavior), its contents (PackageContent) and the
	# settings (GAME_SETTINGS, below). Nothing left by name but two /root/ lookups: the null-safe GameSettings
	# accessor and EventBus, whose signals it connects by name because a test may replace EventBus with a
	# plain Node.
	"res://scripts/gameplay/package/package_feedback.gd": {"call": 0, "callv": 0, "get": 0, "root": 2},
	# What each trap shows on the box (split out of package_feedback.gd, N-225.5), typed the same way.
	"res://scripts/gameplay/package/package_trap_visuals.gd": {"call": 0, "callv": 0, "get": 0, "root": 0},
	# The truck's faults (N-224.4) are typed: the effects (EFFECTS) and the repair spots (REPAIR_SPOT) by
	# preload (no class name), the phone holder as Player (a stand-in Node3D, as in the tests, is treated as
	# carrying nothing) and the Dictionary lookups indexed after has(). Two .call and one .get left, all on
	# the van: is_door_open and set_rear_cargo_open (the pop of the rear door) and driver_peer_id. By name
	# because the tests stand a FakeVan Node3D in (with only that API), which `as` a typed truck would drop.
	"res://scripts/gameplay/vehicle/vehicle_faults.gd": {"call": 2, "callv": 0, "get": 1, "root": 0},
	# The depot screen (N-224.4) is typed: the purchases go to the level's Depot (buy_supply,
	# buy_supply_discounted, team_money, supplies), the boxes are DeliveryPackage (package_id, is_aboard),
	# the level is a LevelCommon and the signals of EventBus and UnlockManager are connected directly (the
	# panel's tests keep the real autoloads). One .get and one .call left, both on the `depot` the station
	# hands in, which stays a Node: test_depot_panel gives it a stand-in with only `orders` and
	# `boss_notes()`, and `as Depot` would drop it (the order sheet would come out empty).
	"res://scripts/ui/depot_panel.gd": {"call": 1, "callv": 0, "get": 1, "root": 0},
	# The deer crossing (N-224.4) is typed: the deer through wildlife_animal.gd by preload (no class name:
	# steered, run, freeze_in_headlights, tumble). Two .call and one .get left: CrewProgression's
	# team_money and spend, by name because preloading crew_progression.gd here compiles it before the
	# autoloads exist (route.gd pulls this in, see mud_segment.gd), and the EventBus relay of the incident,
	# by name because a test may replace EventBus with a plain Node. The three /root/ lookups are the
	# null-safe accessors (EventBus twice, CrewProgression).
	"res://scripts/gameplay/route/wildlife_crossing.gd": {"call": 2, "callv": 0, "get": 1, "root": 3},
}
const PATTERNS: Dictionary = {
	"call": "\\.call\\(&?\"",
	"callv": "\\.callv\\(",
	"get": "\\.get\\(&\"",
	"root": "\"/root/",
}
## autoload node -> {constant in the script it runs: autoload it stands for}.
const HANDLES: Dictionary = {
	"/root/CrewProgression": {
		"NETWORK_MANAGER": "/root/NetworkManager",
		"RUN_MANAGER": "/root/RunManager",
		"ROUTE_EVENT_MANAGER": "/root/RouteEventManager",
	},
	"/root/RouteEventManager": {
		"CREW_PROGRESSION": "/root/CrewProgression",
		"NETWORK_MANAGER": "/root/NetworkManager",
		"RUN_MANAGER": "/root/RunManager",
	},
}
## script that is no autoload -> {constant: autoload it stands for}.
const SCRIPT_HANDLES: Dictionary = {
	"res://scripts/gameplay/depot/depot.gd": {
		"NETWORK_MANAGER": "/root/NetworkManager",
		"RUN_MANAGER": "/root/RunManager",
		"CREW_PROGRESSION": "/root/CrewProgression",
		"UNLOCK_MANAGER": "/root/UnlockManager",
	},
	"res://scripts/tools/trailer_shot.gd": {
		"NETWORK_MANAGER": "/root/NetworkManager",
	},
	"res://scripts/gameplay/player/player_cargo_care.gd": {
		"GAME_SETTINGS": "/root/GameSettings",
	},
	"res://scripts/gameplay/route/cargo_animals.gd": {
		"NETWORK_MANAGER": "/root/NetworkManager",
	},
	"res://scripts/gameplay/package/package_feedback.gd": {
		"GAME_SETTINGS": "/root/GameSettings",
	},
}

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path: String in BUDGETS:
		var source: String = FileAccess.get_file_as_string(path)
		_expect(not source.is_empty(), "%s can be read" % path)
		var budget: Dictionary = BUDGETS[path]
		for kind: String in budget:
			var found: int = RegEx.create_from_string(PATTERNS[kind]).search_all(source).size()
			_expect(found <= int(budget[kind]),
					"%s has %d %s by name (budget %d): use a typed reference" % [path, found, kind, budget[kind]])

	for owner_path: String in HANDLES:
		var owner_node: Node = root.get_node_or_null(NodePath(owner_path))
		_expect(owner_node != null, "The %s autoload is loaded" % owner_path)
		if owner_node == null:
			continue
		_check_handles(owner_path, owner_node.get_script() as Script, HANDLES[owner_path])

	var session: Node = root.get_node_or_null(^"/root/NetworkManager")
	_expect(session is NetSession, "The NetworkManager autoload is a NetSession (the box types it so)")

	for script_path: String in SCRIPT_HANDLES:
		var script: Script = load(script_path) as Script
		_expect(script != null, "%s loads" % script_path)
		if script != null:
			_check_handles(script_path, script, SCRIPT_HANDLES[script_path])

	if _failures == 0:
		print("PASS: files moved to typed references stay within their by-name budget")
	quit(_failures)


func _check_handles(owner_name: String, script: Script, handles: Dictionary) -> void:
	var constants: Dictionary = script.get_script_constant_map()
	for handle: String in handles:
		var target_path: String = handles[handle]
		var autoload: Node = root.get_node_or_null(NodePath(target_path))
		_expect(autoload != null, "%s is loaded" % target_path)
		_expect(autoload != null and constants.get(handle) == autoload.get_script(),
				"%s.%s is the script %s runs" % [owner_name, handle, target_path])


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
