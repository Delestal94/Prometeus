class_name PlayerGelProportionSync
extends Node
## Host-authoritative, compact appearance state for one player's gel body.
## The owner submits 17 quantized bytes; the host validates the sender and
## packet shape, decodes only into authored ranges, then replicates the
## canonical packet at spawn and whenever it changes.

signal proportions_changed(proportions: GelBodyProportions)
signal skin_changed(skin_id: StringName)

const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Skins := preload("res://scripts/gameplay/player/gel/gel_skin_catalog.gd")

var proportions := Proportions.new()
var packet: PackedByteArray = proportions.to_packet():
	set(value):
		if value.size() != Proportions.PACKET_SIZE:
			return
		packet = value.duplicate()
		proportions.apply_packet(packet)
		proportions_changed.emit(proportions)
var skin_id: StringName = Skins.DEFAULT_ID:
	set(value):
		skin_id = Skins.valid_id(value)
		skin_changed.emit(skin_id)


func _enter_tree() -> void:
	# Player ownership is recursive, but appearance acceptance belongs to the
	# host. This runs before the synchronizer child enters and registers.
	set_multiplayer_authority(1, true)


func _ready() -> void:
	var player: Node = get_parent()
	var profile: Node = get_node_or_null(^"/root/UnlockManager")
	if player == null or profile == null or not bool(player.call(&"is_local")):
		return
	profile.progress_changed.connect(_sync_from_profile)
	_sync_from_profile()


func _sync_from_profile() -> void:
	var profile: Node = get_node_or_null(^"/root/UnlockManager")
	if profile == null:
		return
	var requested: PackedByteArray = Proportions.packet_from_dictionary(profile.get(&"gel_proportions"))
	var requested_skin := Skins.valid_id(StringName(profile.get(&"selected_gel_skin")))
	if multiplayer.is_server():
		packet = requested
		skin_id = requested_skin
	else:
		_submit_packet.rpc_id(1, requested)
		_submit_skin.rpc_id(1, requested_skin)


@rpc("any_peer", "call_remote", "reliable")
func _submit_packet(requested: PackedByteArray) -> void:
	if not multiplayer.is_server() or requested.size() != Proportions.PACKET_SIZE \
			or not RpcGuard.allow_request(self):
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id != get_parent().get_multiplayer_authority():
		return
	# PackedByteArray elements are 0..255; decoding therefore cannot escape
	# any parameter's minimum/maximum. Re-encoding keeps the host canonical.
	var accepted := Proportions.new()
	accepted.apply_packet(requested)
	packet = accepted.to_packet()


@rpc("any_peer", "call_remote", "reliable")
func _submit_skin(requested: StringName) -> void:
	if not multiplayer.is_server() or not RpcGuard.allow_request(self):
		return
	if multiplayer.get_remote_sender_id() != get_parent().get_multiplayer_authority():
		return
	skin_id = Skins.valid_id(requested)
