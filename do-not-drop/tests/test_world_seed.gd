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

var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var network: Node = root.get_node("NetworkManager")
	var original_seed: int = int(network.world_seed)

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

	network.world_seed = original_seed
	await create_timer(0.1).timeout
	if failures == 0:
		print("PASS: one seed per session builds one world, and solo play still varies")
	quit(failures)


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
