class_name PlayerGelProportionSync
extends Node
## Host-authoritative, compact appearance state for one player's gel body.
## The owner submits 17 quantized bytes; the host validates the sender and
## packet shape, decodes only into authored ranges, then replicates the
## canonical packet at spawn and whenever it changes.

signal proportions_changed(proportions: GelBodyProportions)
signal skin_changed(skin_id: StringName)
signal cosmetics_changed

const Proportions := preload("res://scripts/gameplay/player/gel/gel_body_proportions.gd")
const Skins := preload("res://scripts/gameplay/player/gel/gel_skin_catalog.gd")
const Hair := preload("res://scripts/gameplay/player/gel/gel_hair_catalog.gd")
const Costumes := preload("res://scripts/gameplay/player/gel/gel_costume_catalog.gd")
const Accessories := preload("res://scripts/gameplay/player/gel/gel_accessory_catalog.gd")

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
var hair_id: StringName = Hair.DEFAULT_HAIRSTYLE:
	set(value):
		hair_id = StringName(Hair.hairstyle(value)[&"id"])
		cosmetics_changed.emit()
var eyebrows_id: StringName = Hair.NONE:
	set(value):
		eyebrows_id = Hair.valid_eyebrows(value)
		cosmetics_changed.emit()
var moustache_id: StringName = Hair.NONE:
	set(value):
		moustache_id = Hair.valid_moustache(value)
		cosmetics_changed.emit()
var costume_id: StringName = Costumes.DEFAULT_ID:
	set(value):
		costume_id = StringName(Costumes.costume(value)[&"id"])
		cosmetics_changed.emit()
var accessory_id: StringName = &"none":
	set(value):
		accessory_id = _valid_accessory(value)
		cosmetics_changed.emit()


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
	var requested_styles := {
		&"hair": StringName(profile.get(&"selected_gel_hair")),
		&"eyebrows": StringName(profile.get(&"selected_gel_eyebrows")),
		&"moustache": StringName(profile.get(&"selected_gel_moustache")),
		&"costume": StringName(profile.get(&"selected_gel_costume")),
		&"accessory": StringName(profile.get(&"selected_gel_accessory")),
	}
	if multiplayer.is_server():
		packet = requested
		skin_id = requested_skin
		_set_styles(requested_styles)
	else:
		_submit_packet.rpc_id(1, requested)
		_submit_skin.rpc_id(1, requested_skin)
		_submit_styles.rpc_id(1, requested_styles)


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
	if not multiplayer.is_server() or not RpcGuard.allow_request(self) or not RpcGuard.name_ok(requested):
		return
	if multiplayer.get_remote_sender_id() != get_parent().get_multiplayer_authority():
		return
	skin_id = Skins.valid_id(requested)


@rpc("any_peer", "call_remote", "reliable")
func _submit_styles(requested: Dictionary) -> void:
	if not multiplayer.is_server() or not RpcGuard.allow_request(self) \
			or not RpcGuard.dict_ok(requested):
		return
	if multiplayer.get_remote_sender_id() != get_parent().get_multiplayer_authority():
		return
	for key: StringName in [&"hair", &"eyebrows", &"moustache", &"costume", &"accessory"]:
		if not RpcGuard.name_ok(StringName(requested.get(key, &""))):
			return
	_set_styles(requested)


func _set_styles(styles: Dictionary) -> void:
	hair_id = StringName(styles.get(&"hair", Hair.DEFAULT_HAIRSTYLE))
	eyebrows_id = StringName(styles.get(&"eyebrows", Hair.NONE))
	moustache_id = StringName(styles.get(&"moustache", Hair.NONE))
	costume_id = StringName(styles.get(&"costume", Costumes.DEFAULT_ID))
	accessory_id = StringName(styles.get(&"accessory", &"none"))


func _valid_accessory(requested: StringName) -> StringName:
	if requested == &"none":
		return &"none"
	return StringName(Accessories.accessory(requested)[&"id"])
