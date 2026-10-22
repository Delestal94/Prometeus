class_name OrderTemplateSet
extends Resource
## The order templates of one district, one file per zone in data/order_templates/ (expansion D-0820).

## Templates a district brings (D-0820: "40 pedidos plantilla por distrito").
const PER_ZONE: int = 40

@export var id: StringName = &""
## The zone these orders are delivered to (a ZoneDefinition id).
@export var zone: StringName = &""
@export var templates: Array[OrderTemplate] = []


## Template ids repeat nowhere inside a set.
func by_id(template_id: StringName) -> OrderTemplate:
	for template in templates:
		if template.id == template_id:
			return template
	return null
