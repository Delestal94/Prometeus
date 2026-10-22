# 2026-10-22 · `package.gd`: el setter de `current_mount_path` ya no vacía un soporte de otra caja (D-0316.4)

Para Slatex. Un cambio chico en tu dominio, de paso con D-0316.4 (el conductor cliente frena su propia copia en
el portón del modo Empresa). Lo había marcado `auditor-red` en D-0316.2 (`revisar/D-0316.2.md`, "Pendiente").

## `do-not-drop/scripts/gameplay/package/package.gd`

- **Qué cambió:** el setter de `current_mount_path`, al dejar el soporte anterior (`current_mount`), le pone
  `occupied_by = null` **solo si `occupied_by` sigue siendo esta caja**. Antes lo vaciaba siempre.
- **Por qué:** en un cliente del modo Empresa la copia de una caja lejana se esconde y suelta el soporte donde
  estaba (`CompanyInterest._on_copy_hidden`, D-0316.2). Mientras está escondida, otra caja puede ocupar ese
  soporte. Cuando llegaba la actualización del host que sacaba la primera caja del soporte
  (`current_mount_path` vacío), el setter vaciaba el soporte aunque ahora fuera de la otra caja, y ese cliente
  creía que el lugar estaba libre (carteles, subir, cuidar carga).
- **Firmas:** ninguna cambia. Ni señales, ni RPC, ni lo que se replica.
- **Protocolo:** no cambia (`PROTOCOL_VERSION` sigue en 52). Es solo cómo cada peer aplica lo que ya llega.
- **En el host no cambia nada en la práctica:** `PackageHandling.release_mount()` sigue vaciando `occupied_by`
  a mano antes de borrar el camino, y `place_at()` deja el soporte viejo (que era de la caja) y toma el nuevo
  igual que antes.
- **Test:** `test_company_fleet` (`_check_rack_slot`): con el soporte tomado por otra cosa, la caja que sale de
  él (`current_mount_path = NodePath()`) no lo vacía; una caja que sale de un soporte que sigue siendo suyo, sí.

## Qué tenés que hacer

Nada, salvo que en tu rama tengas código que contaba con que el setter vaciara un soporte ajeno (no encontré
ninguno: los que escriben `occupied_by` son `package_mount_point.gd`, `package_handling.gd` y
`company_interest.gd`). Si tocás ese setter, mantené la condición `occupied_by == self`.
