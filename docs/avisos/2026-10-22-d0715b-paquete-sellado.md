# 2026-10-22 · La caja encintada es un `DeliveryPackage` en cada peer (D-0715.b): `PROTOCOL_VERSION` 41

Para Slatex. Desde D-0715.b, encintar una caja en el modo Empresa (`box_sealed`) crea en **cada peer** el
mismo `DeliveryPackage` (`package.tscn`, tu escena), en `World/Packages/Package_<id de caja>`. No se
tocó nada de tu dominio: ni `package.gd`, ni `package.tscn`, ni sus ayudantes.

## Zona compartida: `do-not-drop/scripts/core/network_manager.gd`

- `PROTOCOL_VERSION` 38 → **41** (líneas "39", "40" y "41" en el historial). Ninguna firma, RPC ni señal
  de `NetworkManager` / `NetSession` cambia; `modules/net_session/` no se tocó.
- **El protocolo cambia:** el evento `box_sealed` viaja igual, pero ahora cada peer crea un nodo con
  `MultiplayerSynchronizer` que el host sincroniza. Un cliente viejo (38) con un host nuevo no tendría el
  nodo (errores "Node not found" del sincronizador); un cliente nuevo con un host viejo tendría una caja
  quieta que nadie mueve. Con el número nuevo, el handshake los separa con el error de versión.
- **Por qué 41 y no 39:** el 39 lo tiene el PR #602 (D-0610.b, carritos) y el 40 la rama
  `exp/D-0302.2-company-van` (salidas en red), los dos en vuelo; `test_protocol_version` exige historial
  consecutivo, así que sus líneas 39 y 40 van **copiadas tal cual** de esas dos ramas (como hizo D-0302.2
  con la del 39). **Quien mezcle después de otra de las tres toma los números libres siguientes** y corrige
  su línea del historial (convenciones §6, paso 3); las líneas copiadas no reservan nada.
- El 41 también cubre un `kind` nuevo de `CompanyNet._request`, `package_ack` (ver abajo): un host viejo lo
  descartaría y nunca abriría el sincronizador.

## Para conocer (tu dominio, sin cambios)

- `CompanyPackages` (`scripts/core/company/company_packages.gd`, nuevo) arma el paquete con
  `BoxToPackage.build()` desde la caja encintada que tiene cada peer y le pone lo que dice el host:
  `name` y `package_id`, `trap_definition` (cargada de `data/traps/<trap>.tres`), `impact_absorption`,
  `transform` (posición y orientación del evento) y la meta `BoxToPackage.META_TRAP_PLAN` con calidad e
  intensidad. Todo antes de entrar al árbol.
- En el host le suma **un filtro** al `MultiplayerSynchronizer` con `add_visibility_filter` (regla 10 de
  `red-autoridad.md`): no llega a un peer hasta que **ese peer acusa que tiene el nodo**. El cliente, al
  crear el paquete, le pide al host `package_ack` por el `_request` de `CompanyNet` (ningún RPC nuevo) y el
  host le abre el sincronizador. Se suma al filtro que ya pone `package.gd` en `_enter_tree()` (mundo
  listo); tu `_on_peer_level_ready` sigue llamando a `update_visibility(peer)` y el filtro nuevo decide que
  un peer sin el nodo no lo reciba. Sin el filtro, el tercero que entra tarde logueaba `Node not found:
  "Packages/Package_box_1/MultiplayerSynchronizer"`; abriéndolo al mandar el evento (primera versión), un
  cliente que esperaba un snapshot aplicaba el `box_sealed` después y su copia quedaba quieta para siempre
  (auditor-red, B1). Los dos casos están en `test_company_sealed_package`.
- **Ancho de banda:** cada paquete manda su pose a 30 Hz a cada peer que lo acusó, ~3 KB/s por peer
  aunque esté quieto. Antes de una prueba con muchas cajas tienen que entrar a `company_loose_box`
  (D-0316.3) o bajar la frecuencia en reposo; si tocás `NetRestThrottle` o la frecuencia del sincronizador
  de `package.tscn`, avisá.
- En el host, `CompanyRoot` registra el paquete en `cells.track_body()` (D-0318.1): se congela
  (`freeze`, `FREEZE_MODE_STATIC`, velocidades guardadas) mientras su celda no está cargada y se suelta
  al salir del árbol. El galpón está en celdas fijas, así que adentro nunca se congela.
- Si cambiás el camino del sincronizador (`MultiplayerSynchronizer` hijo directo) o algo de lo que lee
  `CompanyPackages` (`package_id`, `trap_definition`, `impact_absorption`), avisá: lo usa este camino.

Tests: `test_company_sealed_package` (nuevo), `test_company_root` (ampliado), `test_company_shared_table`
sin cambios.
