extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_delivery_houses.gd
## Covers the house delivery system (docs/tareas-nacho.md): route.gd builds
## house_count houses, each with a doorbell that reacts to whatever package
## (if any) was carried when it was rung, and the goal auto-resolves any
## house nobody ever rang instead of leaving it unresolved.

var _failures: int = 0


func _initialize() -> void:
	await process_frame

	var scene := load("res://scenes/gameplay/route/route.tscn") as PackedScene
	var route := scene.instantiate() as Node3D
	route.set(&"house_count", 4)
	root.add_child(route)
	await process_frame

	var houses: Array = route.get(&"houses")
	_expect(houses.size() == 4, "route.gd builds exactly house_count houses (got %d)" % houses.size())

	var resolved_log: Array = []
	route.connect(&"house_resolved", func(index: int, outcome: StringName, package_id: StringName) -> void: resolved_log.append([index, outcome, package_id]))

	# House 0: ring it with a healthy package -- delivered_ok, consumed.
	var good_package := _make_fake_package(ITrapBehavior.TrapState.OK)
	var good_player := _make_fake_player(good_package)
	houses[0].doorbell.interact(good_player)
	_expect(bool(houses[0].get(&"delivered")), "House 0 is marked delivered after ringing with a healthy package")
	# The box is freed one frame later on purpose: whoever listens to
	# `resolved` (level_base.gd -> RunManager) has to still see a valid
	# package when the signal fires, so the free is deferred past it.
	_expect(is_instance_valid(good_package), "The package is still readable while the resolved signal is being handled")
	await process_frame
	_expect(not is_instance_valid(good_package) or good_package.is_queued_for_deletion(),
		"The delivered package gets consumed (\"se come la caja\")")

	# House 1: ring it with a ruined package -- delivered_ruined, still consumed.
	var ruined_package := _make_fake_package(ITrapBehavior.TrapState.RUINED)
	var ruined_player := _make_fake_player(ruined_package)
	houses[1].doorbell.interact(ruined_player)
	_expect(bool(houses[1].get(&"delivered")), "House 1 is marked delivered even for a ruined package")

	# House 2: a box that arrived dented is its own outcome, not "fine" --
	# it's the one a resident may complain about afterwards, which is what
	# makes the delivery photo worth stopping for.
	var dented_package := _make_fake_package(ITrapBehavior.TrapState.AT_RISK)
	var dented_player := _make_fake_player(dented_package)
	houses[2].doorbell.interact(dented_player)
	_expect(bool(houses[2].get(&"delivered")), "House 2 is marked delivered for a dented package")

	# House 3: never rung -- the goal should force-resolve it as "missed"
	# instead of leaving it dangling forever.
	_expect(not bool(houses[3].get(&"delivered")), "House 3 starts unresolved")
	for house: Node in houses:
		house.call(&"force_resolve_if_missed")
	_expect(bool(houses[3].get(&"delivered")), "House 3 gets force-resolved once nobody ever rang it")

	await process_frame  # let the resolved signal's deferred-ish connections settle

	_expect(resolved_log.size() == 4, "All four houses reported an outcome (got %d)" % resolved_log.size())
	var outcomes: Dictionary = {}
	for entry: Array in resolved_log:
		outcomes[int(entry[0])] = String(entry[1])
	_expect(outcomes.get(0, "") == "delivered_ok", "House 0 resolved as delivered_ok (got %s)" % outcomes.get(0, "<missing>"))
	_expect(outcomes.get(1, "") == "delivered_ruined", "House 1 resolved as delivered_ruined (got %s)" % outcomes.get(1, "<missing>"))
	_expect(outcomes.get(2, "") == "delivered_at_risk", "House 2 resolved as delivered_at_risk, not rounded up to ok (got %s)" % outcomes.get(2, "<missing>"))
	_expect(outcomes.get(3, "") == "missed", "House 3 resolved as missed (got %s)" % outcomes.get(3, "<missing>"))

	# Ringing an already-resolved house again shouldn't re-fire it.
	var repeat_package := _make_fake_package(ITrapBehavior.TrapState.OK)
	var repeat_player := _make_fake_player(repeat_package)
	houses[0].doorbell.interact(repeat_player)
	await process_frame
	_expect(resolved_log.size() == 4, "A second ring on an already-resolved house doesn't re-resolve it (still %d entries)" % resolved_log.size())

	good_player.free()
	ruined_player.free()
	dented_player.free()
	repeat_player.free()
	if is_instance_valid(repeat_package):
		repeat_package.free()
	route.free()
	await create_timer(0.1).timeout
	if _failures == 0:
		print("PASS: delivery houses build per house_count, react to package state, and the goal catches anything never rung")
	quit(_failures)


func _make_fake_package(trap_state: int) -> Node:
	var package := Node.new()
	package.set_script(GDScript.new())
	# A bare Node can't fake a real property getter cleanly without a real
	# script resource, so this stores state as metadata and package.gd's own
	# contract (trap_state, get()) is mimicked via a tiny inline script.
	var script := GDScript.new()
	script.source_code = "extends Node\nvar trap_state: int = %d\n" % trap_state
	script.reload()
	package.set_script(script)
	return package


func _make_fake_player(carried_package: Node) -> Node:
	var player := Node.new()
	var script := GDScript.new()
	script.source_code = "extends Node\nvar carried_package: Node = null\n"
	script.reload()
	player.set_script(script)
	player.set(&"carried_package", carried_package)
	if carried_package != null:
		player.add_child(carried_package)
	return player


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
