# Una caja en una salida de la empresa vive como carga de una entrega (D-0710.d)

**Decisión:** el mundo Empresa sigue sin arrancar `RunManager`. Las cajas de un `Trip` en curso llevan un metadato
local, `PackageHandling.ON_TRIP_META`, y con él `DeliveryPackage._is_run_active()` y `_registered_for_run()` dan
verdadero. Lo pone y lo saca `TripCargo` (`scripts/gameplay/districts/trip_cargo.gd`), hijo de `CompanyRoot` en cada
peer. Al cerrar el viaje (por el portón, por remolque o porque el vehículo salió del mundo), `CompanyTrips` le pregunta
a `TripCargo` qué cajas están rotas y se las pasa a `Trip.close()`. Quedan en `Trip.broken_ids`.

**Por qué así:**

- **Sin `RunManager`:** arrancar una entrega en el mundo Empresa traería todo lo que una entrega hace al empezar y al
  terminar (resultados, rutas, plazo, puntaje), y nada de eso es de la empresa. Una caja en una salida necesita solo la
  parte del paquete: trampa, golpes, pasos y cuidado.
- **Metadato y no propiedad replicada:** cada peer ya sabe qué viajes hay. El host lo sabe por `CompanyTrips` y un
  cliente por su `CompanyTripsView`, que recibe `trip_started` con las cajas y también el snapshot. Así no hay RPC ni
  campo nuevo, y `PROTOCOL_VERSION` no cambia. La integridad la sigue llevando el sincronizador del paquete y los
  eventos de `EventBus`, como en una entrega.
- **Qué es una caja rota al cierre:** la arruinada (`RUINED`) y también la que tiene el contenido afuera sin
  reponer (`care.needs_restore`). Las dos llegan sin poder entregarse (`TripCargo.is_broken`).
- **Sin mover productos:** `CompanyTrips` no le pasa `Inventory` a `Trip.close()`. El stock es estado compartido y
  moverlo pide un evento del host. `company_net.gd` y `company_root.gd` estaban tomados por D-0254. Quedan como
  estaban con el remolque (`tow()`), que tampoco los movía.
- **La entrega clásica no cambia:** ahí nadie pone el metadato. Los mismos tests de trampas y paquete pasan.

**Lo que queda:** que el resumen del viaje y los clientes vean `broken_ids`, que las rotas pierdan sus productos y
las sanas devuelvan los suyos al stock, y que los insumos de cuidado de una salida salgan del galpón. Está anotado en
[revisar/D-0710.d](../expansion-distritos/revisar/D-0710.d.md).
