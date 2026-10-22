class_name CustomerNames
extends RefCounted
## Names of the customers on the orders (expansion D-0840, "Modo Empresa").
##
## The name is part of the order the host rolls and every peer shows as is, so it can not depend on
## the viewer's language: the pool is first names and surnames that read the same in Spanish and in
## English (no translation key). One draw of the day's generator picks both, so the stream of the
## rest of the day does not move when the pool grows. Pure function: no node, no autoload.

const FIRST: Array[String] = [
	"Marta", "Gustavo", "Lucia", "Bruno", "Elena", "Tomas", "Rosa", "Hugo",
	"Irene", "Julian", "Paula", "Ramiro", "Silvia", "Dario", "Nora", "Felix",
	"Carla", "Mateo", "Alma", "Ivan", "Clara", "Pablo", "Olga", "Sergio",
	"Vera", "Nico", "Ada", "Leon", "Mia", "Oscar", "Rita", "Andres",
	"Julia", "Ruben", "Sofia", "Emilio", "Laura", "Hector", "Diana", "Ariel",
	"Celia", "Martin", "Eva", "Lorenzo", "Ines", "Adrian", "Flora", "Gael",
]
const LAST: Array[String] = [
	"Rojas", "Vidal", "Costa", "Navarro", "Ferrer", "Molina", "Soler", "Prieto",
	"Cruz", "Luna", "Ortega", "Bravo", "Ramos", "Pons", "Silva", "Mora",
	"Vega", "Duarte", "Lara", "Campos", "Reyes", "Paz", "Rey", "Salas",
	"Moreno", "Pena", "Arias", "Bosch", "Cano", "Gil", "Leal", "Mena",
]


## How many different names the pool can make.
static func count() -> int:
	return FIRST.size() * LAST.size()


## The name at `index` (any integer: it wraps), "First Last".
static func name_at(index: int) -> String:
	var n: int = posmod(index, count())
	return "%s %s" % [FIRST[n % FIRST.size()], LAST[(n / FIRST.size()) % LAST.size()]]


## A name from the seeded generator (one draw).
static func pick(rng: RandomNumberGenerator) -> String:
	return name_at(rng.randi())
