class_name BoxToPackage
extends RefCounted
## Turns a PackedBox from the warehouse into the DeliveryPackage the truck
## carries (expansion D-0213), so the delivery itself stays as it is today.
##
## What you pack is the trap (docs/expansion-distritos/diseno/armado-y-trampas.md):
## the packing never changes which trap rides, only how hard it hits.
## - trap and content: those of the product with the hardest trap
##   (UnlockManager.TRAP_DIFFICULTY_ORDER, rightmost wins; ties keep the first placed);
## - impact_absorption: lerp(ABSORPTION_UNPADDED, ABSORPTION_FULL_PADDING, protection),
##   protection = padded share of the free cells (1 when products fill the box);
## - metadata: META_PACKED_BOX (to_dict()), META_ORDER_ID and, when more than
##   OVERSIZED_FREE_RATIO of the box is empty without padding, META_LOOSE_BOX
##   (D-0710 adds the low Balance trap from it).
## Adds only: no signature of package.gd or package_content.gd changes. The
## UnlockManager script is preloaded, never named (lesson N-919).

const PACKAGE_SCENE: PackedScene = preload("res://scenes/gameplay/package/package.tscn")
const UNLOCK_MANAGER := preload("res://scripts/core/unlock_manager.gd")
const PRODUCTS_DIR: String = "res://data/products/"
const TRAP_PATH: String = "res://data/traps/%s.tres"

const META_PACKED_BOX: StringName = &"packed_box"
const META_ORDER_ID: StringName = &"order_id"
const META_LOOSE_BOX: StringName = &"loose_box"


## A new, not yet added DeliveryPackage for the box, or null if the box holds no
## known product. products maps id -> ProductDefinition; an id missing there is
## loaded from data/products/<id>.tres.
static func build(box: PackedBox, products: Dictionary = {}) -> DeliveryPackage:
	var main: ProductDefinition = ruling_product(box, products)
	if main == null:
		return null
	var trap: TrapDefinition = load(TRAP_PATH % main.trap_id) as TrapDefinition
	if trap == null:
		return null
	var package: DeliveryPackage = PACKAGE_SCENE.instantiate()
	package.trap_definition = trap
	package.content = main.content
	package.impact_absorption = absorption(box)
	if box.label_order_id != &"":
		package.package_id = StringName("box_%s" % box.label_order_id)
		package.name = "Package_box_%s" % box.label_order_id
	package.set_meta(META_PACKED_BOX, box.to_dict())
	package.set_meta(META_ORDER_ID, box.label_order_id)
	if is_loose(box):
		package.set_meta(META_LOOSE_BOX, true)
	return package


## The product whose trap rides: the hardest one in the box, or null if none is known.
static func ruling_product(box: PackedBox, products: Dictionary = {}) -> ProductDefinition:
	var best: ProductDefinition = null
	var best_rank: int = -1
	for item: Dictionary in box.items:
		var product: ProductDefinition = _product(item["product"], products)
		if product == null:
			continue
		var rank: int = UNLOCK_MANAGER.TRAP_DIFFICULTY_ORDER.find(product.trap_id)
		if best == null or rank > best_rank:
			best = product
			best_rank = rank
	return best


## Padded share of the free cells; 1.0 when the products fill the box.
static func protection(box: PackedBox) -> float:
	var product_cells: int = 0
	for value: StringName in box.grid.values():
		if value != PackedBox.FILL:
			product_cells += 1
	if box.total_cells() - product_cells <= 0:
		return 1.0
	return box.fill_ratio()


static func absorption(box: PackedBox) -> float:
	return lerpf(
		CompanyTuning.ABSORPTION_UNPADDED, CompanyTuning.ABSORPTION_FULL_PADDING, protection(box)
	)


## More than OVERSIZED_FREE_RATIO of the whole box empty and unpadded.
static func is_loose(box: PackedBox) -> bool:
	return box.free_ratio() > CompanyTuning.OVERSIZED_FREE_RATIO


static func _product(id: StringName, products: Dictionary) -> ProductDefinition:
	if products.has(id):
		return products[id] as ProductDefinition
	var path: String = PRODUCTS_DIR + String(id) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ProductDefinition
