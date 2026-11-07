# D-0710.b · Trampas por nivel de armado

Generado por `tests/sim_trap_balance.gd -- --levels` con los comportamientos reales: 5 recorridos × 10 repeticiones por combinación, 0 ms, las mismas semillas en cada nivel.
Severidad por nivel (`CompanyTuning.TRAP_SEVERITY_*`, `ITrapBehavior.severity`): bajo 1.00 (la trampa como es hoy), medio 1.10, alto 1.25. Cada trampa multiplica por ella el daño que hace (golpes, derrame, enojo, peso, mecha y tiempo hasta volcar), nunca lo que hace la respuesta correcta.

## % de cajas perdidas por nivel

| Trampa | Torpe bajo | Torpe medio | Torpe alto | Experto bajo | Experto medio | Experto alto | Más en alto |
|---|---:|---:|---:|---:|---:|---:|---|
| balance | 46.0% | 48.0% | 54.0% | 0.0% | 0.0% | 0.0% | sí |
| explosive | 48.0% | 54.0% | 64.0% | 0.0% | 0.0% | 0.0% | sí |
| fragile | 50.0% | 50.0% | 50.0% | 2.0% | 20.0% | 20.0% | sí |
| growing_weight | 48.0% | 54.0% | 60.0% | 0.0% | 0.0% | 0.0% | sí |
| hostile | 54.0% | 78.0% | 100.0% | 0.0% | 0.0% | 0.0% | sí |
| liquid | 40.0% | 54.0% | 72.0% | 0.0% | 0.0% | 0.0% | sí |
| noisy | 48.0% | 56.0% | 60.0% | 0.0% | 0.0% | 2.0% | sí |

Más roturas en alto que en bajo en 7 de 7 trampas (D-0710.b pide 5): **CUMPLE**.

Recorridos: seed 1081 (1408 m, 105.7 s), seed 1082 (1424 m, 107.4 s), seed 1084 (1344 m, 101.3 s), seed 1085 (1442 m, 110.5 s), seed 1087 (1448 m, 109.2 s).
