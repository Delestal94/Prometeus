class_name RoadNode
extends Resource
## One point of a RoadNetwork: where streets meet, where one ends, or where a
## lock can close the way. Data only (portable module, docs/modulos.md).

const KINDS: Array[StringName] = [&"junction", &"dead_end", &"gate"]

## Unique inside its network.
@export var id: StringName = &""
## Position on the ground plane, in meters (x east, y = world Z).
@export var position: Vector2 = Vector2.ZERO
## junction: three or two streets meet. dead_end: exactly one street ends here.
## gate: a street that a lock can close (see lock_id).
@export var kind: StringName = &"junction"
## Free tag for whoever owns the network (a region, a district). The module
## never reads it.
@export var area: StringName = &""
## Only for kind gate: the lock that must be open to go past this node.
## Empty: it never closes.
@export var lock_id: StringName = &""
