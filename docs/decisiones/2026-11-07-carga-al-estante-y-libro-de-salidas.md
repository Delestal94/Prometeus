# Decisión 2026-11-07 · "Cargar" sube las cajas al estante y el libro compartido sigue las salidas

Tarea: D-0302.2.b.3, con D-0717.b. Rol: `constructor-mundo`.

## Contexto

El tablero (D-0310.b) dejaba la carga solo en `CompanyTrips`: las cajas seguían en el piso del despacho, la camioneta
salía vacía y el pedido seguía abierto en el libro compartido, porque `CompanyTrips.book` es otro libro.

## Decisión

1. **"Cargar" pone las cajas en los `PackageMountPoint` del vehículo** (`DispatchRack.store()`, solo el host), el mismo
   `store()` que usan las manos. No hay evento nuevo: el sincronizador de cada caja ya lleva el estante.
2. **Una caja en el estante de la flota no se congela.** Congelada hasta "el arranque de la corrida" quedaba en el aire,
   porque en el mundo de la empresa no hay corrida.
3. **Solo sale lo que está arriba.** Una caja que alguien baja deja la carga con su pedido, al leer el tablero o en el
   portón (`CompanyTrips.left_behind`), así no falla un pedido cuya caja nunca se fue.
4. **El libro compartido sigue a `trip_started` y `trip_closed`** en `CompanyTripsView.apply_trip()`, en cada peer, con el
   mismo orden de eventos. Sin evento nuevo ni cambio de protocolo.
5. **D-0302.2.b.6 pasa a D-0528** (post-lanzamiento): vender es lo único que saca un vehículo a mitad de día.

## Queda igual

`CompanyTrips.book` y `_bridge()` hasta que la puerta real cobre sobre el libro compartido (fila 20). Hasta entonces un
pedido entregado por el bot queda `OUT` en el compartido; en el juego real todavía no hay puerta.
