# Eventos del día (D-0123)

> Última actualización: 2026-10-22
> Qué cambia de un día a otro en el modo Empresa para que el día 12 no sea igual al día 6. Fuentes:
> [vision.md](vision.md), [corte-vertical.md](corte-vertical.md), [critica-alcance.md](critica-alcance.md),
> [roles-tripulacion.md](roles-tripulacion.md), [economia.md](economia.md), [hitos.md](hitos.md),
> [distritos.md](distritos.md), [narrativa-empresa.md](narrativa-empresa.md),
> [referencias-logistica.md](referencias-logistica.md), [red-autoridad.md](red-autoridad.md),
> [supuestos.md](../detalle/supuestos.md), [decisiones delegadas](../../decisiones/2026-10-04-expansion-decisiones-delegadas.md).
> Código que ya existe y no se duplica: [route_event_manager.gd](../../../do-not-drop/scripts/core/route_event_manager.gd),
> [low_visibility_event.gd](../../../do-not-drop/scripts/gameplay/route/low_visibility_event.gd),
> [company_seed.gd](../../../do-not-drop/scripts/core/company/company_seed.gd),
> [order_generator.gd](../../../do-not-drop/scripts/gameplay/business/order_generator.gd),
> [supplier_schedule.gd](../../../do-not-drop/scripts/gameplay/business/supplier_schedule.gd),
> [bankruptcy.gd](../../../do-not-drop/scripts/gameplay/business/bankruptcy.gd).
> Los números viven en `company_tuning.gd` y en los `.tres` de `data/day_events/`, no acá.

## 1. Propósito

**El problema.** El galpón lo arma el jugador y lo va a optimizar. Para el día 10 el layout ya está resuelto y el
día se repite: un camión a las 08:30, de 8 a 16 pedidos con la misma curva y el cierre. En *Overcooked* el
antagonista es la cocina; acá el plano lo dibuja el jugador, así que **el antagonista lo ponen los eventos del
día** ([referencias-logistica.md](referencias-logistica.md), fila "Nivel armado alrededor de un elemento"). Un
evento del día es una regla que cambia **un día entero** (o una franja anunciada) y obliga a decidir algo
distinto con lo que ya se sabe hacer: comprar más, armar en otra caja, mandar a toda la tripulación a una
salida o controlar antes de encintar.

Además le da a la Jefa algo que decir por radio cada día, sin personajes nuevos ([narrativa-empresa.md](narrativa-empresa.md) §1).

**Qué NO son:**

- **No son peligros ni eventos de zona.** P14 de [critica-alcance.md](critica-alcance.md) (D-0321, D-0322, D-0334,
  D-0335, D-1522 a D-1537, etc.) sigue pospuesto. Ningún evento de esta lista depende de una zona, suma un
  peligro en la ruta o cierra una zona (R4 recortó la tormenta D-1338 y el paso cerrado D-1629). La única tarea
  de "evento del día por zona" que queda en el backlog es la erupción programada (D-1716, F4). Usa el mismo
  formato de datos, pero no es uno de estos 15 y conserva su tarea.
- **No quitan plata sin aviso ni decisión.** Es el criterio con el que R4 recortó el robo de stock (D-0632), la
  huelga de empleados (D-1036) y los impuestos (D-0529). Todo evento negativo se anuncia antes y tiene una
  respuesta.
- **No son contratos de varios días** (D-0424 pospuesto) **ni precios variables** (D-0523 pospuesto). Todo
  empieza y termina en el día; la víspera solo avisa.
- **No reemplazan los eventos de ruta.** Ver §1.1.

### 1.1 Cómo conviven con `RouteEventManager`

| | Eventos de ruta (lo que existe) | Eventos del día (esto) |
|---|---|---|
| Dónde | Dentro del vehículo, entre paradas | En el día de la empresa: galpón, proveedor, pedidos, flota |
| Duración | 60-90 s reales | Horas de juego o el día entero |
| Quién los maneja | `RouteEventManager` (autoload), `LowVisibilityEvent`, `VehicleFaults` | Una clase nueva del host en el mundo de la empresa (§5), sin autoload |
| Premio | Mérito y `team_money` de `CrewProgression` | Plata y reputación de `CompanyState` (S8) |
| Aviso | Cartel grande en el centro (`route_event_started`) | Pizarra, radio, celular y resumen; **nunca** el cartel del centro |

Reglas:

1. **Ids distintos.** El `inspection` de ruta (`secure_cargo`: cargas sueltas en la camioneta) ya existe. La
   inspección del día se llama `shed_inspection`. Ningún id de este documento repite uno de `RouteEventManager.EVENTS`.
2. **Ninguno dispara al otro.** Un evento del día no arranca un evento de ruta ni cambia su probabilidad, y al revés.
3. **Hoy `RouteEventManager` no está conectado al modo Empresa** (nada en `scripts/core/company/` lo nombra). Si
   D-0520 / D-0427 lo conectan a las salidas, su premio y su multa tienen que pasar por `CompanyNet` hacia
   `CompanyState` (S8) y contar en el techo del día (§2.4). Su sorteo usa `pick_random()` y `randi_range()`
   globales: en la empresa tiene que salir de una semilla (regla de D-0246).
4. `LowVisibilityEvent` y la fauna siguen en la capa de ruta. La única relación con un evento del día es
   cosmética: la ola de calor fuerza el perfil `soleado` donde la zona lo permite.

## 2. Reglas generales

### 2.1 Cuántos por día

| Días de campaña | Eventos | Qué puede salir |
|---|---|---|
| 1-3 | **0** | Nada. Es la semana guiada: hitos 1-5 ([hitos.md](hitos.md)) y pedidos chicos (`ORDER_EARLY_DAYS` = 3) |
| 4-7 | 0 o 1 (50 %) | Solo positivos y mixtos |
| 8-14 | 0 o 1 (75 %); nunca dos días seguidos sin evento | Todos los que su día mínimo y sus requisitos permitan |
| 15 en adelante | 1 seguro; un segundo con 35 % | El segundo es positivo o mixto, de **otro sistema**, y no se anuncia la víspera |

- **Con 1 jugador, nunca más de 1 por día** (carga mental del solitario). El segundo evento pide 2 o más jugadores.
- El mismo evento **no sale dos días seguidos**, y cada uno tiene un enfriamiento (`cooldown_days`, 3 por defecto)
  en su `.tres`.
- **Nunca dos días negativos seguidos.** Después de un día con un evento negativo viene uno sin evento, o con uno
  positivo o mixto.
- **Empresa en rojo** (cerró el día anterior con saldo negativo, D-0510): ese día solo pueden salir eventos
  positivos. Ayuda a salir del pozo sin crear un pozo nuevo.

### 2.2 Cuándo se anuncian

| Momento (`announce`) | Dónde | Para qué |
|---|---|---|
| `eve`: víspera | Línea "Mañana:" en el resumen del cierre (D-1905) y radio de la Jefa en la apertura de ese día | Eventos que se preparan **comprando** (la compra al proveedor es del día anterior, D-0602) |
| `opening`: apertura | Radio de la Jefa o pizarra del Jefe en `OPENING` | Eventos que cambian el día desde las 08:00 |
| `scheduled`: a una hora | Se anuncia la hora en la apertura, se recuerda 60 min de juego antes y se avisa al empezar | Inspección, pedido gigante |
| `arrival`: al llegar | Burbuja del Jefe cuando estaciona el camión | Solo para eventos **positivos** (el palet de más) |

Regla dura: **ningún evento negativo o mixto aparece sin aviso.** Como mínimo se anuncia en la apertura. Los que
se preparan comprando se anuncian la víspera.

### 2.3 Sorteo determinista en el host

- **Corriente nueva** `CompanySeed.EVENTS = &"events"` en `STREAMS`. La semilla del día D es
  `CompanySeed.for_day(company_seed, D, "events")`. Al ser una corriente aparte, no corre los sorteos de
  `ORDERS` ni de `SUPPLIERS` (D-0246, [red-autoridad.md](red-autoridad.md) §12).
- **Cuándo.** El host sortea el día D **al cerrar el D−1**, cuando arma el resumen, para poder mostrar la línea
  "Mañana:". El plan se guarda con el cierre. Si al abrir no hay plan (día 1 o un guardado viejo), lo sortea en
  `OPENING`, sin los eventos de víspera.
- **Orden del sorteo** (un único `RandomNumberGenerator`):
  1. Candidatos: `min_day` ≤ D, requisitos cumplidos (§3), `min_players` ≤ tripulación, fuera de enfriamiento y
     distinto del evento de ayer.
  2. Filtros de §2.1: días 4-7, negativo seguido, empresa en rojo.
  3. Cuántos, según la tabla de §2.1. Después, el sorteo con pesos (`weight` del `.tres`), sin reposición.
  4. Parámetros (hora, tamaño de caja, producto) con el mismo generador.
- **La tripulación cuenta en la apertura.** El plan guarda el **id**; los parámetros que dependen de cuántos
  juegan (§2.5) se recalculan en `OPENING` con la tripulación de ese momento, igual que el tope de pedidos
  ([roles-tripulacion.md](roles-tripulacion.md) §4).
- **Ningún cliente sortea.** Los clientes reciben los hechos (§5). Volver a cargar no cambia nada: el plan del
  día está guardado y la semilla es fija, así que no se puede recargar para que salga otro.

### 2.4 Techo de castigo y de premio por día

| Qué | Tope por día (con dos eventos, sumados) | Constante |
|---|---|---|
| Multas directas de eventos | **150** | `DAY_EVENT_FINE_CAP` |
| Premios directos (incluye el stock regalado a precio de compra) | **300** | `DAY_EVENT_BONUS_CAP` |
| Reputación directa | −5 / +5 | `DAY_EVENT_REPUTATION_CAP` |

- **Ninguna multa de evento deja la caja en negativo por sí sola.** Se cobra `min(multa, plata)`, como ya hace
  `RouteEventManager._resolve`, así que un evento no empuja a la quiebra (D-0510).
- **De dónde salen los números.** 150 es alrededor del 40 % de la ganancia diaria de un jugador solo (+380/día,
  [economia.md](economia.md) §5). 300 respeta la regla de [hitos.md](hitos.md): un premio no reemplaza jugar.
- **Lo indirecto no entra en el techo.** Los pedidos vencidos o las roturas por haber decidido mal se cobran con
  las reglas de siempre (D-0506, D-0807): eso es el juego.
- **Validación:** `sim_economy` (D-0540) con eventos activados. La curva del §5 de economia.md no se corre más
  de ±10 % al día 20, y con juego correcto nunca baja de la reserva de 100.

### 2.5 Escalado de 1 a 8 jugadores

- **La cantidad de eventos no escala** con la tripulación (salvo el segundo evento, que pide 2+). Lo que escala
  son los **parámetros**, por tramos de 1 / 2 / 3-4 / 5-8 jugadores, en el `.tres` de cada evento (por ejemplo,
  cajas que revisa la inspección: 2 / 3 / 3 / 4).
- **Modo solo:** máximo 1 evento por día, sin `loaner_van` (pide 3+). Todo lo que pasa en el galpón corre en
  **tiempo de galpón** (`DayCycle.shed_minute()`), así que el solitario que sale a repartir no se pierde el
  camión atrasado ni la inspección: el galpón congelado también los congela (S4).
- **De 5 a 8:** el día de ofertas y el pedido gigante son los que más trabajo agregan. Ayudan a la regla de los
  2 min ([roles-tripulacion.md](roles-tripulacion.md) §1).

### 2.6 Dónde se ve

- **Pizarra del tablero de pedidos** (D-0804): franja "Hoy" con una línea por evento.
- **Radio de la Jefa / burbuja del Jefe del depósito:** texto con clave y murmullo de `SynthAudio` (fila 8 de
  las decisiones delegadas).
- **HUD del día** (D-1903): un ícono por evento con su línea. **Celular** (D-0814): la misma notificación.
- **Resumen del cierre** (D-1905, D-0508): una línea por evento con su resultado y la plata, con motivo
  `day_event:<id>`, y la línea "Mañana:" para los de víspera.
- **Nunca** el cartel grande del centro de la pantalla. El abogado del diablo ya marcó que el cartel de evento
  de ruta tapa el juego (`docs/critica-diseno-abogado-del-diablo.md`), y un evento que dura horas no puede
  vivir ahí.
- **Legibilidad:** cada evento se explica en una frase en el anuncio, y su resultado dice **qué** falló y
  **cuánto** costó ("Inspección: d6_o04 sin el sello Frágil, −40").

### 2.7 Datos y números

- **`DayEventDefinition`** (`data/day_events/<id>.tres`, nombre de archivo = id): `id`, `name_key`,
  `announce_keys`, `kind` (`positive` / `negative` / `mixed`), `systems`, `min_day`, `requires` (capacidades:
  `fridge`, `vehicle_faults`, `fleet_loan`, `hiring_agency`), `min_players`, `weight`, `cooldown_days`,
  `announce` (`eve` / `opening` / `scheduled` / `arrival`) y `params` por tramo de tripulación.
- **En `CompanyTuning`:** `DAY_EVENTS_FIRST_DAY = 4`, `DAY_EVENT_NEGATIVE_FROM_DAY = 8`,
  `DAY_EVENT_CHANCE_EARLY = 0.5`, `DAY_EVENT_CHANCE_MID = 0.75`, `DAY_EVENT_SECOND_FROM_DAY = 15`,
  `DAY_EVENT_SECOND_CHANCE = 0.35`, `DAY_EVENT_MAX_DRY_DAYS = 1`, `DAY_EVENT_DEFAULT_COOLDOWN = 3`,
  `DAY_EVENT_REMINDER_MIN = 60`, `DAY_EVENT_FINE_CAP = 150`, `DAY_EVENT_BONUS_CAP = 300`,
  `DAY_EVENT_REPUTATION_CAP = 5.0`.
- **Textos:** voces en `strings_world.csv` (`WORLD_DAY_EVENT_<ID>_<n>`), líneas de pizarra y resumen en
  `strings_ui.csv` (`UI_DAY_EVENT_<ID>`). Los números van por `%s/%d`, en una frase aparte del chiste
  ([narrativa-empresa.md](narrativa-empresa.md) §3-§4).
- **El sorteo** (pesos, enfriamientos, sin repetir, topes) no sabe nada del juego. Lo escribe directamente como
  módulo la tarea que lo construye (`modules/day_events/`, con su `module.cfg` y su test), y lo conecta un
  adaptador en `scripts/gameplay/business/` ([critica-alcance.md](critica-alcance.md) §3.3: el módulo lo
  escribe la tarea que lo usa, no una extracción aparte).

## 3. Los 15 eventos

**Núcleo**: pocos, baratos y sobre sistemas que ya existen o están en el corte. **Ampliación**: suma variedad o
espera una dependencia de F2. Tipo: **positivo**, **negativo** o **mixto**.

### 3.1 Núcleo (F1)

#### 1. `supplier_late`: Proveedor tarde · Núcleo · F1 · día 4 · mixto
- **Qué pasa:** el camión del día llega tarde y espera las 3 h de siempre en la dársena.
- **Anuncio** (apertura, el Jefe en la pizarra): "Llamó el proveedor: pinchó una goma." / "Llega a las %s."
- **Toca:** proveedor y reloj del galpón. `SupplierSchedule.arrival_minute()` suma el atraso del día; el
  camión (D-0601) ya maneja solo.
- **Números:** atraso de 120 a 180 min en pasos de 30 (llega entre las 10:30 y las 11:30); espera 180 min. Al
  descargar, el proveedor devuelve el 10 % de lo que costó la carga (línea "Descuento del proveedor").
- **Decisión:** jugar la mañana con el stock que quedó. Se toman los pedidos que ya se pueden armar (D-0811
  deja los otros en espera) y se sale temprano con pocas cajas, o se espera al camión.
- **Resultado:** sin multa. No sale si ayer se cerró con menos de 4 unidades en los estantes: sería una mañana
  muerta sin decisión.
- **Requisitos:** que ese día haya camión.

#### 2. `transport_strike`: Huelga de transporte · Núcleo · F1 · día 8 · negativo
- **Qué pasa:** el día S no entra ningún camión. La víspera (S−1) el proveedor adelanta la entrega: lo que se
  pida antes de las 14:00 llega ese mismo día a las 16:00, y lo que se pida después llega el S+1.
- **Anuncio** (apertura del S−1, la Jefa por radio): "Mañana paran los camioneros. Yo también pararía." / "Lo
  que pidan antes de las %s llega hoy a las %s." El día S, la pizarra: "Hoy no viene nadie. Lo que hay, hay."
- **Toca:** proveedor (`SupplierSchedule` con una segunda llegada el S−1) y pedidos (la paga del día S).
- **Números:** corte de compra a las 14:00, llegada a las 16:00 y 180 min de espera, todo en tiempo de galpón.
  El día S los pedidos pagan +20 % ("hoy no reparte nadie más") y la cantidad no cambia.
- **Decisión:** comprar a media tarde, con la plata que haya a esa hora, para cubrir dos días y hacerle lugar
  en los estantes; o comprar poco y cerrar el día S con pedidos en espera.
- **Resultado:** sin multa directa. Duele lo que no se pudo armar, y el +20 % premia al que se preparó.
- **Requisitos:** ninguno. La huelga de empleados (D-1036) sigue recortada (R4). Esta es la del transporte,
  que se anuncia y se prepara.

#### 3. `supplier_gift`: Palet de más · Núcleo · F1 · día 4 · positivo
- **Qué pasa:** el camión trae un palet extra gratis, y ese día ese producto se pide más.
- **Anuncio** (al estacionar, burbuja del Jefe): "Vino un palet de más. El chofer dice que no lo quiere ver
  nunca más." / "%d unidades de %s, sin cargo."
- **Toca:** proveedor y stock (un palet más en `supply_arrived`, con costo 0) y pedidos (peso ×2 para ese
  producto en el plan del día).
- **Números:** 4 / 6 / 6 / 8 unidades (1 / 2 / 3-4 / 5-8 jugadores). El producto es el de menos stock entre los
  del catálogo abierto (si empatan, va por orden de id). Vale de 200 a 400 a precio de compra y cuenta en el
  techo de premio.
- **Decisión:** dónde guardarlo (un hueco más en los estantes o el piso, D-2006) y si se usa hoy.
- **Resultado:** stock gratis, sin nada que pueda salir mal. Enfriamiento de 5 días.
- **Requisitos:** que ese día haya camión.

#### 4. `box_shortage`: Faltan cajas · Núcleo · F1 · día 8 · negativo
- **Qué pasa:** un tamaño de caja no se repone en todo el día.
- **Anuncio** (apertura, pizarra del Jefe): "Hoy no hay cajas %s." / "El de las cajas se fue de vacaciones.
  Sin avisar, como las cajas."
- **Toca:** armado e insumos. Ese `box_<tamaño>` no se repone (D-0718), y `box_restock` (D-0715.c) lo rechaza
  con `no_supply`.
- **Números:** sale M (peso 3) o L (peso 1). Cada mesa arranca con 2 cajas de ese tamaño como máximo (3 con 1
  jugador).
- **Decisión:** armar en el tamaño de al lado. En uno más chico no siempre entra: la torta (2×3×2) no entra en
  S. En uno más grande hay que rellenar (1 por celda) o cargar con Equilibrio por el hueco (más del 50 % libre,
  [supuestos.md](../detalle/supuestos.md)). Es "lo que armás es la trampa" en estado puro.
- **Resultado:** sin multa. Cuesta relleno (de +4 a +10 por caja) y suma riesgo de trampa. Las cajas raras
  dan clip.
- **Requisitos:** D-0718 y la reposición por red (D-0715.c).

#### 5. `shed_inspection`: Inspección de la casa central · Núcleo · F1 · día 6 · mixto
- **Qué pasa:** desde una hora anunciada, el inspector revisa las próximas N cajas que se encintan: contenido
  contra el pedido, etiqueta, sellos pedidos y calidad. En gris, es el Jefe del depósito con un portapapeles
  en el despacho, sin modelo nuevo.
- **Anuncio** (apertura, la Jefa): "A las %s viene un inspector de la casa central." / "Revisa %d cajas. Sean
  naturales." Una hora antes y al empezar, el Jefe: "Llegó el inspector. Tiene una lapicera muy seria."
- **Toca:** armado y despacho. No mide nada nuevo: lee lo que el host ya calcula en `box_sealed`
  (`AssemblyQuality`, `box_content_check.gd`, la etiqueta y los sellos).
- **Números:** hora entre las 11:00 y las 15:00 (pasos de 30, tiempo de galpón); N = 2 / 3 / 3 / 4. Una caja
  pasa si tiene el contenido correcto, la etiqueta de su pedido, los sellos pedidos y `Q` ≥ 70. Si pasan
  todas: +100 y +2 de reputación. Cada caja mal: −40 y −1, dentro del techo.
- **Decisión:** bajar el ritmo y controlar (balanza D-0713, control por otro jugador D-0734), o seguir rápido
  y pagar.
- **Resultado:** el resumen dice caja por caja qué falló. Si a las 20:00 no se encintó ninguna, termina sin
  efecto. Una caja sin etiqueta cuenta como mal.
- **Requisitos:** D-0707, D-0708, D-0709. No es el `inspection` de ruta (§1.1).

#### 6. `giant_order`: Pedido gigante · Núcleo · F1 · día 6 · mixto (opcional)
- **Qué pasa:** a media mañana llega la oferta de K pedidos para la **misma casa**, con ventana larga. Se
  acepta o se rechaza en el tablero.
- **Anuncio** (a la hora sorteada, la Jefa por radio): "Un cliente quiere %d cajas para la misma casa." /
  "Dice que es un cumpleaños chico." En el tablero: "Aceptar / Rechazar · %d %% extra si llegan todas sanas."
- **Toca:** pedidos (K pedidos más en el plan del día, con ids `d<día>_g<n>`, que solo se publican con
  `order_added` si se aceptan) y cierre (el bono).
- **Números:** hora entre las 09:30 y las 11:00. K = 3 / 3 / 4 / 5, de 1 a 2 productos por caja, elegidos
  entre lo que hay en stock a la apertura. Ventana de 360 min y 30 min de juego para contestar: sin respuesta
  queda rechazado, sin costo. **Suman** a los pedidos del día, por encima del tope de 16, porque son opcionales.
  Si **todas** llegan cobradas y sin roturas: +25 % de la paga del grupo (unos 160-260) y +3 de reputación. Si
  falla alguna, no hay bono y se pierden 3 de reputación una sola vez.
- **Decisión:** aceptar y mandar a toda la tripulación en una salida con K cajas (cada pasajero cuida una, y
  quizás el galpón se congela), o rechazar.
- **Resultado:** es el clip del juego: la camioneta llega a una puerta con cinco cajas y cinco personas
  haciendo malabares. Enfriamiento de 4 días.
- **Requisitos:** D-0813.1 (el plan del día en la apertura) y una petición nueva, `day_event_answer` (§5).

### 3.2 Ampliación F1 (todos tocan el plan de pedidos del día)

#### 7. `sale_day`: Día de ofertas · Ampliación · F1 · día 7 · mixto
- **Qué pasa:** entran más pedidos, más concentrados a la mañana.
- **Anuncio** (víspera y apertura, la Jefa): "Mañana hay ofertas en todo el país. Nosotros no pusimos
  ninguna, pero igual." / "Entran %d pedidos más."
- **Toca:** pedidos. La cantidad del generador va ×1,25 con tope 20, y el peso de las 10-12 h de
  `ORDER_HOUR_WEIGHTS` va ×1,5.
- **Números:** 8 → 10 (1 jugador), 14 → 18 (4 jugadores), 16 → 20 (5-8 jugadores).
- **Decisión:** comprar más la víspera y organizar a la tripulación para el pico.
- **Resultado:** más plata posible y más vencimientos. No sale después de cerrar en rojo.

#### 8. `boss_favor`: Favor de la Jefa · Ampliación · F1 · día 4 · positivo
- **Qué pasa:** uno de los pedidos del día viene "de parte de la Jefa" y paga el doble si llega sano y a tiempo.
- **Anuncio** (apertura, la Jefa): "El pedido %s es de una prima mía." / "Si llega bien, paga doble. Si no,
  mejor no me cuenten."
- **Toca:** pedidos. El evento guarda el id del pedido y el bono es una línea aparte al entregar; el pedido no
  cambia de forma. La hoja del pedido lo marca (D-0714).
- **Números:** se elige entre los pedidos planeados de 10:00 a 14:00 con productos en stock. El bono es la paga
  base del pedido, con tope 200, más 2 de reputación. Si falla, no hay castigo.
- **Decisión:** armarlo con más cuidado y elegir quién lo cuida en la salida.

#### 9. `urgent_morning`: Mañana de urgencias · Ampliación · F1 · día 6 · mixto
- **Qué pasa:** a las 08:00 entran pedidos urgentes que se pueden armar con el stock del día anterior.
- **Anuncio** (apertura, el Jefe): "Hay %d urgentes desde temprano." / "Nadie desayunó todavía."
- **Toca:** pedidos (requisito `urgent`, D-0806; reemplazan a los primeros del plan, así que la cuenta del día
  no cambia) y reloj.
- **Números:** 2 / 3 / 3 / 4 pedidos de un solo producto en stock, con la ventana y el recargo de `urgent`
  (`OrderPricing`).
- **Decisión:** salir a las 08:00 o recibir primero el camión de las 08:30. Con 1 o 2 jugadores no da para
  todo, y esa es la decisión.
- **Resultado:** si no hay stock para armarlos, el evento no sale: nunca pide algo imposible.

#### 10. `antiques_fair`: Feria de antigüedades · Ampliación · F1 · día 5 · mixto
- **Qué pasa:** los pedidos del día se inclinan a lo frágil y a lo que se balancea, y pagan más.
- **Anuncio** (víspera y apertura, la Jefa): "Mañana hay feria de antigüedades." / "Todo lo que se pide es
  viejo y se rompe."
- **Toca:** pedidos (peso ×3 para los productos con trampa `fragile` o `balance`; paga +15 %).
- **Decisión:** comprar frágiles la víspera, usar relleno y caja justa, y manejar como si fuera porcelana.
- **Resultado:** un día de cuidado puro con Frágil, la trampa más fácil de entender.

#### 11. `farm_fair`: Feria rural · Ampliación · F1 · día 8 · mixto
- **Qué pasa:** los pedidos se inclinan a los animales (gallina, cachorro, mapache) y pagan más.
- **Anuncio** (víspera y apertura, la Jefa): "Mañana hay feria rural. Los clientes piden bichos." / "Los
  bichos no opinan, pero se quejan."
- **Toca:** pedidos (peso ×3 para `noisy` y `hostile`; paga +15 %). Es el mismo código que el 10, con otra
  lista de trampas en el `.tres`.
- **Decisión:** la misma que en el 10, pero Ruidoso y Hostil le dan trabajo al que cuida la caja en el viaje.
- **Resultado:** una camioneta llena de animales indignados: clip.
- **Requisitos:** productos con esas trampas en el catálogo abierto (en F1, los tres de `data/contents/`).

### 3.3 Ampliación F2 (esperan un sistema de F2)

#### 12. `heat_wave`: Ola de calor · Ampliación · F2 · día 10 · mixto
- **Qué pasa:** lo frío dura la mitad fuera de la heladera y en la ruta, y los pedidos fríos son más y pagan más.
- **Anuncio** (víspera y apertura, la Jefa): "Mañana viene una ola de calor." / "Lo frío, a la heladera;
  ustedes, a la sombra."
- **Toca:** stock (vencimiento de los fríos, D-0616), armado (conservadora, D-0721), pedidos (peso ×2 para
  productos `frío`; paga +25 %) y clima (perfil `soleado` donde la zona lo permite; solo cosmético).
- **Números:** el tiempo hasta vencer fuera de la heladera va ×0,5 (de 2 h a 1 h), y la duración de la
  conservadora va ×0,75.
- **Decisión:** armar los fríos al final, con conservadora, salir directo y priorizar la ruta corta.
- **Resultado:** sin multa. Lo que vence se paga como roto, con las reglas de siempre.
- **Requisitos:** D-0616, D-0617 y D-0721, y que la empresa tenga heladera (si no, no sale). No es un peligro
  de zona y no toca Nieve ni Volcán: la trampa de temperatura es D-0738.

#### 13. `loose_rear_door`: Puerta floja · Ampliación · F2 · día 8 · negativo
- **Qué pasa:** una camioneta de la empresa amanece con la puerta trasera que no traba. Es la falla
  `rear_door` de `VehicleFaults` que ya existe en Entrega.
- **Anuncio** (apertura, el Jefe): "La puerta de atrás de la camioneta no cierra." / "Hay una correa en el
  estante, y fe."
- **Toca:** flota (la falla y su lugar de arreglo `FaultRepairSpot`, tal como están hoy).
- **Números:** arreglo con correa (gratis; se suelta con un golpe fuerte, como hoy) o repuesto (40, arregla el
  día entero; cuenta como mantenimiento, D-0527).
- **Decisión:** arreglarla antes de salir (alguien del galpón), salir con la correa y un pasajero atento, o
  pagar el repuesto.
- **Resultado:** si se ignora, la puerta se abre en cada bache y las cajas se pueden caer (el clip del juego
  base). Al solitario la correa le lleva 10 s.
- **Requisitos:** conectar `VehicleFaults` a los vehículos de la empresa (hoy vive en la corrida de Entrega) y
  D-0527.

#### 14. `loaner_van`: Camioneta prestada · Ampliación · F2 · día 10 · positivo
- **Qué pasa:** la Jefa presta una segunda camioneta por el día.
- **Anuncio** (apertura, la Jefa): "Hoy les presto mi otra camioneta." / "Devuélvanla con las cuatro ruedas."
- **Toca:** flota. Hay un `van_classic` más en el garaje hasta el cierre; no entra en `CompanyState.fleet`.
- **Números:** solo con 3 o más jugadores y si la empresa tiene una sola camioneta. Sigue el tope de 2
  vehículos afuera (`VEHICLES_FAR_MAX`).
- **Decisión:** dos salidas a la vez: quién arma y quién sale.
- **Resultado:** más entregas posibles. Si vuelve golpeada no pasa nada: es de la Jefa y D-0527 no la cobra.
- **Requisitos:** D-1201, D-1205, D-0316.

#### 15. `trainee`: Pasante por un día · Ampliación · F2 · día 7 y después del hito 8 · positivo
- **Qué pasa:** la agencia manda un empleado novato gratis por el día.
- **Anuncio** (apertura, el Jefe): "Mandó la agencia un pasante a prueba." / "Hoy no cobra. Tampoco sabe nada."
- **Toca:** empleados. Hay uno más, nivel novato (rinde 0,5); se va al cierre (D-1015) y en el cierre se puede
  contratar al precio normal.
- **Números:** sueldo 0 ese día. Respeta el límite por etapa (D-1017): si el cupo está lleno, no sale.
- **Decisión:** a qué estación ponerlo. Es la prueba gratis de "contratar".
- **Resultado:** le sirve sobre todo al solitario (la tabla de roles baja una fila, roles-tripulacion §4).
- **Requisitos:** hito 8 `first_employee` (agencia, D-0413), D-1001, D-1003, D-1004, D-1015.

## 4. Tabla resumen

| # | id | Nombre | Bloque | Fase | Día mín. | Tipo | Anuncio | Sistemas | Costo |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `supplier_late` | Proveedor tarde | Núcleo | F1 | 4 | mixto | apertura | proveedor, reloj | bajo (0,5 d) |
| 2 | `transport_strike` | Huelga de transporte | Núcleo | F1 | 8 | negativo | víspera | proveedor, pedidos | medio (1,5 d) |
| 3 | `supplier_gift` | Palet de más | Núcleo | F1 | 4 | positivo | al llegar | proveedor, stock, pedidos | bajo (1 d) |
| 4 | `box_shortage` | Faltan cajas | Núcleo | F1 | 8 | negativo | apertura | armado (insumos) | bajo (1 d) |
| 5 | `shed_inspection` | Inspección | Núcleo | F1 | 6 | mixto | a una hora | armado, despacho | medio (1,5 d) |
| 6 | `giant_order` | Pedido gigante | Núcleo | F1 | 6 | mixto | a una hora | pedidos, cierre | medio (2,5 d) |
| 7 | `sale_day` | Día de ofertas | Ampliación | F1 | 7 | mixto | víspera | pedidos | bajo (0,5 d) |
| 8 | `boss_favor` | Favor de la Jefa | Ampliación | F1 | 4 | positivo | apertura | pedidos | bajo (0,5 d) |
| 9 | `urgent_morning` | Mañana de urgencias | Ampliación | F1 | 6 | mixto | apertura | pedidos, reloj | bajo (1 d) |
| 10 | `antiques_fair` | Feria de antigüedades | Ampliación | F1 | 5 | mixto | víspera | pedidos | bajo (0,5 d) |
| 11 | `farm_fair` | Feria rural | Ampliación | F1 | 8 | mixto | víspera | pedidos | bajo (comparte con el 10) |
| 12 | `heat_wave` | Ola de calor | Ampliación | F2 | 10 | mixto | víspera | stock, armado, pedidos | medio (1 d, después de sus dependencias) |
| 13 | `loose_rear_door` | Puerta floja | Ampliación | F2 | 8 | negativo | apertura | flota | medio (2 d) |
| 14 | `loaner_van` | Camioneta prestada | Ampliación | F2 | 10 | positivo | apertura | flota | medio (2 d) |
| 15 | `trainee` | Pasante por un día | Ampliación | F2 | 7 + hito 8 | positivo | apertura | empleados | bajo (1 d) |

Reparto: 4 positivos, 3 negativos y 8 mixtos. El marco (definición, sorteo, red, guardado, resumen) son 3 a 4
días-persona. Con los 15 eventos, unos **20 días-persona** (unas 4 semanas-persona de
[critica-alcance.md](critica-alcance.md) §1). La primera tanda útil son el marco y 3 eventos: unos 6 días.

## 5. Red y guardado

Sigue [red-autoridad.md](red-autoridad.md): el host decide, los hechos viajan numerados por `CompanyNet`
(`_apply_event` con `seq`) y ningún cliente sortea ni escribe estado.

| Qué | Quién | Cómo viaja |
|---|---|---|
| Plan del día D | Host, al cerrar el D−1 (o en `OPENING` si no hay plan) | No es un evento: vive en `CompanyState.day_events` y viaja en la parte `company` del snapshot y en el guardado |
| Se anuncia | Host: en el cierre del D−1 (víspera), en `OPENING`, a una hora o al llegar el camión | `day_event_announced` `{day, id, when, start_min, params}` |
| Empieza | Host, en su minuto (tiempo de galpón para proveedor e inspección) | `day_event_started` `{day, id, minute, params}` |
| Avanza | Host: caja revisada, caja del grupo entregada | `day_event_progress` `{day, id, done, total, failed}` |
| Termina | Host | `day_event_ended` `{day, id, minute, result, money, reputation, detail}`. `result` ∈ `ok` / `failed` / `expired` / `declined`. **Plata y reputación absolutas** (saldo del host después, como D-0910). `detail` lleva hasta 8 entradas `{ref, reason}` con motivos de una lista blanca (para el resumen legible) |

| # | Acción | Inicia | Petición: `kind` y `data` | El host valida | Evento: `kind` y `data` | Cambia en cada peer |
|---|---|---|---|---|---|---|
| 25 | Contestar el pedido gigante | Jugador, en el tablero | `day_event_answer` `{station, event, accept: bool, rid}` | Alcance al tablero; el evento está esperando respuesta y nadie contestó antes (gana la primera). Motivos de `_rejected`: `no_event`, `answered`, `out_of_reach`, `bad_data` | `day_event_answered` `{day, id, accept}`; si se acepta, después los `order_added` del grupo | El evento sale de la espera; los pedidos entran al libro como cualquier otro |

- **Los efectos viajan con los eventos de cada sistema**, no se duplican. El camión atrasado es un
  `supply_arrived` en su minuto nuevo. El palet regalado es un palet más en ese `supply_arrived`. La paga +15 /
  +20 / +25 % va dentro del pedido de `order_added` (campo `pay`, sin cambiar la forma del pedido). El pasante
  y la camioneta prestada usan los eventos de empleados (D-1012) y de flota. Ningún evento del día cambia la
  forma de `Order.normalize()`, y por eso `order_ok()` no cambia.
- **Clase propia:** `CompanyDayEventsNet` en `scripts/core/company/`, como `CompanyOrdersNet`. `company_net.gd`
  solo suma los `kind` a `HOST_EVENT_KINDS` / `REQUEST_KINDS` y una rama de `_apply_state()` sin `_:`. Está en
  996 de 1000 líneas de gdlint, así que primero hay que sacar algo (§10 de red-autoridad.md).
- **Snapshot:** parte `day_events` `{day, announced, active: [{id, start_min, params, progress}], ended: [{id,
  result}]}`. El cliente la valida antes de tocar nada (como mucho 4 entradas por lista, ids de
  `data/day_events/`, enteros en rango) y la aplica sin señales de hechos. Lo que muestra eventos se redibuja
  en `company_state_restored`.
- **Señales:** `EventBus.company_day_event_started` / `_ended`, emitidas desde `event_applied` y nunca dentro
  de la aplicación del evento. Son solo para presentación. `event_bus.gd` es zona compartida: lleva aviso.
- **Guardado (D-0206):** `CompanyState.day_events = {plan: {day, events: [{id, start_min, params}]}, history:
  [{day, ids}]}` con los últimos 7 días (para no repetir y para los enfriamientos). El campo es aditivo: un
  guardado viejo lo trae vacío y el día se planea en la apertura. Un día interrumpido (D-2005) arranca desde
  la apertura con el **mismo** plan; el progreso de un evento a mitad del día no se guarda.
- **Telemetría (D-0239):** `day_event_started` y `day_event_ended`, con id y resultado, en el registro del día.
- **Protocolo:** la tarea del marco sube `PROTOCOL_VERSION` una vez, como dice `docs/convenciones-godot.md` §6.

## 6. Qué tareas lo construyen

No hay ninguna tarea abierta que construya los eventos del día. Lo nuevo es **tarea nueva a crear en el grupo
05** (economía y crecimiento del negocio). Va como ampliación de F1: **no entra al corte vertical** (su lista
está cerrada, [corte-vertical.md](corte-vertical.md) §2) y se arranca con el corte cerrado.

| Qué | Tarea | Depende de |
|---|---|---|
| Marco: `DayEventDefinition`, sorteo (módulo), `CompanyDayEventsNet`, snapshot, guardado, líneas del resumen, telemetría, `test_company_day_events` | Tarea nueva a crear en el grupo 05 | D-0246, D-0203, D-0206, D-0813.1, D-0508 |
| Núcleo de proveedor: 1, 2, 3 | Tarea nueva a crear en el grupo 05 (con aviso si toca `supplier_*`) | D-0601, D-0602, D-0603 (◐), D-0618 (◐) |
| Núcleo de armado: 4, 5 | Tarea nueva a crear en el grupo 05 | D-0718, D-0715.c, D-0707, D-0709, D-0713 |
| Núcleo de pedidos: 6 (petición nueva, oferta en el tablero) | Tarea nueva a crear en el grupo 05; pasa por `auditor-red` | D-0813.1, D-0804 |
| Ampliación F1: 7 a 11 (modificadores del plan de pedidos) | Tarea nueva a crear en el grupo 05; D-0848 (`test_order_golden`) suma un día con modificadores | D-0813.1, D-0806 |
| Ampliación F2: 12, 13, 14, 15 | Tarea nueva a crear en el grupo 05, una por evento, abierta cuando exista su dependencia | 12: D-0616, D-0617, D-0721 · 13: D-0527 + `VehicleFaults` en la empresa · 14: D-1201, D-1205, D-0316 · 15: D-0413, D-1003, D-1015 |
| Mostrarlos | Tareas existentes: D-1903 (ícono en el HUD), D-1905 (líneas del cierre y "Mañana:"), D-1935 (feed), D-0804 (franja "Hoy") | Dominio de UI de Slatex: con aviso |
| Textos | Tareas existentes: D-0822 (mensajes con humor), D-1920 (test de `tr()`), `localizador` | — |
| Balance | Tareas existentes: D-0540 (`sim_economy` con eventos), D-0538 / D-0539, D-2024 (bot solo de 20 días con eventos) | — |
| Erupción del Volcán | D-1716 (existente, F4) usa `DayEventDefinition` con zona. No es uno de los 15 | El marco |

**Primera tanda (la mínima):** el marco más `supplier_late`, `supplier_gift` y `shed_inspection` (uno mixto,
uno positivo y uno con hora). Con eso se prueba el anuncio, el tiempo de galpón, el resultado legible y el
techo. Se mide con `bot_company_day` forzando el evento desde el test (un parámetro del planificador solo
para tests, que no queda en release, D-2045) y con `sim_economy` a 20 días.

## 7. Riesgos y "Decidir al final"

### Riesgos

1. **Un sistema más encima de otro sistema** (`docs/critica-diseno-abogado-del-diablo.md` §1). Mitigación: 0
   eventos en los días 1-3, como mucho 1 hasta el 15, una frase por evento y nada en el cartel del centro.
   Ningún evento introduce un verbo nuevo; solo cambia números o pone una hora.
2. **`company_net.gd` en el tope de líneas.** El marco tiene que sacar algo antes de sumar (§5). Si no, el
   gdlint de CI lo frena.
3. **Dependencias de F2.** Los eventos 12 a 15 no se pueden probar sin la heladera, `VehicleFaults` en la
   empresa, varias camionetas y empleados. Quedan como tareas que se abren cuando existe su sistema, no antes.
4. **Números sin simular.** `sim_economy` (D-0540) no existe todavía. Los topes de §2.4 acotan el daño mientras
   tanto.
5. **El reloj de los pedidos con el galpón congelado** está descrito distinto en roles-tripulacion.md §1 (el
   de pedidos sigue) y en red-autoridad.md §10 (`poll` con `shed_minute()`). Cada evento usa el reloj del
   sistema que toca. D-0813.1 tiene que fijarlo, y los eventos 6 y 9 lo heredan.
6. **"Huelga" puede leerse como huelga de empleados.** El texto dice "paro de transporte" para que no se lea
   como el D-1036 recortado.
7. **El pedido gigante toca la UI del tablero** (dominio de Slatex) y suma una petición nueva. Es el evento más
   caro del núcleo y el de mayor clip: si hay que recortar, se recorta antes cualquier ampliación que este.

### Decidir al final (con playtesting, no ahora)

- Frecuencias (50 % / 75 % / 1 + 35 %) y si un segundo evento por día satura con 5-8 jugadores.
- Techos de 150 / 300 y el umbral `Q` ≥ 70 de la inspección.
- Bono del pedido gigante (+25 %) y su K por tramo; si 5 cajas con 5-8 jugadores es fiesta o caos ilegible.
- Si las cajas forzadas (`box_shortage`) divierten o cansan.
- Si la línea "Mañana:" del resumen se lee: si nadie la lee, los eventos de víspera también se anuncian en la
  pizarra a media tarde del día anterior.
- Si hace falta una opción "sin eventos" al crear la empresa. Hoy no la hay (D-0127: una sola dificultad).
- La dificultad de la feria rural (Hostil y Ruidoso juntos) antes del día 8.

## Decisiones

- **Decisión: la huelga es de transporte, no de empleados**, porque R4 recortó la de empleados (D-1036) por
  quitar valor sin decisión. Esta se anuncia la víspera, se prepara comprando antes de las 14:00 y premia con
  +20 % al que se preparó.
- **Decisión: el plan del día D se sortea al cerrar el D−1**, con una corriente propia `events` de
  `CompanySeed`, y se guarda. Así hay aviso la víspera, no se puede recargar para sortear de nuevo y no se
  corren los sorteos de pedidos y proveedores.
- **Decisión: 0 eventos en los días 1-3, sin negativos hasta el día 8, como mucho 1 por día hasta el 15 y nunca
  más de 1 con un solo jugador**, para no tapar la semana guiada ni sumar carga al solitario.
- **Decisión: techo diario de 150 en multas, 300 en premios y ±5 de reputación**, y ninguna multa deja la caja
  en rojo por sí sola. Con la empresa en rojo, solo eventos positivos.
- **Decisión: los efectos viajan dentro de los eventos de cada sistema** (`supply_arrived`, `order_added` con
  su `pay`) y el pedido no cambia de forma. Lo único nuevo en red son los 4 eventos `day_event_*`, la petición
  `day_event_answer` y una parte de snapshot.
- **Decisión: ningún evento es de zona.** P14 sigue pospuesto, y D-1716 (erupción) reutiliza el formato sin
  contar entre los 15.
