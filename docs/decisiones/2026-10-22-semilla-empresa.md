# 2026-10-22 · Semilla de la empresa (D-0246)

Decidido por la rutina desarrollador (carril 1), regla 3 del README de rutinas. Detalle en
[detalle/F0-02-arquitectura.md](../expansion-distritos/detalle/F0-02-arquitectura.md), D-0246.

- **Decisión: D-0246 no reparte la semilla para que cada peer sortee**, porque el contrato de red (D-0813) ya manda los
  pedidos enteros y solo el host sortea. La tarea queda en dar la semilla del día que el host usa.
- **Decisión: la semilla es de la empresa (guardada), no de la sesión** (`NetworkManager.world_seed`), así la misma
  empresa tiene el mismo día la cargue quien la cargue.
- **Decisión: una corriente por sistema** (`orders`, `suppliers`) para que los sorteos no se corran entre sí.

Revisar al final: [revisar/D-0246.md](../expansion-distritos/revisar/D-0246.md).
