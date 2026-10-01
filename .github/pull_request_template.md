## Qué cambia

<!-- Una o dos frases: qué hace el PR y por qué. -->

## Dominio

- [ ] Nacho (vehículo, ruta, ambientación, depósito)
- [ ] Slatex (jugador, paquetes, interacción, UI, progresión)
- [ ] Zona compartida (`event_bus.gd`, `network_manager.gd`, `run_manager.gd`, `level_base.*`) — avisado en `docs/avisos/`

## Cómo se probó

- [ ] Tests del cambio en verde (`tools/run-tests.sh <filtro>`; la batería completa la corre CI)
- [ ] Test nuevo o ampliado para lo que cambia: <!-- nombre -->
- [ ] Cambio visual revisado con capturas (agente `revisor-visual`, scripts `render_*`)
- [ ] Probado en red (host + cliente) si toca algo que se replica

## Docs

- [ ] `docs/tareas-nacho.md` / `docs/tareas-slatex.md` actualizados
- [ ] El test nuevo describe qué cubre en su encabezado (`tools/list-tests.sh --missing` vacío)
