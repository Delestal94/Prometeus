# Parámetros de diseño — valores iniciales

> Basado en: `docs/requerimientos-tecnicos.md` (sección 4, catálogo de trampas).
> Última actualización: 2026-09-26
> **Importante**: todos los números de este documento son puntos de partida
> razonables para poder empezar a programar, no valores finales. Se ajustan con
> playtesting real (Fase 7 del plan de desarrollo). Cada valor está pensado para vivir
> en el `params: Dictionary` del `TrapDefinition` correspondiente (ver
> `docs/arquitectura.md` sección 4), es decir, **ajustable sin tocar código**.

## Objetivos cuantitativos de balance (S-108, definidos antes del ajuste)

Los perfiles se prueban sobre cinco recorridos físicos grabados y 50 repeticiones por
combinación. Un pasajero ausente debe perder entre 80 % y 100 % de los paquetes; uno torpe
(0,8 s de reacción, 60 % de acierto y 20 % de abandono de una acción sostenida), entre 30 % y
55 %, dejando en promedio al menos una casi pérdida por viaje; uno experto (0,25 s y 95 %),
menos de 12 %. Agregar 150 ms de latencia no debe aumentar la pérdida experta más de 8 puntos
porcentuales.

Estos objetivos se aplican a las seis trampas con una acción de pasajero. `Frágil` es la
excepción explícita: su comportamiento no consume input y el propio diseño establece que la
única defensa es conducir despacio. El simulador igualmente la mide en todos los perfiles para
detectar cualquier divergencia accidental, pero su objetivo depende del conductor y sus seis
filas deben ser idénticas.

### Ajuste medido de S-108 (2026-09-26)

El banco definitivo usa las semillas 1081, 1082, 1084, 1085 y 1087: cinco rutas reales de una
casa, a 50 km/h y 60 cuadros de física por segundo. Se descartaron dos candidatos en los que el
piloto automático volcó o fue teletransportado por un rescate (picos irreales de 589-596 m/s y
hasta 171°). El objetivo es aislar la atención del pasajero; una colisión que destruye cualquier
carga imponía por sí sola 20 % de pérdidas al experto y hacía matemáticamente imposible el límite
de 12 %. Esos accidentes siguen cubiertos por los bancos de ruta y golpes.

Solo se modificaron recursos `.tres`; los siete scripts de comportamiento quedaron intactos:

| Trampa | Parámetro | Antes → después | Motivo |
|---|---|---:|---|
| Equilibrio | `angle_ok_max` | 15 → 8° | La inclinación normal nunca agotaba una caja abandonada. |
| Equilibrio | `damage_per_second_at_risk` | 20 → 28 | Convierte el abandono prolongado en una pérdida. |
| Equilibrio | `correction_strength` | 20 → 9,8°/s | Conserva diferencia medible entre reacción torpe y experta. |
| Explosivo | `countdown_seconds` | 14 → 12 s | Lleva al perfil torpe al rango objetivo sin afectar al experto. |
| Explosivo | `mistake_penalty` | 1,5 → 2 s | Hace significativa una secuencia incorrecta. |
| Peso creciente | `weight_fail_threshold` | 2,5 → 2,9× | Da una ventana de rescate adicional al perfil torpe. |
| Peso creciente | `weight_at_risk_threshold` | 1,5 → 1,45× | Expone antes el aviso y produce casi-pérdidas recuperables. |
| Hostil | `command_seconds` | 2,8 → 11 s | El ausente permanece suficiente tiempo bajo una orden para perder. |
| Hostil | `correct_decay` | 13 → 14/s | La respuesta correcta compensa los errores aislados. |
| Hostil | `wrong_gain` | 22 → 7 | Evita que un único fallo condene al experto. |
| Hostil | `passive_gain` | 3,5 → 2,5/s | Mantiene tensión sin daño inevitable durante la latencia. |
| Líquido | `impact_spill` | 18 → 0,05 | Un pico físico no llena instantáneamente el medidor. |
| Líquido | `mop_rate` | 22 → 9/s | La limpieza torpe ya no borra el riesgo demasiado rápido. |
| Líquido | `integrity_loss_per_spill` | 0,23 → 0,55 | Un charco desatendido deja daño permanente y casi-pérdidas. |
| Ruidoso | `agitation_gain_per_shake` | 25 → 16 | Acumula tensión en varios golpes, no en uno solo. |
| Ruidoso | `shake_threshold` | 7 → 0,30 m/s | Las sacudidas reales de la caja sí entran al comportamiento. |
| Ruidoso | `agitation_decay_rate` | 30 → 16/s | El perfil torpe no neutraliza cada sacudida de inmediato. |
| Ruidoso | `fail_seconds_at_max` | 2 → 0,8 s | Abandonar el botón en el máximo tiene una consecuencia visible. |

`Frágil` no necesitó ajustes: las rutas cuidadas producen daño y casi-pérdidas, pero no una
pérdida automática; su dificultad la decide el conductor, como establece el comportamiento.

La corrida definitiva (`tests/sim_data/balance_report.md`, 5 recorridos × 50 repeticiones) dio:

| Trampa | Ausente perdido | Torpe perdido | Experto perdido | Experto +150 ms | Casi pérdida torpe |
|---|---:|---:|---:|---:|---:|
| Equilibrio | 100 % | 45,2 % | 0 % | 0 % | 13,2 % |
| Explosivo | 100 % | 38,8 % | 1,2 % | 0,8 % | 9,2 % |
| Peso creciente | 100 % | 50,0 % | 0 % | 0 % | 18,0 % |
| Hostil | 100 % | 36,8 % | 0 % | 0 % | 27,2 % |
| Líquido | 100 % | 33,6 % | 0 % | 0 % | 12,8 % |
| Ruidoso | 100 % | 44,8 % | 0,8 % | 1,6 % | 0 % |
| Frágil (solo conductor) | 0 % | 0 % | 0 % | 0 % | 20,0 % |

Las seis trampas interactivas cumplen 80–100 % / 30–55 % / <12 %; el aumento experto con
150 ms queda muy por debajo de 8 puntos. Sumando los siete paquetes, el perfil torpe produce
**1,00 casi-pérdidas esperadas por viaje**. Las filas idénticas de Frágil confirman que el perfil
del pasajero no altera una trampa que no consume input.

## Principio de diseño para los números
En vez de fallas binarias e instantáneas (que se sienten injustas en un juego de
fiesta), todas las trampas usan un **medidor de integridad 0-100** con degradación
progresiva. Esto permite tensión creciente, "casi lo logro" (near-miss, bueno para
momentos clipeables) y que un solo error no arruine la partida de golpe.

## 1. Frágil (`FragileTrapBehavior`)
| Parámetro | Valor inicial | Notas |
|---|---|---|
| `integrity_max` | 100 | Medidor de integridad del paquete |
| `impact_damage_light` | 10 | Daño si el impacto supera un umbral bajo |
| `impact_damage_heavy` | 35 | Daño si el impacto supera un umbral alto |
| `impact_threshold_light` | 3.0 (m/s de cambio de velocidad instantáneo) | Equivalente aprox. a un pozo/lomada tomada a velocidad media |
| `impact_threshold_heavy` | 7.0 (m/s de cambio de velocidad instantáneo) | Frenada brusca o choque leve |
| `ruined_at` | integrity <= 0 | Estado `Arruinado` |
| `at_risk_at` | integrity <= 40 | Estado `EnRiesgo` (dispara feedback visual/sonoro de advertencia) |

**Medición técnica**: usar el delta de velocidad lineal del `RigidBody3D` entre frames
de física (o el impulso reportado por `body_entered`/contact monitor de Godot), no la
fuerza cruda — es más estable y fácil de tunear.

## 2. Peso creciente (`GrowingWeightTrapBehavior`)
| Parámetro | Valor inicial | Notas |
|---|---|---|
| `puzzle_time_limit` | 8.0 segundos | Tiempo para resolver el mini-puzzle antes de que empiece a crecer el peso |
| `puzzle_type` | Secuencia de 4 inputs (ej. WASD en orden mostrado) | Mini-juego simple, reemplazable por diseño más adelante |
| `weight_growth_rate` | +15% de masa cada 2 segundos tras vencer el timer | Escalada progresiva, no instantánea |
| `weight_fail_threshold` | 250% de la masa base | Punto en que se considera "imposible de manejar" → `Arruinado` |
| `at_risk_at` | 150% de la masa base | Umbral de `EnRiesgo` |
| `reset_on_success` | true | Resolver el puzzle en cualquier momento reinicia el peso a 100% |

## 3. Equilibrio (`BalanceTrapBehavior`)
| Parámetro | Valor inicial | Notas |
|---|---|---|
| `angle_ok_max` | 15° | Por debajo de esto, sin penalidad |
| `angle_at_risk_max` | 30° | Entre 15°-30°, estado `EnRiesgo`, empieza a acumular daño lento |
| `angle_fail` | 30° sostenido por 1.5s | Dispara `Arruinado` (se derrama/cae) |
| `damage_per_second_at_risk` | 20 (sobre integrity_max 100) | Daño acumulado mientras está en riesgo |
| `player_correction_action` | Mantener presionado botón de "sostener" | Reduce el ángulo activamente mientras se mantiene presionado |
| `correction_strength` | Compensa hasta 20°/s de inclinación | Suficiente para corregir curvas normales, no frenadas de emergencia |

## 4. Ruidoso/vivo (`NoisyTrapBehavior`)
| Parámetro | Valor inicial | Notas |
|---|---|---|
| `agitation_max` | 100 | Medidor de agitación (no de integridad — se comporta distinto) |
| `agitation_gain_per_shake` | +25 por evento de sacudida fuerte (mismo umbral que `impact_threshold_heavy` de Frágil, reutilizable) | Reutiliza detección de impacto del sistema base |
| `agitation_decay_rate` | -30/segundo mientras el jugador mantiene la acción de "calmar" | Requiere atención activa, no un solo click |
| `agitation_passive_decay` | -5/segundo sin acción (decae solo un poco) | Para no ser 100% dependiente del jugador todo el tiempo |
| `ruined_at` | agitation >= 100 sostenido por 2s | Se "escapa"/arruina el paquete |
| `at_risk_at` | agitation >= 60 | Umbral de advertencia |

---

## Sistema de puntaje (para la pantalla de resultados)

| Componente | Peso |
|---|---|
| Paquete entregado intacto (integrity/agitation en estado OK al llegar) | 100 pts |
| Paquete entregado en riesgo (`EnRiesgo` pero no arruinado) | 50 pts |
| Paquete arruinado | 0 pts |
| Bonus por tiempo (llegar antes del promedio esperado de la ruta) | hasta +50 pts |
| Multiplicador por jugadores simultáneos en riesgo alto (recompensa el caos) | x1.2 si 2+ paquetes estuvieron en `EnRiesgo` al mismo tiempo en algún momento | 

El multiplicador de "caos simultáneo" está para reforzar el diseño de momentos
clipeables (sección 3.4 del doc técnico) — recompensa los momentos de tensión múltiple,
no solo la entrega prolija.

### Reglas que surgieron al implementarlo (2026-09-20)

- **Arruinar un paquete ya no termina la entrega.** Con hasta cuatro pasajeros, que el
  error de uno le corte la partida a todos sería miserable. La entrega sigue y
  simplemente se puntúa menos; solo termina si se pierde *toda* la carga.
- **Solo puntúa la carga que subió a la furgoneta.** Un paquete que quedó en el depósito
  nunca fue parte de la entrega, así que no cuenta ni a favor ni en contra.
- **Un paquete puede darse por perdido por fuera de su trampa** (por ejemplo, si se cae
  de la furgoneta en marcha). Eso lo decide el paquete, no la trampa: ninguna trampa
  necesita saber que existe esa forma de fallar.
- **La trampa ruidosa no se calma sola al máximo.** El decaimiento pasivo se pausa una
  vez que llega al tope: si nadie la atiende, se escapa. Sin esto bajaba del máximo el
  mismo frame y era literalmente imposible de perder.

## Duración de la entrega (medida, 2026-09-24)

Regla de oro: una entrega dura **entre 2 y 5 minutos**, tenga las casas que tenga (tareas de
Nacho N-102). Medido con `tests/bench_route_duration.gd`: un piloto automático maneja la ruta
real a 50 km/h de crucero, afloja en las curvas, frena en cada casa y suma 25 s por parada;
semillas 1-20.

**Antes** (tramos de 400-600 m fijos, semillas 1-5): con 1 casa, 1,89 min promedio (menos de 2);
con 4 casas, 5,40 min promedio y 5,52 de máximo (más de 5).

**Regla nueva** (`route.gd`): el largo de cada tramo sale de un presupuesto de
`ROUTE_TARGET_SECONDS` = 240 s. Se le resta `HOUSE_STOP_SECONDS` = 25 s por casa y lo que queda
se reparte entre los tramos (casas + 1) a `ROUTE_CRUISE_SPEED` = 12,8 m/s, la velocidad media que
midió el bench (46 km/h). Cada tramo varía ±10 % y queda entre 250 y 700 m. El techo pensado
era 600 m, pero con 1 casa daba 1,9 min: con 700 m queda en ~2,3.

**Después** (con el ritmo de N-103 incluido, ver abajo):

| Casas | Largo del tramo | Largo medio (m) | Minutos promedio | Máximo | Mínimo |
|---|---|---|---|---|---|
| 1 | 700 m | 1.402 | 2,37 | 2,77 | 2,16 |
| 2 | 700 m | 2.082 | 3,68 | 3,90 | 3,51 |
| 3 | 528 m | 2.154 | 4,25 | 4,43 | 4,01 |
| 4 | 358 m | 1.864 | 4,24 | 4,63 | 4,00 |

`test_route_duration_budget` lo vigila sin manejar: el largo planeado y el construido para
varias semillas, con 1 a 4 casas, dan entre 2 y 5 minutos a esa velocidad media. Si cambia la
velocidad del camión (ver "Manejo"), volver a correr el bench y actualizar
`ROUTE_CRUISE_SPEED`.

## Ritmo dentro de cada tramo (2026-09-24)

`route.gd` planea toda la ruta antes de construirla (`plan_spine()`, tareas de Nacho N-103),
con estas reglas, que `test_route_pacing` revisa en 200 semillas:

| Regla | Valor |
|---|---|
| Siempre pasa algo: tramo difícil (chicana, puente angosto, curva en S, ripio, obras, cruce de tren), curva cerrada o parada en una casa | al menos cada `MOMENT_SPACING` = 250 m |
| Curva cerrada | `SHARP_CURVE_DEG` = 45° o más |
| Dos tramos difíciles seguidos | nunca |
| Llegada tranquila a cada casa: solo recta o curva suave | últimos `QUIET_ZONE` = 80 m; curva suave hasta `GENTLE_CURVE_DEG` = 30° |
| Arranque sin obstáculos ni curvas | primeros `SAFE_START_LENGTH` = 100 m (antes 150) |
| Dificultad creciente | peso de los tramos difíciles de 0,25 a 2,5 a lo largo de la entrega, la misma curva que Endless |

Resultado en 200 semillas: los tramos difíciles pasan de ser minoría en la primera mitad de la
entrega a ser más frecuentes en la segunda (el test imprime los porcentajes).

## Golpes por tipo de tramo (medido, 2026-09-24)

Qué siente una caja según el tramo, comparado con los umbrales de Frágil (3,0 m/s leve, 7,0 m/s
pesado). Medido con `tests/bench_route_shocks.gd` (tareas de Nacho N-105): el piloto automático
recorre rutas reales (semillas 1-10, 2 casas) y registra el golpe por tick en el primer anclaje de
la caja de carga (cambio de velocidad en ese punto, sin la gravedad, que es lo mismo que mide
`package.gd`) y cuánto se inclina el camión. "Golpe típico" es la mediana del peor golpe de cada
pasada.

| Tramo | Típico a 50 km/h | Máximo a 50 | Típico a 30 km/h | Máximo a 30 | Pasadas con golpe pesado (50 / 30) |
|---|---|---|---|---|---|
| Recta | 0,2 | 0,6 | 0,3 | 0,6 | 0 % / 0 % |
| Badén | 0,2 | 0,6 | 0,3 | 0,6 | 0 % / 0 % |
| Ripio | 0,2 | 0,3 | 0,3 | 0,3 | 0 % / 0 % |
| Puente angosto | 0,2 | 0,4 | 0,3 | 0,4 | 0 % / 0 % |
| Loma | 0,3 | 1,6 | 0,3 | 0,6 | 0 % / 0 % |
| Túnel | 0,2 | 0,6 | 0,3 | 0,6 | 0 % / 0 % |
| Curva | 0,2 | 6,8 | 0,3 | 0,6 | 0 % / 0 % |
| Chicana | 0,2 | 0,5 | 0,3 | 9,6 | 0 % / 10 % |
| Obras | 0,2 | 0,5 | 0,3 | 9,2 | 0 % / 25 % |
| Curva en S | 0,2 | 0,4 | 0,3 | 9,5 | 0 % / 20 % |
| Cruce de tren | 0,5 | 538 | 0,4 | 10,0 | 40 % / 40 % |

Lo que dice:

- **Ningún tramo golpea siempre por encima del umbral pesado**: todos se pasan sin daño manejando
  con cuidado (el típico de cada uno queda en 0,2-0,5 m/s). No hizo falta bajarle la severidad a
  ninguno.
- **Los golpes pesados son choques, no el camino**: en chicana, obras y curva en S aparecen solo
  cuando el piloto (que sigue el eje de la ruta y no esquiva) le pega a los bloques; en el cruce de
  tren, cuando no frena ante la barrera y el tren se lo lleva puesto. La curva de 6,8 a 50 km/h
  fue un vuelco del piloto.
- **Hallazgo para diseño, no resuelto acá:** el badén, el ripio y la loma no amenazan a una caja
  Frágil (a lo sumo 1,6 m/s, la mitad del umbral leve): la suspensión del camión se los come. Si
  se quiere que el badén "cueste" pasarlo rápido, hay que hacerlo más alto o más seco, y conviene
  medirlo junto con el simulador de balance de Slatex (S-108), porque este bench mide el anclaje
  del camión y no la caja suelta rebotando sobre el piso.

## Manejo (medido, 2026-09-24)

Medido con `tests/test_vehicle_handling.gd` (`-- --measure` imprime todo), en piso plano,
para cada variante de `vehicle.gd` `VARIANTS` (tareas de Nacho N-104).

| Medida | Clásica | Ágil |
|---|---|---|
| 0 → 50 km/h | 2,42 s | 1,78 s (26 % más rápida) |
| Frenado desde 50 km/h | 6,4 m | 5,6 m |
| Radio de giro a 20 km/h, volante a fondo | 14,6 m | 12,0 m |
| Vuelco en la curva más cerrada de la ruta (70°, radio ~49 m) | nunca, hasta su velocidad máxima | nunca, hasta su velocidad máxima |

**Decisión:** estos valores **son** los objetivos. La tarea proponía un camión mucho más pesado
(0 → 50 en 5-7 s, frenado de hasta 18 m), pero cambiar así la sensación de manejo sin
playtesting es apostar a ciegas; el camión de hoy es el que se jugó en todas las pruebas. El
test falla si un cambio mueve cualquiera de estos números más de ±10 %, así que la sensación
no cambia por accidente. Revisarlos es de las primeras cosas para cuando haya playtesting.

Lo que dicen los números: con esta aceleración y estos frenos, el riesgo para la carga no sale
de no poder frenar a tiempo sino de los golpes (badenes, ripio, frenadas y volantazos). Ninguna
curva de la ruta vuelca al camión por sí sola: un vuelco siempre viene de pegarle a un obstáculo
o de salirse del camino.

## Próximo paso
Estos valores van directo a los `TrapDefinition.tres` que se crean en la Fase 1-2 del
plan de desarrollo. Cualquier ajuste posterior se hace editando esos Resources, sin
tocar los scripts de comportamiento.
