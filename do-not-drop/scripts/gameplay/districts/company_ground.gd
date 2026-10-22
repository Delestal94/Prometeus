class_name CompanyGround
extends RefCounted
## The ground under the company's world (expansion D-0302.2.b.2), beside the zone slabs CompanyRoot lays.
##
## The zones' rectangles don't tile the map (there are holes of hundreds of metres between them), and a vehicle
## that left the slabs fell for ever, taking the host's day with it. add_backup() lays one plain slab (layer 1,
## grey, collision and a flat colour) under the rectangle that holds every zone, BACKUP_TOP_Y under the zone slabs'
## top so it never shows through them. Built the same on every peer; CompanyFleet.recover_fallen() is the
## host's net for a vehicle that still gets under FALL_Y_M.

## Top of the backup slab (m): below the zone slabs' (-0.1).
const BACKUP_TOP_Y: float = -0.5
const BACKUP_THICKNESS_M: float = 0.2
const BACKUP_COLOR: Color = Color(0.42, 0.42, 0.44)


## The rectangle (XZ, metres) that holds every zone of `from`; empty with none.
static func zones_rect(from: Array[ZoneDefinition]) -> Rect2:
	var rect := Rect2()
	for index: int in range(from.size()):
		rect = from[index].bounds if index == 0 else rect.merge(from[index].bounds)
	return rect


## The backup slab under `from`'s rectangle, a child of `parent` (nothing with no zones). Returns it, or null.
static func add_backup(parent: Node, from: Array[ZoneDefinition]) -> StaticBody3D:
	if from.is_empty():
		return null
	var rect: Rect2 = zones_rect(from)
	var size := Vector3(rect.size.x, BACKUP_THICKNESS_M, rect.size.y)
	var center := Vector3(rect.get_center().x, BACKUP_TOP_Y - BACKUP_THICKNESS_M * 0.5, rect.get_center().y)
	var slab: StaticBody3D = CompanyShed.solid_box("GroundBackup", size, center, BACKUP_COLOR)
	parent.add_child(slab)
	return slab
