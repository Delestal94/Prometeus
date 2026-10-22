# 2026-10-22 · Las cajas de Empresa se mandan solo a los que están cerca (D-0316.3): `PROTOCOL_VERSION` 44

Para Slatex. Desde D-0316.3, cada `DeliveryPackage` que deja `box_sealed` en el modo Empresa
(`World/Packages/Package_<id>`) entra al grupo `company_loose_box`: el host manda su `MultiplayerSynchronizer`
solo a los peers con su jugador cerca (regla 11 de `red-autoridad.md`) y un cliente lejos esconde su copia. Toca
dos archivos tuyos (`package.gd`, `package_handling.gd`), poco y sin cambiar firmas. **Fuera del modo Empresa no
cambia nada:** nadie conecta la señal nueva y las cajas de Delivery y Endless no entran a ningún grupo.

## Tu dominio: `do-not-drop/scripts/gameplay/package/`

- `package.gd`: **señal nueva `consuming`** (sin argumentos) en `DeliveryPackage`. Ningún RPC nuevo ni cambiado,
  ni propiedades replicadas nuevas (`test_package_split` sigue con la misma tabla).
- `package_handling.gd`: `PackageHandling.consume()` emite `p.consuming` **al principio**, antes de
  `release_carrier()` y antes del broadcast `_remote_consume.rpc(...)`. Firma igual.
- **Por qué:** un RPC llamado sobre un cuerpo cuyo sincronizador está oculto para un peer no le llega a ese peer,
  tampoco un broadcast. Con la caja oculta para un jugador lejano, `_remote_consume` no le llegaba y se quedaba con
  una caja fantasma para siempre. En Empresa, `CompanyRoot` conecta `consuming` a `CompanyInterest.release()`: la
  caja deja de estar seguida (su sincronizador vuelve a ser público, con el filtro de acuse de la regla 10 y el tuyo
  de `_enter_tree()` igual que antes) y el broadcast que sigue llega a todos.
- **Qué tenés que saber:** si agregás otro RPC de hecho único o de baja que se llame **sobre la caja** (no sobre el
  jugador: `pick_up`, `drop_carried` y compañía no cambian), en Empresa tiene que ir después de `consuming` o como
  propiedad ON_CHANGE del sincronizador. Si sacás o movés el `emit` de `consume()`, avisá.
- La copia escondida de un cliente tiene capa y máscara en 0; si una actualización (el setter de `is_held`) o el
  juego le escribe una capa mientras está escondida, el módulo la guarda y la vuelve a poner en 0, y al mostrarla
  `CompanyInterest` vuelve a correr tu setter de `is_held` (sin tocar tu código) para que las capas queden como las
  dejaría la caja.

## Zona compartida

- `do-not-drop/modules/world_cells/cell_interest.gd` (`WorldCellInterest`), solo agregado: `release(body)` (deja de
  seguir el cuerpo y lo saca de `groups`; lo que se llame después sobre él llega a todos), señal
  `copy_shown(body)` (una copia escondida se volvió a mostrar) y la cuenta de capas de la copia escondida (lo no nulo
  que se le escribe mientras está escondida es lo que vuelve al mostrarla). Firmas existentes iguales.
- `do-not-drop/scripts/core/network_manager.gd`: `PROTOCOL_VERSION` 43 → **44** (línea "44" en el historial).
  Ninguna firma, RPC ni señal de `NetworkManager` / `NetSession` cambia; `modules/net_session/` no se tocó.
- **El protocolo cambia:** el host nuevo deja de mandar la caja a un peer lejano; un cliente viejo (43) no esconde
  esa copia vieja ni la saca de la física, y con un host viejo un cliente nuevo escondería cajas lejanas que el host
  le sigue mandando. Con el número nuevo el handshake los separa con el error de versión.
- **Por qué 44:** `main` está en 43 (D-0605.b). Los PRs abiertos #629 (D-0603.b2, dice 43) y #630 (D-0618.b, dice
  44) también suben; el que se mezcle después que otro sube al siguiente libre y corrige su línea
  (`test_protocol_version`).

## Del juego (dominio de Nacho, sin aviso propio)

- `CompanyInterest`: `add_loose_box(box, removing)` (grupo + `release()` en el host), `anchor_point()` (el ancla de un
  jugador es su `reach_origin()`: sentado, el asiento, no el cuerpo que quedó donde se sentó; también en
  `cell_anchors()`), y al mostrarse una copia vuelve a aplicar `is_held`.
- `CompanyRoot._on_package_added()` llama a `add_loose_box(package, package.consuming)` en cada peer.

Tests: `test_world_cells_interest` (release, capas de la copia escondida, `copy_shown`), `test_company_sealed_package`
(host + cliente ENet: con el jugador del cliente a 5 celdas, el `_remote_consume` sobre la caja oculta no le llega; con
`consume()` del host primero, sí), `test_company_split_crew` (el que viaja sentado se ancla en su asiento) y
`test_company_root` (la caja entra al grupo y `consuming` la suelta).
