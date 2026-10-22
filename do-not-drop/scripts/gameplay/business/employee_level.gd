class_name EmployeeLevel
extends Resource
## One hiring level of an employee (expansion D-0515): what it is called, what it costs per day
## and how much work it does compared with one player.
##
## Data only. The daily deduction at closing is D-1009 and the roles are D-1002; this is the table
## they read (diseno/economia.md section 4).

## Same id (and file name) as the .tres in data/employees/.
@export var id: StringName = &""
## Translation key of the level name.
@export var display_key: String = ""
## Wallet cost per game day, paid at closing.
@export var wage: int = 0
## Work done per day as a fraction of one player (1.0 = a player).
@export var output: float = 0.0
## Position in the ladder, 1 = first hire.
@export var rank: int = 0


func is_valid() -> bool:
	return id != &"" and display_key != "" and wage > 0 and output > 0.0 and output <= 1.0 and rank > 0
