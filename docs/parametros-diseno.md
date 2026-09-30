# Parámetros de diseño — valores iniciales

> Basado en: `docs/requerimientos-tecnicos.md` (sección 4, catálogo de trampas).
> Última actualización: 2026-09-30
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

Estos objetivos se aplican a las siete trampas. `Frágil` era la excepción (no consumía input, la
única defensa era conducir despacio); desde N-117.2 tiene su acción, el toque "Amortiguá", y entra
en la regla como las demás (ver "Tanda 1 de N-117" más abajo).

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

## Tanda 1 de N-117: código del explosivo y toque de Frágil (2026-09-29)

Se agregó el perfil **siempre mantiene** (aprieta el botón principal toda la partida y nunca toca
nada más) y se volvió a correr el arnés (5 recorridos × 50 repeticiones, `tests/sim_data/balance_report.md`).
Porcentaje de cajas perdidas, 0 ms:

| Trampa | Ausente antes → después | Torpe antes → después | Experto antes → después | Siempre mantiene antes → después |
|---|---:|---:|---:|---:|
| Equilibrio | 100 → 100 | 45,2 → 45,2 | 0 → 0 | 0 → 0 |
| Explosivo | 100 → 100 | 38,8 → 45,2 | 1,2 → 0 | 100 → 100 |
| Frágil | 0 → 100 | 0 → 49,2 | 0 → 2,8 (+150 ms: 3,2) | 0 → 100 |
| Peso creciente | 100 → 100 | 53,6 → 53,6 | 0 → 0 | 100 → 100 |
| Hostil | 100 → 100 | 83,2 → 83,2 | 0 → 0 | 100 → 100 |
| Líquido | 100 → 100 | 33,6 → 33,6 | 0 → 0 | 0 → 0 |
| Ruidoso | 100 → 100 | 44,8 → 44,8 | 0,8 → 0,8 | 0 → 0 |

- El que siempre mantiene pierde 80 % o más en **4 de 7** (antes 3 de 7); la meta de 5 de 7 pide las
  tandas 2 y 3 (Equilibrio y Líquido).
- **Explosivo** ya perdía el 100 % con "siempre mantiene" (sin flechas no se desactiva): lo que cambia es
  que el código se sortea por caja y lo lee el conductor, así que el experto ya no lo memoriza. El
  arnés le da el código al bot sin demora (no mide lo que tarda el conductor en decirlo).
- **Frágil** no pierde con nadie en los recorridos grabados porque el piloto automático pasa los
  baches sin golpe (la suspensión se los come, ver la tabla de golpes más abajo): se le suman a cada
  recorrido 3 baches a la velocidad de crucero, anunciados. Sin esa carga el "antes" y el "después" no
  se pueden comparar; con ella cumple 100 / 49,2 / 2,8 %. Los choques sin anunciar son los del
  recorrido 1085. El torpe y el experto ven el aviso con atención del 48 % y 95 % y clavan el toque con
  una dispersión de 0,20 s y 0,05 s alrededor del medio de la ventana: son supuestos del arnés, no medidas.
- **Hostil** ya estaba fuera de objetivo antes de esta tanda (torpe 83,2 %, no 36,8 %: la tabla de
  arriba es de 2026-09-26 y `hostile_trap_behavior.gd` cambió después). Las casi-pérdidas esperadas por
  viaje torpe bajan de 0,83 a 0,66 (la de Frágil pasa de 20 % a 0,8 %): el resultado global sigue en
  "REQUIERE AJUSTE" y no lo causa esta tanda.

## Tanda 3 de N-117: Hostil a objetivo (2026-09-29)

Hostil estaba fuera de objetivo desde antes de N-117 (torpe 83,2 %, la tabla del 26/09 decía 36,8 %). Se llevó a
objetivo con dos parámetros de `data/traps/hostile.tres`, medido con el arnés (5 recorridos × 50 repeticiones):

| Parámetro | Antes → después | Motivo |
|---|---:|---|
| `command_seconds` | 11 → 9 s | La orden cambia más seguido y se lee en la caja (`:)` mantené, `>:(` soltá); 9 s alcanzan para que el ausente pierda en la primera calma. |
| `correct_decay` | 14 → 16 /s | Con 14 el torpe (que se equivoca el 40 % del tiempo) casi siempre perdía; con 16 pierde la mitad. |

| Perfil | Antes | Después |
|---|---:|---:|
| Ausente | 100 % | 100 % |
| Torpe | 83,2 % | 50,0 % (+150 ms: 48,4 %) |
| Experto | 0 % | 0 % (+150 ms: 0) |
| Siempre mantiene | 100 % | 100 % |

La respuesta es muy sensible a `correct_decay` (14: 83 %, 16: 50 %, 20: 9 % con órdenes de 11 s). Las casi-pérdidas del torpe
suben de 9,2 % a 22,4 %. El resultado global del reporte sigue en "REQUIERE AJUSTE" solo por las casi-pérdidas
esperadas por viaje torpe (0,73, objetivo ≥ 1), con Ruidoso en 0 % y Frágil en 0,8 %.

## N-229: el torpe vuelve a tener casi-pérdidas (2026-09-30)

El reporte seguía en "REQUIERE AJUSTE" solo por las casi-pérdidas del torpe: 0,73 por viaje de 7 paquetes
(objetivo ≥ 1, decisión 9 de `docs/decisiones/2026-09-30-preguntas-auditoria.md`). Casi pérdida = la caja llega con
integridad entre 5 y 25. Dos trampas no daban ninguna:

- **Frágil (0,8 %)**: a 50 km/h cada bache es un golpe pesado de 35 y el amortiguado deja pasar 3,5. Dos baches
  sin amortiguar y uno amortiguado dejaban 26,5, apenas fuera de la banda; tres sin amortiguar, rota. Con
  `impact_damage_heavy` 35 → **36** quedan 24,4: el caso más común del torpe (falla dos de tres) pasa a ser casi
  pérdida sin cambiar cuántas pierde. Con 37 también cumple (37,2 %), pero el choque sin anunciar del recorrido
  1085 más tres toques perfectos del experto deja 4,9 y le saca sus casi-pérdidas (16,8 % → 1,2 %); con 36 deja 7,2.
- **Ruidoso (0 %)**: no se tocó. Las sacudidas de los recorridos llegan en ráfagas de 13 a 34 en pocos segundos
  (+16 cada una) y llevan la agitación al máximo con cualquier perfil; ahí la integridad que ve el arnés es 0, así
  que un rescate en el máximo no cuenta como casi pérdida. Bajar la ganancia para que pase por la banda deja vivo
  al ausente en el recorrido 1082 (una sola ráfaga de 13). Queda como propuesta: medir la casi pérdida de Ruidoso
  por "rescatada en el máximo" en vez de por integridad.

Mismo arnés, mismas semillas, 5 recorridos × 50 repeticiones, 0 ms (perdidas / casi pérdidas del torpe):

| Trampa | Torpe perdido antes → después | Casi pérdida torpe antes → después | Experto perdido | Ausente / siempre mantiene |
|---|---:|---:|---:|---:|
| Frágil | 49,2 → 49,2 | 0,8 → 37,6 | 2,8 → 2,8 (+150 ms: 3,2) | 100 / 100 sin cambio |
| Las otras seis | sin cambio | sin cambio | sin cambio | sin cambio |

Casi pérdidas esperadas por viaje torpe: **0,73 → 1,10**. El reporte pasa a **CUMPLE**.

## Tanda 2 de N-117: Contrapesá y Fregá (2026-09-29)

Equilibrio y Líquido dejan de ser "mantener el botón". Porcentaje de cajas perdidas, 0 ms, mismos recorridos:

| Trampa | Ausente antes → después | Torpe antes → después | Experto antes → después | Siempre mantiene antes → después |
|---|---:|---:|---:|---:|
| Equilibrio | 100 → 100 | 45,2 → 46,0 | 0 → 0 (+150 ms: 0) | 0 → 100 |
| Explosivo | 100 → 100 | 45,2 → 45,2 | 0 → 0 | 100 → 100 |
| Frágil | 100 → 100 | 49,2 → 49,2 | 2,8 → 2,8 | 100 → 100 |
| Peso creciente | 100 → 100 | 53,6 → 53,6 | 0 → 0 | 100 → 100 |
| Hostil | 100 → 100 | 83,2 → 83,2 | 0 → 0 | 100 → 100 |
| Líquido | 100 → 100 | 33,6 → 38,0 | 0 → 0 (+150 ms: 0) | 0 → 100 |
| Ruidoso | 100 → 100 | 44,8 → 44,8 | 0,8 → 0,8 | 0 → 0 |

- El que siempre mantiene pierde 80 % o más en **6 de 7** (antes 4): Ruidoso queda como la trampa de aprendizaje
  ("Abrazalo", mantener) y por eso es la única que ese bot todavía salva.
- Equilibrio: `correction_strength` sigue en 9,8°/s; la corrección ahora es ese valor por cuánto empuja el
  jugador contra la dirección de la inclinación (tope: cuánto sostiene), con los ejes tal como los ve su asiento
  (LeftSeat mira a la derecha del camión y RackSeat a la izquierda: allí "izquierda" es adelante o atrás en la ruta). Sin tres zonas: el mismo eje sirve al ayudante (a
  medio efecto) y no hay castigo por pasarse, solo que la caja no vuelve.
- Líquido: `mop_rate` (9/s mantenido) se reemplaza por `scrub_amount` = 2 por golpe al otro lado, con
  `scrub_gap` = 0,08 s entre golpes (un stick tembloroso no seca más de lo que puede una mano). Un fregado
  rápido (5 golpes/s) equivale a los 10/s de antes. El arnés supone 4,5 golpes/s para el torpe y 5,5 para el
  experto (asunciones, no medidas); con 3,5 el torpe perdía 71 %.
- Hostil sigue fuera de objetivo desde antes de N-117 y no lo toca esta tanda.

### Frágil, "Amortiguá" (`data/traps/fragile.tres`)

| Parámetro | Valor | Notas |
|---|---|---|
| `cushion_window` | 0,35 s | Un toque protege los golpes anunciados que caen dentro de esta ventana. |
| `cushion_cooldown` | 1,0 s | Espera después de cada toque: machacar no sirve. Solo cuenta el flanco de subida. |
| `cushion_leak` | 0,1 | Fracción del daño que pasa aunque el toque sea bueno. |
| `warn_lead` | 0,7 s | Cuánto antes del bache la caja muestra el anillo que se cierra. |
| `bump_safe_speed` | 9,7 m/s (35 km/h) | Por debajo, el camión se come el bache y no golpea. |
| `bump_jolt_per_speed` | 1,8 | m/s de golpe por cada m/s sobre la velocidad segura: 40 km/h no llega al umbral leve, 50 km/h es un golpe pesado. En 0 se apaga. |

Decisión de diseño (supuesto, a validar en playtest): como la suspensión se come los baches a cualquier
velocidad razonable (tabla de golpes más abajo), un bache anunciado no le hacía nada a una caja Frágil y
"Amortiguá" no habría tenido nada que amortiguar. `FragileTrapBehavior.road_jolt_strength()` convierte
el bache tomado rápido en un golpe que el paquete aplica al cruzarlo (`PackageRescue._road_jolt()`); a
30-35 km/h sigue sin costar nada. Además mantener apretado ya no protege a una caja Frágil
(`hold_protects()` en `false`; `HOLD_PROTECTION` le daba 72 % menos de golpe), salvo el ayudante del
rack en una partida solo.

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
| `impact_damage_heavy` | 36 (N-229; antes 35) | Daño si el impacto supera un umbral alto. Dos golpes pesados sin amortiguar y uno amortiguado dejan 24,4: casi pérdida (5 a 25); un tercero la rompe. |
| `impact_threshold_light` | 3.0 (m/s de cambio de velocidad instantáneo) | Equivalente aprox. a un pozo/lomada tomada a velocidad media (medido: la suspensión se los come; ver la tanda 1 de N-117) |
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
| `radio_calm_extra_decay` | +4/s (N-406) | Con la radio del camión en **tranquila**, el decaimiento pasivo sube de 5 a 9/s. Solo cuando nadie lo calma y no está en el máximo. |
| `radio_loud_gain_mult` | ×1,25 (N-406) | Con la radio **fuerte**, cada sacudida suma 20 en vez de 16. |
| `radio_loud_passive_mult` | ×0,4 (N-406) | Con la radio **fuerte**, el decaimiento pasivo baja de 5 a 2/s. |

**Radio (N-406).** `TruckRadio` (perilla del tablero, estado en el host) le pasa su modo a la trampa por el contexto
(`radio_mode`); apagada (el modo de arranque) y noticiero no cambian nada, así que el balance medido con
`tests/sim_trap_balance.gd` (que no manda `radio_mode`) sigue siendo el de la radio apagada: Ruidoso queda en
100 / 44,8 / 0,8 / 0 % (ausente / torpe / experto / siempre mantiene). Los tres números son deliberadamente chicos:
la radio ayuda o molesta, no reemplaza a quien calma la caja. Una caja ya en el máximo no se salva con música
(`agitation >= agitation_max` sigue exigiendo a alguien calmándola). Si en un playtest la tranquila resulta
obligatoria o la fuerte injugable, se ajustan en `data/traps/noisy.tres` sin tocar código.

---

## Sistema de puntaje (para la pantalla de resultados)

Esto es lo que hace `RunManager.finish_run()` (N-227.2, 2026-09-30). **Modo entrega**:

`puntos de carga` = lo que sigue en el camión al terminar (la carga que ya se entregó en una puerta
no cuenta acá, cuenta en la puerta):

| Carga que volvió en el camión | Peso |
|---|---|
| Intacta (estado OK) | 100 pts (`POINTS_INTACT`) |
| En riesgo (`EnRiesgo`, no arruinada) | 50 pts (`POINTS_AT_RISK`) |
| Arruinada, o la entrega no llegó | 0 pts |

`puntos de puerta` (`delivery_points`, lo arma `_resolve_deliveries()`):

| Componente | Peso |
|---|---|
| Entregada intacta en la puerta | +150 |
| Entregada en riesgo (abollada) | +75 (y siempre un reclamo: -40 si no hay foto) |
| Entregada arruinada | +20 (y siempre un reclamo: -40 si no hay foto) |
| Reparada / dudosa / sustituto (rescate de carga) | +110 / +35 / +10, sin reclamo |
| Foto de entrega aceptada | +25 (y cierra el reclamo de esa casa) |
| Plazo cumplido / vencido | +40 / -15 |
| Casa a la que no se llegó, o cuya caja quedó en el camino | -60 |

- **Puntaje** = `max(round((puntos de carga + puntos de puerta) x multiplicador), 0)`. El
  multiplicador es x1.2 (`CHAOS_MULTIPLIER`) si la entrega salió bien y 2+ paquetes estuvieron en
  riesgo al mismo tiempo; si no, x1.
- **Pago al equipo** (`CrewProgression.award_delivery()`) = `max(puntos de puerta + puntos de carga, 0)`,
  **sin** el multiplicador de caos: el caos premia el puntaje, no la billetera. Se suma a la billetera
  compartida y la pantalla de resultados lo muestra como "Pago del equipo".
- **No hay bono de tiempo.** `PAR_SECONDS`, `time_bonus` y `lost_time_bonus` se borraron: la entrega
  más corta dura más que los 75 s del promedio, así que el bono siempre valía 0. La velocidad
  se premia solo con los plazos por casa (+40 / -15).
- **Endless** no entrega: su resultado trae `distance_traveled` y `score`, y ni `cargo_points` ni
  `delivery_points`. `score` = `round(suma de metros que sobrevivió cada caja / cantidad de cajas)`
  (`DISTANCE_POINTS_PER_METER` = 1.0; si hay una caja arruinada cuenta hasta el metro en que se
  arruinó; sin cargamento, la distancia a secas). Como no trae puntos de puerta ni de carga, **Endless no
  paga dinero**: entra solo en su propio ranking.

Precios de la tienda (`CrewProgression.SUPPLIES`): acolchado 160, seguro 140, gancho 120, repuesto 100
(media 130). Una entrega típica de 2-3 casas con cajas intactas paga 300-450 (más plazos y fotos): alcanza
para un ítem de precio medio y otro barato, y el estante entero (520) cuesta unas dos entregas. La
billetera arranca con 100 (`STARTING_MONEY`). El seguro devuelve 50 por caja arruinada entregada
(`Depot.INSURANCE_REFUND`).

El multiplicador de "caos simultáneo" está para reforzar el diseño de momentos
clipeables (sección 3.4 del doc técnico) — recompensa los momentos de tensión múltiple,
no solo la entrega prolija.

### Reglas que surgieron al implementarlo (2026-09-20)

- **Arruinar un paquete ya no termina la entrega.** Con hasta siete pasajeros, que el
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

## Duración medida de la entrega (N-102: 2026-09-24; S-110: 2026-09-27)

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

### Medición completa con bot de entrega (S-110)

`tests/bench_delivery_time.gd` reemplaza la parada supuesta de 25 s por el flujo físico. Usa el
mismo conductor automático de S-108 a 50 km/h; al estacionar en el punto de parada de la ruta,
un `Player` baja, recoge el `DeliveryPackage` asignado, camina a 3,6 m/s hasta el `DoorbellPoint`,
entrega y vuelve a subir. La puerta solo cuenta si el sistema real de la casa la resuelve.

Matriz definitiva: semillas 1081, 1082, 1084, 1085 y 1087, con 1 a 4 casas (20 entregas,
60 cuadros de física por segundo). Todas terminaron, se entregaron las cajas asignadas y no hubo
corridas incompletas:

| Casas | Largo medio (m) | Manejo medio (s) | Paradas totales (s) | Minutos promedio | Máximo | Mínimo |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 1.413 | 108,2 | 20,9 | 2,15 | 2,20 | 2,08 |
| 2 | 2.105 | 163,6 | 41,4 | 3,42 | 3,49 | 3,30 |
| 3 | 2.152 | 168,1 | 59,9 | 3,80 | 3,89 | 3,70 |
| 4 | 1.888 | 149,2 | 81,2 | 3,84 | 3,91 | 3,76 |

La parada física tarda **20,0-20,9 s por casa**, algo menos que los 25 s presupuestados por N-102.
Incluso con esa diferencia, promedio, mínimo y máximo quedan dentro de la regla de 2-5 minutos.
S-110 no cambia el largo de la ruta: estos números se entregan a Nacho para decidir cualquier
ajuste posterior.

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
- **Hallazgo para diseño (N-117.2 lo resuelve del lado de la trampa, ver "Frágil, Amortiguá"):** el badén, el ripio y la loma no amenazan a una caja
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

## Correr (N-115, 2026-09-30)

Sin playtest todavía (el usuario dejó los playtests para el final): los números son un primer borrador, todos son
constantes con nombre en `player_sprint.gd` y en el `on_carried_step()` de cada trampa.

| Qué | Valor |
|---|---|
| Velocidad caminando / corriendo / con caja / con Peso Creciente | 3,6 / 6,0 / 5,0 / 4,2 m/s |
| Distancia entre pasos al correr | 2,0 m (unos 2,5 pasos por segundo con caja) |
| Chance de tropezar por paso | 0,008 + 0,14 x peligro (0 a 1) |
| Peligro | giro de vista 1,6 a 3,6 rad/s (hasta 0,5), pendiente 9 a 24 grados (hasta 0,5), ripio 1 / banquina 0,25 (x 0,5), choque 0,8 |
| Tras tropezar | 1,5 s sin correr, 0,5 s a media velocidad, caja con 6 m/s de golpe |
| Frágil / Equilibrio / Líquido / Ruidoso / Explosivo / Hostil por paso | 1,4 de integridad / 2,5 grados / 1,6 de charco / 3,5 de agitación / 0,12 s de mecha / 1,2 de agresión |
| Corriendo, primera persona | FOV +4 grados (suavizado), balanceo x 2,6 |

Orden de magnitud: una caja Frágil aguanta unos 28 s de carrera continua antes de arruinarse, contra ninguno
caminando; con estas probabilidades, en 20 s de carrera por asfalto se tropieza el 33 % de las veces (sin contar
giros ni ripio). Ajustar acá cuando haya playtest.

## Próximo paso
Estos valores van directo a los `TrapDefinition.tres` que se crean en la Fase 1-2 del
plan de desarrollo. Cualquier ajuste posterior se hace editando esos Resources, sin
tocar los scripts de comportamiento.
