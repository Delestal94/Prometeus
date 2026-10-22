class_name ProductOrientation
extends RefCounted
## Products that must travel upright (expansion D-0727, "Modo Empresa").
##
## Static and stateless. Liquids and the wedding cake spill or collapse when the box is laid on its
## side (PackedBox.on_side). tipped() lists the upright-only products a laid-down box holds, so the
## table can warn before taping and assembly quality can take points off (penalty()). The list is
## kept by id here, like ProductCompatibility, so no .tres of the catalog changes.

## Product ids that need the box upright.
const UPRIGHT_ONLY: Array[StringName] = [&"milk_canister", &"wedding_cake"]


static func needs_upright(product: StringName) -> bool:
	return UPRIGHT_ONLY.has(product)


## Ids of the upright-only products in the box, once each, when it lies on its side. Empty when the
## box stands, holds none or is null.
static func tipped(box: PackedBox) -> Array[StringName]:
	var out: Array[StringName] = []
	if box == null or not box.on_side:
		return out
	for id: StringName in box.contents():
		if needs_upright(id):
			out.append(id)
	return out


static func is_safe(box: PackedBox) -> bool:
	return tipped(box).is_empty()


## Assembly quality points to take off for the products lying down (0 when safe).
static func penalty(box: PackedBox) -> int:
	return tipped(box).size() * CompanyTuning.TIPPED_QUALITY_PENALTY
