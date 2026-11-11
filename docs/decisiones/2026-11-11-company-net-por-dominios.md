# `CompanyNet` enruta por dominio y `CompanyRoot` reparte en piezas (D-0254)

**Decisión:** al partir `company_net.gd` y `company_root.gd` no alcanzaba con bajar líneas: cada dominio de la red de la
empresa declara sus propios `kind` (`REQUEST_KINDS`, `EVENT_KINDS`, `HOST_EVENT_KINDS`, `CRITICAL_KINDS`) y `CompanyNet`
los suma y manda cada petición o evento a la rama de su dominio, sin rama para "lo demás". Del root salieron la
tripulación (`CompanyCrew`), el fondo (`CompanyBackdrop`) y el uso de piezas (`ShedUse`); el guardado del día se queda.

**Por qué:**

- Después de esto vienen cinco o seis PRs en paralelo que suman cada uno un `kind` (la puerta, abrir el palet, la mesa,
  `order_packed`, el estado del remolque). Con las listas y el `match` en `CompanyNet` todos editaban las mismas líneas
  y chocaban entre sí. Ahora un `kind` nuevo de un dominio que ya existe toca solo ese dominio.
- El protocolo no cambia: los RPC van por nombre de método y los cuatro `@rpc` siguen iguales; los `kind` viajan como
  texto y las listas son los mismos conjuntos (lo comprueba `test_company_net_domains`).
- El guardado del día (`save_closed_day()` y compañía) no se movió: el root ya baja a 692 líneas y esas funciones leen
  `_hosted_state`, que tres tests tocan directo. Moverlas sumaba reenvíos sin bajar riesgo.
- `test_company_layout_net` y `test_company_shed_expand_net` leían las ramas `match` de `_apply_state()` y se adaptaron a
  las ramas por dominio. Siguen pidiendo lo mismo: cada `kind` en una sola rama y nada que caiga en la de otro.
- `test_company_net_domains` falla si `company_net.gd` o `company_root.gd` vuelven a pasar de 850 líneas, para que el
  margen no se gaste en silencio hasta el tope de 1000 del lint.

**Cómo volver atrás:** las piezas nuevas no guardan estado propio que viaje ni nada que se guarde en disco; juntar todo de
nuevo en los dos archivos es mover código, sin migración.
