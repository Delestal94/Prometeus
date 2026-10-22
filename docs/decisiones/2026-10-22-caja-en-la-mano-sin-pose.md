# 2026-10-22 · La caja en la mano no manda su pose (D-2002.5)

**Decisión:** en todos los modos (Reparto, Infinito y Empresa: es el mismo `package.tscn`):

1. **Una caja en la mano de un jugador a pie no manda su pose.** El host mutea su `NetRestThrottle`
   (`set_muted()`, módulo `net_pose_smoother`) mientras `is_held` y `carrier_peer_id > 0`
   (`PackageNetPose.muted()`, `package.gd` `_publish_net_state()`): manda una pose cada 5 s
   (`muted_interval`), no 30 por segundo. Al soltarla (al piso, a otro, a un estante, al sentarse con ella) vuelve
   a ritmo completo desde el tick siguiente, con su ventana de asentarse.
2. **Cada peer la dibuja en las manos de su copia de ese jugador**, con el mismo código que usa el dueño
   (`PlayerCarry.hands_pose()`: el punto de agarre bajo la cámara, que gira con la cabeza que ya viaja en la pose del
   jugador; el rayo contra lo que estorba; la subida de 1,3 s desde `pick_up`). Por eso `hold_offset` ya no viaja:
   sale de la replicación de la caja, y `submit_carry_transform` pierde su `in_hands`.
3. **Al soltarla, cada peer la deja donde la dibujó hasta la primera pose nueva del host** (las de antes de
   tomarla o del goteo de 5 s son viejas: no entran al buffer) y desde ahí la acerca en `DROP_BLEND_SECONDS`.
   Si estaba en la caja de carga de una camioneta, la deja ahí en el espacio de esa camioneta (la del que la
   llevaba: el `net_vehicle` de la caja no se actualiza mientras está muteada) (a 20 m/s, en el
   espacio del mundo quedaba ~3 m atrás durante un viaje de ida y vuelta: `auditor-red`). El cliente del que la
   lleva, si deja de predecir sin soltarla (un menú abierto), la dibuja en sus propias manos.
   El host la sigue simulando en la última pose que le manda el que la lleva (`submit_carry_transform`, como antes).

**Por qué:** la salida con 8 jugadores daba 67,3 KB/s de 40 (modelo, techo de Steam; 52,2-54,0 con ENet). Las 6 cajas
en la mano de los que cargan en el galpón eran 28,5: cada una mandaba 150 B a 30/s, aunque los demás ya la dibujaban
en las manos de quien la llevaba (N-217): de cada envío solo se usaba `hold_offset`, no la pose. Sacarlas deja 39,0
de 40 con 8 (ENet 25,0-26,7) y 27,8 con 4 (antes 38,7); con `net_vehicle` de D-0302.2.b.4.b (5 B más por pose de
caja y de jugador, mezclado después) queda en 39,7 de 40 (ENet 24,6-26,6) y 28,3 con 4. De paso, sin `hold_offset`
cada caja que se mueve pesa 98 B en vez de 150 (103 con `net_vehicle`): 2 lejos baja a 42,2 con 4 y 53,6 con 8, y en el Reparto el caso estable con 8 baja de 80,7 a 67,9 KB/s
(todo moviéndose, de 107,2 a 85,9). El galpón con toda la cuadrilla cargando una caja, que antes no se contaba,
habría dado ~29 con 4 y ~58 con 8 a 30/s; con la caja muteada da 9,4 y 20,9.

**Por qué no un `hold_offset` más lento:** con 8, después de sacar las cajas en la mano quedan ~1 KB/s de margen
para 6 cajas. Un `hold_offset` `ON_CHANGE` es un delta confiable de ~150 B con su datagrama: entraría uno cada 1,5 s por
caja, y la caja quedaría hasta segundo y medio a destiempo de la cabeza del que la lleva (y la subida, a saltos).
Calcularlo en cada peer no cuesta nada y queda en paso con la cabeza y el cuerpo que se dibujan (antes `hold_offset`
era el más nuevo y la copia del jugador va 50-200 ms atrás).

**Por qué 5 s y no nunca:** el reloj de 16 bits de los paquetes de sincronización de SceneMultiplayer se da vuelta
cada 65.536 envíos a ese peer (~9 min a 60 por segundo); un sincronizador callado más de la mitad de eso ve
descartadas sus poses nuevas por un rato. Un goteo cada 5 s lo evita por casi nada (6 cajas: 0,1 KB/s). Además,
muteada, mostrarla a un peer (un join tardío, alguien que se acerca, un pulso de keepalive de `CompanyInterest`)
manda una pose enseguida (2 frames a cada tick, `MUTED_SHOW_FRAMES`): si no, una copia que nunca recibió nada se
ocultaba por vieja a los 1,5 s y el pulso casi nunca mandaba. El pulso a una caja muteada dura dos de sus intervalos
(10 s cada 20); si se suelta en medio, ese peer lejano recibe la caja a ritmo completo hasta que se asienta (~1 s) y
en reposo el resto del pulso.

**Descartado:** solo en la Empresa (el Reparto tiene el mismo problema con 8 y el código es uno solo; bifurcarlo era
más código para menos); mandarla a 15/s como a su portador (~53, no alcanzaba); un segundo sincronizador para la
pose (cambia `package.tscn` mucho más y todo lo que busca `MultiplayerSynchronizer` en la caja); ocultar el
sincronizador mientras está en la mano (corta también los deltas, como `is_held` al soltarla, y pelea con la
visibilidad de `CompanyInterest` y del join tardío); mutearla con el intervalo directo en `package.gd` (el
`NetRestThrottle` lo pisaba al descansar o despertar: por eso es una función del módulo).

**Protocolo:** cambia, 57 -> 58 (era 55; renumerado al mezclar `main`). Sale una propiedad del sincronizador de la caja (`hold_offset`) y cambia la firma
de `submit_carry_transform` (dos argumentos en vez de tres). Un host y un cliente de builds distintas no se conectan.
