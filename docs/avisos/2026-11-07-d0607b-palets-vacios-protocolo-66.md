# Aviso 2026-11-07 · los palets agotados salen del libro (D-0607.b)

**Cambia el protocolo:** `PROTOCOL_VERSION` 65 -> 66 (`scripts/core/network_manager.gd`, zona compartida; solo la
línea del historial y la constante). Un cliente viejo con un host nuevo no se conecta (error claro de versión). Si
otro PR ya usó el 66, sube al siguiente libre (`docs/convenciones-godot.md` §6.3).

Qué cambió en la red de la empresa (Nacho, `scripts/core/company/`): evento nuevo del host `jack_cleared {pallets}`,
sin RPC nuevo (viaja por `_apply_event`) y sin parte nueva del snapshot.

Qué tiene que hacer Slatex: nada.
