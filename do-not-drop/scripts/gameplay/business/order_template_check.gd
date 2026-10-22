class_name OrderTemplateCheck
extends RefCounted
## Validates the order templates of data/order_templates/ against the catalogs (expansion D-0820).
##
## Pure: the caller passes the catalogs (product id -> ProductDefinition, requirement id ->
## OrderRequirement, zone ids). Returns one readable text per problem, empty when all is sound.

const DIR: String = "res://data/order_templates"
## Most units of one product a template asks for (OrderGenerator asks 1 or 2).
const MAX_QTY: int = 2


## Every set of data/order_templates/, in file name order.
static func load_sets(dir: String = DIR) -> Array[OrderTemplateSet]:
	var sets: Array[OrderTemplateSet] = []
	for file in CompanyCatalog.tres_files(dir):
		var set_res := load(dir.path_join(file)) as OrderTemplateSet
		if set_res != null:
			sets.append(set_res)
	return sets


static func problems(
	sets: Array[OrderTemplateSet],
	products: Dictionary,
	requirements: Dictionary,
	zone_ids: Array[StringName],
) -> Array[String]:
	var out: Array[String] = []
	var set_ids: Array[StringName] = []
	var zones_seen: Array[StringName] = []
	for set_res in sets:
		var tag: String = "set '%s'" % set_res.id
		if set_res.id == &"" or set_res.id in set_ids:
			out.append("%s: id empty or repeated" % tag)
		set_ids.append(set_res.id)
		if not set_res.zone in zone_ids:
			out.append("%s: zone '%s' is not a zone" % [tag, set_res.zone])
		if set_res.zone in zones_seen:
			out.append("%s: zone '%s' already has a set" % [tag, set_res.zone])
		zones_seen.append(set_res.zone)
		if set_res.templates.size() != OrderTemplateSet.PER_ZONE:
			out.append("%s: %d templates, expected %d" % [tag, set_res.templates.size(), OrderTemplateSet.PER_ZONE])
		out.append_array(_set_problems(set_res, tag, products, requirements))
	return out


static func _set_problems(
	set_res: OrderTemplateSet, tag: String, products: Dictionary, requirements: Dictionary
) -> Array[String]:
	var out: Array[String] = []
	var ids: Array[StringName] = []
	var shapes: Array[String] = []
	for template in set_res.templates:
		var label: String = "%s/%s" % [tag, template.id]
		if template.id == &"" or template.id in ids:
			out.append("%s: id empty or repeated" % label)
		ids.append(template.id)
		out.append_array(_template_problems(template, label, set_res.zone, products, requirements))
		var shape: String = _shape(template)
		if shape in shapes:
			out.append("%s: same products and requirements as another template" % label)
		shapes.append(shape)
	return out


static func _template_problems(
	template: OrderTemplate, label: String, zone: StringName, products: Dictionary, requirements: Dictionary
) -> Array[String]:
	var out: Array[String] = []
	var count: int = template.items.size()
	if count < CompanyTuning.ORDER_ITEMS_MIN or count > CompanyTuning.ORDER_ITEMS_MAX:
		out.append("%s: %d products, expected %d..%d" % [
			label, count, CompanyTuning.ORDER_ITEMS_MIN, CompanyTuning.ORDER_ITEMS_MAX
		])
	var seen: Array[StringName] = []
	var has_home := false
	var implied: Array[StringName] = []
	for item in template.items:
		var product_id := StringName(item.get("product", &""))
		var def: ProductDefinition = products.get(product_id)
		if def == null:
			out.append("%s: product '%s' is not in the catalog" % [label, product_id])
			continue
		if product_id in seen:
			out.append("%s: product '%s' repeats" % [label, product_id])
		seen.append(product_id)
		var qty := int(item.get("qty", 0))
		if qty < 1 or qty > MAX_QTY:
			out.append("%s: '%s' qty %d outside 1..%d" % [label, product_id, qty, MAX_QTY])
		if zone in def.districts:
			has_home = true
		if def.fragile:
			implied.append(&"fragile")
		if def.temperature == &"cold":
			implied.append(&"cold")
	if not has_home and not template.items.is_empty():
		out.append("%s: no product of the zone '%s'" % [label, zone])
	var reqs_seen: Array[StringName] = []
	for req_id in template.requirements:
		if not requirements.has(req_id):
			out.append("%s: requirement '%s' is not in the catalog" % [label, req_id])
		if req_id in reqs_seen:
			out.append("%s: requirement '%s' repeats" % [label, req_id])
		reqs_seen.append(req_id)
	for req_id in implied:
		if not req_id in template.requirements:
			out.append("%s: its products imply '%s'" % [label, req_id])
	return out


## Order-independent key of what a template asks for.
static func _shape(template: OrderTemplate) -> String:
	var parts: Array[String] = []
	for item in template.items:
		parts.append("%s*%d" % [item.get("product", &""), int(item.get("qty", 0))])
	parts.sort()
	var reqs: Array[String] = []
	for req_id in template.requirements:
		reqs.append(str(req_id))
	reqs.sort()
	return "%s|%s" % [",".join(parts), ",".join(reqs)]
