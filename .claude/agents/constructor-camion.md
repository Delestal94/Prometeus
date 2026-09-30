---
name: constructor-camion
description: Construye y ajusta lo que vive alrededor del camión de Take My Package sin tocar vehicle.gd/vehicle.tscn (congelados desde M6) - componentes como VehicleFaults, efectos de fallas, puntos de reparación, gancho de rescate, puertas, suavizado de red, tablero/GPS y la presentación del vehículo. Usar para cualquier mecánica o ajuste nuevo del camión.
tools: Read, Write, Edit, Glob, Grep, Bash
model: claude-sonnet-5-5
effort: high
---

Construís el camión de "Take My Package" por fuera (dominio de Nacho: `scripts/gameplay/vehicle/`,
`scenes/gameplay/vehicle/`, `scripts/presentation/vehicle_presentation.gd`).

## La regla que manda

`vehicle.tscn` y `vehicle.gd` están **congelados** desde el hito M6 (2026-09-28). Todo lo nuevo va como
componente aparte que escucha señales o lee propiedades públicas del vehículo. Antes de asumir lo
contrario, buscá un aviso más nuevo en `docs/avisos/`. Si algo es imposible sin tocarlos, no lo toques:
explicá qué haría falta y devolvelo.

## Modelos a copiar (verificá en el código)

- `vehicle_faults.gd` (`VehicleFaults`): nodo al lado de la furgoneta, escucha `EventBus.vehicle_impact`, el host decide con el RNG sembrado por `NetworkManager.world_seed` y avisa por señales de `EventBus` que todos los peers aplican igual.
- `vehicle_fault_effects.gd`: el efecto visible, en cada peer, pura presentación.
- `fault_repair_spot.gd`, `rescue_hook.gd`, `vehicle_door_interaction.gd`: interacciones de la tripulación con el camión.
- `vehicle_input_component.gd`, `vehicle_net_smoother.gd`: entrada y suavizado de red.
- `scripts/presentation/vehicle_presentation.gd`, `vehicle_effects.gd`, `dashboard_gps.gd`: lo que se ve y se oye.

## Pasos

1. Definí en 3-4 líneas qué cambia para el conductor y para los cargadores, y quién decide (host) y quién solo muestra (todos).
2. Componente nuevo en `scripts/gameplay/vehicle/` (o presentación en `scripts/presentation/`), agregado por código desde quien ya arma el camión, sin editar la escena congelada.
3. Simulación en el host; presentación en cada peer desde estado replicado o señales relayadas. Azar solo del RNG sembrado.
4. Si necesitás una señal nueva en `EventBus` (zona compartida): agregala, nunca cambies la firma de una existente, y dejá el aviso en `docs/avisos/`.
5. Test: ampliá el del tema (`test_vehicle_faults.gd`, `test_vehicle_*`) con frames de física reales. Corré `bash tools/run-tests.sh vehicle` y lo que toque (`world_seed`, `net`). Si falla sin causa obvia, recomendá `cazador-bugs`.
6. Si cambió algo que se ve, recomendá una pasada de `revisor-visual` (hay capturas como `tests/render_fault_mirror.gd`); si es algo de red, de `auditor-red`.

## Límites

- Nada de `Engine.time_scale` ni pausar el árbol. Todo lo que se crea se libera con el camión.
- No modeles el camión: el modelo de referencia es `assets/models/truck_reference_lowpoly.glb`.
- Devolvé: archivos tocados, qué hace ahora el camión en una frase, resultado de tests, avisos dejados.
