# 2026-10-22 · Ancho de banda de las salidas: lo que faltaba contar y las 4 palancas (D-2002.4)

**Decisión:** en el modo Empresa, y solo ahí (Reparto e Infinito no cambian):

1. **La camioneta de la flota manda su pose cada 0,03 s en movimiento** (`CompanyTuning.FLEET_POSE_INTERVAL_SEC`,
   la pone `CompanyFleet._make()` antes de que `NetRestThrottle` lea el intervalo en `_ready`). `vehicle.tscn` sigue
   en 0,0167 para el camión del Reparto. Estacionada manda igual que antes (cada 0,5 s).
2. **Sentado (conductor y pasajeros) el jugador manda su pose 15 veces por segundo**
   (`CompanyTuning.SEATED_POSE_RATE_HZ`, `player_ride.gd` `set_seated_pose_rate()`, lo pide
   `CompanyRoot.join_crew()`). Parado en la caja de carga de un vehículo sigue a 30.
3. **El pulso de keepalive no despierta los cuerpos quietos**: `WorldCellInterest.pulse_visibility()` muestra y
   oculta con la meta `net_rest_quiet` puesta, y `NetRestThrottle` no se despierta con ella ni cuando se oculta el
   cuerpo a un peer (solo cuando se le muestra a uno de verdad: un join tardío, alguien que se acerca).
4. **Una caja de la empresa publica su `care_state` cada 0,2 s** en vez de 0,1 (`CompanyTuning.CARE_PUBLISH_SEC`,
   `BoxToPackage.tune()`, meta `care_publish_sec` que lee `PackageRescue.care_publish_interval()`). Un aviso de
   golpe (cambio del amortiguado) sale igual en el próximo tick.

**Por qué:** contado todo lo que D-2002.2 dejaba afuera (salvedades de `auditor-red`), con 4 jugadores la salida
daba 54,3 KB/s de 40 y 2 lejos 69,9 de 64 (modelo, techo de Steam). Lo nuevo que pesa: el `care_state` real de una
caja cuidada mide hasta 912 B (la bomba: secuencia, pista y aviso van adentro), 9,9 KB/s por caja a 10/s; una caja
en la mano por cada jugador que carga en el galpón (5,2 KB/s cada una); y los pulsos de keepalive desfasados
(cada cliente del galpón tiene su reloj: con 8, 9,9 KB/s para los de a bordo). Con las 4 palancas, en ese orden:
salida 38,7 (ENet 30,8) y 2 lejos 45,9 (36,9) con 4; con 8, 2 lejos 57,0 (42,4) entra y el test lo exige.

**El número de la camioneta (0,03 y no `pose_interval(30)` = 0,0333):** medido con dos peers ENet y el tope de
FPS del motor, el 0,0167 de hoy manda 35,8 por segundo a 60 FPS y 47,9 a 144. Con 0,0333 manda 25,0 a 60 FPS
(dos frames son 33,33 ms y cualquier frame un pelo corto hace esperar al tercero) y 28,7 a 144; con 0,03, 30,0 y
29,0. A 60 FPS el conductor pasa de ~36 a 30 correcciones por segundo (N-218), no a 25. El modelo lo cuenta a
33,3/s en su propio paquete (techo).

**Lo que no entra:** la salida con 8 (67,3 KB/s de 40; ENet 54,0). El culpable son las 6 cajas en la mano de los
que cargan en el galpón (28,5 KB/s): ninguna de las palancas previstas lo baja lo suficiente (a 15/s quedaría en
~53). Se imprime (`over_budget`) y no falla, como hasta ahora. Ver `revisar/D-2002.4.md`.

**Descartado:** `pose_interval(30)` para la camioneta (25/s a 60 FPS, ver arriba); filtrar jugadores por
distancia (no hizo falta para 2 lejos); quitar `hold_offset` de la pose de la caja (es `package.tscn`, del Reparto
también); bajar `care_state` a menos de 5/s (el panel de cuidado del que cuida se dibuja con eso).

**Protocolo:** no cambia. Son intervalos de envío del dueño y una meta local; ni RPC ni propiedades ni modos de
replicación. Un host y un cliente de builds distintas se entienden.
