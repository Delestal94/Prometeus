class_name DistrictLabel
extends RefCounted
## The colour stripe of a shipping label by district (expansion D-0732, "Modo Empresa").
##
## Static and stateless. Every district has one label colour and one name key, so a crew sorting boxes in
## the dispatch zone reads the destination from the colour before the street. The colours are not the
## ground colours of the map (CompanyRoot.ZONE_COLORS): those are muted for terrain, these are saturated
## and far apart so they stay apart on a small paper. Painting the stripe on package_shipping_label.gd is
## D-0732.b; this class only decides which colour and name a label carries.

## Label stripe per zone id (ZoneDefinition.id).
const COLORS: Dictionary = {
	&"parque_industrial": Color(0.35, 0.35, 0.40),
	&"centro": Color(0.90, 0.25, 0.25),
	&"suburbio": Color(0.95, 0.60, 0.15),
	&"campo": Color(0.30, 0.75, 0.30),
	&"puerto": Color(0.20, 0.40, 0.85),
	&"islas": Color(0.15, 0.80, 0.80),
	&"montana": Color(0.55, 0.35, 0.20),
	&"nieve": Color(0.85, 0.90, 1.00),
	&"volcan": Color(0.65, 0.15, 0.55),
}
## Colour of a zone this table does not know (a label never goes without one).
const FALLBACK_COLOR: Color = Color(0.60, 0.60, 0.60)
## Name key per zone id (strings_ui.csv).
const NAME_KEYS: Dictionary = {
	&"parque_industrial": &"UI_COMPANY_DISTRICT_PARQUE_INDUSTRIAL",
	&"centro": &"UI_COMPANY_DISTRICT_CENTRO",
	&"suburbio": &"UI_COMPANY_DISTRICT_SUBURBIO",
	&"campo": &"UI_COMPANY_DISTRICT_CAMPO",
	&"puerto": &"UI_COMPANY_DISTRICT_PUERTO",
	&"islas": &"UI_COMPANY_DISTRICT_ISLAS",
	&"montana": &"UI_COMPANY_DISTRICT_MONTANA",
	&"nieve": &"UI_COMPANY_DISTRICT_NIEVE",
	&"volcan": &"UI_COMPANY_DISTRICT_VOLCAN",
}


## The zone an order is shipped to; &"" when it names none.
static func zone_of(order: Dictionary) -> StringName:
	return StringName(str(order.get("zone", "")))


## The stripe colour of a zone; FALLBACK_COLOR for one the table does not know.
static func color_for(zone: StringName) -> Color:
	return COLORS.get(zone, FALLBACK_COLOR)


## The stripe colour of the label an order's box carries.
static func color_for_order(order: Dictionary) -> Color:
	return color_for(zone_of(order))


## Translation key of a district's name; &"" for a zone the table does not know.
static func name_key(zone: StringName) -> StringName:
	return NAME_KEYS.get(zone, &"")


## The district's name in the current language; "" for a zone the table does not know.
static func district_name(zone: StringName) -> String:
	var key: StringName = name_key(zone)
	return "" if key == &"" else TranslationServer.translate(key)


## True when two boxes' orders go to the same district (sorted into one stack in dispatch).
static func same_district(a: Dictionary, b: Dictionary) -> bool:
	var zone: StringName = zone_of(a)
	return zone != &"" and zone == zone_of(b)
