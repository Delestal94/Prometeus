# D-2002.4: ritmos de envío del modo Empresa (camioneta, sentados, care_state, keepalive)

Tocado en archivos del dominio de Slatex y en zona compartida (`modules/`). **Protocolo: no cambia** (ni RPC ni
propiedades replicadas ni modos; solo cada cuánto manda el dueño y una meta local). Decisión:
[`decisiones/2026-10-22-palancas-ancho-de-banda-salidas.md`](../decisiones/2026-10-22-palancas-ancho-de-banda-salidas.md).

- `scripts/gameplay/player/player_ride.gd` (Slatex): nueva `set_seated_pose_rate(p, rate_hz)` (meta
  `seated_pose_rate`); `apply_pose_rate()` usa ese ritmo sentado si un mundo lo pidió. Sin pedirlo (Reparto,
  Infinito) todo sigue igual: sentado o a bordo, el de `player.tscn`.
- `scripts/gameplay/package/package_rescue.gd` (Slatex): nuevas `CARE_PUBLISH_SEC` (0,1, el de siempre),
  `CARE_PUBLISH_META` y `care_publish_interval(p)`; el publish de `care_state` y el aviso de amortiguado leen el
  intervalo de ahí. Solo cambia para una caja con la meta `care_publish_sec` (las de la empresa,
  `BoxToPackage.tune()`: 0,2 s).
- `package_rescue.gd` / `package.gd` (Slatex, después de `auditor-red`): `_publish_cushion_change()` pasó a
  `_publish_hand_change()` con la nueva `PackageRescue.care_signature(behavior)`: además del amortiguado, un paso
  de secuencia (índice, errores, resuelto: bomba, peso creciente) y el lado del empuje de un gesto (equilibrio,
  líquido) publican `care_state` en el próximo tick y no esperan el intervalo. `_cushion_signature` guarda esa
  firma (solo cambió su comentario). `test_company_care_publish`.
- `modules/net_pose_smoother/net_rest_throttle.gd` (compartido): `NetRestThrottle` ya no se despierta cuando el
  sincronizador se oculta a un peer (bandera apagada y no público) ni cuando cambia la visibilidad con la meta
  `QUIET_META` (`net_rest_quiet`) puesta. Mostrarlo a un peer de verdad (join tardío) lo despierta como antes.
- `modules/world_cells/cell_interest.gd` (compartido): nueva `WorldCellInterest.pulse_visibility(sync, peer,
  show)` y `QUIET_META`; los pulsos de keepalive la usan, así no despiertan los cuerpos quietos. Un peer que se
  acerca durante un pulso recibe otra vez `update_visibility(peer)` sin la meta (para que despierte).
- Juego de Nacho: `CompanyFleet._make()` pone la camioneta en `CompanyTuning.FLEET_POSE_INTERVAL_SEC` (0,03 s);
  `CompanyRoot.join_crew()` pide `SEATED_POSE_RATE_HZ` (15).
