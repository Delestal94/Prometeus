class_name PalletBox
extends RefCounted
## The grey-box stand-in of a supplier pallet (expansion D-0605.b): a wooden base with a load of boxes on it,
## the load coloured by its product. One shape for every place a pallet is drawn (the truck's bed, the jack's
## forks, the shed's floor), so a pallet looks the same wherever it is. No physics, no collider.
##
## The node's origin is on the floor at the middle of the pallet's footprint (CompanyTuning.PALLET_FOOTPRINT_M,
## 1.2 m along X by 0.8 m along Z), the same point PalletJack keeps for a pallet on the floor. A final model
## replaces build() only (docs/expansion-distritos/arte-pendiente/D-0605.md).

const BASE_HEIGHT: float = 0.14
const LOAD_HEIGHT: float = 0.75
const LOAD_MARGIN_M: float = 0.06
const BASE_COLOR: Color = Color(0.55, 0.42, 0.27)


## Height of a pallet with its load.
static func height() -> float:
	return BASE_HEIGHT + LOAD_HEIGHT


## The colour of a pallet's load: its product's, the same as the units on a picking cart.
static func load_color(product: StringName) -> Color:
	return PickingCartView.product_color(product)


## A pallet {id, product, qty} drawn standing on the floor at the node's origin. `turned` lays its long side
## along Z (inside a truck, where two fit across).
static func build(pallet: Dictionary, turned: bool = false) -> Node3D:
	var size: Vector2 = CompanyTuning.PALLET_FOOTPRINT_M
	var root := Node3D.new()
	root.name = "Pallet_%s" % pallet.get("id", "")
	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(size.x, BASE_HEIGHT, size.y)
	base_mesh.material = DepotKit.flat(BASE_COLOR)
	base.mesh = base_mesh
	base.position = Vector3(0.0, BASE_HEIGHT * 0.5, 0.0)
	root.add_child(base)
	var cargo := MeshInstance3D.new()
	cargo.name = "Load"
	var cargo_mesh := BoxMesh.new()
	cargo_mesh.size = Vector3(size.x - LOAD_MARGIN_M * 2.0, LOAD_HEIGHT, size.y - LOAD_MARGIN_M * 2.0)
	cargo_mesh.material = DepotKit.flat(load_color(StringName(pallet.get("product", &""))))
	cargo.mesh = cargo_mesh
	cargo.position = Vector3(0.0, BASE_HEIGHT + LOAD_HEIGHT * 0.5, 0.0)
	root.add_child(cargo)
	if turned:
		root.rotation.y = PI * 0.5
	return root
