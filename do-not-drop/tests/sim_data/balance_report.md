# S-108 · Balance de trampas

Generado por `tests/sim_trap_balance.gd` con los comportamientos reales: 5 recorridos × 50 repeticiones por combinación.
Perfiles: ausente; torpe (0,8 s, 60 % de acierto, 20 % de abandono); experto (0,25 s, 95 %). Cada uno se mide con 0 y 150 ms adicionales.

| Trampa | Perfil | Latencia | Perdidos | Segundos en riesgo | Casi pérdida |
|---|---|---:|---:|---:|---:|
| balance | absent | 0 ms | 100.0% | 16.0 | 0.0% |
| balance | absent | 150 ms | 100.0% | 16.0 | 0.0% |
| balance | clumsy | 0 ms | 45.2% | 27.7 | 13.2% |
| balance | clumsy | 150 ms | 48.8% | 28.0 | 12.4% |
| balance | expert | 0 ms | 0.0% | 0.2 | 0.0% |
| balance | expert | 150 ms | 0.0% | 1.1 | 0.4% |
| explosive | absent | 0 ms | 100.0% | 6.0 | 0.0% |
| explosive | absent | 150 ms | 100.0% | 6.0 | 0.0% |
| explosive | clumsy | 0 ms | 38.8% | 1.9 | 9.2% |
| explosive | clumsy | 150 ms | 44.0% | 2.2 | 7.6% |
| explosive | expert | 0 ms | 1.2% | 0.1 | 0.8% |
| explosive | expert | 150 ms | 0.8% | 0.1 | 0.4% |
| fragile | absent | 0 ms | 0.0% | 10.3 | 20.0% |
| fragile | absent | 150 ms | 0.0% | 10.3 | 20.0% |
| fragile | clumsy | 0 ms | 0.0% | 10.3 | 20.0% |
| fragile | clumsy | 150 ms | 0.0% | 10.3 | 20.0% |
| fragile | expert | 0 ms | 0.0% | 10.3 | 20.0% |
| fragile | expert | 150 ms | 0.0% | 10.3 | 20.0% |
| growing_weight | absent | 0 ms | 100.0% | 18.0 | 0.0% |
| growing_weight | absent | 150 ms | 100.0% | 18.0 | 0.0% |
| growing_weight | clumsy | 0 ms | 50.0% | 20.4 | 18.0% |
| growing_weight | clumsy | 150 ms | 62.8% | 22.5 | 20.8% |
| growing_weight | expert | 0 ms | 0.0% | 0.0 | 0.0% |
| growing_weight | expert | 150 ms | 0.0% | 0.0 | 0.0% |
| hostile | absent | 0 ms | 100.0% | 4.0 | 0.0% |
| hostile | absent | 150 ms | 100.0% | 4.0 | 0.0% |
| hostile | clumsy | 0 ms | 36.8% | 13.2 | 27.2% |
| hostile | clumsy | 150 ms | 36.8% | 13.4 | 20.8% |
| hostile | expert | 0 ms | 0.0% | 0.0 | 0.0% |
| hostile | expert | 150 ms | 0.0% | 0.0 | 0.0% |
| liquid | absent | 0 ms | 100.0% | 6.7 | 0.0% |
| liquid | absent | 150 ms | 100.0% | 6.7 | 0.0% |
| liquid | clumsy | 0 ms | 33.6% | 8.2 | 12.8% |
| liquid | clumsy | 150 ms | 29.6% | 8.3 | 11.2% |
| liquid | expert | 0 ms | 0.0% | 8.9 | 0.0% |
| liquid | expert | 150 ms | 0.0% | 8.9 | 0.0% |
| noisy | absent | 0 ms | 100.0% | 1.3 | 0.0% |
| noisy | absent | 150 ms | 100.0% | 1.3 | 0.0% |
| noisy | clumsy | 0 ms | 44.8% | 13.0 | 0.0% |
| noisy | clumsy | 150 ms | 47.2% | 13.8 | 0.0% |
| noisy | expert | 0 ms | 0.8% | 15.0 | 0.0% |
| noisy | expert | 150 ms | 1.6% | 15.0 | 0.0% |

## Objetivos

- balance: CUMPLE
- explosive: CUMPLE
- growing_weight: CUMPLE
- hostile: CUMPLE
- liquid: CUMPLE
- noisy: CUMPLE
- Casi pérdidas esperadas por viaje torpe (7 paquetes): 1.00 (objetivo ≥ 1).
- Resultado interactivo: **CUMPLE**.

`fragile` se informa aparte: no tiene acción de pasajero por diseño; sus seis filas deben coincidir y miden solamente el manejo del conductor.

Recorridos: seed 1081 (1408 m, 105.7 s), seed 1082 (1424 m, 107.4 s), seed 1084 (1344 m, 101.3 s), seed 1085 (1442 m, 110.5 s), seed 1087 (1448 m, 109.2 s).
