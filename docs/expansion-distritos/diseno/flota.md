# Flota: tabla de vehículos (D-0115)

> Asientos, carga, velocidad, quién maneja, trampa que amplifica, licencia, precio y zonas de cada vehículo
> del modo Empresa. Es la fuente de los `.tres` de `VehicleDefinition` (D-0207, `data/vehicles/`) y del
> balance medido de D-1241.
> Los números no viven acá. Si uno cambia, se cambia donde vive y esta tabla se corrige en el mismo PR:
> - cada vehículo, en su `.tres`;
> - la velocidad de las camionetas y la 4x4, en `vehicle.gd` `VARIANTS`;
> - los valores compartidos, en `company_tuning.gd`.
>
> El detalle de D-0115 dice "7 filas" pero enumera 8 vehículos (camioneta ×3, 4x4, bici, carrito, lancha,
> avioneta). Van las 8.

## Tabla principal

| # | Vehículo | id | Fase · estado | Quién maneja | Asientos | Carga (cajas · kg) | Vel. máx. | Trampa que amplifica | Licencia / requisito | Precio | Zonas donde entrega |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Camioneta clásica | `van_classic` | **F1** · existe (corte vertical, ítem 11) | conductor; los demás cuidan su caja | 8 | 7 · 300 | 72 km/h | — (la base que perdona) | ninguna; la empresa arranca con una | 1 500 cada unidad extra (la primera es gratis) | parque_industrial, centro, suburbio, campo, puerto |
| 2 | Camioneta ágil | `van_agile` | existe en Partida rápida · en Empresa **F2** | conductor | 8 | 7 · 300 | 84 km/h | Frágil, emergente (dirección nerviosa) | hito `deliveries_25` | 1 800 | las mismas que la 1 |
| 3 | Camioneta vieja (manual) | `van_vintage` | existe en Partida rápida · en Empresa **F2** | conductor, que además hace los cambios | 8 | 7 · 300 | 68 km/h | —; el riesgo es bajar mal un cambio (freno motor) | hito `deliveries_50` | 2 000 | las mismas que la 1 |
| 4 | 4x4 | `offroad` | **F3** · D-1231 abierta (la pide el grupo 16) | conductor; las cadenas las pone cualquiera, a mano (D-1612) | 6 | 6 · 250 | 60 km/h | Peso Creciente | licencia 4x4 (D-0124); con base en Montaña pide además la avioneta | 2 500 | base galpón: las del llano; base Montaña: montana, nieve (con cadenas), volcan (base) |
| 5 | Bici | `bike` | **F2** núcleo · D-1207 a D-1220 | el que pedalea, solo | 1 | 2 · 25 | 30 km/h | Equilibrio | ninguna | 250 | parque_industrial, centro, suburbio, puerto |
| 6 | Carrito (eléctrico tipo golf) | `cart` | **F2** ampliación · D-1221 a D-1229 | conductor | 4 | 4 · 80 | 40 km/h | Ruidoso | ninguna; aparece con el hito `deliveries_25` (abre Suburbio); con base en Islas pide la lancha | 900 | base galpón: parque_industrial, centro, suburbio, puerto; base Islas: islas |
| 7 | Lancha | `boat` | **F3** · D-1301 a D-1320 | timonel | 6 | 6 · 150 | 50 km/h | Líquido | licencia náutica (la misma que pide `gate_puerto`) | 5 000 | puerto (muelles), islas |
| 8 | Avioneta | `plane` | **F4** · D-1401 a D-1420 | piloto; el copiloto navega y apunta el lanzamiento (D-1421) | 6 | 4 · 100 | 160 km/h | Frágil | licencia de vuelo (D-1418) y aeródromo (D-1405) | 12 000 | montana (pista), nieve (esquís, D-1425), volcan (paracaídas, D-1420) |

Ninguna fila está recortada ni pospuesta: son vehículos que nombró el usuario (fila 5 de las decisiones
delegadas). Lo pospuesto son **variantes que no son filas**: camión grande D-1232, lancha grande D-1325,
avioneta grande D-1430, moto de nieve D-1623 y vehículo dentro de otro D-1237.

## Campos para VehicleDefinition (D-0207)

| id | scene | variant | seats | cargo_slots | cargo_kg | movement | gate_key | price | fleet_key ¹ | amplified_trap ¹ |
|---|---|---|---|---|---|---|---|---|---|---|
| `van_classic` | `res://scenes/gameplay/vehicle/vehicle.tscn` | `&"classic"` | 8 | 7 | 300.0 | `&"wheels"` | `&""` | 1500 | `&"van"` | `&""` |
| `van_agile` | `res://scenes/gameplay/vehicle/vehicle.tscn` | `&"agile"` | 8 | 7 | 300.0 | `&"wheels"` | `&""` | 1800 | `&"van"` | `&""` |
| `van_vintage` | `res://scenes/gameplay/vehicle/vehicle.tscn` | `&"vintage"` | 8 | 7 | 300.0 | `&"wheels"` | `&""` | 2000 | `&"van"` | `&""` |
| `offroad` | `res://scenes/gameplay/vehicle/vehicle.tscn` | `&"offroad"` (nueva en `VARIANTS`, D-1231) | 6 | 6 | 250.0 | `&"wheels"` | `&""` | 2500 | `&"offroad"` | `&"growing_weight"` |
| `bike` | `res://scenes/gameplay/fleet/bike.tscn` (la crea D-1207) | `&""` | 1 | 2 | 25.0 | `&"pedal"` | `&""` | 250 | `&"bike"` | `&"balance"` |
| `cart` | `res://scenes/gameplay/fleet/cart.tscn` (D-1221) | `&""` | 4 | 4 | 80.0 | `&"wheels"` | `&""` | 900 | `&"cart"` | `&"noisy"` |
| `boat` | `res://scenes/gameplay/fleet/boat.tscn` (D-1302) | `&""` | 6 | 6 | 150.0 | `&"hull"` | `&"water"` | 5000 | `&"boat"` | `&"liquid"` |
| `plane` | `res://scenes/gameplay/fleet/plane.tscn` (D-1401) | `&""` | 6 | 4 | 100.0 | `&"wings"` | `&"altitude"` | 12000 | `&"plane"` | `&"fragile"` |

¹ **Campos que suma esta tabla** a los de D-0207:

- **`fleet_key`** es la clave que miran tres lugares: `ZoneDefinition.vehicles` (`centro.tres` ya lista
  `bike` y `van`; `campo.tres`, `van`), `GateRequirement.vehicle_key` (`gate_islas_agua` pide `boat`;
  `gate_montana_altura`, `plane`) y la entrada `"vehicle"` de `CompanyState.fleet` que lee `gate_owned()`.
  Así las tres camionetas cuentan como `van` sin repetir ids en cada zona.
- **`amplified_trap`** usa el id de la trampa en `data/traps/`.

Reglas de los campos:
- `cargo_slots` cuenta todas las cajas a bordo: en las manos de un pasajero o en un soporte.
- `gate_key` vale `water` o `altitude` (`GateRequirement.Kind`) solo para el vehículo que cruza ese
  bloqueo sin colisión.
- `price` es el de **una unidad**. La primera `van_classic` la regala la empresa nueva:
  `STARTING_FLEET = [&"van_classic"]` en `company_tuning.gd` (nuevo, lo agrega D-0207).

## Reglas comunes

- **Trampa amplificada.** Cuando la caja viaja en un vehículo con `amplified_trap`, la intensidad que
  calcula `BoxTrap` (D-0710) para esa trampa se multiplica por `VEHICLE_TRAP_AMPLIFY = 1.5`, con tope 1
  (constante nueva en `company_tuning.gd`).
  - La intensidad sale de la calidad (1 − Q/100): una caja con Q = 100 vale 0 y sigue en 0. **Armar bien
    anula la amplificación**, que es la promesa de [vision.md](vision.md) §1.
  - El despacho (D-1202) muestra el ícono de la trampa amplificada al lado de cada caja que la tiene, así
    el fallo se entiende antes de salir.
  - En las camionetas no hay multiplicador: lo "emergente" lo pone la física que ya existe.
- **Unidades y base.** La flota se compra por unidad (D-1201). Cada unidad guarda `{id, fleet_key, base}`:
  la base es el galpón o la zona donde queda estacionada (carrito en el muelle de Islas, 4x4 en la pista de
  Montaña). Es la alternativa barata de la crítica (P13: "ya están allá"), porque no hay vehículo dentro de
  otro (D-1237 pospuesta). Una unidad no cambia de base.
- **Tope de 2 vehículos lejos del galpón** (mapa continuo, punto 6): cuenta el que tiene conductor; las
  unidades estacionadas en su base duermen. Comprar cinco bicis no da cinco salidas.
- **Velocidad.** No es campo de `VehicleDefinition`: camionetas y 4x4 en `vehicle.gd` `VARIANTS`; los
  vehículos nuevos en el ajuste de cada uno (D-1208, D-1221, D-1302, D-1401). D-1241 la mide con bots
  contra esta tabla.
- **Precio.** Vive en el `.tres` del vehículo. La lista de flota de [economia.md](economia.md) §4
  (250 / 900 / 2 500 / 5 000 / 12 000) se respeta tal cual; no se duplica en `company_tuning.gd`.
- **La camioneta vieja en Empresa.** `pay_multiplier` (×1,25, `VehicleGearbox.PAY_MULTIPLIER`) se aplica
  **solo al envío** (`shipping_fee`), no al pedido entero (`VINTAGE_PAY_ON_SHIPPING_ONLY = true`). Sobre el
  pedido medio serían +52 (210 × 0,25), la mitad del margen (≈ 102), y con 4 jugadores casi duplicaría el
  ritmo de +740 por día: sería la compra obligatoria. Sobre el envío son +10 a +37 por pedido.
- **Partida rápida no cambia.** `UnlockManager.TRUCKS` y `UNLOCKS` siguen abriendo la ágil y la vieja en el
  perfil. En Empresa mandan los hitos de `CompanyState` ([reutilizacion.md](reutilizacion.md), fila 9).

## Chequeo de tiempos (regla N-102: 2-5 min)

Velocidad media ≈ 60 % de la máxima, la misma proporción que la referencia de [mapa.md](mapa.md): 12 m/s
para 72 km/h.

| Vehículo | Tramo | Largo | Media | Tiempo | Límite |
|---|---|---|---|---|---|
| Bici | portón → primera casa de Centro | ~400 m | 5 m/s | ~80 s | ≤ 90 s ✔ |
| Carrito | portón → fondo de Suburbio | ~1,3 km | 6,7 m/s | ~3,2 min | 2-4 min ✔ |
| Lancha | muelle (1792, 256) → isla lejana | ~2 km | 8 m/s | ~4 min | 3-5 min ✔ (desde el muelle, que D-1305 hace anexo del galpón) |
| Avioneta | aeródromo → pista del Volcán (1024, −2304) | ~2,5 km | 27 m/s | ~95 s + ~60 s de despegue y aterrizaje | 4-5 min ✔ |
| 4x4 | pista de Montaña → casas por calle local | ≤ 2 km | 10 m/s | ≤ 3,5 min | 4-5 min con paradas ✔ |

## Notas por vehículo

1. **Camioneta clásica.** La de hoy, sin cambios de manejo (corte vertical). `vehicle.tscn` tiene un
   conductor, 10 puntos de asiento y 7 soportes de caja; 8 asientos es el tope de la tripulación
   (`NetworkManager.MAX_PLAYERS`) y 7 cajas es una por casa (`UnlockManager.MAX_DELIVERY_HOUSES`). Los
   "4 asientos" de [roles-tripulacion.md](roles-tripulacion.md) §1 son el reparto sugerido por salida, no la
   capacidad.
2. **Camioneta ágil.** Más rápida, así que entran más salidas por día, pero castiga lo frágil (comentario de
   `VARIANTS`). No lleva multiplicador: la física ya lo hace, y uno encima la volvería inútil.
3. **Camioneta vieja.** Caja manual (`VehicleGearbox`): bajar un cambio de más frena con el motor como un
   frenazo. El trabajo extra es del conductor. Paga más el envío.
4. **4x4.** Variante nueva de `VARIANTS` sobre la misma escena (D-1231), así que no hace falta arte de
   vehículo para arrancar. **Peso Creciente:** en pendiente la carga se desliza (D-1602) y la más pesada,
   más; el "Asegurá" se vuelve urgente en la subida. Con base en Montaña llega "ya allá" (P13). Montaña se
   abre con la avioneta (mapa continuo), no con la 4x4: D-0416 queda marcada para reescribir.
5. **Bici.** El rol de un jugador en Centro: barata, pasa por los callejones (D-1507) y lleva 2 cajas
   livianas. **Equilibrio:** la caja del canasto se inclina con la bici, así que manejar derecho es
   cuidarla. La caja demasiado grande ya suma Equilibrio ([supuestos.md](../detalle/supuestos.md)), y en la
   bici pega 1,5×. Tándem (D-1210: 2 asientos, 2 cajas) y trailer (D-1211: 1 asiento, 4 cajas, 50 kg) son
   `.tres` propios con `fleet_key = bike`; su precio lo fija cada tarea, entre el de la bici y el del carrito.
6. **Carrito.** 4 asientos (la fila 2 dice de 2 a 4; se toma el máximo para el coop). **Ruidoso:** la caja
   es abierta y no hay radio, que en la camioneta (N-406) calma a los animales. La batería (D-1223) es
   autonomía, no costo.
7. **Lancha.** Timonel + 5 (D-1317). **Líquido:** el oleaje (D-1303) sacude todo a la vez. Solo, el timonel
   no puede cuidar: conviene llevar cajas sin Líquido, y el despacho lo avisa con el ícono.
8. **Avioneta.** Piloto + copiloto + 4 con carga (D-1407). Pocas cajas y poco peso: la entrega cara a la
   zona alta. **Frágil:** aterrizaje duro (D-1403), turbulencia (D-1408) y paracaídas (D-1420; no abre si el
   armado fue malo, D-1423). El copiloto tiene trabajo propio (navegar y apuntar).

## Decisiones

- **8 filas, ids en snake_case**, con `fleet_key` aparte para que zonas y bloqueos no listen variantes.
- **La primera camioneta es gratis**; las extra y las variantes se compran como unidades
  (1 500 / 1 800 / 2 000), entre el carrito y la 4x4 (D-0512).
- **La ágil y la vieja se abren en Empresa con hitos que ya usan los bloqueos** (`deliveries_25` de
  `gate_suburbio`, `deliveries_50` de `gate_puerto`). D-0118 puede cambiar el id.
- **La trampa amplificada es una regla de datos** (×1,5 sobre la intensidad del armado), no solo física:
  así se puede leer y testear.
- **Carrito y 4x4 tienen base fija** (galpón o su zona).
- **La vieja paga ×1,25 solo el envío** en Empresa.

Registro: [docs/decisiones/2026-10-19-flota.md](../../decisiones/2026-10-19-flota.md).

## Fuentes

- [README de la expansión](../README.md), [supuestos.md](../detalle/supuestos.md),
  [F0-01-diseno.md](../detalle/F0-01-diseno.md) (D-0115), [F0-02-arquitectura.md](../detalle/F0-02-arquitectura.md)
  (D-0207 a D-0209)
- [vision.md](vision.md) §7, [distritos.md](distritos.md), [mapa.md](mapa.md), [economia.md](economia.md) §4,
  [critica-alcance.md](critica-alcance.md) (P13, §5.1), [roles-tripulacion.md](roles-tripulacion.md),
  [corte-vertical.md](corte-vertical.md), [armado-y-trampas.md](armado-y-trampas.md),
  [reutilizacion.md](reutilizacion.md), [catalogo-productos.md](catalogo-productos.md)
- Grupos: [04](../04-progresion-e-hitos.md), [12](../12-flota-bici-carrito.md), [13](../13-lancha-e-islas.md),
  [14](../14-avioneta-y-aerodromos.md), [15](../15-distritos-de-tierra.md), [16](../16-montana-y-nieve.md)
- Decisiones: [mapa continuo](../../decisiones/2026-10-04-mapa-continuo.md),
  [delegadas](../../decisiones/2026-10-04-expansion-decisiones-delegadas.md),
  [recortes](../../decisiones/2026-10-19-recortes-expansion.md)
- Código: [vehicle.gd](../../../do-not-drop/scripts/gameplay/vehicle/vehicle.gd) (`VARIANTS`),
  [vehicle_gearbox.gd](../../../do-not-drop/scripts/gameplay/vehicle/vehicle_gearbox.gd),
  [unlock_manager.gd](../../../do-not-drop/scripts/core/unlock_manager.gd) (`TRUCKS`, `UNLOCKS`),
  [company_tuning.gd](../../../do-not-drop/scripts/core/company/company_tuning.gd),
  [company_state.gd](../../../do-not-drop/scripts/core/company/company_state.gd) (`gate_owned`),
  [gate_requirement.gd](../../../do-not-drop/scripts/gameplay/districts/gate_requirement.gd),
  [data/zones/](../../../do-not-drop/data/zones/), [data/gates/](../../../do-not-drop/data/gates/)
