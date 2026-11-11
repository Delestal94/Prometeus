# Logros de Steam del modo Empresa (D-0138)

> Diseño de los 30 logros de Steam de la expansión ([`docs/expansion-distritos/`](../expansion-distritos/README.md)).
> Lo construye **D-0440** ([grupo 04](../expansion-distritos/04-progresion-e-hitos.md), absorbió los hitos
> secretos D-0421 y D-2028). Escrito 2026-10-22, sin AppID propio (N-901) y con cero código de logros
> ([estado-steam.md](estado-steam.md), fila Logros).
> "Logro" es solo lo de Steam; "hito" son los 30 de [hitos.md](../expansion-distritos/diseno/hitos.md)
> ([glosario](../expansion-distritos/diseno/glosario.md)). Algunos logros se apoyan en un hito, pero no son lo mismo.

## 1. Reglas de diseño

1. **Alcanzables con 1 y con 8 jugadores.** Ningún logro pide una cantidad de jugadores ni dos personas en dos
   lugares a la vez. Lo que en coop hace "el que se queda", el solitario lo hace con la pausa, el galpón congelado
   y los empleados ([roles-tripulacion.md](../expansion-distritos/diseno/roles-tripulacion.md) §6).
2. **Ninguno perdible para siempre.** Si depende de algo al azar (evento del día, clima), ese algo vuelve a salir
   en otro día. Si depende de un hito de la empresa, se puede volver a conseguir en otra empresa (otra ranura de
   guardado). No hay logros de "nunca" ni de "sin perder".
3. **Nada de plata real ni de grindeo puro.** El conteo más largo es 100 entregas (llega hacia el día 18 de un
   solitario, el mismo día del hito `deliveries_100`). El resto pide hacer algo, no repetirlo.
4. **Los modificadores de dificultad no bloquean nada** ([dificultad.md](../expansion-distritos/diseno/dificultad.md)
   §5). Las banderas de desarrollo (`CompanyDevFlags`) sí: con una prendida no se otorga ningún logro.
5. **Mezcla:** 13 de progreso (acompañan zonas y flota de F1 a F4), 9 de habilidad coop y 8 graciosos o
   situacionales que venden el caos coop en una captura.
6. **Ocultos: 5**, los "secretos" que heredó D-0421 (paquete en llamas, entrega perfecta en ventisca) y tres más
   que arruinaría leerlos antes. Steam muestra "Logro oculto" hasta que se consigue.
7. **Se deciden en el host y se replican.** El host evalúa la condición y manda un hecho `achievement_earned` por
   `CompanyNet`; cada peer presente lo guarda en su perfil y llama a Steam desde su propio cliente (Steam solo deja
   desbloquear logros del usuario local). **El que entró tarde no recibe lo que pasó antes de entrar**: lo reciben
   los que estaban en la sesión al momento del hecho. Es la regla de los hechos de `CompanyNet` (un snapshot no
   dispara ninguno, `event_bus.gd`), así que no hace falta caso aparte. Los stats de progreso suman solo mientras
   el jugador está presente.
8. **Todos son de equipo.** Si la tripulación lo logra, lo reciben todos los presentes, también el que se quedó en
   el galpón. El modo Empresa es de empresa, no de jugador (como las licencias, hitos.md "Cómo se obtienen" 3).
9. **Prefijo `EXP_`** en mayúsculas. Los 15 del juego actual (S-907) van con `BASE_`, así las dos tablas no chocan.
   Ninguno de estos repite los de S-907: los que se parecen (explosivo, rescate) piden algo propio del modo Empresa.

## 2. Los 30 logros

Fase = la primera fase de la expansión en la que se puede conseguir ([README](../expansion-distritos/README.md)).
Montaña y Nieve son contenido de F3, pero solo se llega con la avioneta (`gate_montana_altura`), así que sus
logros quedan en F4. "Señal" son nombres que ya existen en `do-not-drop/scripts/`; "a crear" es lo que falta.

### 2.1 Progreso (13)

| # | API name | Nombre es / en | Descripción es / en | Condición medible | Fase | Oculto | Stat |
|---|---|---|---|---|---|---|---|
| 1 | `EXP_DAY_ONE` | Abrimos / Open for Business | Cerrá el primer día de tu empresa sin deber plata. / Close your company's first day out of the red. | `EventBus.company_day_summary` con `day == 1` y `CompanyState.money >= 0` al cierre (`Bankruptcy.is_bankrupt` falso) | F1 | no | — |
| 2 | `EXP_DELIVERIES_100` | Cien paquetes / A Hundred Parcels | Estuviste en 100 entregas del modo Empresa. / Be there for 100 Company mode deliveries. | `EventBus.order_delivered` con pago > 0 (regla "Entrega" de hitos.md) suma 1 al stat de cada peer presente | F1 | no | `EXP_STAT_DELIVERIES` 0/100 |
| 3 | `EXP_ZONE_SUBURBIO` | Barrio vecino / Next Door | Entregá un pedido en el Suburbio. / Deliver an order in the Suburbs. | `order_delivered` con pago > 0 y `zone == &"suburbio"` en la orden de `OrderBook` | F2 | no | — |
| 4 | `EXP_FIRST_EMPLOYEE` | Hora de contratar / Hiring Day | Contratá a tu primer empleado. / Hire your first employee. | Primer contrato de la empresa: evento a crear `employee_hired` en `CompanyNet` (grupo 10, D-1001) | F2 | no | — |
| 5 | `EXP_MACHINES_6` | Galpón en marcha / Shed in Motion | Tené seis tipos de máquina andando en el galpón. / Run six kinds of machines in your shed. | `EventBus.milestone_reached(&"machines_6")` | F2 | no | — |
| 6 | `EXP_ZONE_PUERTO` | Olor a puerto / Harbor Smell | Entregá un pedido en el Puerto. / Deliver an order at the Harbor. | `order_delivered`, pago > 0, `zone == &"puerto"` | F3 | no | — |
| 7 | `EXP_ZONE_ISLAS` | Zarpamos / Cast Off | Entregá un pedido en las Islas. / Deliver an order on the Islands. | `order_delivered`, pago > 0, `zone == &"islas"` | F3 | no | — |
| 8 | `EXP_ZONE_MONTANA` | Aterrizaje forzoso / Mountain Landing | Entregá un pedido en la Montaña. / Deliver an order on the Mountain. | `order_delivered`, pago > 0, `zone == &"montana"` | F4 | no | — |
| 9 | `EXP_ZONE_NIEVE` | Cadenas puestas / Chains On | Entregá un pedido en la Nieve. / Deliver an order in the Snow. | `order_delivered`, pago > 0, `zone == &"nieve"` | F4 | no | — |
| 10 | `EXP_ZONE_VOLCAN` | Entrega caliente / Hot Delivery | Entregá un pedido en el Volcán. / Deliver an order on the Volcano. | `order_delivered`, pago > 0, `zone == &"volcan"` | F4 | no | — |
| 11 | `EXP_ALL_ZONES` | Todo el mapa / Coast to Crater | Estuviste en una entrega en cada una de las 8 zonas. / Be there for a delivery in all 8 zones. | Conjunto de zonas (sin `parque_industrial`) en el perfil de cada peer; stat = tamaño del conjunto | F4 | no | `EXP_STAT_ZONES` 0/8 |
| 12 | `EXP_FULL_FLEET` | Flota completa / Full Fleet | Tené bici, carrito, lancha, 4x4 y avioneta a la vez. / Own a bike, cart, boat, 4x4 and plane at once. | Al cierre: `CompanyFleet` tiene al menos un `bike`, `cart`, `boat`, `offroad` y `plane` ([flota.md](../expansion-distritos/diseno/flota.md)) | F4 | no | — |
| 13 | `EXP_NATIONAL` | Logística Nacional / National Logistics | Llevá la empresa hasta el final de la campaña. / Take the company to the end of the campaign. | `EventBus.milestone_reached(&"national_logistics")` | F4 | no | — |

### 2.2 Habilidad coop (9)

| # | API name | Nombre es / en | Descripción es / en | Condición medible | Fase | Oculto | Stat |
|---|---|---|---|---|---|---|---|
| 14 | `EXP_FIVE_STARS` | Cinco estrellas / Five Stars | Conseguí una entrega de cinco estrellas. / Get a five-star delivery. | `OrderRating.stars(result) == 5` sobre el resultado de `OrderSettlement.settle` | F1 | no | — |
| 15 | `EXP_PERFECT_TRIP` | Salida perfecta / Flawless Run | Volvé de una salida con 4 o más pedidos, todos a tiempo, sanos y bien etiquetados. / Return from a run of 4+ orders, all on time, intact and correctly labeled. | `TripResult.build`: `orders >= 4`, `delivered == orders`, `failed == 0`, `broken == 0` y ningún veredicto con `kinds` (`OrderPenalties.assess`) | F1 | no | — |
| 16 | `EXP_PERFECT_DAY` | Día redondo / Perfect Day | Cerrá un día con todos los pedidos entregados, sin roturas ni tardanzas. / Close a day with every order delivered, nothing broken, nothing late. | `company_day_summary`: entregados == pedidos del día (≥ 8), 0 rotos, 0 tarde | F1 | no | — |
| 17 | `EXP_TETRIS` | Ni un hueco / Not an Inch | Sellá una caja L llena hasta el último hueco solo con productos. / Seal an L box filled to the last cell with products only. | `EventBus.box_sealed` con `PackedBox.box_size == &"L"` y celdas de productos == `total_cells()` (el relleno no cuenta; así `assisted_packing` no lo da ni lo bloquea) | F1 | no | — |
| 18 | `EXP_GIANT_ORDER` | Pedido gigante / Bulk Order | Cumplí un Pedido gigante completo y a tiempo. / Fill a Giant Order, complete and on time. | Evento del día `giant_order` ([eventos-del-dia.md](../expansion-distritos/diseno/eventos-del-dia.md)) cerrado con éxito: evento a crear `day_event_resolved(id, success)` | F1 | no | — |
| 19 | `EXP_INSPECTION` | Todo en regla / Up to Code | Pasá una Inspección sin ninguna observación. / Pass an inspection with zero remarks. | Evento `shed_inspection` resuelto sin observaciones: mismo `day_event_resolved` | F1 | no | — |
| 20 | `EXP_CLEAN_FORTNIGHT` | Manos de seda / Silk Gloves | Encadená diez días sin romper nada. / Go ten days in a row without breaking anything. | `milestone_reached(&"clean_fortnight")` | F2 | no | — |
| 21 | `EXP_COLD_VOLCANO` | Helado en el infierno / Snowball's Chance | Entregá un pedido frío intacto en el Volcán. / Deliver a cold order intact on the Volcano. | `order_delivered` en `volcan` de un pedido con requisito frío, sin rotos ni pérdida de frío (`ColdChain`) | F4 | no | — |
| 22 | `EXP_AIRDROP` | Correo aéreo / Air Mail | Tirá una caja en paracaídas a la cumbre del Volcán y que llegue sana. / Parachute a box onto the Volcano summit and have it land intact. | Entrega por lanzamiento de la avioneta (D-1420) en `volcan`, sin `kinds` en el veredicto: evento a crear `airdrop_delivered(order_id)` | F4 | no | — |

### 2.3 Graciosos y situacionales (8)

| # | API name | Nombre es / en | Descripción es / en | Condición medible | Fase | Oculto | Stat |
|---|---|---|---|---|---|---|---|
| 23 | `EXP_LAST_MINUTE` | Sobre la hora / Just in Time | Entregá un pedido en los últimos 5 minutos de su ventana. / Deliver an order in the last 5 minutes of its window. | En el veredicto: `due_min - now_min` entre 0 y 5 (minutos del reloj de juego, `GameClock`), sin `KIND_LATE` | F1 | no | — |
| 24 | `EXP_FUSE` | Paquete en llamas / Hot Potato | Entregá unos fuegos artificiales desactivados con menos de un segundo de mecha. / Deliver fireworks defused with under a second of fuse left. | `ExplosiveTrapBehavior` desactivada con `seconds_left < 1.0` en una caja de `fireworks_crate` cuyo pedido después se entrega con pago > 0. Hace falta que la trampa exponga el valor al desactivarse: señal a crear | F1 | **sí** | — |
| 25 | `EXP_WRONG_DOOR` | No era para mí / Not My Package | Entregá una caja en la casa equivocada. / Deliver a box to the wrong house. | Veredicto con `OrderPenalties.KIND_WRONG` | F1 | **sí** | — |
| 26 | `EXP_COMEBACK` | Resurgir / Back from the Red | Cerrá un día en rojo y llegá después a 2 000 de caja. / Close a day in the red, then build back to 2,000 cash. | Marca en `CompanyState` al cierre con `Bankruptcy.is_bankrupt`; después `money_changed` deja `money >= 2000` | F1 | **sí** | — |
| 27 | `EXP_DOG_DOOR` | Mejor amigo / Good Boy | Entregá en el Suburbio con un perro persiguiéndote. / Deliver in the Suburbs with a dog on your heels. | `order_delivered` en `suburbio` mientras un `ChasingDog` de la casa está en modo persecución (estado a exponer) | F2 | no | — |
| 28 | `EXP_BIKE_FRAGILE` | Pedal y cristal / Glass on Wheels | Entregá un producto frágil intacto yendo en bici. / Deliver a fragile item intact by bike. | `TripResult` con `vehicle_id` `bike` o `bike_tandem`, pedido con requisito frágil entregado sin rotos | F2 | no | — |
| 29 | `EXP_OVERBOARD` | Hombre al agua / Box Overboard | Rescatá una caja que se cayó de la lancha. / Rescue a box that fell off the boat. | `EventBus.cargo_overboard_ended(package_id, rescued = true)` con el paquete cargado en `boat` | F3 | **sí** | — |
| 30 | `EXP_BLIZZARD` | Ni la ventisca / Through the Blizzard | Hacé una entrega perfecta en plena ventisca. / Make a flawless delivery in a blizzard. | `order_delivered` en `nieve` con el clima del día en ventisca ([distritos.md](../expansion-distritos/diseno/distritos.md), D-0135) y veredicto sin `kinds` | F4 | **sí** | — |

Reparto por fase: F1 12, F2 6, F3 3, F4 9. Un jugador del primer Early Access con solo F1-F2 ve 18 alcanzables.

### 2.4 Stats de Steam

| Stat | Tipo | Mín / máx | Liga a | Regla |
|---|---|---|---|---|
| `EXP_STAT_DELIVERIES` | INT, solo sube | 0 / 100 | `EXP_DELIVERIES_100` | Suma 1 por entrega con el peer presente. Se deja de mandar al llegar a 100. |
| `EXP_STAT_ZONES` | INT, solo sube | 0 / 8 | `EXP_ALL_ZONES` | Tamaño del conjunto de zonas del perfil; se manda solo cuando crece. |

En Steamworks cada stat va como "progress stat" del logro: Steam dibuja la barra en la Comunidad y lo desbloquea
solo al llegar al valor ([Heathen KB, stats](https://kb.heathen.group/steam/features/stats)). La notificación
intermedia (`IndicateAchievementProgress`) solo muestra el aviso, no guarda nada
([Heathen KB](https://kb.heathen.group/old-kb/old-toolkit-for-steamworks/unreal/blueprint-nodes/functions/indicate-achievement-progress)):
se llama a 25, 50 y 75 entregas y a 4 y 6 zonas, no en cada entrega. `StoreStats` al cierre del día y al salir.

## 3. Íconos

**Formato.** Por logro, dos imágenes de **256 × 256**, JPG o PNG: la desbloqueada y la bloqueada; Steam muestra
una versión de 64 × 64 en las listas ([hilo de Steam Community](https://steamcommunity.com/discussions/forum/1/558751364691954719/)).
La documentación oficial (`partner.steamgames.com/doc/features/achievements`) no se pudo abrir desde este entorno:
**verificarla al cargar los logros** (tamaño, formato y si sigue pidiendo las dos imágenes).

**Estilo común** (para `artista-conceptual`, sesión de arte de la PC): un objeto o escena chica centrada, silueta
legible a 64 px, fondo liso del color de la familia (progreso: azul de la empresa; habilidad: verde; graciosos:
naranja), marco redondeado igual en los 30. **Sin texto ni números**: la IA nunca dibuja letras. La bloqueada no se
pide: se genera por código (desaturar y oscurecer al 40 %) con un script del pipeline, así las 30 quedan parejas.
Los 5 ocultos usan el mismo ícono bloqueado que el resto (Steam no lo muestra hasta conseguirlo).

| # | API name | Qué se ve |
|---|---|---|
| 1 | `EXP_DAY_ONE` | Persiana del galpón a medio subir con luz cálida adentro |
| 2 | `EXP_DELIVERIES_100` | Torre de cajas marrones apiladas, la de arriba con moño |
| 3 | `EXP_ZONE_SUBURBIO` | Casita con cerco y buzón con una caja al lado |
| 4 | `EXP_FIRST_EMPLOYEE` | Gorra de la empresa colgada de un perchero |
| 5 | `EXP_MACHINES_6` | Engranajes sobre un tramo de cinta transportadora con cajas |
| 6 | `EXP_ZONE_PUERTO` | Grúa portuaria levantando una caja chica |
| 7 | `EXP_ZONE_ISLAS` | Lancha con cajas cruzando una ola |
| 8 | `EXP_ZONE_MONTANA` | Avioneta sobre picos con una caja en la puerta abierta |
| 9 | `EXP_ZONE_NIEVE` | Rueda de 4x4 con cadenas en la nieve |
| 10 | `EXP_ZONE_VOLCAN` | Caja térmica plateada frente a un cráter que humea |
| 11 | `EXP_ALL_ZONES` | Mapa doblado con 8 alfileres de colores |
| 12 | `EXP_FULL_FLEET` | Bici, carrito, lancha, 4x4 y avioneta en fila, de perfil |
| 13 | `EXP_NATIONAL` | Copa dorada con forma de caja |
| 14 | `EXP_FIVE_STARS` | Caja con cinco estrellas encima |
| 15 | `EXP_PERFECT_TRIP` | Camioneta volviendo con la caja de carga vacía y brillo |
| 16 | `EXP_PERFECT_DAY` | Sol poniéndose detrás de un portapapeles con todo tildado (tildes, no letras) |
| 17 | `EXP_TETRIS` | Caja abierta vista de arriba con productos encajados sin huecos |
| 18 | `EXP_GIANT_ORDER` | Montaña de cajas más alta que un muñeco de la tripulación |
| 19 | `EXP_INSPECTION` | Lupa sobre una caja bien cerrada con cinta |
| 20 | `EXP_CLEAN_FORTNIGHT` | Guantes blancos sosteniendo una copa de cristal |
| 21 | `EXP_COLD_VOLCANO` | Pote de helado sin derretir sobre roca de lava |
| 22 | `EXP_AIRDROP` | Caja colgando de un paracaídas sobre el cráter |
| 23 | `EXP_LAST_MINUTE` | Reloj con la aguja a punto de llegar, caja en la puerta |
| 24 | `EXP_FUSE` | Cajón de fuegos artificiales con la mecha casi consumida |
| 25 | `EXP_WRONG_DOOR` | Vecino sorprendido sosteniendo una caja ajena |
| 26 | `EXP_COMEBACK` | Alcancía rota pegada con cinta de embalar |
| 27 | `EXP_DOG_DOOR` | Perro mordiendo la punta de una caja |
| 28 | `EXP_BIKE_FRAGILE` | Bici con una lámpara de cristal en el canasto |
| 29 | `EXP_OVERBOARD` | Caja flotando con un salvavidas alrededor |
| 30 | `EXP_BLIZZARD` | Caja con escarcha bajo copos en diagonal |

## 4. Qué falta para construirlos (para D-0440)

Nada de esto está hecho; lista para que D-0440 lo arme sin preguntar.

1. **Definición de datos.** `data/achievements/exp_*.tres` (o una tabla `const`): API name, claves `tr()` de
   nombre y descripción, oculto, stat y fase. Test de datos: 30 ids únicos con `EXP_`, claves en
   `strings_ui.csv` en es y en, ningún id de S-907 repetido.
2. **Evaluador en el host** (`CompanyAchievements`, adaptador en `scripts/`; la parte que no sabe de pedidos puede
   ir a un módulo `modules/achievements/`): escucha `order_delivered`, `company_day_summary`, `milestone_reached`,
   `box_sealed`, `money_changed`, `cargo_overboard_ended` y los veredictos de `OrderPenalties`/`TripResult`.
   No evalúa nada si `CompanyDevFlags` tiene algo prendido.
3. **Hecho de red `achievement_earned(api_name)`** en `CompanyNet`: el host lo emite, cada peer lo aplica. Sube
   `PROTOCOL_VERSION` (hoy 51) según `docs/convenciones-godot.md` §6. Pasa por `auditor-red`.
4. **Eventos a crear** (cada uno en su tarea dueña, D-0440 solo los escucha): `employee_hired` (grupo 10),
   `day_event_resolved(id, success)` (eventos del día), `airdrop_delivered` (D-1420), la mecha al desactivar
   (`ExplosiveTrapBehavior`), estado de persecución de `ChasingDog`, clima del día legible (D-0135).
5. **Sistema local** compartido con S-907: `achievements` en el perfil de `UnlockManager` (y el conjunto de zonas
   de `EXP_STAT_ZONES`), aviso en pantalla (`constructor-ui`). Funciona sin Steam: es lo que prueba el CI.
6. **Puente a Steam** (`constructor-red`): `setAchievement`, `setStatInt`, `indicateAchievementProgress`,
   `storeStats` por GodotSteam; solo si Steam está corriendo y el AppID no es 480. Al arrancar, sube lo que el
   perfil tiene y Steam no (sesiones sin Steam). **Espera a N-901** (AppID propio).
7. **Steamworks**: cargar 30 logros, 2 stats, 60 íconos, textos es/en (y los idiomas que sume `localizador`).
8. **Tests**: un test por condición en sim (bot o datos), uno de red con 2 peers donde el segundo entra después
   del hecho y no lo recibe, y uno de que las banderas de desarrollo no otorgan nada.

## 5. Decisiones

- **Decisión: logros de equipo, para todos los presentes**, porque es un coop de empresa: si solo lo recibiera el
  que entregó, el que arma en el galpón nunca sacaría los de ruta, y con 1 jugador no cambia nada.
- **Decisión: el que entra tarde no recibe lo anterior**, porque es lo que ya hacen los hechos de `CompanyNet` (el
  snapshot no dispara nada) y evita que un amigo regale la campaña entera al sumarse. No se pierde nada: los de
  hito se repiten en otra empresa y los stats suman desde que entra.
- **Decisión: el host decide y cada peer desbloquea en su Steam**, porque Steam solo deja desbloquear logros del
  usuario local; un solo camino (`achievement_earned`) es más barato de testear que evaluar en cada peer.
- **Decisión: 13 de progreso que no copian los 30 hitos**, porque un logro por hito duplica el tablero de D-0410.
  Se usan tres hitos (`machines_6`, `clean_fortnight`, `national_logistics`) y el resto mide **entregar** en cada
  zona, no abrirla: abrir se puede pagar (la obra de Campo), entregar hay que jugarlo.
- **Decisión: sin logro de Campo**, porque es la ruta del juego actual y abre el día 4; con Suburbio alcanza para
  el primer "barrio nuevo". Campo cuenta para `EXP_ALL_ZONES`.
- **Decisión: Montaña y Nieve en F4**, porque aunque sean contenido de F3 solo se llega con la avioneta.
- **Decisión: 5 ocultos y no 8** (D-0421 pedía 8): los que arruina leerlos antes. Más ocultos esconden la lista en
  la página de Steam, que también vende el juego.
- **Decisión: dos stats y no más**, porque solo dos logros cuentan algo; los demás son de un solo hecho. Los stats
  son del jugador (suman entre empresas), así nadie los pierde al cambiar de ranura.
- **Decisión: 100 entregas como techo de conteo**, porque coincide con el hito `deliveries_100` (día ~18 de un
  solitario): más sería grindeo.
- **Decisión: `EXP_TETRIS` cuenta solo productos**, así `assisted_packing` no lo da gratis ni lo bloquea (§1.4).
- **Decisión: `EXP_WRONG_DOOR` y `EXP_COMEBACK` premian un error**, porque son baratos, dan risa y salen solos en
  la primera semana; ocultos para que nadie se equivoque a propósito antes de saberlo.
- **Decisión: sin logros de lo recortado o pospuesto** ([critica-alcance.md](../expansion-distritos/diseno/critica-alcance.md)):
  nada de rival, sabotaje, prestigio, clientes VIP o recurrentes, contratos, desafíos diarios, estadísticas,
  récords, mercado de proveedores, huelgas, ni vehículos pospuestos (moto de nieve, camión grande).
- **Decisión: prefijo `BASE_` para S-907**, para que el día que se carguen los 45 juntos en Steamworks se ordenen
  por modo.
- **Decisión: ícono bloqueado por código**, porque 30 corridas más de la PC (el cuello de botella) para una
  versión gris no suman nada.

## Para revisar al final

- Confirmar en la documentación oficial de Steamworks el formato de íconos y de stats antes de cargarlos.
- `EXP_PERFECT_DAY` con 1 jugador: el objetivo del bot solitario es ≥ 70 % entregado; si en la práctica nadie
  llega al 100 %, bajar a "todos menos uno" (lo mide `pulidor-jugabilidad`).
- `EXP_COLD_VOLCANO` supone que el generador de pedidos (D-0807) puede pedir fríos en el Volcán; si no, pasa a
  "pedido caliente intacto en la Nieve".
- `EXP_AIRDROP` con 1 jugador necesita que el piloto pueda soltar sin copiloto (D-1421).
