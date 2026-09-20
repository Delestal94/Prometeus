# Parámetros de diseño — valores iniciales

> Basado en: `docs/requerimientos-tecnicos.md` (sección 4, catálogo de trampas).
> Última actualización: 2026-09-20
> **Importante**: todos los números de este documento son puntos de partida
> razonables para poder empezar a programar, no valores finales. Se ajustan con
> playtesting real (Fase 7 del plan de desarrollo). Cada valor está pensado para vivir
> en el `params: Dictionary` del `TrapDefinition` correspondiente (ver
> `docs/arquitectura.md` sección 4), es decir, **ajustable sin tocar código**.

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

## Próximo paso
Estos valores van directo a los `TrapDefinition.tres` que se crean en la Fase 1-2 del
plan de desarrollo. Cualquier ajuste posterior se hace editando esos Resources, sin
tocar los scripts de comportamiento.
