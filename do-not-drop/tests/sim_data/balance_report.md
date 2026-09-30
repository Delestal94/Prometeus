# S-108 · Balance de trampas

Generado por `tests/sim_trap_balance.gd` con los comportamientos reales: 5 recorridos × 50 repeticiones por combinación.
Perfiles: ausente; torpe (0,8 s, 60 % de acierto, 20 % de abandono); experto (0,25 s, 95 %); siempre mantiene (aprieta el botón principal toda la partida y no toca nada más). Cada uno se mide con 0 y 150 ms adicionales.

## Resumen: % de cajas perdidas por trampa y perfil (0 ms)

| Trampa | Ausente | Torpe | Experto | Siempre mantiene |
|---|---:|---:|---:|---:|
| balance | 100.0% | 46.0% | 0.0% | 100.0% |
| explosive | 100.0% | 45.2% | 0.0% | 100.0% |
| fragile | 100.0% | 49.2% | 2.8% | 100.0% |
| growing_weight | 100.0% | 53.6% | 0.0% | 100.0% |
| hostile | 100.0% | 83.2% | 0.0% | 100.0% |
| liquid | 100.0% | 38.0% | 0.0% | 100.0% |
| noisy | 100.0% | 44.8% | 0.8% | 0.0% |

Antes de N-117.3 (los mismos recorridos con Equilibrio y Líquido de la tanda 1, donde mantener el botón bastaba):

| Trampa | Ausente | Torpe | Experto | Siempre mantiene |
|---|---:|---:|---:|---:|
| balance | 100.0% | 45.2% | 0.0% | 0.0% |
| explosive | 100.0% | 45.2% | 0.0% | 100.0% |
| fragile | 100.0% | 49.2% | 2.8% | 100.0% |
| growing_weight | 100.0% | 53.6% | 0.0% | 100.0% |
| hostile | 100.0% | 83.2% | 0.0% | 100.0% |
| liquid | 100.0% | 33.6% | 0.0% | 0.0% |
| noisy | 100.0% | 44.8% | 0.8% | 0.0% |

El que siempre mantiene pierde el 80 % o más en 6 de 7 trampas (meta de N-117: 5 de 7, cuando cada trampa tenga su acción propia).

## Todas las filas

| Trampa | Perfil | Latencia | Perdidos | Segundos en riesgo | Casi pérdida |
|---|---|---:|---:|---:|---:|
| balance | absent | 0 ms | 100.0% | 16.0 | 0.0% |
| balance | absent | 150 ms | 100.0% | 16.0 | 0.0% |
| balance | clumsy | 0 ms | 46.0% | 27.8 | 13.6% |
| balance | clumsy | 150 ms | 49.2% | 27.9 | 13.2% |
| balance | expert | 0 ms | 0.0% | 0.2 | 0.0% |
| balance | expert | 150 ms | 0.0% | 1.1 | 0.4% |
| balance | always | 0 ms | 100.0% | 16.0 | 0.0% |
| balance | always | 150 ms | 100.0% | 16.0 | 0.0% |
| explosive | absent | 0 ms | 100.0% | 6.0 | 0.0% |
| explosive | absent | 150 ms | 100.0% | 6.0 | 0.0% |
| explosive | clumsy | 0 ms | 45.2% | 1.8 | 10.8% |
| explosive | clumsy | 150 ms | 54.0% | 2.2 | 7.2% |
| explosive | expert | 0 ms | 0.0% | 0.0 | 0.0% |
| explosive | expert | 150 ms | 0.0% | 0.0 | 0.0% |
| explosive | always | 0 ms | 100.0% | 6.0 | 0.0% |
| explosive | always | 150 ms | 100.0% | 6.0 | 0.0% |
| fragile | absent | 0 ms | 100.0% | 22.8 | 0.0% |
| fragile | absent | 150 ms | 100.0% | 22.8 | 0.0% |
| fragile | clumsy | 0 ms | 49.2% | 21.2 | 0.8% |
| fragile | clumsy | 150 ms | 47.2% | 18.6 | 0.0% |
| fragile | expert | 0 ms | 2.8% | 9.2 | 16.8% |
| fragile | expert | 150 ms | 3.2% | 9.1 | 16.8% |
| fragile | always | 0 ms | 100.0% | 22.8 | 0.0% |
| fragile | always | 150 ms | 100.0% | 22.8 | 0.0% |
| growing_weight | absent | 0 ms | 100.0% | 18.0 | 0.0% |
| growing_weight | absent | 150 ms | 100.0% | 18.0 | 0.0% |
| growing_weight | clumsy | 0 ms | 53.6% | 22.2 | 18.8% |
| growing_weight | clumsy | 150 ms | 66.8% | 23.9 | 20.0% |
| growing_weight | expert | 0 ms | 0.0% | 0.0 | 0.0% |
| growing_weight | expert | 150 ms | 0.0% | 0.0 | 0.0% |
| growing_weight | always | 0 ms | 100.0% | 18.0 | 0.0% |
| growing_weight | always | 150 ms | 100.0% | 18.0 | 0.0% |
| hostile | absent | 0 ms | 100.0% | 4.0 | 0.0% |
| hostile | absent | 150 ms | 100.0% | 4.0 | 0.0% |
| hostile | clumsy | 0 ms | 83.2% | 19.3 | 9.2% |
| hostile | clumsy | 150 ms | 79.2% | 20.3 | 11.6% |
| hostile | expert | 0 ms | 0.0% | 0.0 | 0.0% |
| hostile | expert | 150 ms | 0.0% | 0.0 | 0.0% |
| hostile | always | 0 ms | 100.0% | 4.0 | 0.0% |
| hostile | always | 150 ms | 100.0% | 4.0 | 0.0% |
| liquid | absent | 0 ms | 100.0% | 6.7 | 0.0% |
| liquid | absent | 150 ms | 100.0% | 6.7 | 0.0% |
| liquid | clumsy | 0 ms | 38.0% | 8.1 | 6.8% |
| liquid | clumsy | 150 ms | 33.6% | 8.2 | 10.8% |
| liquid | expert | 0 ms | 0.0% | 8.9 | 0.0% |
| liquid | expert | 150 ms | 0.0% | 8.9 | 0.0% |
| liquid | always | 0 ms | 100.0% | 6.7 | 0.0% |
| liquid | always | 150 ms | 100.0% | 6.7 | 0.0% |
| noisy | absent | 0 ms | 100.0% | 1.3 | 0.0% |
| noisy | absent | 150 ms | 100.0% | 1.3 | 0.0% |
| noisy | clumsy | 0 ms | 44.8% | 13.0 | 0.0% |
| noisy | clumsy | 150 ms | 47.2% | 13.8 | 0.0% |
| noisy | expert | 0 ms | 0.8% | 15.0 | 0.0% |
| noisy | expert | 150 ms | 1.6% | 15.0 | 0.0% |
| noisy | always | 0 ms | 0.0% | 14.5 | 0.0% |
| noisy | always | 150 ms | 0.0% | 14.5 | 0.0% |

## Objetivos

- balance: CUMPLE
- explosive: CUMPLE
- fragile: CUMPLE
- growing_weight: CUMPLE
- hostile: FUERA DE OBJETIVO
- liquid: CUMPLE
- noisy: CUMPLE
- Casi pérdidas esperadas por viaje torpe (7 paquetes): 0.60 (objetivo ≥ 1).
- Resultado interactivo: **REQUIERE AJUSTE**.

`fragile` (N-117, Amortiguá): los recorridos grabados pasan los baches sin golpe (la suspensión se los come, ver `docs/parametros-diseno.md`), así que el arnés le suma a cada recorrido 3 baches a la velocidad de crucero, anunciados como los anuncia el juego. Los choques sin anunciar (que nadie puede amortiguar) son los que ya traen los recorridos grabados (el de la semilla 1085). El torpe y el experto ven el aviso con una atención del 48 % y 95 % y clavan el toque con una dispersión de 0,20 s y 0,05 s alrededor del medio de la ventana (0,35 s). Mantener apretado no protege.

`balance` y `liquid` (N-117.3): el gesto nuevo se modela con los mismos tiempos de reacción, atención y abandono de cada perfil. Equilibrio: mientras el bot mantiene también se inclina hacia el lado contrario (los recorridos grabados siempre se inclinan a la derecha). Líquido: mientras friega alterna izquierda y derecha a 4.5 (torpe) y 5.5 (experto) golpes por segundo, un supuesto del arnés. El que siempre mantiene aprieta el botón y no se inclina ni friega: no protege.

Recorridos: seed 1081 (1408 m, 105.7 s), seed 1082 (1424 m, 107.4 s), seed 1084 (1344 m, 101.3 s), seed 1085 (1442 m, 110.5 s), seed 1087 (1448 m, 109.2 s).
