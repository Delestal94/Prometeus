extends MultiplayerSpawner
## Spawn data belongs to the host; movement belongs to the player. Supply
## both identity and position before entering the tree on every machine.
##
## A player who joins with the truck on the road (late_join_seating.gd) comes
## with `vehicle_position` too: where it appears in the truck's own space. Each
## peer resolves it against its own copy of the truck, which it draws a moment
## behind the host's: a world position taken from the host's truck would land
## a few metres ahead of it on a fast road and outside the cargo bay.


func _ready() -> void:
	clear_spawnable_scenes()
	spawn_function = _create_player


func _create_player(data: Variant) -> Node:
	var player: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.name = "Player_%d" % int(data.peer_id)
	player.position = data.position
	player.set_multiplayer_authority(int(data.peer_id))
	var truck := get_tree().get_first_node_in_group(&"vehicle") as Node3D
	if data.has("vehicle_position") and truck != null:
		var local: Vector3 = data.vehicle_position
		player.position = (get_node(spawn_path) as Node3D).to_local(truck.to_global(local))
		# Riding from the first frame: the host's copy (and every other
		# peer's, via the spawn state) follows the truck until the owner's
		# own state arrives.
		player.set(&"net_in_vehicle", true)
		player.set(&"net_position", local)
	return player
