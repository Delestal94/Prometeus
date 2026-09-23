class_name PackageContent
extends Resource
## What is actually inside a delivery box, and the box it ships in.
##
## Data only, like TrapDefinition: the trap decides how a package fails, the
## content decides what the players see when they open it (and what falls out
## when an open box tips over). A trap lists the contents it can carry
## (TrapDefinition.contents); DeliveryPackage picks one per package.

@export var id: StringName = &"porcelain_vase"
@export var display_name: String = "Jarrón de porcelana"
## Printed on the shipping label under "CONTENIDO DECLARADO".
@export var declared_weight: String = "4 kg"
@export var handling: String = "FRÁGIL"
## How the item is doing at each trap state (OK, AT_RISK, RUINED) -- what the
## player reads when they look inside.
@export var condition_texts: PackedStringArray = ["intacto", "con fisuras", "hecho añicos"]
## Content GLB: Filler (optional), Intact, Damage and Ruined (an empty whose
## children are the loose pieces). See assets/tools/build_cargo_packages.py.
@export var model: PackedScene
## Openable box GLB: Body plus FlapFront/FlapBack/FlapRight/FlapLeft, each
## pivoted on its hinge.
@export var box_model: PackedScene
## Outer size of that box, which is also the package's collider.
@export var box_size: Vector3 = Vector3(0.65, 0.65, 0.65)


func condition_text(state: int) -> String:
	if condition_texts.is_empty():
		return ""
	return condition_texts[clampi(state, 0, condition_texts.size() - 1)]
