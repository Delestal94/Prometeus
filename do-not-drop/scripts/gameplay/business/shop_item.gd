class_name ShopItem
extends Resource
## One thing the company can buy in its shop (expansion D-0511).
##
## Data only. `kind` says what buying grants: a vehicle (one more entry in the fleet),
## a machine or upgrade (a key in the company's equipment), or a shed expansion (the next
## warehouse stage). Prices of vehicles, machines and expansions are D-0512 to D-0514.

const KINDS: Array[StringName] = [&"vehicle", &"machine", &"expansion"]

## Same id (and file name) as the .tres in data/shop/.
@export var id: StringName = &""
## Translation key of the name shown in the shop.
@export var display_key: String = ""
## One of KINDS.
@export var kind: StringName = &"machine"
## Wallet cost.
@export var price: int = 0
## vehicle: the VehicleDefinition fleet_key. machine: the equipment key. Unused by expansion.
@export var grant_key: StringName = &""
## expansion only: the warehouse stage this one leaves the shed in (previous stage + 1).
@export var stage: int = 0
## machine only: an item that must be owned first (its grant_key in equipment); empty when none.
@export var requires: StringName = &""
## False hides the item from the shop (kept for later phases).
@export var enabled: bool = true


func is_valid() -> bool:
	if id == &"" or display_key == "" or price <= 0 or not KINDS.has(kind):
		return false
	if kind == &"expansion":
		return stage > 0
	return grant_key != &""
