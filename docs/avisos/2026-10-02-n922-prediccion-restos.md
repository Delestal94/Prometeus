# Predicción del camión: restos de la auditoría de red (N-922.3 a N-922.8)

**Fecha:** 2026-10-02 · **De:** Nacho (red) · **Para:** Slatex

## Qué cambió

Sin RPC nuevos ni cambiados, sin propiedades replicadas nuevas: **el protocolo no cambia**, `PROTOCOL_VERSION` sigue
en 27 y un cliente de antes de este cambio se entiende con un host nuevo (y al revés).

- **Zona compartida, `modules/net_prediction/`:**
  - `NetDelayQueue` (nuevo): un sentido de un enlace malo simulado (lag, jitter y pérdida de un perfil `--net-sim`,
    en orden). Con `--net-sim` en LAN, el cliente al volante retiene con dos de estas sus inputs y los estados del host
    contra los que predice (la mitad del lag cada uno); antes solo se retrasaba el búfer de poses y la predicción se
    veía perfecta.
  - `NetPredictionReconciler.nudge()` (agregado): un error conocido antes de que lo mida el host, suavizado igual que
    uno medido. La copia predicha ahora arranca donde se la dibuja y se lleva así a la pose más nueva del host, sin el
    salto de la cámara.
  - `NetInputBuffer.is_stale()` (mismo nombre, otro alcance): sigue verdadero hasta que se juega un input llegado
    después del corte, no solo hasta que llega uno.
- **Zona compartida, comentarios:** `modules/net_session/net_stats.gd` (qué simula `--net-sim` en LAN) y
  `docs/modulos.md` (catálogo de `net_prediction`).
- **Mío (camión, ruta, depósito):** `TruckPassThrough` (`scripts/gameplay/vehicle/truck_pass_through.gd`, nuevo): los
  operarios y el autoelevador del depósito (y los del lote final) dejan pasar al camión en todos los peers, y las
  barreras y vagones del paso a nivel en los que no son host. `Vehicle.configure_net_sim()`; la copia predicha arranca
  solo con piso abajo (`VehiclePrediction.has_ground()`), suelta el volante sin retroceder, y en la camioneta vieja
  pone el embrague cuando llega la marcha del host. Barro: el empuje de la cuadrilla y el arrastre también en la copia
  predicha; `MudSegment.stop_orphaned_run()`.
- **`scripts/gameplay/level_common.gd` `_stop_orphaned_run`:** además de congelar el camión, llama al grupo
  `stops_with_orphaned_run` (`stop_orphaned_run()`): el barro suelta el rescate en vez de seguirlo como host huérfano.
- **Pruebas:** `net_trio` agrega `through=` a la línea TRIO; `net_pair` maneja 2 s más con el perfil `--net-sim`
  estándar e imprime una segunda línea `DRIVE` (`tools/run-net-pair.sh` muestra todas). Nuevo `test_mud_prediction`.

## Qué tiene que hacer Slatex

Nada. Dos reglas nuevas, por si te tocan (`docs/convenciones-godot.md` §2):

- Un cuerpo sólido en la capa 1 que se mueve y no se replica (cada peer lo mueve con su reloj) deja pasar al camión
  con `TruckPassThrough.let_through([cuerpo], get_tree())`, o la copia predicha del cliente choca con algo que el
  host no tiene.
- Algo que haga de host por su cuenta y deba frenar cuando el host se va a mitad de partida entra al grupo
  `stops_with_orphaned_run` con un método `stop_orphaned_run()`.
