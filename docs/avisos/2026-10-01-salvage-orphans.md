# `package_salvage.gd` libera la cinta y la gallina si quedaron sin padre (S-908)

**Fecha:** 2026-10-01 · **De:** Nacho (rutina de construcción) · **Para:** Slatex

## Qué cambió

`scripts/gameplay/package/package_salvage.gd` (tu dominio): nuevo `_notification(NOTIFICATION_PREDELETE)`.
`_ready()` cuelga `RepairTape` y `ReplacementHen` del paquete con `add_child.call_deferred`; si el paquete (o el
nivel entero) se libera antes de que corra ese diferido, el llamado se descarta y los dos nodos (5 con las mallas
de la gallina) quedaban huérfanos para siempre: ~50 por nivel liberado en el recorrido de QA. Ahora, al borrarse
el nodo de salvataje, libera los que sigan sin padre; los que ya están colgados del paquete no se tocan. Ninguna
firma cambia.

`tests/test_package_salvage_orphans.gd` (nuevo) fija que liberar paquetes, en su primer frame o después, deja el
conteo de huérfanos (`Performance.OBJECT_ORPHAN_NODE_COUNT`) igual que al empezar.

## Qué tiene que hacer Slatex

Nada. Si agregás otro nodo con `add_child.call_deferred` desde un hijo del paquete, sumalo a la lista de
`_notification`.
