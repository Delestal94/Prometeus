class_name PickingCartView
extends Node3D
## A picking cart as the players see and work it in the shed (expansion D-0610.b, "Modo Empresa").
##
## It only DRAWS state: the units are the Inventory's (cart:<id>, PickingCart) and the spot is the host's
## (CompanyCarts), equal on every peer, so no RPC and no random roll here: two peers with the same state
## draw the same cart. Grey-box stand-in made of boxes (docs/expansion-distritos/arte-pendiente/D-0610.md):
## a platform with low rails, wheels and a push handle, 1.0 x 1.0 (with the handle) x 0.6 m, the node's
## origin on the floor at the middle of the platform, the handle at -X.
##
## The units are not physics: each one is a cube of UNIT_SIZE standing on a fixed slot of the platform
## (slot_centre()), in the order of the products sorted as text, so six units always fit inside the rails
## and nothing falls, whatever order they came in. Moving the cart is a jump of its node to the spot the
## host decided (place_at()); only the look slides, so the reach spot and the colliders are already there.
##
## Interaction: a PickingCartPoint for the platform (load or unload), one for the handle (push) and a take
## point over each product's cubes (D-0610.c2: aim at the product to take; refresh() places them, unused
## ones have no prompt); they forward their `used` here. Pivot, size and slots are art's contract: when the
## final model comes, only _build_look() changes.

signal used(cart_id: StringName, action: StringName, peer_id: int, from: Vector3, product: StringName)

const LENGTH: float = 1.0
const WIDTH: float = 0.6
const HEIGHT: float = 1.0
## Top of the platform above the floor, and the side of one unit (a cube).
const DECK_TOP: float = 0.25
const DECK_THICKNESS: float = 0.04
const UNIT_SIZE: float = 0.25
const RAIL_THICKNESS: float = 0.02
const RAIL_HEIGHT: float = 0.12
const HANDLE_X: float = -0.48
## Slots of the platform: 3 along the cart and 2 across (CompanyTuning.CART_MAX_UNITS = 6).
const SLOT_X: Array[float] = [-0.24, 0.03, 0.30]
const SLOT_Z: Array[float] = [-0.14, 0.14]
const FRAME_COLOR: Color = Color(0.58, 0.59, 0.61)
const SLIDE_SECONDS: float = 0.25
## Reach sphere of a take point: about one cube, so two products side by side keep apart.
const TAKE_RADIUS: float = 0.14

## The cart's id and its Inventory location (PickingCart). Set by make().
var cart: PickingCart = PickingCart.new()
## The point of the platform and the point of the handle.
var load_point: PickingCartPoint
var push_point: PickingCartPoint
## One take point per product on the cart (at most one per slot), in the order of slot_products().
var take_points: Array[PickingCartPoint] = []

var _look: Node3D
var _units: Array[MeshInstance3D] = []
var _slot_products: Array[StringName] = []
var _slide: Tween


## A cart `id` standing at `local` (the shed's frame), empty until refresh().
static func make(id: StringName, local: Vector3) -> PickingCartView:
	var view := PickingCartView.new()
	view.name = "Cart_%s" % id
	view.cart = PickingCart.make(id)
	view.position = local
	view._build()
	return view


## The centre of slot `slot` (0 to CART_MAX_UNITS - 1) in the cart's frame: where its unit's cube stands.
static func slot_centre(slot: int) -> Vector3:
	var row: int = floori(slot / float(SLOT_X.size()))
	return Vector3(SLOT_X[slot % SLOT_X.size()], DECK_TOP + UNIT_SIZE * 0.5, SLOT_Z[row])


## The colour of a product's units: from its name, the same on every peer.
static func product_color(product: StringName) -> Color:
	return Color.from_hsv(float(String(product).hash() % 360) / 360.0, 0.45, 0.82)


## Redraws the units from `stock`: one cube per unit on the cart, up to the slots there are, grouped by
## product (sorted as text), each group its own colour.
func refresh(stock: Inventory) -> void:
	_slot_products.clear()
	var on_cart: Dictionary = cart.contents(stock)
	for product: StringName in cart.products(stock):
		for _unit: int in int(on_cart[product]):
			if _slot_products.size() < _units.size():
				_slot_products.append(product)
	for slot: int in _units.size():
		var shown: bool = slot < _slot_products.size()
		_units[slot].visible = shown
		if shown:
			(_units[slot].mesh as BoxMesh).material = DepotKit.flat(product_color(_slot_products[slot]))
	_place_take_points()


## The take point of `product`, null while it is not on the cart.
func take_point_of(product: StringName) -> PickingCartPoint:
	for point: PickingCartPoint in take_points:
		if point.product == product and product != &"":
			return point
	return null


## The product on each shown slot, in slot order (as many entries as units drawn).
func slot_products() -> Array[StringName]:
	return _slot_products.duplicate()


## The cubes drawn now (the visible ones), in slot order.
func shown_units() -> Array[MeshInstance3D]:
	var shown: Array[MeshInstance3D] = []
	for unit: MeshInstance3D in _units:
		if unit.visible:
			shown.append(unit)
	return shown


## Stands the cart at `local` (the shed's frame). With `slide` the look rolls there from where it was.
func place_at(local: Vector3, slide: bool = false) -> void:
	var from: Vector3 = position
	position = local
	if _slide != null and _slide.is_valid():
		_slide.kill()
	_look.position = Vector3.ZERO
	if slide and is_inside_tree() and from != local:
		_look.position = from - local
		_slide = create_tween()
		_slide.tween_property(_look, "position", Vector3.ZERO, SLIDE_SECONDS)


func _build() -> void:
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	_build_look()
	for slot: int in CompanyTuning.CART_MAX_UNITS:
		var unit := MeshInstance3D.new()
		unit.name = "Unit_%d" % slot
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * UNIT_SIZE
		unit.mesh = mesh
		unit.position = slot_centre(slot)
		unit.visible = false
		_look.add_child(unit)
		_units.append(unit)
	# The deck is solid (nobody walks through it); the handle and the rails are not, so a player can stand at
	# the handle end and the interaction ray over the platform reaches the points.
	var body := StaticBody3D.new()
	body.name = "Deck"
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(LENGTH, DECK_TOP, WIDTH)
	shape.shape = box_shape
	shape.position = Vector3(0.0, DECK_TOP * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)
	load_point = PickingCartPoint.make(cart.id, PickingCartPoint.ACTION_LOAD, Vector3(0.1, 0.7, 0.0), 0.45)
	push_point = PickingCartPoint.make(cart.id, PickingCartPoint.ACTION_PUSH,
		Vector3(HANDLE_X - 0.14, 0.9, 0.0), 0.3)
	for slot: int in CompanyTuning.CART_MAX_UNITS:
		var take := PickingCartPoint.make(cart.id, PickingCartPoint.ACTION_TAKE, slot_centre(slot), TAKE_RADIUS)
		take.name = "Take_%s_%d" % [cart.id, slot]
		take_points.append(take)
	var points: Array[PickingCartPoint] = [load_point, push_point]
	points.append_array(take_points)
	for point: PickingCartPoint in points:
		point.used.connect(func(id: StringName, how: StringName, peer_id: int, origin: Vector3,
				what: StringName) -> void:
			used.emit(id, how, peer_id, origin, what))
		add_child(point)


## One take point per product group, at the middle of its cubes; the rest go back to no product.
func _place_take_points() -> void:
	var groups: Array[StringName] = []
	var centres: Dictionary = {}
	var counts: Dictionary = {}
	for slot: int in _slot_products.size():
		var product: StringName = _slot_products[slot]
		if not centres.has(product):
			groups.append(product)
			centres[product] = Vector3.ZERO
			counts[product] = 0
		centres[product] += slot_centre(slot)
		counts[product] += 1
	for index: int in take_points.size():
		var point: PickingCartPoint = take_points[index]
		if index < groups.size():
			point.product = groups[index]
			point.position = centres[groups[index]] / float(counts[groups[index]])
		else:
			point.product = &""
			point.position = slot_centre(index)


## The grey box: deck, rails, wheels and the push handle.
func _build_look() -> void:
	var material: StandardMaterial3D = DepotKit.flat(FRAME_COLOR)
	_part("Platform", Vector3(LENGTH, DECK_THICKNESS, WIDTH),
		Vector3(0.0, DECK_TOP - DECK_THICKNESS * 0.5, 0.0), material)
	var rail_y: float = DECK_TOP + RAIL_HEIGHT * 0.5
	for side: float in [-1.0, 1.0]:
		_part("RailSide", Vector3(LENGTH, RAIL_HEIGHT, RAIL_THICKNESS),
			Vector3(0.0, rail_y, side * (WIDTH * 0.5 - RAIL_THICKNESS * 0.5)), material)
	_part("RailEnd", Vector3(RAIL_THICKNESS, RAIL_HEIGHT, WIDTH),
		Vector3(LENGTH * 0.5 - RAIL_THICKNESS * 0.5, rail_y, 0.0), material)
	var post: float = HEIGHT - DECK_TOP
	for side: float in [-1.0, 1.0]:
		_part("HandlePost", Vector3(0.03, post, 0.03),
			Vector3(HANDLE_X, DECK_TOP + post * 0.5, side * (WIDTH * 0.5 - 0.03)), material)
		for end: float in [-1.0, 1.0]:
			_part("Wheel", Vector3(0.12, 0.17, 0.05),
				Vector3(end * (LENGTH * 0.5 - 0.1), 0.085, side * (WIDTH * 0.5 - 0.05)), material)
	_part("HandleBar", Vector3(0.03, 0.03, WIDTH - 0.04), Vector3(HANDLE_X, HEIGHT - 0.015, 0.0), material)


func _part(part_name: String, size: Vector3, at: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	part.mesh = mesh
	part.position = at
	_look.add_child(part)
