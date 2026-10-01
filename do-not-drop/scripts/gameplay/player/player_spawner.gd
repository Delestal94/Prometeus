extends MultiplayerSpawner
## Spawn data belongs to the host; movement belongs to the player. Supply
## both identity and position before entering the tree on every machine.
##
## A player who joins with the truck on the road (late_join_seating.gd) comes
## with `vehicle_position` too: where it appears in the truck's own space. Every
## peer runs this with the same data and resolves it against its own copy of
## the truck: the peers who were already here draw theirs a moment behind the
## host's (NetPoseSmoother), so a world position taken from the host's truck
## would land a few metres ahead of it and outside the cargo bay. The joiner's
## own copy may not have its first pose yet, so the player starts out riding it
## (Player._riding / _ride_last_transform) and goes wherever that copy is
## teleported (player_ride.gd ride_with_vehicle(), which also takes a jump of more than 5 m
## for a teleport, not a fall: no ground-safety rescue back to the depot).

func _ready() -> void:
	clear_spawnable_scenes()
	spawn_function = _create_player


func _create_player(data: Variant) -> Node:
	var player: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.name = "Player_%d" % int(data.peer_id)
	player.position = data.position
	player.set_multiplayer_authority(int(data.peer_id))
	var truck := get_tree().get_first_node_in_group(&"vehicle") as Node3D
	if data.has("vehicle_position") and truck != null and RpcGuard.finite_vec3(data.vehicle_position):
		var local: Vector3 = data.vehicle_position
		player.position = (get_node(spawn_path) as Node3D).to_local(truck.to_global(local))
		player.set(&"net_in_vehicle", true)
		player.set(&"net_position", local)
		player.set(&"_riding", true)
		player.set(&"_ride_last_transform", truck.global_transform)
	return player
