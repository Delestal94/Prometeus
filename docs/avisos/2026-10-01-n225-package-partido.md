# Aviso: `package.gd` partido por responsabilidad (N-225.4)

Archivos de Slatex: `scripts/gameplay/package/package.gd` (995 → 661 líneas) y tres nuevos en la misma carpeta.
Refactor puro: sin cambio de comportamiento, de RPC ni de `PROTOCOL_VERSION`.

- `package_handling.gd` (`PackageHandling`): llevar, pasar de mano, soltar, anclar en estante y entregar en la
  puerta (`take_by`, `place_at`, `consume`, `release_mount`…).
- `package_tending.gd` (`PackageTending`): entrada del que cuida la caja, ayudante y mérito.
- `package_impacts.gd` (`PackageImpacts`): golpes, choques entre cajas y con jugadores, reporte de daño.
- `DeliveryPackage` conserva todo su estado, los 10 `@rpc` (mismos nombres, modos y orden) y envoltorios para
  cada método que usan otros archivos o los tests: nada de afuera cambia de firma.
- Si agregás lógica nueva a la caja, va en el helper de su responsabilidad; `tests/test_package_split.gd`
  falla si `package.gd` pasa de 700 líneas o si cambia la tabla de RPC.

Qué hacer: `git pull` antes de tocar la caja.
