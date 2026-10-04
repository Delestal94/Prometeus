class_name OrderRequirement
extends Resource
## One requirement a customer order can carry (expansion D-0806, "Modo Empresa").
##
## Data only, like ZoneDefinition: it says what the packed box has to show
## (seals, minimum quality), how it changes the delivery window and what it adds
## to the pay. The ids are the ones Order.requirements lists. Nothing here names
## autoloads or UI classes (lesson N-919). The numbers are a starting point for
## sim_economy (D-0540). They are per-requirement data in
## data/order_requirements/, not in CompanyTuning; the window it scales is
## CompanyTuning.ORDER_WINDOW_MIN.

## Same id (and file name) as the .tres in data/order_requirements/.
@export var id: StringName = &""
## Translation key of the name (WORLD_REQ_<ID>). The CSV row is added by the
## task that first shows the name (D-0804, D-0845).
@export var display_key: String = ""
## Stamp ids the closed box must carry (D-0708 validates them at the door).
@export var required_seals: Array[StringName] = []
## Minimum packing quality 0-100 (D-0709) for the order to pay in full.
@export_range(0, 100) var min_quality: int = 0
## Multiplies the delivery window (CompanyTuning.ORDER_WINDOW_MIN); 1.0 leaves it alone.
@export_range(0.1, 1.0) var window_factor: float = 1.0
## Share of the order's pay added when the requirement is met (0.2 = +20 %).
@export_range(0.0, 1.0) var pay_bonus: float = 0.0


## The delivery window in game minutes after applying this requirement.
func window_min(base_min: int) -> int:
	return maxi(1, roundi(base_min * window_factor))


## Pay with the bonus applied.
func paid(pay: int) -> int:
	return roundi(pay * (1.0 + pay_bonus))
