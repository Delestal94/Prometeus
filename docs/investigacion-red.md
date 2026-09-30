# Investigación: red de nivel profesional para Take My Package

> 2026-09-29. Disparada por la prueba por Steam (Spacewar 480, dos PCs por internet): el cliente
> veía la caja que cargaba seguirlo con atraso y el camión "seguir andando" después de soltar las
> teclas. Este documento junta cómo resuelven la sincronización los estudios grandes, qué medidas
> defensivas conviene tomar y qué le falta a nuestro juego, con un plan por fases.

## 1. Resumen

**Diagnóstico.** Hay dos problemas distintos que en la prueba se sintieron como uno:

1. **Congestión (lag que crece).** Replicamos jugadores y cajas *en cada frame de render*
   (`replication_interval = 0`). Cada caja manda además su `care_state`, un diccionario de 19 claves de
   texto, en modo "siempre", aunque cambia cada 0,1 s. Steam limita cada conexión a **256 KB/s por
   defecto** y lo que se pase de eso lo **encola** en un buffer de hasta 512 KB, o sea ~2 s de atraso.
   Una vez que la cola se llena, *todo* llega tarde, también lo no confiable. Eso explica el "así con
   todo". **Medido: en Reparto mandamos 527-1263 KB/s a cada cliente, entre 2 y 5 veces el límite**
   (sección 4.2).
2. **Latencia estructural (el ping, una vez).** El host decide todo. El cliente espera un viaje de ida y
   vuelta para ver el resultado de lo que hizo, y en el camión se suman 100 ms de colchón de
   interpolación. Esto no se arregla con ancho de banda: se arregla con **predicción**.

**Las cinco cosas que más rinden, en orden:**

| # | Qué | Por qué | Costo |
|---|---|---|---|
| 1 | Mandar a ritmo fijo (30 Hz), separado del framerate, y `care_state` solo cuando cambia | Saca la congestión. Hoy una PC a 144 Hz manda 2,4× más que una a 60 Hz | Chico |
| 2 | No mandar cajas dormidas, y priorizar lo cercano/activo | Un camión cargado casi no se mueve respecto del camión | Mediano |
| 3 | Interpolación con buffer para jugadores y cajas (como ya tiene el camión) | Con jitter de internet, hoy saltan | Chico |
| 4 | Predicción local del conductor, con reconciliación suave | El volante responde al instante | Grande |
| 5 | HUD de red + simulación de lag de Steam en cada prueba | Sin medir no se puede afinar ni reproducir | Chico |

Ya hecho el 2026-09-29: la caja se dibuja en las manos del que la carga (`predict_carry`), y Nagle
está apagado en el peer de Steam (`no_nagle`).

## 2. Cómo lo resuelven los estudios grandes

### 2.1 Elegir el modelo de autoridad

Hay tres familias. Todo lo demás depende de esta elección.

| Modelo | Quién lo usa | Idea | Para nosotros |
|---|---|---|---|
| **Servidor (host) autoritativo + snapshots** | Quake, Source (CS, TF2), Overwatch, Fortnite, Valorant | El servidor simula; los clientes mandan input y reciben estado | **Es el nuestro.** Bien para física de cajas compartida |
| **Lockstep determinista / rollback** | RTS (Age of Empires), juegos de pelea (GGPO), Rocket League en parte | Solo viajan inputs; todos simulan lo mismo | No: Jolt no es determinista entre PCs |
| **Autoridad distribuida (ownership)** | Destiny (misiones), Unity NGO, Photon, VR cooperativo (Fiedler) | Cada objeto lo simula quien "lo tiene" | Útil **por objeto**: la caja que cargo, el camión que manejo |

Los juegos cooperativos de física (el caso más parecido al nuestro) suelen mezclar: host autoritativo
para el mundo y **autoridad transferible** para lo que un jugador está manipulando. Glenn Fiedler lo
describe para cubos en VR: el jugador que agarra un cubo toma su autoridad, y el cubo que ese cubo toca
hereda la autoridad del jugador. Así nadie ve lag en lo que tiene en las manos.

### 2.2 Tick fijo y ritmo de envío separado del framerate

Todos los motores serios separan tres ritmos:

- **simulación** a paso fijo (Source 66/128 Hz, Overwatch 62,5 Hz, Rocket League 120 Hz, Valorant 128 Hz);
- **envío** de estado (Source manda 20-66 actualizaciones/s según `cl_updaterate`);
- **render**, que puede ir a lo que dé la placa de video.

Nunca se manda estado "por frame de render": el ancho de banda pasaría a depender del monitor del
jugador. En Unreal cada actor declara su `NetUpdateFrequency` (un peatón 2-10 Hz, un vehículo 30-60 Hz).

**Para nosotros:** en Godot, `replication_interval` de cada `MultiplayerSynchronizer`. Hoy está en 0
(cada frame de proceso) en jugador y caja, y en 1/60 en el camión.

### 2.3 Estado no confiable, eventos confiables

La regla de Quake 3 que sigue vigente es que **el estado continuo viaja sin confirmación y "el último
gana"**. Reenviar una posición vieja es peor que perderla. Lo confiable se reserva para **eventos
discretos**: agarré, entregué, se rompió, empezó la partida. Si se mezclan por el mismo canal
confiable, un paquete perdido frena todo lo que viene detrás (*head-of-line blocking*).

**Para nosotros:** vamos bien. `ON_CHANGE` (confiable) está en flags y estados discretos, y `ALWAYS`
(no confiable) en poses. El problema es `care_state`, que es un estado grande y lento mandado como
si fuera rápido.

### 2.4 Interpolación de entidades (cómo se ven los demás)

Source dibuja a los demás **100 ms en el pasado** (`cl_interp`), interpolando entre los dos snapshots que
rodean ese instante. Así un paquete perdido o que llega tarde no se nota. Si se acaban los snapshots, se
extrapola un poco y después se congela. Gabriel Gambetta lo explica paso a paso ("Entity Interpolation").

**Refinamiento profesional: buffer adaptativo.** El colchón se ajusta al jitter medido: chico en LAN, más
grande con mala conexión. Overwatch ajusta así el buffer de input del servidor para cada cliente, y los
teléfonos VoIP hacen lo mismo con el audio.

**Para nosotros:** `VehicleNetSmoother` ya hace esto para el camión con 100 ms fijos. Los jugadores
remotos (`player.gd _apply_net_state`) y las cajas en el cliente (`package.gd _process`) se colocan
**crudos**, con el último valor recibido. Con el jitter de internet eso da saltos y tirones.

### 2.5 Predicción del cliente y reconciliación con el servidor

Lo que el jugador controla responde **ya**, en su propia máquina. El servidor sigue siendo la verdad. El
esquema clásico (Quake, Source, Gambetta):

1. El cliente numera cada input, lo aplica localmente y lo guarda en un historial.
2. El servidor procesa el input y devuelve el estado junto con "último input procesado = N".
3. El cliente toma ese estado, descarta los inputs ≤ N del historial y **re-simula** los que quedan.
4. Si igual hay diferencia, se corrige **suave** a lo largo de unos frames, sin teletransporte.

**Vehículos con física: Rocket League (GDC 2018, Jared Cone).** Física a 120 Hz fija. El cliente
predice su auto *y la pelota*. Cuando llega el estado del servidor, rebobina el mundo y re-simula los
inputs pendientes. El servidor mantiene un pequeño buffer de inputs por cliente para absorber jitter.
Funcionó porque escribieron una física de autos propia, simple y bastante determinista.

**Para nosotros:** el jugador a pie ya es autoritativo del dueño (no tiene lag propio). El camión es el
caso a resolver: ver la sección 5, fase 3.

### 2.6 Compensación de lag (juzgar lo que vio el cliente)

En shooters, el servidor "rebobina" a los demás jugadores a la posición que el tirador veía al disparar
(Bernier/Valve 2001, "Latency Compensating Methods"). Así el que apunta bien acierta aunque tenga 100 ms
de ping.

**Para nosotros no hay disparos, pero sí el mismo problema al agarrar cosas.** El cliente ve una caja 100
ms en el pasado y el host juzga el alcance con la posición actual, así que un agarre justo puede
fallar. La versión barata es **tolerancia proporcional al ping** en los chequeos de alcance del host.
La completa es guardar unos 250 ms de historial de posiciones y juzgar contra el instante que vio el
cliente.

### 2.7 Presupuesto de ancho de banda: prioridad, relevancia, compresión

- **Prioridad con acumulador** (Fiedler, "State Synchronization"; Halo Reach, GDC 2011). Cada objeto
  acumula prioridad por frame (más si se mueve, si está cerca o si está en interacción). En cada envío se
  mandan los de mayor prioridad hasta llenar el presupuesto, y después su acumulador vuelve a cero. Los
  quietos casi no se mandan pero nunca se olvidan.
- **Relevancia** (Unreal *Net Relevancy* y *Replication Graph*). Lo que está lejos o fuera de interés no
  se manda.
- **Objetos dormidos.** Un cuerpo físico en reposo no manda nada; se manda un "se durmió aquí" y listo.
- **Cuantización.** Posición con precisión de 1 mm en un rango acotado, rotación como "smallest three"
  del cuaternión (3 × 9-10 bits en vez de 4 floats). Fiedler ("Snapshot Compression") pasa de 17 Mbps a
  256 kbps con esto más compresión delta.
- **Compresión delta.** Mandar solo lo que cambió respecto del último snapshot que el cliente confirmó.

**Para nosotros:** Godot ya hace delta en `ON_CHANGE`. Las poses `ALWAYS` van enteras y en float de 32
bits. El orden de ganancias es: bajar la frecuencia, no mandar dormidos, prioridad, y por último
cuantizar (esto último solo si hace falta).

### 2.8 Reloj compartido

Para interpolar hace falta saber en qué instante del host fue tomado cada snapshot. Lo estándar es
marcarlos con el tiempo del servidor y estimar el offset de reloj con la llegada menos demorada (estilo
NTP), suavizando los cambios. **`VehicleNetSmoother` ya lo hace bien** (`net_time`, `_clock_offset`);
hay que reusarlo en jugadores y cajas en vez de inventar otro.

## 3. Medidas defensivas (robustez y seguridad)

### 3.1 Nunca confiar en el cliente (aunque sea cooperativo)

Hay pocos tramposos en un juego cooperativo, pero una sala pública de Steam puede traer un troll, y un
cliente con un bug manda basura igual que un tramposo.

- **Validar el remitente de cada RPC `any_peer`.** Ya es costumbre en el repo (`get_remote_sender_id`,
  `_from_host()`, `driver_peer_id`). Hay que mantenerla con un test que liste los RPC `any_peer` y
  exija el chequeo.
- **Validar valores:** rechazar `NaN`/`inf` en transforms y vectores (un `NaN` en una pose rompe la
  física de Jolt para todos), limitar magnitudes (`throttle` ya se clampa) y limitar el tamaño de los
  diccionarios que llegan (`submit_care_input`).
- **Rate limit por peer** en RPC confiables: no más de N pedidos por segundo. Un cliente que spamea
  `request_supply` no debería poder llenar la cola del host.
- **Chequeos de cordura en lo que el cliente es dueño.** La posición del jugador la decide su dueño.
  El host puede rechazar saltos imposibles (velocidad > máximo × 1,5) y no usar esa posición para
  puntuar sin chequearla.
- **Nada de `var_to_bytes` con objetos** (`allow_objects`) en datos de red; el handshake ya usa datos
  planos.

### 3.2 Robustez de la sesión

- **Handshake con versión de protocolo.** Ya existe (`PROTOCOL_VERSION`). Regla: subirlo en cualquier
  cambio de RPC o de propiedades replicadas.
- **Timeouts y desconexión limpia.** Ya existen para ENet; revisar los de Steam.
- **Reconexión.** Un cliente que se cae a mitad de la partida debería poder volver (Destiny, y cualquier
  cooperativo moderno). Ya soportamos a quien entra tarde, así que falta guardar el lugar del que se fue.
- **Migración de host.** Destiny la hace, pero es cara. **Recomendación: no.** Si el host se va, se termina
  la partida con un mensaje claro (ya es así).
- **Degradación elegante.** Con ping alto, agrandar el colchón de interpolación. Con pérdida alta, mostrar
  un aviso de "conexión inestable" en lugar de dejar que el jugador crea que el juego anda mal.

### 3.3 Steam específicamente

- **Límite de envío.** 256 KB/s por conexión por defecto (`SendRateMin/Max`). Se puede subir con
  `Steam.setConnectionConfigValueInt32` o `setGlobalConfigValueInt32` (GodotSteam 4.22.1 lo expone). Es
  un parche: subir el límite no arregla un juego que manda de más, y la conexión real del jugador
  puede ser peor.
- **Buffer de envío.** 512 KB (`SendBufferSize`). Si se llena, `SendMessage` falla.
- **Nagle.** 5 ms por defecto, y aplica también a lo no confiable. Ya lo apagamos (`no_nagle`).
- **Relays (SDR).** Steam enruta por sus relays, lo que protege la IP del host y suma algunos ms. Es lo
  correcto.
- **Spacewar (480)** es una app compartida por miles de desarrolladores: sirve para probar, pero para
  jugar de verdad necesitamos el AppID propio (N-901).
- **Estadísticas en vivo:** `getConnectionRealTimeStatus` devuelve ping, calidad, bytes encolados y tasa
  de envío. Es la base del HUD de red.

### 3.4 Observabilidad y pruebas (lo que hacen todos los estudios)

- **HUD de red** (F3 o una opción): ping, pérdida, KB/s de entrada y salida, bytes en cola y colchón de
  interpolación. Overwatch, Valorant y CS lo tienen para los jugadores; los estudios lo usan en cada
  playtest.
- **Simular mala red siempre.** Steam trae simulación incorporada (`FAKE_PACKET_LAG`, `_JITTER`,
  `_LOSS`, `_REORDER`, `_DUP`, `FAKE_RATE_LIMIT`), que se puede exponer como `--net-sim=150,20,5` (lag
  ms, jitter ms, pérdida %). Para ENet ya existe `--fake-lag` en el camión; en Windows también está la
  herramienta *clumsy*.
- **Perfil de prueba estándar:** 150 ms de ida y vuelta, ±20 ms de jitter y 2 % de pérdida. Toda feature
  de red se prueba así antes de darla por cerrada.
- **Presupuesto en CI.** Un test que carga el nivel con N cajas, calcula los bytes/s que se mandarían a
  un cliente y falla si pasa, por ejemplo, 64 KB/s. Así nadie vuelve a meter un diccionario por frame
  sin darse cuenta.

## 4. Nuestro juego hoy

### 4.1 Tabla de estado

| Tema | Hoy | Falta | Gravedad |
|---|---|---|---|
| Modelo de autoridad | Host autoritativo; jugador a pie autoritativo del dueño | Autoridad/predicción para el camión | Alta |
| Ritmo de envío | Jugador y caja por frame de render; camión 60 Hz | 30 Hz fijo; caja dormida sin envío | **Crítica** |
| `care_state` | Diccionario de 19 claves, `ALWAYS`, por frame | `ON_CHANGE`, publicado a 10 Hz | **Crítica** |
| Interpolación | Solo el camión (100 ms fijo) | Jugadores y cajas; colchón adaptativo | Alta |
| Caja en mano | Predicha localmente (2026-09-29) | — | Hecho |
| Conductor cliente | Input → host → pose (+100 ms) | Predicción + reconciliación | Alta |
| Alcance al agarrar | Juzgado con la posición actual del host | Tolerancia por ping | Media |
| Validación de RPC | Remitente chequeado en casi todos | NaN/inf, tamaños, rate limit, test | Media |
| Handshake/versiones | Sí | Regla de subir versión | Baja |
| Reconexión | Entrar tarde, sí | Retomar el lugar del que se cayó | Media |
| HUD de red / simulación | F3 y `--net-sim` (N-216, 2026-09-30) | Verlo con Steam real entre dos PCs (N-215) | Hecho |
| Nagle en Steam | Apagado (2026-09-29) | — | Hecho |

### 4.2 Mediciones de ancho de banda

Medido el 2026-09-29 con `var_to_bytes()` sobre las propiedades `ALWAYS` reales de cada
`SceneReplicationConfig`. Es un piso: no incluye el encuadre de `SceneMultiplayer` ni las cabeceras
de UDP y del relay de Steam.

**Tamaño por envío:** caja 616 B, de los cuales **524 B son `care_state`** (85 %: casi todo es el costo
fijo del diccionario, 19 claves de texto con un tag de tipo por valor). Jugador 76 B. Camión 304 B, de
los cuales 208 B son las 4 transforms de rueda.

**Cuántas cajas se replican:** en Reparto, hasta **14** a la vez (7 del nivel más 7 de stock extra del
depósito, `depot.gd _spawn_extra_stock`), estén o no en el camión. En Endless, 4-8.

**Host → un cliente:**

| Modo | fps | Jugadores | Cajas | Total | vs 256 KB/s de Steam |
|---|---|---|---|---|---|
| Reparto | 60 | 2 | 14 | ≈527 KB/s | **2,1×** |
| Reparto | 60 | 4 | 14 | ≈536 KB/s | **2,1×** |
| Reparto | 144 | 2 | 14 | ≈1241 KB/s | **4,8×** |
| Reparto | 144 | 4 | 14 | ≈1263 KB/s | **4,9×** |
| Endless | 60 | 4 | 4 | ≈179 KB/s | 0,7× |
| Endless | 144 | 4 | 4 | ≈405 KB/s | **1,6×** |

**Conclusión:** en una partida de Reparto normal pasamos el límite de Steam entre 2 y 5 veces, con
cualquier monitor. Steam encola el exceso y el cliente ve un mundo cada vez más viejo, que es el síntoma
exacto de la prueba. En LAN no se notaba porque ENet no tiene ese límite.

**Qué bajaría cada arreglo (Reparto, 14 cajas, 4 jugadores):**

| Cambio | 60 fps | 144 fps |
|---|---|---|
| Hoy | 536 KB/s | 1263 KB/s |
| `care_state` → `ON_CHANGE` | ≈107 KB/s | ≈210 KB/s |
| + caja y jugador a 30 Hz fijos | ≈62 KB/s | ≈62 KB/s |
| + cajas dormidas sin enviar | unos KB/s menos | unos KB/s menos |

## 5. Plan por fases

> Estado al 2026-09-29: ya se hicieron la fase 1 (PR #34, sin la parte de cajas dormidas) y la
> caja predicha en las manos. El 2026-09-30, la fase 0 (N-216: panel F3 y `--net-sim`, ver el README). Lo que falta está como tareas en `docs/tareas-nacho.md`: N-215 (prueba
> por Steam), N-216 (fase 0), N-217 (fase 2), N-218 (fase 3) y N-221 (fase 4).

**Fase 0: medir antes de tocar (1 día).**
- HUD de red con ping, KB/s y cola (`getConnectionRealTimeStatus` en Steam; `ENetPacketPeer` en LAN).
- `--net-sim=lag,jitter,pérdida` usando la simulación de Steam y `--fake-lag` en ENet.
- Test de presupuesto de ancho de banda en CI.

**Fase 1: sacar la congestión (1-2 días).**
- `replication_interval` fijo: jugador y caja a 1/30 s (camión a 1/60 mientras se mueve).
- `care_state` en `ON_CHANGE`, publicado a 10 Hz como ya hace `package_rescue.gd`, y sin claves de texto
  largas.
- Cajas dormidas o quietas respecto del camión: no mandar pose. Se puede apagar `public_visibility` o
  alternar el synchronizer, más un último envío "quedó aquí".
- Validar con el perfil de 150 ms / 2 % que la cola de Steam queda en ~0.

**Fase 2: que se vea suave (2-3 días).**
- Sacar de `VehicleNetSmoother` un `NetSnapshotBuffer` genérico y usarlo en jugadores remotos y en cajas
  del cliente, marcados con el reloj del host.
- Colchón adaptativo: 2 intervalos de envío + 2 × jitter medido, entre 50 y 200 ms.
- Tolerancia de alcance por ping en los chequeos del host.

**Fase 3: el conductor sin lag (1-2 semanas).**
- Opción recomendada: **predicción del conductor con reconciliación**. El cliente que maneja descongela su
  copia del camión y lo simula con su input, numerado. El host devuelve su pose con "último input N". El
  cliente compara con su historial en N y, si difiere, corrige suave (posición en ~150 ms, rotación
  antes) sin re-simular. Re-simular a lo Rocket League no es viable con Jolt en Godot.
- Las cajas siguen en el host. En el cliente conductor se dibujan en el espacio *de su* camión (ya
  funciona así con `net_in_vehicle`), así que se mueven con la predicción.
- Descartada, salvo que la opción anterior fracase: **transferir la autoridad del camión al conductor**.
  El host terminaría simulando las cajas sobre un camión que llega por red y con atraso, y ya costó
  mucho que no atraviesen paredes (playtests del 25 y el 27/09).

**Fase 4: defensivo y sesión (continuo).**
- Validador genérico de RPC (NaN/inf, tamaños, rate limit) y un test que recorra todos los `any_peer`.
- Reconexión a mitad de la partida.
- AppID propio (N-901) antes de jugar con gente de afuera.

## 6. Fuentes

- Valve, *Source Multiplayer Networking* — https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking
- Yahn Bernier (Valve, 2001), *Latency Compensating Methods in Client/Server In-game Protocol Design and Optimization* — https://developer.valvesoftware.com/wiki/Latency_Compensating_Methods_in_Client/Server_In-game_Protocol_Design_and_Optimization
- Gabriel Gambetta, *Fast-Paced Multiplayer* (predicción, reconciliación, interpolación, compensación de lag) — https://www.gabrielgambetta.com/client-server-game-architecture.html
- Glenn Fiedler, *Gaffer On Games*: *Networked Physics*, *Snapshot Interpolation*, *Snapshot Compression*, *State Synchronization*, *Networked Physics in Virtual Reality* — https://gafferongames.com/
- Jared Cone, *It IS Rocket Science! The Physics of Rocket League Detailed*, GDC 2018 — GDC Vault
- Timothy Ford, *Overwatch Gameplay Architecture and Netcode*, GDC 2017 — GDC Vault
- David Aldridge, *I Shot You First: Networking the Gameplay of Halo: Reach*, GDC 2011 — GDC Vault
- Justin Truman, *Shared World Shooter: Destiny's Networked Mission Architecture*, GDC 2015 — GDC Vault
- Epic Games, documentación de Unreal: *Actor Relevancy*, *Replication Graph*, *NetUpdateFrequency*
- Valve, *steamnetworkingtypes* (SendRate, SendBufferSize, NagleTime, FakePacket*) — https://partner.steamgames.com/doc/api/steamnetworkingtypes
- Valve, GameNetworkingSockets (valores por defecto: `SendRateMin/Max` = 256 KB/s) — https://github.com/ValveSoftware/GameNetworkingSockets
- Godot, *High-level multiplayer* y `MultiplayerSynchronizer` — https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
