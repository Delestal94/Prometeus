extends MultiplayerSpawner
## Spawn data belongs to the host; movement belongs to the player. Supply
## both identity and position before entering the tree on every machine.

func _ready() -> void:
	clear_spawnable_scenes()
	spawn_function = _create_player


func _create_player(data: Variant) -> Node:
	var player: Node3D = load("res://scenes/gameplay/player/player.tscn").instantiate()
	player.name = "Player_%d" % int(data.peer_id)
	player.position = data.position
	player.set_multiplayer_authority(int(data.peer_id))
	return player
