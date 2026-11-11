# F2 · Grupo 04 — Progresión e hitos (detalle)

> Tareas de F2 del grupo 04 que ya tienen detalle; el resto sigue en la tabla de
> [04-progresion-e-hitos.md](../04-progresion-e-hitos.md). Números de [supuestos.md](supuestos.md).

### D-0437 · Cosméticos de la empresa por hitos — A · Sonnet 5.5 · low · Aviso: no · F2
**Depende de:** D-0137 (diseño, [cosmeticos-empresa.md](../diseno/cosmeticos-empresa.md)), D-0403 (recompensa
`cosmetic`), D-0404 (`.tres` de hitos), D-0511.2 (`CompanyShopPanel`)
**Qué:** que los 10 cosméticos de los hitos se desbloqueen, el host elija los de la empresa en el cierre y todos
vean lo mismo. Cómo se ven en la flota es D-1234.
- [ ] D-0437.1 `CosmeticDefinition` (`Resource`: `id`, `slot` ∈ `paint`/`livery`/`logo`/`uniform`, `title_key`,
  `color`, `texture` opcional, `unlocked_by`) y los **18** `.tres` de `data/cosmetics/` con los colores e ids del §3
  del diseño. El validador de D-0245 suma: ids únicos, ranura válida, una base (`unlocked_by` vacío) por ranura, y
  cada recompensa `cosmetic` de `data/milestones/` (salvo `volcano_trophy`) abre al menos un `.tres`.
- [ ] D-0437.2 `CompanyCosmetics` (estática, `scripts/core/company/`): `unlocked(milestones_done, rewards)`,
  `base(slot)`, `sanitize(cosmetics, milestones_done)` (id bloqueado o inexistente → base de su ranura) y
  `next(slot, current, milestones_done)` (siguiente desbloqueado con vuelta).
- [ ] D-0437.3 `CompanyState.cosmetics` `{paint, livery, logo, uniform}` en `to_dict`/`from_dict`, saneado después
  de `milestones_done`; un save sin la clave carga las bases (sin subir la versión, `guardado.md` §5).
- [ ] D-0437.4 `CompanyCosmeticsNet` (ayudante como `CompanyShopNet`; antes, sacar líneas de `company_net.gd`, que
  está al borde de 1000): petición `cosmetic_set {slot, id, rid}` con chequeo `host_only` → ranura → id de esa ranura
  → desbloqueado; evento `cosmetics_set` con el diccionario entero, validado al aplicarlo (4 claves, ids de su
  ranura y desbloqueados en esa copia; si no, se espera un snapshot); viaja en el snapshot. Fila nueva en
  `red-autoridad.md` §2 y "Lo construido". `PROTOCOL_VERSION` según `docs/convenciones-godot.md` §6.
  `auditor-red` antes del PR.
- [ ] D-0437.5 Bloque **Empresa** en `CompanyShopPanel`: 4 filas (muestra de 48 px + "Cambiar"), bloqueados en gris
  con "Se gana con: <hito>", foco en la misma columna; en un cliente, botones apagados y `UI_SHOP_HOST_ONLY`.
  Claves `UI_COSMETIC_<ID>`, `UI_COMPANY_COSMETICS*` en `strings_ui.csv` (es y en). Captura con `revisor-visual`.
**Test** `test_company_cosmetics`: sin hitos solo las 4 bases; con `clean_hands` aparece `paint_cream` y con
`reputation_70` los 6 logos; `next` salta lo bloqueado y da la vuelta; un save con un id bloqueado carga la base;
un save viejo sin `cosmetics` carga las bases; la petición de un cliente da `host_only`, la de un id de otra ranura
o bloqueado se rechaza, la válida emite `cosmetics_set` y la copia del cliente queda igual a la del host; un evento
con 3 claves se descarta.
**Hecho cuando:** el test pasa, `test_expansion_resources` sigue verde con los 18 `.tres` y la tienda del cierre
muestra el bloque Empresa (captura).
