# Decisión 2026-10-21: quién recibe un vehículo lejos (D-0316)

Baja a números el punto 6 de [la decisión del mapa continuo](2026-10-04-mapa-continuo.md) ("todos en el mismo
mundo, el host simula todos los vehículos, como máximo 2 lejos del galpón"). La tomó `constructor-red` al hacer
D-0316; D-0317 confirma o sube el tope con las mediciones de D-2002.

**Decisión:**

1. **Cada jugador es un ancla de `world_cells`.** En el host, las celdas se cargan alrededor de todos los
   jugadores y vehículos (simula todo); en un cliente, solo alrededor de su jugador: el que se queda en el galpón
   no carga la ruta de los demás.
2. **Un vehículo o una caja suelta de Empresa va solo a los peers cuyo jugador está cerca**, con los mismos radios
   que las celdas: se empieza a mandar a ≤ `CompanyTuning.CELL_LOAD_RADIUS` (2 celdas, 512-768 m) y se deja de
   mandar pasado `CELL_UNLOAD_RADIUS` (3 celdas, más de 768 m); en el medio queda como estaba (histéresis). Así un
   peer recibe un cuerpo justo mientras ese cuerpo está en las celdas que tendría cargadas. El conductor (y un peer
   que todavía no tiene jugador en el mundo) lo recibe siempre. Se decide 4 veces por segundo
   (`INTEREST_UPDATE_REAL_SECONDS`).
3. **Pulso cada 20 s** (`INTEREST_KEEPALIVE_REAL_SECONDS`, 0,1 s de envío): SceneMultiplayer descarta una
   actualización cuyo reloj de 16 bits parece más viejo que el último que llegó, y ese reloj da la vuelta a los
   65 536 cuadros de red (18 min a 60 cuadros por segundo). Sin pulso, una salida de más de 9 minutos podía dejar
   la camioneta congelada en el galpón varios minutos después de volver.
4. **El cliente esconde su copia lejana y la saca de la física** (`visible = false`, capa y máscara de colisión en
   0 en el cuerpo y en todo lo de adentro, áreas incluidas; el procesamiento sigue, para que el suavizado la siga
   moviendo), con la misma histéresis que el host: la esconde pasadas 3 celdas, o pasadas 2 si hace 1,5 s
   (`copy_stale_sec`) que no le llega nada, o cerca si nunca le llegó nada pasados esos 1,5 s (la de quien entra
   tarde, donde la puso la escena); la muestra a ≤ 2 celdas cuando le llegó una actualización desde la última
   mirada. Nadie ve una camioneta quieta a lo lejos, ni la ve saltar al volver, ni choca con una invisible.
5. **"Lejos" para el tope = con una salida abierta, o afuera sin salida porque se le negó**:
   `CompanyTuning.VEHICLES_FAR_MAX = 2`. El tablero de despacho no carga un tercer vehículo (motivo
   `WORLD_DISPATCH_FAR_LIMIT`) y el portón no le abre salida a un tercero que cruce igual
   (`CompanyTrips.departure_refused`), pero ese vehículo cuenta como afuera (`trips_out()`, el día lo espera)
   hasta que vuelve a cruzar; su carga queda guardada. Desde D-0316.2 (2026-10-22) el portón lo frena: vuelve a su última pose adentro, y su conductor recibe el motivo.
6. **Contrato para lo que entra a esos grupos:** un RPC llamado sobre el cuerpo (la raíz del sincronizador) no llega
   a los peers que no lo ven, tampoco un broadcast; un hecho único o una baja va como propiedad ON_CHANGE, como
   evento de `CompanyNet` o después de `untrack()`. Nada que cree un `MultiplayerSpawner` (no verlo lo despawnea;
   `track()` lo rechaza con un aviso cuando lo detecta).

**Por qué:** los radios de las celdas ya son la distancia a la que un jugador "está" en una zona; usar otros números
abría la puerta a un peer que recibe un cuerpo sin piso cargado debajo, o al revés. La visibilidad es una decisión
del host sobre a quién mandar, no un cambio de qué se replica: este PR no sube `PROTOCOL_VERSION` (todavía ningún
cuerpo real entra a los grupos). **El PR que meta cuerpos reales en `company_vehicle` o `company_loose_box`
(D-0207/D-0302.2, D-0318.1) sí lo sube**: un cliente viejo con un host nuevo no escondería las copias que el host
deja de mandar.

**Costo del pulso (para D-2002.2):** por cada cuerpo oculto a un peer, 0,1 s de envíos (o dos intervalos de
replicación, si son más) cada 20 s: con el vehículo a 60 Hz, unos 6 paquetes cada 20 s por peer oculto; medirlo con
2 vehículos lejos y la tripulación entera en el galpón.

**Descartado:**
- Filtro por `add_visibility_filter` en cada cuadro: Godot llama al filtro por peer en cada cuadro; las banderas
  por peer solo cuestan cuando cambian.
- Contar "lejos" por distancia: un vehículo estacionado afuera del galpón contaría; la salida es lo que cuesta
  (pedidos en curso, la ruta cargada en el host).
- Filtrar también a los jugadores: la tarea habla de vehículos y cajas; queda para D-2002.2 si no entra.

**Revisar:** D-0317 (tope), D-2002.2 (ancho de banda con 2 vehículos lejos), `revisar/D-0316.md`.
