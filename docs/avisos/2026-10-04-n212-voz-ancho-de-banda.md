# La voz tiene tope de envío y de bytes decodificados (N-212, ancho de banda)

**Fecha:** 2026-10-04 · **De:** Nacho (con Claude) · **Para:** Slatex

## Qué cambió

- **Módulo `net_session` (zona compartida), `SteamVoice`** (`modules/net_session/steam_voice.gd`). Solo
  agregados, salvo dos constantes que cambian de valor:
  - Tope de envío de cada peer, sin importar los FPS: `VOICE_SEND_PACKETS_PER_SECOND` (60) y
    `VOICE_SEND_BYTES_PER_SECOND` (8192), con ráfaga `VOICE_SEND_PACKET_BURST` (6) y `VOICE_SEND_BYTE_BURST`
    (2048). Antes cada cuadro con voz era un RPC de hasta 8 KB. Función nueva `take_send_budget(now_msec, bytes)`;
    lo que no entra se descarta (una sílaba perdida) y se cuenta en `dropped_sends` (variable nueva).
  - Función virtual nueva `_send_packet(buffer)`: es la que hace `_receive_voice.rpc(buffer)` (antes estaba
    adentro de `_send_pending_voice`). Los tests la sobrescriben para contar lo que saldría.
  - Cupo de bytes decodificados por peer junto al de paquetes: `VOICE_BYTES_PER_SECOND` (16384, el doble del
    tope de envío) y `VOICE_BYTE_BURST` (8192). `take_voice_packet(peer_id, now_msec, bytes = 0)` suma un
    parámetro opcional: sin él se comporta igual que antes.
  - **Cambia de valor:** `MAX_PACKET_BYTES` 8192 → 2048 (emisor y receptor). Un paquete de voz real de Steam es
    mucho más chico; uno así es el atraso de un tirón largo.
  - `override_clock_msec` (variable nueva, solo tests): el reloj que leen los dos cupos.
- **`tests/test_net_bandwidth_budget.gd`**: suma la voz (todos hablando al tope) al caso estable. Con 5 jugadores
  tiene que entrar en el envío de Steam por cliente y en la subida de 10 Mbit/s del host; con `MAX_PLAYERS` (8) no
  entra en la subida y **solo lo imprime** (`NOTE: voice is tested for 5 ...`), junto con el máximo que entra.

**No hay RPC nuevo ni cambiado ni replicación nueva: `PROTOCOL_VERSION` no sube.** `_receive_voice` sigue igual
(`any_peer`, `unreliable_ordered`, canal 3). Un cliente viejo con un host nuevo se entienden: lo único distinto es
que el nuevo descarta paquetes de más de 2048 B y decodifica menos bytes por segundo de cada peer, cosas que una voz
normal no alcanza.

## Por qué

La voz de un cliente no va directo a los demás: pasa por el host (`server_relay`), que reenvía una copia a cada
uno. Con N hablando, el host sube (N-1)² flujos. Al tope (unos 14 KB/s por flujo con su encabezado) son ~1,8 Mbit/s
con 5 y ~5,6 Mbit/s con 8, antes del tráfico del juego.

## Supuestos y riesgos

- Los topes suponen que Steam comprime la voz en unos pocos KB/s y entrega como mucho un paquete cada ~20 ms. Falta
  confirmarlo con Steam real (pendiente de N-212.1 y N-212.2): si `ProximityVoice.dropped_sends` sube mientras
  alguien habla normal, los topes son chicos para la voz real.
- Con 8 hablando a la vez al tope no entra en una subida de 10 Mbit/s. La voz está probada para 5.

## Qué tiene que hacer Slatex

Nada. Si algo tuyo sobrescribe `take_voice_packet()` o llama a `_receive_voice.rpc()` directo, avisá: lo que sale
ahora pasa por `take_send_budget()` y `_send_packet()`.
