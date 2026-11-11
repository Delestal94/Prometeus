class_name CompanyPhoneMap
extends Control
## The phone's map app (expansion D-1923 with D-0331): every zone's rectangle (ZoneDefinition.bounds, metres on the
## world's X and Z) scaled to fit this control with MARGIN around, in its district colour (DistrictLabel), its name,
## and a badge with how many open orders go there; the player is a dot. map_point() is the same transform, so a test
## (or a later marker) places a world spot on it.

const MARGIN: float = 10.0
const DOT_RADIUS: float = 6.0

## ZoneDefinitions to draw, open orders by zone id, the player's world position (null: none).
var zones: Array = []
var counts: Dictionary = {}
var player_at: Variant = null


## The union of the zones' bounds (the world area the map shows), or an empty Rect2 without zones.
func world_rect() -> Rect2:
	var area := Rect2()
	var first: bool = true
	for zone: Variant in zones:
		if zone is ZoneDefinition and (zone as ZoneDefinition).bounds.has_area():
			area = (zone as ZoneDefinition).bounds if first else area.merge((zone as ZoneDefinition).bounds)
			first = false
	return area


## Where the world point `at` (X and Z) falls on this control, keeping the map's proportions; null outside the map.
func map_point(at: Vector3) -> Variant:
	var area: Rect2 = world_rect()
	if not area.has_area():
		return null
	var world := Vector2(at.x, at.z)
	if not area.grow(0.001).has_point(world):
		return null
	var room: Vector2 = size - Vector2.ONE * MARGIN * 2.0
	var scale: float = minf(room.x / area.size.x, room.y / area.size.y)
	var offset: Vector2 = Vector2.ONE * MARGIN + (room - area.size * scale) * 0.5
	return offset + (world - area.position) * scale


## A zone's rectangle on the map.
func zone_rect(zone: ZoneDefinition) -> Rect2:
	var start: Variant = map_point(Vector3(zone.bounds.position.x, 0.0, zone.bounds.position.y))
	var end: Variant = map_point(Vector3(zone.bounds.end.x, 0.0, zone.bounds.end.y))
	return Rect2(start, end - start) if start is Vector2 and end is Vector2 else Rect2()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.PAPER, 0.08))
	var font: Font = UiTheme.display_font()
	for raw: Variant in zones:
		var zone := raw as ZoneDefinition
		if zone == null:
			continue
		var rect: Rect2 = zone_rect(zone)
		if not rect.has_area():
			continue
		draw_rect(rect, Color(DistrictLabel.color_for(zone.id), 0.55))
		draw_rect(rect, UiTheme.INK, false, 2.0)
		draw_string(font, rect.position + Vector2(6, 18), DistrictLabel.district_name(zone.id),
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, 13, UiTheme.WHITE)
		var count: int = int(counts.get(zone.id, 0))
		if count > 0:
			var badge: Vector2 = rect.get_center()
			draw_circle(badge, 11.0, UiTheme.YELLOW)
			draw_string(font, badge + Vector2(-6, 5), str(count), HORIZONTAL_ALIGNMENT_CENTER, 12.0, 13, UiTheme.INK)
	if player_at is Vector3:
		var dot: Variant = map_point(player_at)
		if dot is Vector2:
			draw_circle(dot, DOT_RADIUS + 2.0, UiTheme.INK)
			draw_circle(dot, DOT_RADIUS, UiTheme.MINT)
