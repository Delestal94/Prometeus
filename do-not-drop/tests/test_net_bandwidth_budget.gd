extends SceneTree
## Run: Godot --headless --path do-not-drop --script res://tests/test_net_bandwidth_budget.gd
##
## What the host sends one client every second stays well under Steam's
## default send rate (256 KB/s per connection). Past it Steam queues, and the
## client sees an ever older world: in the Steam playtest of 2026-09-29 each
## box sent its 19-key care_state every rendered frame, 2-5x the limit, and
## the truck "kept going" seconds after the driver let go
## (docs/investigacion-red.md).
##
## Worst case on purpose: a full depot of boxes, a crew of four, a 144 Hz
## monitor wherever a synchronizer still follows the frame rate. Counts only
## the always-sent properties, as var_to_bytes() sizes them: a floor, since
## the framing of SceneMultiplayer and of the relay comes on top.

## Half of Steam's default, for that framing and for whatever comes next.
const BUDGET_BYTES_PER_SECOND: float = 128.0 * 1024.0
## A property sent every tick is a pose or a flag. Anything bigger (a
## Dictionary, a String) belongs in ON_CHANGE.
const MAX_ALWAYS_PROPERTY_BYTES: int = 64
const WORST_FPS: float = 144.0
const CREW: int = 4
## Seven boxes in the level plus the depot's extra stock of seven.
const FULL_DEPOT: int = 14

var _failures: int = 0


func _initialize() -> void:
	await process_frame
	var level: Node = load("res://scenes/gameplay/level_base.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	await physics_frame

	var box: Node = get_nodes_in_group(&"cargo")[0]
	var player: Node = level.local_player
	var van: Node = level.vehicle
	var box_rate: float = _per_second(box)
	var player_rate: float = _per_second(player)
	var van_rate: float = _per_second(van)
	_expect(box_rate > 0.0 and player_rate > 0.0 and van_rate > 0.0,
		"Every synchronizer checked here was found")
	for node: Node in [box, player, van]:
		var sync := node.get_node(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
		_expect(sync.replication_interval > 0.0,
			"%s sends at a fixed rate, not once per rendered frame" % node.name)

	var cargo: int = maxi(get_nodes_in_group(&"cargo").size(), FULL_DEPOT)
	var total: float = box_rate * cargo + player_rate * (CREW - 1) + van_rate
	print("Host -> one client: %.1f KB/s (boxes %.1f x %d, players %.1f x %d, truck %.1f)" % [
		total / 1024.0, box_rate / 1024.0, cargo, player_rate / 1024.0, CREW - 1, van_rate / 1024.0])
	_expect(total < BUDGET_BYTES_PER_SECOND,
		"Host -> one client stays under %.0f KB/s (%.1f KB/s)" % [BUDGET_BYTES_PER_SECOND / 1024.0, total / 1024.0])

	if _failures == 0:
		print("PASS: what the host sends each client fits Steam's send rate with room to spare")
	quit(_failures)


## Bytes per second this node's synchronizer sends one peer, always-sent
## properties only.
func _per_second(node: Node) -> float:
	var sync := node.get_node_or_null(^"MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync == null:
		push_error("%s has no MultiplayerSynchronizer" % node.name)
		return 0.0
	var synced: Node = sync.get_node(sync.root_path)
	var config: SceneReplicationConfig = sync.replication_config
	var bytes: int = 0
	for path: NodePath in config.get_properties():
		if config.property_get_replication_mode(path) != SceneReplicationConfig.REPLICATION_MODE_ALWAYS:
			continue
		var owner_node: Node = synced.get_node(NodePath(path.get_concatenated_names()))
		var size: int = var_to_bytes(owner_node.get_indexed(NodePath(path.get_concatenated_subnames()))).size()
		_expect(size <= MAX_ALWAYS_PROPERTY_BYTES,
			"%s %s is sent every tick at %d bytes: make it ON_CHANGE" % [node.name, path, size])
		bytes += size
	var rate: float = 1.0 / sync.replication_interval if sync.replication_interval > 0.0 else WORST_FPS
	return bytes * rate


func _expect(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
