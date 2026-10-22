# F2 · Grupo 12 — Flota: base común, garaje, bici y carrito (detalle)

> Tareas de F2 del grupo 12 que ya tienen detalle; el resto sigue en la tabla de
> [12-flota-bici-carrito.md](../12-flota-bici-carrito.md). Números de [supuestos.md](supuestos.md).

### D-1234 · Pintura y logo de la empresa en la flota — A · Sonnet 5.5 · medium · Aviso: no · F2
**Depende de:** D-0437 (`CompanyState.cosmetics`, `cosmetics_set`), D-0137 (diseño,
[cosmeticos-empresa.md](../diseno/cosmeticos-empresa.md) §4)
**Qué:** que la flota se vea con lo que eligió la empresa. Solo presentación: nada de esto se replica aparte.
- [ ] D-1234.1 `vehicle.gd`: `company_body: Color` local, no replicado (transparente = ninguno); `_apply_paint()` lo
  usa antes que `PAINTS` y solo para la carrocería (`DT_White`); la moldura (`DT_Blue`) sigue la de cada variante.
  En Empresa `paint_id` queda en `white`. Partida rápida no cambia (`test_reference_truck` verde).
- [ ] D-1234.2 Franja y logo en las camionetas: anclas fijas en los dos costados de la caja de carga (`LiveryAnchor`,
  `LogoAnchorL/R`), mallas finas a 1 cm, material sin luz con `alpha scissor`, sin colisión; color blanco si la
  luminancia de la carrocería es < 0,5 y `#2B2F36` si no. Logos del pack dibujados por código mientras no haya arte
  (pedido en `arte-pendiente/D-1234.md`: 6 logos 256×256 con alfa y la copa), Inicial con `Label3D`.
- [ ] D-1234.3 `CompanyFleet` aplica todo al crear cada vehículo (`_make`) y al recibir `cosmetics_set` o
  `company_state_restored`. La copa del volcán: nodo fijo al lado de la entrada del galpón, visible con `volcan_6`
  en `milestones_done`, con las mismas dos señales.
- [ ] D-1234.4 La 4x4, la bici, el carrito, la lancha y la avioneta suman sus anclas cuando existan sus escenas
  (cada una en su tarea; sin anclas, solo se pintan).
**Test** `test_company_livery`: con `paint_gold` la carrocería de las tres camionetas es `#C9A23A` y cada moldura la
de su variante; `paint_factory` deja el color de fábrica; con `livery_none` no hay franja y con `livery_stripes` sí;
el logo cambia de blanco a gris con una pintura clara; un `cosmetics_set` repinta la flota del galpón y un
`company_state_restored` también; la copa aparece solo con `volcan_6`.
**Hecho cuando:** el test pasa y una captura de `revisor-visual` muestra la flota con pintura, franja y logo
legibles en el galpón.
