extends RefCounted
## The courier's label, stuck on the back of the box: printed paper plus the
## declared contents and, on the printed "PARA:" rules, recipient and sender
## (S-602). Presentation only; package_feedback.gd owns the body it returns
## (it tears off on a hard hit) and rewrites the texts for a swapped label.

const INK: Color = Color("1e2235")
const TEXTURE: Texture2D = preload("res://assets/textures/cargo/tx_cargo_shipping_label_512.png")
const ASPECT: float = 320.0 / 512.0
const TEXT_SCALE: float = 0.62
## The "PARA:" rules of the printed label (512x320 texture px, ruled lines at
## v=99 and v=125): the two-line block is centred at u=211, v=102, which drops
## recipient and sender each onto its own rule. Font px * pixel_size (below) * 512/width = texture px.
const PARTIES_CENTER_UV: Vector2 = Vector2(211.0, 102.0)
const PARTIES_MAX_TEXTURE_PX: float = 260.0
const PARTIES_FONT_SIZE: int = 28
const PARTIES_CHAR_EM: float = 0.56
const PARTIES_LINE_SPACING: float = 2.0

static var _material_cache: StandardMaterial3D


## A frozen, collisionless RigidBody3D named ShippingLabel with the paper and
## two Label3D children, "ShippingText" (contents) and "ShippingParties".
static func build(contents: String, parties: String, box_size: Vector3) -> RigidBody3D:
	var width: float = minf(0.4, box_size.x * 0.78)
	var height: float = width * ASPECT
	var body := RigidBody3D.new()
	body.name = "ShippingLabel"
	body.freeze = true
	# While attached this is paper painted on the box, not a second solid
	# object for the carrier to collide with. Collision is enabled only once
	# a hard impact tears it free.
	body.collision_layer = 0
	body.collision_mask = 0
	# A few millimetres proud of the face: closer than this and depth
	# precision at a few metres makes box and paper fight (flicker).
	body.position = Vector3(0.0, -box_size.y * 0.5 + minf(box_size.y * 0.42, height * 0.5 + 0.06),
		-box_size.z * 0.5 - 0.006)
	body.rotation.y = PI
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.01)
	collision.shape = shape
	body.add_child(collision)
	var paper := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	paper.mesh = quad
	paper.material_override = _material()
	body.add_child(paper)
	var text := _ink(width, "ShippingText")
	text.text = contents
	text.font_size = 32
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.width = 480.0
	# Under "CONTENIDO DECLARADO", on the left of the printed label.
	text.position = Vector3(-width * 0.04, -height * 0.11, 0.004)
	body.add_child(text)
	var party := _ink(width, "ShippingParties")
	party.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	party.line_spacing = PARTIES_LINE_SPACING
	party.position = Vector3((PARTIES_CENTER_UV.x / 512.0 - 0.5) * width,
		(0.5 - PARTIES_CENTER_UV.y / 320.0) * height, 0.004)
	body.add_child(party)
	write_parties(party, parties)
	return body


## Writes the recipient/sender lines, shrinking the font so the longest one
## stays between the "PARA:" rules (the paper is a fixed size).
static func write_parties(label: Label3D, parties: String) -> void:
	if label == null:
		return
	label.text = parties
	var longest: int = 1
	for line: String in parties.split("\n"):
		longest = maxi(longest, line.length())
	var fit: float = PARTIES_MAX_TEXTURE_PX / TEXT_SCALE / (float(longest) * PARTIES_CHAR_EM)
	label.font_size = clampi(floori(fit), 14, PARTIES_FONT_SIZE)


static func _ink(width: float, node_name: String) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.pixel_size = width / 512.0 * TEXT_SCALE
	label.outline_size = 0
	label.modulate = INK
	return label


static func _material() -> StandardMaterial3D:
	if _material_cache == null:
		_material_cache = StandardMaterial3D.new()
		_material_cache.albedo_texture = TEXTURE
		_material_cache.roughness = 0.8
		_material_cache.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material_cache
