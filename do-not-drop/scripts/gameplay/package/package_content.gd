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

const TEXT_KEYS: Dictionary = {
	&"porcelain_vase": ["HUD_CONTENT_VASE", "HUD_HANDLING_FRAGILE",
		"HUD_CONDITION_VASE_OK", "HUD_CONDITION_VASE_RISK", "HUD_CONDITION_VASE_RUINED"],
	&"antique_lamp": ["HUD_CONTENT_LAMP", "HUD_HANDLING_FRAGILE",
		"HUD_CONDITION_LAMP_OK", "HUD_CONDITION_LAMP_RISK", "HUD_CONDITION_LAMP_RUINED"],
	&"hen": ["HUD_CONTENT_HEN", "HUD_HANDLING_LIVE",
		"HUD_CONDITION_HEN_OK", "HUD_CONDITION_HEN_RISK", "HUD_CONDITION_HEN_RUINED"],
	&"puppy": ["HUD_CONTENT_PUPPY", "HUD_HANDLING_LIVE",
		"HUD_CONDITION_PUPPY_OK", "HUD_CONDITION_PUPPY_RISK", "HUD_CONDITION_PUPPY_RUINED"],
	&"glass_tower": ["HUD_CONTENT_GLASS_TOWER", "HUD_HANDLING_UPRIGHT",
		"HUD_CONDITION_GLASS_OK", "HUD_CONDITION_GLASS_RISK", "HUD_CONDITION_GLASS_RUINED"],
	&"wedding_cake": ["HUD_CONTENT_CAKE", "HUD_HANDLING_UPRIGHT",
		"HUD_CONDITION_CAKE_OK", "HUD_CONDITION_CAKE_RISK", "HUD_CONDITION_CAKE_RUINED"],
	&"sourdough": ["HUD_CONTENT_SOURDOUGH", "HUD_HANDLING_HEAVY",
		"HUD_CONDITION_SOURDOUGH_OK", "HUD_CONDITION_SOURDOUGH_RISK", "HUD_CONDITION_SOURDOUGH_RUINED"],
	&"milk_canister": ["HUD_CONTENT_MILK", "HUD_HANDLING_UPRIGHT",
		"HUD_CONDITION_MILK_OK", "HUD_CONDITION_MILK_RISK", "HUD_CONDITION_MILK_RUINED"],
	&"fireworks_crate": ["HUD_CONTENT_FIREWORKS", "HUD_HANDLING_NO_IMPACTS",
		"HUD_CONDITION_FIREWORKS_OK", "HUD_CONDITION_FIREWORKS_RISK", "HUD_CONDITION_FIREWORKS_RUINED"],
	&"raccoon_cage": ["HUD_CONTENT_RACCOON", "HUD_HANDLING_HOSTILE",
		"HUD_CONDITION_RACCOON_OK", "HUD_CONDITION_RACCOON_RISK", "HUD_CONDITION_RACCOON_RUINED"],
}


func localized_name() -> String:
	var keys: Array = TEXT_KEYS.get(id, [])
	return tr(String(keys[0])) if not keys.is_empty() else display_name


func localized_handling() -> String:
	var keys: Array = TEXT_KEYS.get(id, [])
	return tr(String(keys[1])) if keys.size() > 1 else handling


func condition_text(state: int) -> String:
	if condition_texts.is_empty():
		return ""
	var index: int = clampi(state, 0, condition_texts.size() - 1)
	var keys: Array = TEXT_KEYS.get(id, [])
	return tr(String(keys[index + 2])) if keys.size() > index + 2 else condition_texts[index]
