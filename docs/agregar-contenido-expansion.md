# Cómo agregar contenido de la expansión (Modo Empresa)

> Tarea D-0244 (2026-10-22). Una sola guía para todo el contenido de datos del modo empresa, en vez
> de una por tipo (decisión de `docs/expansion-distritos/diseno/critica-alcance.md`; absorbe
> D-0850, D-0950, D-1050, D-1150 y D-1250). Para el vehículo del juego actual
> (`VehiclePresentation`) mirá `docs/agregar-vehiculo.md`.

## La regla general

El contenido son `.tres` (clases `Resource` de solo datos) en `do-not-drop/data/<tipo>/`. El nombre
del archivo y el campo `id` son el mismo. **Los números viven en esos `.tres` y en
`scripts/core/company/company_tuning.gd` (`CompanyTuning`); no se copian en código ni en docs.** Los
campos de cada clase tienen su comentario y sus rangos en el script; esta guía dice qué archivos
tocar, cómo lo encuentra el juego y qué test lo cubre.

`CompanyCatalog` (`scripts/core/company/catalog.gd`) lee por id, sin código, las carpetas
`products`, `zones`, `vehicles`, `gates`, `suppliers` y `boxes` (constante `KINDS`). Un id repetido,
faltante o un archivo que no carga no es fatal: queda en `errors` y gana el primero. Las demás
carpetas (`order_requirements`, `placeables`, `shop`, `shed`, `world`) las leen sus propios scripts
por ruta, como se indica abajo.

Para cualquier alta, antes de cerrar: texto visible con clave de traducción (`WORLD_*`, ver
`docs/convenciones-godot.md` y la skill `localizador`) y `tools/run-tests.sh <filtro>` del test que
se nombra en cada sección. Los tests que validan los datos están anotados en su encabezado.

## Producto

- **Archivos**: `data/contents/<id>.tres` (`PackageContent`: modelo, textos, notas; ya existente en el
  juego base) y `data/products/<id>.tres` con el mismo nombre (`ProductDefinition`,
  `scripts/gameplay/business/product_definition.gd`). Además la trampa que carga el contenido,
  `data/traps/<trap_id>.tres`, tiene que listar ese contenido en `TrapDefinition.contents`.
- **Campos**: `id`, `content`, `cells` (tamaño en celdas de 0,2 m; cada eje entra en la caja XL),
  `weight_kg`, `fragile`, `temperature` (`ambient`/`cold`/`heat`), `buy_price`, `sell_price` (0 =
  compra x `CompanyTuning.SELL_MARKUP`), `trap_id`, `districts`.
- **Encuentro**: `CompanyCatalog.product(id)` por carpeta. Para que se venda, sumalo a
  `SupplierDefinition.products` de algún proveedor (ver abajo).
- **Test**: `tests/test_product_definitions.gd` (uno por contenido, tamaños, rango de precios,
  temperatura, trampa real) y `tests/test_company_catalog.gd`. Ojo: ambos fijan la cantidad actual
  (diez); sumar un producto implica actualizarlos. Catálogo de diseño:
  `docs/expansion-distritos/diseno/catalogo-productos.md`. README: `data/products/README.md`.

## Caja

- **Archivo**: `data/boxes/<id>.tres` (`BoxDefinition`, `scripts/gameplay/business/box_definition.gd`):
  `id`, `cells`, `cost`, `model`.
- **Números**: `cells` y `cost` espejan `CompanyTuning.BOX_CELLS` y `BOX_COST`; cambiá los dos lados.
- **Encuentro**: `CompanyCatalog.box(id)` y `boxes()` (de menor a mayor volumen).
- **Test**: `tests/test_company_catalog.gd` (coinciden con `CompanyTuning`, cada una más grande y cara
  que la anterior). README: `data/boxes/README.md`.

## Proveedor

- **Archivo**: `data/suppliers/<id>.tres` (`SupplierDefinition`,
  `scripts/gameplay/business/supplier_definition.gd`): `products` (ids de `data/products/`),
  `price_factor`, `arrival_min`, `wait_minutes`, `truck_scene` (opcional).
- **Encuentro**: `CompanyCatalog.supplier(id)`. El calendario de entregas lo arma `SupplierSchedule`.
- **Tests**: `tests/test_company_catalog.gd`, `test_supplier_schedule.gd`, `test_supplier_purchase.gd`,
  `test_supplier_truck.gd`. README: `data/suppliers/README.md`.

## Vehículo de la flota

- **Archivos**: `data/vehicles/<id>.tres` (`VehicleDefinition`,
  `scripts/gameplay/fleet/vehicle_definition.gd`) más su escena. Campos: `id`, `scene`, `variant`
  (clave de `vehicle.gd` `VARIANTS`, vacío si no tiene), `seats`, `cargo_slots`, `cargo_kg`,
  `movement` (uno de `MOVEMENTS`), `gate_key`, `price`, `fleet_key`, `amplified_trap`. `is_valid()`
  pide id, escena, movimiento conocido, asientos, carga y `fleet_key`.
- **Cómo entra a la flota**: se compra con un `data/shop/<id>.tres` (`ShopItem`, `kind = &"vehicle"`,
  `grant_key` = el `fleet_key`); `CompanyShop.buy` agrega `{"vehicle": grant_key}` a
  `CompanyState.fleet`. `ZoneDefinition.vehicles` y `GateRequirement.vehicle_key` miran ese mismo
  `fleet_key`. Hoy `CompanyState.new_company()` arranca con la flota vacía (nota en
  `company_tuning.gd`, hasta el concesionario D-1201).
- **Un vehículo que se maneja**: además la escena tiene que cumplir `docs/agregar-vehiculo.md`
  (presentación y `FleetMotion` para la carga).
- **Test**: `tests/test_vehicle_definitions.gd` (hoy exige una definición por clave de
  `unlock_manager.gd` `TRUCKS`, la variante en `VARIANTS` y la escena instanciable),
  `tests/test_fleet_components.gd`, `tests/test_fleet_motion.gd`, `tests/test_company_shop.gd`.
  Diseño: `docs/expansion-distritos/diseno/flota.md`. README: `data/vehicles/README.md`.

## Requisito de pedido (tipo de pedido)

- **Archivo**: `data/order_requirements/<id>.tres` (`OrderRequirement`,
  `scripts/gameplay/business/order_requirement.gd`): `id`, `display_key` (`WORLD_REQ_<ID>`),
  `required_seals`, `min_quality` (0..100), `window_factor` (0,1..1,0; multiplica
  `CompanyTuning.ORDER_WINDOW_MIN`), `pay_bonus` (0..1).
- **Encuentro**: sin catálogo; `BoxSeals.required()` carga `res://data/order_requirements/<id>.tres`
  por el id que lista `Order.requirements`. Los sellos de `required_seals` tienen que estar en
  `BoxSeals.KINDS` (si el requisito pide un sello nuevo hay que sumarlo ahí y al armado de cajas).
  Generación y precio: `order_generator.gd`, `order_pricing.gd`; el pedido: `order.gd`.
- **Test**: `tests/test_order_requirements.gd` (hoy fija exactamente los seis actuales: sumar uno
  implica actualizarlo), `test_box_seals.gd`, `test_box_content_check.gd`.
- **Sin README propio** en `data/order_requirements/`; el resumen está en
  `scripts/gameplay/business/README.md`.

## Objeto colocable del galpón

- **Archivo**: `data/placeables/<id>.tres` (`PlaceableDefinition`,
  `scripts/gameplay/business/placeable_definition.gd`): `id`, `display_key` (`WORLD_PLACEABLE_<ID>`),
  `footprint` (celdas de `CompanyTuning.WAREHOUSE_GRID_M`), `height_m`, `price`, `role`
  (`assembly`/`storage`/`dispatch`), `slots` (solo `storage`), `cold`, `blocks_walking`,
  `owned_at_start`. El reembolso al vender es `CompanyTuning.PLACEABLE_REFUND_RATIO` del precio.
- **Encuentro**: `PlaceableShop.definition(id)` carga `res://data/placeables/<id>.tres`; el modo
  construcción (`build_mode.gd`) y la colocación (`build_placement.gd`) leen esa definición. No pasa
  por `CompanyCatalog`. La escena/dibujo del objeto nuevo en el galpón es aparte (`CompanyShed`).
- **Para que arranque puesto**: agregarlo a `data/shed/default_shed.tres` (`DefaultShed`).
- **Tests**: `tests/test_placeable_definitions.gd` (hoy fija los cuatro actuales),
  `test_placeable_shop.gd`, `test_company_default_layout.gd`. READMEs: `data/placeables/README.md`,
  `data/shed/README.md`.

## Zona (distrito), puertas y mapa

- **Archivos**: `data/zones/<id>.tres` (`ZoneDefinition`,
  `scripts/gameplay/districts/zone_definition.gd`: `id`, `display_key` `WORLD_ZONE_<ID>`, `bounds`,
  `vehicles`, `hazards`, `gates`, `mood_profiles`, `shipping_fee`, `houses_per_trip`,
  `base_reputation_gain`) y, por cada puerta que cierra la zona, `data/gates/gate_<lugar>.tres`
  (`GateRequirement`, `gate_requirement.gd`: `kind`, `milestone`, `vehicle_key`, `equipment`, `cost`,
  `position_xz`). El id de puerta empieza con `gate_`, es único entre zonas y tiene que coincidir con
  el archivo.
- **Mapa**: `data/world/road_graph.tres` (`RoadGraph`: calles y nodos, un nodo `gate` nombra su
  archivo de `data/gates/`) y `data/world/houses.tres` (`HouseMap`: casas de entrega, a 4..12 m de la
  calzada, 12 m entre sí). El detalle de campos está en `data/world/README.md`.
- **Encuentro**: `CompanyCatalog.zone(id)`, `zones()`, `gate(id)`. Sin código si la zona no trae
  mecánicas nuevas.
- **Tests**: `tests/test_zone_definitions.gd` (límites sin solaparse dentro del mapa, puertas con su
  archivo), `test_company_catalog.gd`, `test_company_dispatch_rules.gd`, `test_road_graph.gd`,
  `test_road_graph_path.gd`, `test_company_houses.gd`, `test_company_addresses.gd`. READMEs:
  `data/zones/README.md`, `data/gates/README.md`, `data/world/README.md`,
  `scripts/gameplay/districts/README.md`. Diseño: `docs/expansion-distritos/diseno/distritos.md`.

## Ítem de la tienda de la empresa (máquinas, vehículos, ampliaciones)

- **Archivo**: `data/shop/<id>.tres` (`ShopItem`, `scripts/gameplay/business/shop_item.gd`): `id`,
  `display_key`, `kind` (`vehicle`/`machine`/`expansion`), `price`, `grant_key`, `stage` (solo
  ampliación), `requires`, `enabled`.
- **Encuentro**: `CompanyShop.items()` lee todos los `.tres` de `res://data/shop`.
- **Test**: `tests/test_company_shop.gd`. README: `data/shop/README.md`.
- Esto es lo que hoy existe para "máquinas" como equipo comprable (`machine` entra a
  `CompanyState.equipment`); la máquina que trabaja en el galpón es el punto siguiente.

## Rol de empleado

Todavía no existe; se completa con D-1002 (los cinco roles) y D-1021 (stats), ver
`docs/expansion-distritos/10-empleados.md`.

## Máquina del galpón

Todavía no existe como objeto que trabaja; se completa con D-1101 (cinta), D-1104 (encintadora) y
D-1105 (etiquetadora) de `docs/expansion-distritos/11-automatizacion.md`; el ítem comprable ya está
en la tienda (arriba).

## Cómo cerrar un alta

1. `tools/run-tests.sh <filtro>` del test de la sección (y `company_catalog` si tocaste una carpeta
   del catálogo).
2. `python tools/check_modules.py` si tocaste algo bajo `modules/`.
3. Si el cambio afecta al otro integrante, un aviso nuevo en `docs/avisos/`.
