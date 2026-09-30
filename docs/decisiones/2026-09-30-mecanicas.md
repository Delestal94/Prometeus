# Decisiones 2026-09-30: debate de mecánicas (critico-diseno vs abogado-del-diablo)

`critico-diseno` y `abogado-del-diablo` discutieron tres rondas sobre las mecánicas en `main`; el consenso de las
rondas 1-2 y las posturas finales de la 3 las desempató `arbitro-decisiones`, verificando los hechos en el código.
Cada fila dice si va a tarea **AHORA** (antes del lanzamiento), **DESPUÉS** (post-lanzamiento) o **NO** se hace;
`planificador-tareas` solo arma tareas de las AHORA. Lo que es del usuario está abajo, en "Para el usuario".
Respeta `2026-09-30-preguntas-auditoria.md` (8 jugadores, plata compartida, reclamo determinista, trampas de solo).

| # | Disputa | Decisión | Confianza / revisar si | Quién la ejecuta |
|---|---|---|---|---|
| 1 | Kit: 2 herramientas (cinta + sustituto) o 3 (cinta, reparar, cincha) | **AHORA.** Tres a mano en el ciclo: **cinta, reparar, cincha**. Dos contextuales que se sugieren solas y no están en el ciclo: **trapo** (fuga de Líquido) y **sustituto** (gallina perdida). Se corta la herramienta **relleno** (el relleno de la tienda queda). Borrar `DIRECTIONS` y `work_direction()`. Kit inicial escalado por cajas: cinta = cajas + 1, reparar = ⌈cajas/2⌉, cincha = 1 + (cajas − pasajeros), trapo 1 si hay Líquido, sustituto 1 si hay Ruidosa (números finos con el arnés). El doc de rescate deja de prometer minijuegos: es "mantener N s". | Alta. Revisar si la telemetría (S-805) muestra que la cincha casi no se usa fuera de la puerta y la Inspección: entonces pasa a contextual. | `constructor-jugador` (+ `pulidor-jugabilidad` para cantidades, `escritor-tests`). Aviso: sí (dominio de Slatex, zona compartida) |
| 2 | Eventos de ruta que sobreviven | **AHORA.** Sorteo = **Cliente impaciente, Inspección, Paquete mimético**. Inspección aprueba solo si cada caja está cargada, cerrada y con cinta o cincha (hoy se aprueba sola). Mimético solo sale si la caja real es de dificultad ≥ 3 (Ruidosa, Explosiva, Hostil), así no aparece con Frágil + Equilibrio en la primera partida. **Caja parásita y Etiquetas mezcladas salen del sorteo sin borrar código.** Puerta trabada y Tienda confusa no se borran (ya no salen; `test_run_relay` las usa de fixture). | Media. Revisar si Parásita se vuelve resoluble con un solo pasajero (entonces vuelve, DESPUÉS) o si el arnés/telemetría muestra que el Mimético arruina la caja revelada en > 70 % (entonces sale). | `constructor-progresion` |
| 3 | Cuánto pagan los eventos | **AHORA.** Premio **75** (una caja abollada) en los tres. Multa solo en **Inspección: 75** (es su única consecuencia). Impaciente y Mimético sin multa: su castigo ya está en el mundo (plazo −15 % y la caja revelada). El campo `merit` queda (alimenta el MVP). | Media. Revisar si el premio pesa más que una entrega en dúo en `bench`/telemetría: bajarlo a 50. | `constructor-progresion` (+ `pulidor-jugabilidad`) |
| 4 | Peso Creciente: consecuencia y lugar en la curva | **AHORA.** Queda en la 1.0 (la capacidad de 8 la necesita). Consecuencia: `on_impact` propio que desgasta en proporción a (`mass_multiplier` − 1), en un acumulador aparte de la masa; cinta, cincha y relleno lo bajan por `impact_scale()`. Solo host, sin RPC nuevo. En la curva **cambia de umbral con Explosiva**: Explosiva a 1 entrega/0, Peso Creciente a 8/750. `TRAP_DIFFICULTY_ORDER` no se toca (la liberación por capacidad de 8 sigue igual). | Media. Revisar si en `sim_trap_balance` el torpe no gana casi-pérdidas por golpes con el camión real: va la pregunta 6 de abajo. | `constructor-trampas` + `pulidor-jugabilidad`; `escritor-tests` (`test_locked_traps`, arnés) |
| 5 | Foto: bono o quitar el −40 | **AHORA.** `COMPLAINT_PENALTY` 40 → **0**: el reclamo por caja abollada sigue saliendo siempre (la decisión 3 del 30/09 queda intacta) pero no cobra; la foto sigue pagando +25. La línea de reclamos del resultado se muestra sin puntos. | Media. Revisar si con telemetría casi nadie saca fotos: hacerla automática al entregar. | `constructor-progresion` |
| 6 | Dúo: asistente o cinchas | **AHORA, opción C.** La caja sobrante (cajas − pasajeros; hoy solo el dúo) sale de `SOLO_TRAPS` (las que protege el manejo) y recibe el asistente de estante mientras nadie la cuida; más la cincha extra de la fila 1. La cincha sola no alcanza. | Alta. Revisar si cambia `MIN_CREW_HOUSES` o el sim muestra que la caja sobrante se pierde > 50 % aun con asistente. | `constructor-mundo` (depósito) + `constructor-jugador` (asistente); después `auditor-red` |
| 7 | Mérito: qué se corta sin romper el MVP | **AHORA, por bandera.** Se apagan cartas, votación de tienda (queda compra directa) y mérito de campaña. Queda el mérito de partida (`_run_merit`: MVP, Rescatista). El módulo `coop_vote` y el código quedan; la campaña v1 se sigue leyendo e ignora `merit`/`card`. N-226.2 se achica: ya no hace falta guardar mérito y carta por color. | Alta. Revisar si el usuario quiere cartas en la 1.0 (pregunta 3). | `constructor-progresion` + `constructor-ui` |
| 8 | Espejo roto: sacar del sorteo o borrar | **AHORA.** Fuera del sorteo de fallas (queda solo la puerta trasera); código, lugar de reparación y `test_vehicle_faults` quedan. | Alta. Revisar si alguna vez hay retrovisor funcional. | `constructor-camion` |
| 9 | Pings: reemplazar o sumar | **Reemplazar 2 de 8, no sumar**: "Tengo la cinta" y "¡Cuidado!" pasan a "¡Izquierda!" y "¡Derecha!" (datos y textos; la rueda no cambia). Cruza la rueda de Slatex (S-311.89): **pregunta 4**. | Alta en el qué; el cuándo es del usuario. | `constructor-ui` con aviso, si el usuario acepta |
| 10 | Estacionamiento: congelar o simplificar | **DESPUÉS: congelar.** Funciona y no hay dato de que falle; simplificar 802 líneas son días sin ganancia medible. | Alta. Revisar si QA o telemetría muestran equipos trabados ahí. | — |
| 11 | Seguro | **AHORA.** Precio 140 → **100**; paga 50 por caja arruinada **o perdida** (hoy solo arruinada). Se paga solo con 2 cajas y sigue sin premiar romper a propósito (20 + 50 < 75; perdida −60 + 50 < 20). | Alta. Revisar si `test_depot` o el bench muestran que conviene perder cajas. | `constructor-progresion` / `constructor-mundo` (depósito) |
| 12 | Frágil (A MEDIAS) y el "a decidir" de N-117.2 | **AHORA.** El golpe por bache a más de 35 km/h (`bump_jolt_per_speed` 1,8) **queda así**; no se sube el badén. Medir en el arnés con recorridos grabados con ese golpe en vez de los 3 baches sintéticos. | Media. Revisar si con recorridos reales el torpe sale de 30-55 %. | `pulidor-jugabilidad` |
| 13 | Explosiva a tercera | **AHORA** (va con la fila 4). | Alta. | `constructor-trampas` |
| 14 | Endless: atasco | **AHORA** el arreglo: el atasco de Endless usa las mismas excepciones que el Reparto (sin conductor o parado a propósito). Si Endless sale en la 1.0: **pregunta 1**. | Alta. | `constructor-tramos` |
| 15 | Tienda: doc promete más ítems | **AHORA.** `economia-y-contramedidas.md` describe los 4 ítems reales y los precios nuevos. | Alta. | `documentador` |
| 16 | Hostil atada a frenada/curva/bocina | **DESPUÉS.** Se desbloquea a las 13 entregas; no la ve casi nadie en el lanzamiento. | Alta. Revisar si Hostil baja en la curva. | — |
| 17 | Ruidosa: "siempre mantiene" pierde 0 % | **DESPUÉS.** La meta de N-117 era 5 de 7 trampas y hoy son 6 de 7; rehacerla son 2-3 días. | Media. Revisar si la telemetría muestra que Ruidosa aburre. | — |
| 18 | Golpe ≥ 7 rearma la Explosiva | **DESPUÉS.** Buen clip, pero agrega una regla nueva a la trampa más difícil de leer. | Media. | — |
| 19 | Cincha que no se afloja con golpe ≥ 7 en solo/dúo | **NO.** El asistente de la fila 6 cubre el dúo; una excepción por tamaño de equipo no se lee. | Media. | — |
| 20 | Depósito: congelar el decorado | **NO** (no es tarea: regla para las rutinas). | Alta. | — |
| 21 | Borrar Puerta trabada y Tienda confusa | **NO.** Ya no salen; borrar toca fixtures sin cambio para el jugador. | Alta. | — |

## Hechos verificados que decidieron

- **Kit.** El trabajo es mantener un botón `TOOL_SECONDS` (`package_care.gd:30-31`, `:271-291`); `DIRECTIONS` (`:32`) y
  `work_direction()` (`:239-240`) no tienen llamadores. La herramienta la sugiere el juego (`:246-266`, usada en
  `player_cargo_care.gd:117`) y se puede cambiar a mano (`care_tool_next`, `:121`). **Reparar** exige ir a ≤ 9 m/s
  (`:234-235`, con la velocidad real que pasa `package_rescue.gd:75`), o sea pedirle al conductor que frene: es la
  herramienta que más refuerza el pilar, por eso no se funde con la cinta. **Cincha**: protección 0,5 (`:134-136`)
  y además es el arreglo improvisado de la puerta trasera (`vehicle_faults.gd:37`, consumida en `:214`): cortarla
  rompía una mecánica del consenso "BIEN". Cinta en crisis ya deja la caja "dudosa" (35) y reparar la deja
  "reparada" (110) (`package_rescue.gd:434-443`), así que los tres resultados ya existen sin cambiar nada.
- **Dúo.** Con 2 jugadores hay 2 casas y 1 pasajero (`route_planner.gd:40,239`); el asistente es solo con 1 jugador
  (`package_rescue.gd:34-36`) y el filtro de trampas fáciles solo en solo (`depot.gd:43`, `:643-650`). La cincha
  solo cambia `impact_scale()` y la tensión (`package_care.gd:134-154`): no da la entrada `steady`/`calm` que leen las
  trampas, y el perfil ausente pierde 100 % en las 7 (`tests/sim_data/balance_report.md:10-16`). Por eso la cincha
  sola no arregla el dúo y el asistente solo tampoco (siempre-mantiene pierde en 6 de 7): la caja sobrante tiene que
  ser de las que protege el manejo, como en solo.
- **Peso Creciente.** No tiene `on_impact`: hereda el de `ITrapBehavior`, que devuelve 0
  (`modules/hazards/i_trap_behavior.gd:38-39`), así que multiplicar `impact_scale()` por la masa (postura del abogado)
  solo no hace nada; y la integridad se recalcula desde la masa cada tick (`growing_weight_trap_behavior.gd:152-156`),
  por eso el desgaste va en un acumulador aparte. La masa solo cambia la de la caja (`:147-149`) y la caja sostenida
  está congelada (`package.gd:699-701`). Primer desbloqueo a 1 entrega (`unlock_manager.gd:22`); la liberación por
  capacidad de 8 va por `TRAP_DIFFICULTY_ORDER` (`:42-44`, `test_locked_traps.gd:60`), que no se toca.
- **Eventos.** Sorteo en `route_event_manager.gd:17`, uno por partida (`run_manager.gd:312`). Inspección se aprueba
  sola si no hay cajas sueltas o abiertas (`:147-151`). Parásita pide dos pasajeros distintos manteniendo a la vez
  (`:359-371`) pero se sortea con 2 peers (`:86-87`): **en dúo sale y no se puede resolver** (multa segura). Mimético
  disfraza de una trampa de dificultad ≤ la real (`:321-331`): con Equilibrio (2) disfrazada de Frágil (1) sale en la
  primera partida. Premios 10-30 (`:22-42`) contra 150 por caja (`run_manager.gd:25`). La carta Rescate resuelve el
  evento con un botón (`:244-248`).
- **Mérito.** El MVP sale de `_run_merit` (`crew_progression.gd:79,156,204`); el mérito de campaña solo alimenta la
  chance de carta (`:342`). Cortar el de campaña no toca el MVP.
- **Foto y seguro.** −40 por reclamo sin foto (`run_manager.gd:33-36`, `:530-533`). Seguro 140 (`crew_progression.gd:59`),
  50 solo por caja entregada arruinada (`depot.gd:58`, `:461`).
- **Espejo.** `vehicle_fault_effects.gd` solo esconde la carcasa (`:81-86`); no hay cámara de retrovisor en el camión.
- **Endless.** Termina tras 6 s bajo 0,3 m/s (`level_endless.gd:31-32`, `:82-93`) sin las excepciones del Reparto
  (`level_base.gd:183-195`): parar a reparar (que exige ≤ 9 m/s) puede cerrar la partida.
- **Pings.** 8 frases fijas (`scripts/ui/ping_catalog.gd:7-16`), sin izquierda/derecha; `scripts/ui/` es de Slatex.

## Para el usuario

1. **¿Endless sale en la 1.0?** Recomiendo **ocultarlo del menú por bandera** en la 1.0 y sacarlo en una actualización con sesión, casas y pago: hoy es solo, no paga y no ejercita el pilar; el arreglo del atasco se hace igual (horas).
2. **¿Trampas repetidas con 8 jugadores?** Recomiendo **sí**: ya pasa (`BOXES_PER_TRAP = 2`; con perfil nuevo, 8 jugadores tienen 4 trampas × 2 cajas para 7 casas) y exigir 7 distintas obliga a tenerlas todas desbloqueadas.
3. **¿La 1.0 sale sin cartas, votación de tienda ni mérito de campaña?** Recomiendo **sí**, apagados por bandera ahora y borrar el código después del lanzamiento si nadie los extraña.
4. **Pings (cruza la rueda de emotes S-311.89 de Slatex):** recomiendo reemplazar **ahora** "Tengo la cinta" y "¡Cuidado!" por "¡Izquierda!" y "¡Derecha!" (solo datos y textos, Nacho con aviso), sin tocar la rueda.
5. **Reparto:** el kit, el asistente y las trampas viven en carpetas de Slatex (`package/`, `traps/`, `player/`). Recomiendo que los hagan las rutinas de Nacho con aviso, como N-117 y N-229; no cruzan S-311 (cuerpo y animación).
6. **Si Peso Creciente con consecuencia sigue sin casi-pérdidas por golpes en el arnés:** recomiendo **no cortarla** (la capacidad de 8 la necesita) y dejarla como trampa fácil de relleno; cortarla es lanzar con 6.
7. **¿La tienda vende algo más que 4 consumibles en la 1.0?** Recomiendo **no**: 4 ítems y los desbloqueos alcanzan; se corrige el doc.
