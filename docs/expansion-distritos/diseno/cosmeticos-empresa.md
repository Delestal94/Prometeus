# Cosméticos de la empresa (D-0137)

> Lo construyen D-0437 (desbloqueo, elección, guardado y red) y D-1234 (cómo se ve en la flota). Parte de:
> [hitos.md](hitos.md) (los 10 cosméticos de recompensa), [critica-alcance.md](critica-alcance.md) P8 (queda el
> mínimo cosmético: D-0137, D-0437 y D-1234; el logo editable D-1828, los uniformes por rango D-1829 y la pantalla
> de personalización D-1925 están pospuestos), [flota.md](flota.md), [guardado.md](guardado.md) y
> [red-autoridad.md](red-autoridad.md). Revisado por `critico-diseno`.
> Decisión: [2026-10-22-cosmeticos-empresa.md](../../decisiones/2026-10-22-cosmeticos-empresa.md).

## 1. Para qué

Que la empresa se vea **propia** y que crecer se note en la calle: la flota que sale del galpón lleva la pintura,
la franja y el logo que eligió el grupo, y los empleados (D-1018) visten el uniforme de la casa. No cambia nada
del juego: ni manejo, ni carga, ni plata. Es una recompensa de hito que se ve desde el día en que se gana.

## 2. Reglas

1. **Cuatro ranuras de la empresa**, una elección cada una: **pintura**, **franja**, **logo** y **uniforme**. El
   trofeo del volcán no es una ranura: aparece solo (regla 9).
2. **Son de la empresa, no del perfil.** Lo desbloqueado sale de `CompanyState.milestones_done` (cada hito trae su
   recompensa `cosmetic`, [hitos.md](hitos.md)), sin una lista aparte que se pueda desincronizar: dos empresas del
   mismo jugador tienen cada una lo suyo. Los cosméticos del perfil (`UnlockManager`: caras, peinados,
   accesorios, uniformes y pinturas de Partida rápida) siguen siendo del jugador y no se mezclan.
3. **Elige el host**, como construir el galpón ([2026-10-18-construccion-solo-host.md](../../decisiones/2026-10-18-construccion-solo-host.md))
   y comprar en la tienda. En un cliente los botones "Cambiar" están apagados y se ve la línea de la tienda
   `UI_SHOP_HOST_ONLY`; el chequeo de la petición igual rechaza con `host_only` antes que nada.
4. **Se elige en el cierre (`SUMMARY`), en la tienda** (`CompanyShopPanel`, D-0511.2): debajo de los ítems, un
   bloque **Empresa** con 4 filas, una por ranura. Cada fila muestra lo elegido (muestra de color o el logo, 48 px)
   y un botón "Cambiar" que pasa al siguiente desbloqueado de esa ranura (con vuelta al primero). Lo bloqueado se
   lista en gris en la misma fila ("Se gana con: Manos limpias"). El foco sigue en la misma columna vertical de la
   tienda (teclado y mando sin cambios). La petición no mira la fase, como `shop_buy` ([red-autoridad.md](red-autoridad.md)
   §13): la pantalla solo existe en el cierre. Gratis. No hay pantalla nueva (D-1925 sigue pospuesta).
5. **Se aplica enseguida** a toda la flota y a los empleados (en `SUMMARY` no queda ninguna salida afuera, S3).
6. **Lo que hay desde el día 1**: pintura **De fábrica** (cada vehículo con su color de fábrica, como hoy), franja
   **Ninguna**, logo **Inicial** (la primera letra del nombre de la empresa en un círculo; sin nombre, una caja) y
   uniforme **Gris de galpón**.
7. **El uniforme de la empresa lo visten solo los empleados** (D-1018). Los jugadores siguen con su vestuario del
   perfil: el jugador es un gel cuyo "uniforme" es un tono de borde (`player_appearance.gd`), el color de equipo
   (`team_color`, N-226) es lo que los distingue de lejos, y guardar algo de la empresa en el perfil rompería la
   regla 2. Los uniformes son un color por pieza del modelo del empleado; el mameluco es el mismo color en las dos
   piezas si el modelo las separa, y si no, un color más.
8. **Logo sin editor**: se elige de una lista cerrada (regla 6 y `logo_pack`). Nada de dibujar ni subir imágenes
   (D-1828 pospuesta; además no hay nada que moderar en un lobby público).
9. **Trofeo del volcán**: con `volcan_6` en `milestones_done` aparece una copa de lava en un lugar fijo del galpón,
   al lado de la entrada. Es un nodo que se muestra o no, no una pieza del modo construcción (la decoración, D-0922,
   está pospuesta) y no depende del tablero de hitos (D-0410).

## 3. Los 10 cosméticos y el resto de cada ranura

| Recompensa (`cosmetic`) | Ranura | Hito (#) | Qué abre |
|---|---|---|---|
| `paint_cream` | pintura | Manos limpias (4) | Crema `#F0D58C` (más cargada que el blanco de base y la crema de la vieja, para que se note) |
| `logo_pack` | logo | Marca conocida (13) | 6 logos: `logo_box`, `logo_arrow`, `logo_wing`, `logo_road`, `logo_star`, `logo_leaf` |
| `livery_stripes` | franja | Diez días sin roturas (17) | Una franja horizontal ancha a lo largo del costado |
| `uniform_blue` | uniforme | Empresa mediana (21) | Azul `#3F6FB5` |
| `uniform_orange` | uniforme | Plantel completo (23) | Naranja de seguridad `#F08A24` |
| `paint_gold` | pintura | Logística seria (24) | Dorado `#C9A23A`, color plano (la carrocería no tiene metálico y no se suma por esto) |
| `livery_premium` | franja | Centro logístico (25) | Franja doble fina |
| `uniform_overalls` | uniforme | Galpón en marcha (27) | Mameluco verde petróleo `#2F6B66` (regla 7) |
| `volcano_trophy` | — | Domador del volcán (29) | La copa del galpón (regla 9) |
| `paint_national` | pintura | Logística Nacional (30) | Azul noche `#1E2A4A`, plano: la flota del final |

De base (regla 6): `paint_factory`, `livery_none`, `logo_initial` y `uniform_shed` (gris `#8A8F96`). Elegibles con
todo ganado: **18** (4 pinturas, 3 franjas, 7 logos y 4 uniformes).

- **La pintura cambia solo la carrocería.** La moldura (`DT_Blue` en `reference_truck.gd`) sigue siendo la de cada
  camioneta con cualquier pintura: es lo que le dice al conductor cuál es la ágil y cuál la manual.
- **Color de franja y logo**: blanco si la luminancia de la carrocería es menor a 0,5; si no, gris `#2B2F36`. Con
  De fábrica cada vehículo lo calcula con su propio color.

## 4. Dónde se ve en cada vehículo (D-1234)

| Vehículo ([flota.md](flota.md)) | Pintura | Franja | Logo |
|---|---|---|---|
| Camionetas (`van_classic`, `van_agile`, `van_vintage`) y `offroad` | carrocería | costados de la caja de carga | los dos costados de la caja de carga |
| `bike` | cuadro | — | la caja de reparto |
| `cart` | chasis | — | los dos costados de la caja |
| `boat` | casco | costados del casco | proa, los dos lados |
| `plane` | fuselaje | fuselaje | cola, los dos lados |

- **Nada sobre piezas que se mueven**: las puertas de la cabina giran y atrás hay rampa; franja y logo van en
  paneles fijos.
- **Sin `Decal`** (GL Compatibility no los dibuja): franja y logo son mallas finas hijas del vehículo, sin
  colisión, a 1 cm de la carrocería, con material sin luz y recorte por alfa (`alpha scissor`), no transparencia:
  sin problemas de orden ni parpadeo a 30 m.
- **Pintura**: `vehicle.gd` suma un color de empresa **local, que no se replica** (`company_body: Color`;
  transparente = ninguno). `_apply_paint()` lo usa antes que `PAINTS`. Lo escribe `CompanyFleet` al crear cada
  vehículo (`_make`) y al aplicar `cosmetics_set` o `company_state_restored`. En Empresa `paint_id` queda en `white`
  (su setter solo acepta las claves de `PAINTS`, y se replica: un color puesto por ahí se perdería con un join
  tardío). La tabla de colores de la empresa vive en el catálogo de datos (§5), no en `vehicle.gd PAINTS`.
- Un vehículo nuevo de la flota (guía de contenido, D-0244) declara en su escena dónde van franja y logo
  (`LiveryAnchor`, `LogoAnchor*`); sin anclas, solo se pinta.

## 5. Datos, guardado y red (D-0437)

- **Catálogo**: un `.tres` por elegible en `data/cosmetics/`, **18** (`CosmeticDefinition`: `id`, `slot`,
  `title_key`, `color`, `texture` opcional para logos y franjas, `unlocked_by`). `unlocked_by` es el id de la
  recompensa `cosmetic` de [hitos.md](hitos.md) que lo abre (vacío = de base); los 6 logos llevan `logo_pack`.
  `volcano_trophy` no es un `.tres`: D-1234 lo lee de `milestones_done`. El validador (D-0245) comprueba ids únicos,
  ranura válida, una base por ranura y que cada recompensa `cosmetic` de los hitos (salvo `volcano_trophy`) abra al
  menos un `.tres`.
- **Desbloqueado** = de base, o su `unlocked_by` es recompensa de un hito de `milestones_done`.
  `CompanyCosmetics` es una clase estática (`CompanyState` no lee otros autoloads); nunca se guarda la lista.
- **Elegido**: `CompanyState.cosmetics: Dictionary` `{paint, livery, logo, uniform}` → id, guardado con la empresa.
  Clave nueva con valor por defecto al cargar un save viejo: no sube la versión ([guardado.md](guardado.md) §5).
  En `from_dict`, después de `milestones_done`, un id bloqueado o inexistente vuelve al de base de su ranura. Un
  cambio en `SUMMARY` entra al guardado al salir, igual que una compra.
- **Red**: ayudante propio `CompanyCosmeticsNet`, como `CompanyShopNet` (`company_net.gd` está al borde de las
  1000 líneas de gdlint: D-0437 saca líneas de ahí antes de sumar el tipo). Petición `cosmetic_set {slot, id, rid}`;
  chequeo: `host_only` primero, ranura de las cuatro, id de esa ranura y desbloqueado. Evento `cosmetics_set
  {paint, livery, logo, uniform}` con el diccionario entero (aplicarlo dos veces no cambia nada). No es crítica
  (regla 8 de red-autoridad). Al aplicarlo, el cliente valida (regla 6): exactamente 4 claves, cada id de su ranura
  y desbloqueado en su copia; si no, espera un snapshot. El que entra tarde lo trae en el snapshot. Suma su fila en
  red-autoridad §2 y su sección de "Lo construido". `PROTOCOL_VERSION` según `docs/convenciones-godot.md` §6.
- **Repintar**: `CompanyFleet`, los empleados y la copa escuchan `cosmetics_set` **y** `company_state_restored`
  (aplicar un snapshot no dispara las señales de cada cambio).
- **Aviso al ganarlo**: la línea del hito en el cierre ya nombra la recompensa; el texto es `title_key`
  (`UI_COSMETIC_<ID>` en `strings_ui.csv`, es y en; para `logo_pack`, "Paquete de logos").

## 6. Arte

Se pide en `arte-pendiente/` cuando se construya D-0437/D-1234; hasta entonces, placeholders por código:

| Asset | Placeholder |
|---|---|
| 6 logos del pack, 256×256 con alfa, silueta de un color | formas primitivas dibujadas en una `Image` por código |
| Logo Inicial | `Label3D` con la letra sobre un disco |
| Franja premium | dos tiras de caja de color plano |
| Copa del volcán (≤ 800 tris) | `CylinderMesh` naranja sobre un `BoxMesh` |

## 7. Qué NO

- Logo dibujado o subido por el jugador, uniformes por rango, pantalla de personalización propia (pospuestos, P8).
- Uniforme de la empresa en los jugadores (regla 7).
- Pintura distinta por vehículo: una sola para toda la flota (se lee como "la empresa").
- Cosméticos comprables con plata del juego: la plata es para crecer; los cosméticos son de hitos.
- Cosméticos del modo Empresa que pasen al perfil o a Partida rápida (ni al revés). Los logros de Steam (D-0138)
  van por otro lado.
- Efectos de juego de cualquier cosmético.

## 8. Qué construye cada tarea

| Tarea | Qué | Test |
|---|---|---|
| D-0437 | `CosmeticDefinition` y los 18 `.tres`; `CompanyCosmetics` (desbloqueados, base, validar); `CompanyState.cosmetics` con guardado; `CompanyCosmeticsNet`; bloque Empresa en `CompanyShopPanel` | `test_company_cosmetics` |
| D-1234 | Color de empresa en `vehicle.gd` y `CompanyFleet`; franja y logo en las camionetas (4x4, bici, carrito, lancha y avioneta cuando existan sus escenas); la copa del volcán | `test_company_livery` + captura con `revisor-visual` |
| D-1018 | Los empleados visten `cosmetics.uniform` | el suyo |
