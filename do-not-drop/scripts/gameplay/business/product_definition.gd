class_name ProductDefinition
extends Resource
## One product of the company catalog (expansion D-0204, "Modo Empresa").
##
## Data only, like TrapDefinition and PackageContent: it says what the product
## is (the PackageContent it reuses for model, texts and notes), how big and
## heavy it is, what it costs and which trap its content carries. Nothing here
## names autoloads, the HUD or any UI class (lesson N-919: a class_name that
## references autoloads breaks --script runs).

## Same id (and file name) as the content in data/contents/.
@export var id: StringName = &""
## What the players see: model, texts and notes (assumption S9).
@export var content: PackageContent
## Size in 0.2 m grid cells (X x Y x Z). Each axis fits the XL box (4x4x4).
@export var cells: Vector3i = Vector3i(2, 2, 2)
@export var weight_kg: float = 1.0
@export var fragile: bool = false
## &"ambient", &"cold" or &"heat". F1 ignores it until D-0616.
@export var temperature: StringName = &"ambient"
## What the company pays to restock one unit.
@export var buy_price: int = 0
## What a delivered unit earns. 0 means "use buy x CompanyTuning.SELL_MARKUP"; read it
## through get_sell_price().
@export var sell_price: int = 0
## The trap the content carries (data/traps/<trap_id>.tres).
@export var trap_id: StringName = &""
## Zone ids where it is mostly ordered.
@export var districts: Array[StringName] = []


## The price a delivered unit earns: sell_price if set, else buy x CompanyTuning.SELL_MARKUP.
func get_sell_price() -> int:
	if sell_price > 0:
		return sell_price
	return roundi(buy_price * CompanyTuning.SELL_MARKUP)
