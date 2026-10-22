class_name CompanySeed
extends RefCounted
## The company's world seed and the day seeds drawn from it (expansion D-0246).
##
## One seed per company, saved with it (CompanyState.company_seed): every random draw of the
## business (the day's orders and their arrival minutes, later the suppliers' market) starts from
## for_day(seed, day, stream), so the same company and day give the same day on every load and on
## every host. Each stream gets its own seed, so drawing one more order never shifts what a
## supplier draws. Clients never draw: the host plans with it and sends the results whole
## (docs/expansion-distritos/diseno/red-autoridad.md, "La semilla de la empresa").
##
## Static only, no state, names no autoload.

## The day's customer orders: OrderGenerator.generate_day() and OrderRhythm (D-0801, D-0803).
const ORDERS: StringName = &"orders"
## The suppliers' day (prices and delays of the market, D-0133, still postponed).
const SUPPLIERS: StringName = &"suppliers"
const STREAMS: Array[StringName] = [ORDERS, SUPPLIERS]
## Highest seed a company keeps: 31 bits, so it survives the JSON of the save (a float) exactly.
const MAX_SEED: int = 0x7FFF_FFFF


## A new company seed, 1 to MAX_SEED, from a randomized generator.
static func fresh() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, MAX_SEED)


## The seed a save or a snapshot carries, or 0 when it is not one: anything but an int or a
## whole float in 1..MAX_SEED.
static func normalize(raw: Variant) -> int:
	if typeof(raw) == TYPE_FLOAT:
		var value: float = raw
		if value != floorf(value):
			return 0
		raw = int(value)
	if typeof(raw) != TYPE_INT:
		return 0
	var seed_value: int = raw
	return seed_value if seed_value >= 1 and seed_value <= MAX_SEED else 0


## The seed of a company saved before D-0246, which has none: drawn from its name, so loading the
## same old save twice plans the same days until the next save writes a real one.
static func from_name(company_name: String) -> int:
	return posmod(hash([company_name, &"company_seed"]), MAX_SEED) + 1


## The seed of `stream` on `day` for the company with `company_seed`. Same three values, same seed.
static func for_day(company_seed: int, day: int, stream: StringName) -> int:
	return hash([company_seed, day, String(stream)])
