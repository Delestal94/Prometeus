class_name RoadEdge
extends Resource
## One street between two RoadNodes, as a cubic Bezier. Data only (portable
## module, docs/modulos.md).
##
## The curve starts at the `from_id` node, ends at the `to_id` node and its two
## inner control points are offsets from the node they hang off, so an edge with
## both handles at zero is a straight street and moving a node drags its streets.

const SURFACES: Array[StringName] = [&"asphalt", &"gravel", &"dirt", &"cobble"]

## Unique inside its network.
@export var id: StringName = &""
@export var from_id: StringName = &""
@export var to_id: StringName = &""
## First control point, relative to the from node (meters, ground plane).
@export var out_handle: Vector2 = Vector2.ZERO
## Second control point, relative to the to node.
@export var in_handle: Vector2 = Vector2.ZERO
## Full width of the roadway in meters (shoulders not included).
@export var width: float = 10.0
@export var surface: StringName = &"asphalt"
## The kinds of piece laid along the street, in order, repeated to fill its
## length. Opaque names: the owner of the network says what each one is.
@export var segments: Array[StringName] = []
## Free tags for the owner of the network (region, street name). Never read here.
@export var area: StringName = &""
@export var street: StringName = &""


func half_width() -> float:
	return width * 0.5
