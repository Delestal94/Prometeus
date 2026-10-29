class_name PlayerGelAppearance
extends Node
## Binds the active gel model to the host-owned appearance state. Shape, skin
## and lightweight cosmetic roots update only when replicated values change.

const Shaper := preload("res://scripts/gameplay/player/gel/gel_body_shaper.gd")
const HairAttachment := preload("res://scripts/gameplay/player/gel/gel_hair_attachment.gd")
const HairLibrary := preload("res://scripts/gameplay/player/gel/gel_hair_library.gd")
const CostumeCatalog := preload("res://scripts/gameplay/player/gel/gel_costume_catalog.gd")
const CostumeLibrary := preload("res://scripts/gameplay/player/gel/gel_costume_library.gd")
const CostumeFitter := preload("res://scripts/gameplay/player/gel/gel_costume_fitter.gd")
const CostumeSprings := preload("res://scripts/gameplay/player/gel/gel_costume_springs.gd")
const AccessoryCatalog := preload("res://scripts/gameplay/player/gel/gel_accessory_catalog.gd")
const AccessoryLibrary := preload("res://scripts/gameplay/player/gel/gel_accessory_library.gd")

var _body: Node3D
var _state: PlayerGelProportionSync
var _shaper := Shaper.new()
var _team_color: Color = Color.TRANSPARENT
var _settings: Node
var _hair_attachment: BoneAttachment3D
var _face_hair_attachments: Array[BoneAttachment3D] = []
var _costume: Node3D
var _costume_fitter
var _accessory: Node3D
var _cosmetics_queued: bool = false


func setup(body: Node3D) -> void:
	_body = body
	_state = get_parent().get_node(^"GelProportions") as PlayerGelProportionSync
	_settings = get_node_or_null(^"/root/GameSettings")
	var use_opaque: bool = bool(_settings.call(&"uses_opaque_gel")) if _settings != null else false
	PlayerAppearance.set_gel_material(_body, use_opaque)
	_shaper.setup(_body)
	_apply_proportions(_state.proportions)
	_state.proportions_changed.connect(_apply_proportions)
	_state.skin_changed.connect(_apply_skin)
	_state.cosmetics_changed.connect(_queue_cosmetics)
	if _settings != null:
		_settings.connect(&"gel_material_mode_changed", _set_opaque)
	_apply_skin(_state.skin_id)
	_rebuild_cosmetics()


func set_team_color(color: Color) -> void:
	_team_color = color
	if _state != null:
		_apply_skin(_state.skin_id)


func _apply_skin(skin_id: StringName) -> void:
	if _body != null:
		PlayerAppearance.apply_gel_skin(_body, skin_id, _team_color)


func _set_opaque(use_opaque: bool) -> void:
	if _body == null:
		return
	PlayerAppearance.set_gel_material(_body, use_opaque)
	_apply_skin(_state.skin_id)


func _apply_proportions(proportions: GelBodyProportions) -> void:
	if _body == null:
		return
	_shaper.apply(proportions)
	if _hair_attachment != null:
		_hair_attachment.apply_proportions(proportions)
	_fit_face_hair(proportions)
	if _costume_fitter != null:
		_costume_fitter.apply(proportions)


## Replication applies five IDs individually. Coalesce them so one profile
## change rebuilds the presentation once after all properties arrive.
func _queue_cosmetics() -> void:
	if _cosmetics_queued:
		return
	_cosmetics_queued = true
	_rebuild_cosmetics.call_deferred()


func _rebuild_cosmetics() -> void:
	_cosmetics_queued = false
	_clear_cosmetics()
	if _body == null or _state == null:
		return
	var skeleton: Skeleton3D = PlayerAppearance.find_skeleton(_body)
	if skeleton == null:
		return
	_hair_attachment = HairAttachment.new()
	_hair_attachment.setup(skeleton, _state.hair_id, 1)
	_add_face_hair(skeleton, HairLibrary.build_eyebrows(_state.eyebrows_id), _state.eyebrows_id)
	_add_face_hair(skeleton, HairLibrary.build_moustache(_state.moustache_id), _state.moustache_id)
	_costume = CostumeLibrary.build_costume(_state.costume_id)
	_body.add_child(_costume)
	_costume_fitter = CostumeFitter.new()
	_costume_fitter.setup(_costume, _body)
	var springs := CostumeSprings.new()
	_costume.add_child(springs)
	if not springs.setup(_costume):
		springs.free()
	if _state.accessory_id != &"none":
		_accessory = AccessoryLibrary.build_accessory(_state.accessory_id)
		_body.add_child(_accessory)
	var costume_rule: StringName = CostumeCatalog.costume(_state.costume_id).get(&"hat_rule", &"none")
	var accessory_rule: StringName = AccessoryCatalog.accessory(_state.accessory_id).get(
		&"hat_rule", &"none") if _state.accessory_id != &"none" else &"none"
	_hair_attachment.set_hat_rule(_strongest_hat_rule(costume_rule, accessory_rule))
	_apply_proportions(_state.proportions)


func _add_face_hair(skeleton: Skeleton3D, visual: Node3D, style_id: StringName) -> void:
	if style_id == &"none":
		visual.free()
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = visual.name
	attachment.bone_name = &"head"
	skeleton.add_child(attachment)
	attachment.add_child(visual)
	_face_hair_attachments.append(attachment)


func _fit_face_hair(proportions: GelBodyProportions) -> void:
	var scale := Vector3(
		1.0 + proportions.head_shape * HairAttachment.HEAD_SHAPE_X,
		1.0 + proportions.head_shape * HairAttachment.HEAD_SHAPE_Y,
		1.0
	) * proportions.head_size
	for attachment: BoneAttachment3D in _face_hair_attachments:
		if attachment.get_child_count() > 0:
			(attachment.get_child(0) as Node3D).scale = scale


func _strongest_hat_rule(first: StringName, second: StringName) -> int:
	if first == &"hide" or second == &"hide":
		return HairAttachment.HatRule.HIDE
	if first == &"compress" or second == &"compress":
		return HairAttachment.HatRule.COMPRESS
	return HairAttachment.HatRule.NONE


func _clear_cosmetics() -> void:
	if is_instance_valid(_hair_attachment):
		_hair_attachment.free()
	_hair_attachment = null
	for attachment: BoneAttachment3D in _face_hair_attachments:
		if is_instance_valid(attachment):
			attachment.free()
	_face_hair_attachments.clear()
	if is_instance_valid(_costume):
		_costume.free()
	_costume = null
	_costume_fitter = null
	if is_instance_valid(_accessory):
		_accessory.free()
	_accessory = null
