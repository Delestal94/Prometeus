class_name FixedCosts
extends RefCounted
## Daily fixed costs of the company (expansion D-0509, "Modo Empresa"): today only the
## shed's rent. Pure functions, no node, no autoload, no UI. The day's close (D-0203)
## calls settle() once per day; the amount lives in CompanyTuning.RENT_PER_DAY.

const REASON_RENT: StringName = &"rent"


## What the company owes at the close of one day, by reason.
static func due() -> Dictionary:
	return {REASON_RENT: CompanyTuning.RENT_PER_DAY}


## Sum of due().
static func total_due() -> int:
	var total: int = 0
	for amount: int in due().values():
		total += amount
	return total


## How much of the day's costs the wallet cannot cover (0 when it can). D-0510 reads it
## to decide what a negative balance means.
static func shortfall(company: Object) -> int:
	if company == null:
		return 0
	return maxi(0, total_due() - maxi(0, int(company.get("money"))))


## Charges the day's fixed costs, even into the red (charge, not spend). Returns the
## amount charged. company is a node with charge().
static func settle(company: Object) -> int:
	if company == null:
		return 0
	var charged: int = 0
	var costs: Dictionary = due()
	for reason: StringName in costs:
		var amount: int = int(costs[reason])
		if company.charge(amount, reason):
			charged += amount
	return charged
