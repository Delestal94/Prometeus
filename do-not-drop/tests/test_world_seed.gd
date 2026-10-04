extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_world_seed.gd
##
## Every peer has to build the same world. route.gd used to call
## _rng.randomize() on each machine independently, so in an online session
## **every player got a different road** -- and because the van's transform
## replicates from the host, a client watched it drive through houses that
## weren't there and off a road that ran somewhere else. Both sides worked
## perfectly on their own, which is why nothing caught it.
##
## What this pins down: the same NetworkManager.world_seed builds the same
## route twice, a different seed builds a different one, and seed 0 (solo
## play) still gives a fresh route each time.
## network_manager.gd also picks a nonzero seed for each hosted run, changes
## it on restart (even if the first random draw repeats it), and sends that
## same seed in the restart and late-join payloads before rebuilding.

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node("NetworkManager")
	var original_state: Dictionary = network.call(&"_session_state").duplicate(true)
	_check_run_seeds(network)

	network.world_seed = 12345
	var first: Array = await _build_signature()
	var second: Array = await _build_signature()
	_expect(first == second, "The same world seed builds the same route twice")
	_expect(first.size() > 1, "The signature actually captured a route (%d stops)" % first.size())

	network.world_seed = 999777
	var other: Array = await _build_signature()
	_expect(first != other, "A different world seed builds a different route")

	# Solo play (seed 0) keeps the per-run variety the procedural route was
	# built for -- the fix must not turn every offline run into the same map.
	network.world_seed = 0
	var solo_signatures: Array = []
	for _i: int in range(4):
		solo_signatures.append(await _build_signature())
	var all_identical: bool = true
	for signature: Array in solo_signatures:
		if signature != solo_signatures[0]:
			all_identical = false
	_expect(not all_identical, "Solo play still randomises the route between runs")

	network.call(&"_apply_session_state", original_state)
	await create_timer(0.1).timeout
	if failures == 0:
		print("PASS: each run gets a fresh shared seed, equal seeds build equal worlds, and solo play varies")
	quit(failures)


func _check_run_seeds(network: Node) -> void:
	# Force the first draw to repeat the previous seed: this must not leave
	# two consecutive runs with the same world. Each test has its own process.
	seed(314159)
	var repeated: int = randi() | 1
	network.world_seed = repeated
	seed(314159)
	network.call(&"_on_hosting")
	_expect(int(network.world_seed) != repeated and int(network.world_seed) != 0,
		"Hosting rejects a repeated seed and never picks zero (got %d)" % int(network.world_seed))
	for index: int in range(32):
		var previous: int = int(network.world_seed)
		network.call(&"_on_hosting")
		_expect(int(network.world_seed) != 0 and int(network.world_seed) != previous,
			"A new room gets a different nonzero seed (room %d, got %d)" % [index, int(network.world_seed)])

	for index: int in range(32):
		var previous: int = int(network.world_seed)
		network.world_house_count = 3
		network.call(&"_before_restart")
		var host_seed: int = int(network.world_seed)
		_expect(host_seed != 0 and host_seed != previous,
			"The next run changes the host seed (run %d, got %d)" % [index, host_seed])
		_expect(int(network.world_house_count) == 0, "A new run decides its house count afresh")
		# The rebuilt host has decided its houses before it sends the restart.
		network.world_house_count = 3
		var restart: Dictionary = network.call(&"_restart_state")
		var late_join: Dictionary = network.call(&"_session_state").duplicate(true)
		_expect(int(restart.get("seed", 0)) == host_seed,
			"The restart carries the new host seed (got %s)" % restart)
		_expect(int(late_join.seed) == host_seed and int(network.world_seed) == host_seed,
			"A late join receives the current seed without rerolling the host")
		# Apply the wire payload as a client still carrying the previous world.
		network.world_seed = previous
		network.call(&"_apply_restart_state", restart)
		_expect(int(network.world_seed) == host_seed and int(network.world_house_count) == 3,
			"A client applies the host seed before rebuilding (got %d)" % int(network.world_seed))
		network.world_seed = previous
		network.call(&"_apply_session_state", late_join)
		_expect(int(network.world_seed) == host_seed,
			"A late join rebuilds with the same seed as the restarted host (got %d)" % int(network.world_seed))

	network.call(&"_reset_session_state")
	_expect(int(network.world_seed) == 0, "Leaving the room restores solo randomisation")


## Where the goal and every house ended up -- the cheapest thing that changes
## whenever any leg length, turn or segment choice does.
func _build_signature() -> Array:
	var route: Node3D = load("res://scenes/gameplay/route/route.tscn").instantiate() as Node3D
	route.set(&"house_count", 3)
	root.add_child(route)
	await process_frame
	var signature: Array = [(route.get(&"goal_transform") as Transform3D).origin.snapped(Vector3.ONE * 0.01)]
	for house: Node3D in route.get(&"houses"):
		signature.append(house.position.snapped(Vector3.ONE * 0.01))
	route.free()
	await process_frame
	return signature


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1
