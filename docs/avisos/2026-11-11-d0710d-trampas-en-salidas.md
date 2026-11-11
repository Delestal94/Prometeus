# Las trampas corren en las salidas de la empresa (D-0710.d)

**Fecha:** 2026-11-11 · **De:** Nacho (expansión, trampas en el mundo Empresa) · **Para:** Slatex

## Qué cambió

- **`scripts/gameplay/package/package_handling.gd`:** constante nueva `ON_TRIP_META` (`&"on_trip"`) y dos funciones
  estáticas nuevas, `PackageHandling.on_trip(p)` y `PackageHandling.set_on_trip(p, on)`. Marcan una caja que va en una
  salida de la empresa (un `Trip` en curso). El metadato no se replica: cada peer lo pone en su copia
  (`TripCargo`, archivo nuevo en `scripts/gameplay/districts/`, dominio de Nacho).
- **`scripts/gameplay/package/package.gd`:** `_is_run_active()` y `_registered_for_run()` también dan verdadero para una
  caja con `ON_TRIP_META`. Sin firmas nuevas. Con eso, en una salida y sin `RunManager` corriendo, la caja vive como
  carga de una entrega: `PackageImpacts.apply_impact`, `PackageRunShake.jolt` y `_simulate_cargo` actúan, el cuidado
  responde y la caja muestra lo que pide.
- **`scripts/gameplay/player/player_cargo_care.gd`:** `_tick()` ya no corta cuando no hay entrega en curso si la caja en
  las manos o en el regazo va en una salida. Funciones nuevas: `pick_target(running)` y la estática
  `cared_for(running, box)`. Con una entrega en curso hace lo mismo que antes. Sin entrega, solo la caja de una salida
  muestra la tarjeta y manda el input de cuidado. La caja que se apunta sin tenerla sigue pidiendo una entrega en curso.

## Qué no cambió

- La entrega clásica no pone nunca `ON_TRIP_META`: ahí todo se comporta igual que antes. Los filtros package, trap,
  fragile, balance, liquid, handling, rescue, box_ y cargo_care pasan sin cambios.
- No hay RPC nuevo ni propiedad replicada nueva. `PROTOCOL_VERSION` sigue igual.

## Qué tiene que hacer Slatex

- Nada obligatorio. Si alguna función nueva del paquete pregunta "¿hay una entrega en curso?", que use
  `_is_run_active()` y no `RunManager.is_running`. Si no, en el mundo Empresa se queda apagada.
- En una salida, las herramientas de cuidado (cinta, reparar…) gastan del kit de `RunManager`
  (`CARE_SUPPLIES_START`, el que deja `reset_run`). En el mundo Empresa nada lo repone ni lo guarda. Esto queda
  anotado en `docs/expansion-distritos/revisar/D-0710.d.md`.
