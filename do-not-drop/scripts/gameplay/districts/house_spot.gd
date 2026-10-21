class_name HouseSpot
extends Resource
## One delivery house of the company map (expansion D-0311). Data only: where it
## stands, which way its door faces and which of DeliveryHouse's models it uses.
## The list is data/world/houses.tres (HouseMap).

## Unique on the map; "<zone>_<nn>".
@export var id: StringName = &""
## The zone it lies in (ZoneDefinition.id).
@export var zone: StringName = &""
## Where the house origin stands on the ground plane, in meters (x east, y = world Z).
@export var position: Vector2 = Vector2.ZERO
## Rotation around Y, in radians, that turns the model's entrance (local -Z) toward the street.
@export var yaw: float = 0.0
## Index into DeliveryHouse.HOUSE_VISUALS.
@export var variant: int = 0
## The street it is on (RoadEdge.id), how far along it (meters from the edge's
## start) and the side of travel: 1 is the right of the way from node to node,
## -1 the left. D-0312 reads the side for even and odd numbers.
@export var edge: StringName = &""
@export var along: float = 0.0
@export var side: int = 1
