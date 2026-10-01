extends Node
## Where the other peers draw a player (N-217): the owner stamps each pose it
## sends with its clock and its heading; everyone else puts them in a
## NetSnapshotBuffer and draws the player a little in the past, interpolated,
## instead of on whatever pose came last (with internet jitter they jumped).
## A child of the Player, replicated next to its net_position and
## net_in_vehicle (player.tscn); player_ride.gd publishes and applies it.
##
## The heading travels as a yaw in the same space as the position: the
## truck's while riding in its bay, so a rider turns with this peer's truck.
##
## On the host the buffer also says how stale a client's player is there,
## which widens the reach its requests are checked with (reach_slack()).

const Sprint = preload("res://scripts/gameplay/player/player_sprint.gd")
## However bad the link, a request is never let reach further than this past
## its own range.
const MAX_REACH_SLACK: float = 1.5

## Replicated (player.tscn): the owner's NetSnapshotBuffer.clock_ms() for this
## pose, and its heading about up (radians, in the truck's space if riding).
var net_time: int = 0
var net_yaw: float = 0.0
var buffer := NetSnapshotBuffer.new()


func _ready() -> void:
	var network: Node = get_node_or_null(^"/root/NetworkManager")
	if network != null and network.has_method(&"pose_net_sim"):
		buffer.configure_sim(network.call(&"pose_net_sim"))


## Owner: stamp what goes out this tick.
func publish(player: Node3D, vehicle: Node3D, riding: bool) -> void:
	var forward: Vector3 = -player.global_basis.z
	if riding:
		forward = vehicle.global_basis.inverse() * forward
	net_yaw = atan2(-forward.x, -forward.z)
	net_time = NetSnapshotBuffer.clock_ms()


## Everyone else: where to draw the player now, `truck` being this peer's
## truck (only used for a pose in its space).
func drawn(position: Vector3, in_vehicle: bool, truck: Transform3D) -> Transform3D:
	var now: float = NetSnapshotBuffer.local_now()
	buffer.take(net_time, Transform3D(Basis(Vector3.UP, net_yaw), position), in_vehicle, now)
	return buffer.sample(now, truck)


## Host: how much further a request from this (remote) player may reach. When
## it arrives, the host's copy of the player is the cushion behind where the
## client was, and a box moving there is drawn a round trip plus a cushion
## behind the host's: a running speed over both, capped.
func reach_slack(peer_id: int) -> float:
	if not is_inside_tree() or not multiplayer.is_server() or peer_id == multiplayer.get_unique_id():
		return 0.0
	var round_trip: float = maxf(NetStats.round_trip_ms(multiplayer.multiplayer_peer, peer_id), 0.0) / 1000.0
	return minf(Sprint.RUN_SPEED * (round_trip + buffer.delay()), MAX_REACH_SLACK)


## The heading about up of a drawn transform.
static func yaw_of(pose: Transform3D) -> float:
	var forward: Vector3 = -pose.basis.z
	return atan2(-forward.x, -forward.z)
