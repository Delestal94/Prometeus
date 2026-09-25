extends SceneTree
## S-804 end-of-run contract: temporary systems close and a player leaving
## cannot leave a package attached to an object that no longer exists.

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bus: Node = root.get_node(^"/root/EventBus")
	var routes: Node = root.get_node(^"/root/RouteEventManager")
	var shop: Node = root.get_node(^"/root/ShopVoteManager")
	var package: DeliveryPackage = load("res://scenes/gameplay/package/package.tscn").instantiate()
	var player: Node = load("res://scenes/gameplay/player/player.tscn").instantiate()
	package.name = "DanglingStatePackage"
	player.name = "DanglingStatePlayer"
	root.add_child(package)
	root.add_child(player)
	await process_frame

	_expect(routes.begin_event(&"inspection") == &"inspection", "A route event is active before the run ends")
	shop.open_shop({&"padding": {"cost": 40, "label": "Acolchado"}})
	_expect(bool(shop.get(&"active")), "A depot vote is active before leaving the depot")
	package.take_by(player)
	_expect(package.carrier == player and package.is_held, "The package starts attached to the departing player")

	# The current package/player relationship is `carrier` (the old task text
	# called it `occupied_by`). Freeing the player must release that reference.
	player.queue_free()
	await process_frame
	_expect(package.carrier == null and not package.is_held,
		"No package remains attached to a player that no longer exists")

	bus.run_ended.emit(0, {})
	_expect(routes.active_event_id.is_empty(), "Run end leaves no active route event")
	_expect(not bool(shop.get(&"active")), "Run end closes the depot vote")
	_expect((shop.get(&"offers") as Dictionary).is_empty() and (shop.get(&"votes") as Dictionary).is_empty(),
		"Run end leaves no stale shop offers or votes")

	routes.reset_route()
	package.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: run end closes temporary state and departing players release packages")
	quit(_failures)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
