# Cosméticos de la empresa (D-0137)

> Lo construyen D-0437 (desbloqueo, elección, guardado y red) y D-1234 (cómo se ve en la flota). Parte de:
> [hitos.md](hitos.md) (los 10 cosméticos de recompensa), [critica-alcance.md](critica-alcance.md) P8 (queda el
> mínimo cosmético: D-0137, D-0437 y D-1234; el logo editable D-1828, los uniformes por rango D-1829 y la pantalla
> de personalización D-1925 están pospuestos), [flota.md](flota.md), [guardado.md](guardado.md) y
> [red-autoridad.md](red-autoridad.md).
> Decisión: [2026-10-22-cosmeticos-empresa.md](../../decisiones/2026-10-22-cosmeticos-empresa.md).

## 1. Para qué

Que la empresa se vea **propia** y que crecer se note en la calle: la flota que sale del galpón lleva la pintura,
la franja y el logo que el grupo eligió, y los empleados (D-1018) visten el uniforme de la casa. No cambia nada
del juego: ni manejo, ni carga, ni plata. Es una recompensa de hito que se ve desde el primer día que se gana.

## 2. Reglas

1. **Cuatro ranuras de la empresa**, una elección cada una: **pintura**, **franja**, **logo** y **uniforme**. El
   trofeo del volcán no es una ranura: aparece solo (regla 9).
2. **Son de la empresa, no del perfil.** Lo desbloqueado sale de `CompanyState.milestones_done` (el hito trae su
   recompensa `cosmetic`, [hitos.md](hitos.md)), sin una lista aparte que se pueda desincronizar: dos empresas del
   mismo jugador tienen cada una lo suyo. Los cosméticos del perfil (`UnlockManager`: caras, peinados,
   accesorios, uniformes y pinturas de Partida rápida) siguen siendo del jugador y no se mezclan.
3. **Elige el host**, como construir el galpón ([2026-10-18-construccion-solo-host.md](../../decisiones/2026-10-18-construccion-solo-host.md))
   y cerrar el día: es quien abre la empresa y la guarda. Un cliente ve las ranuras sin poder tocarlas, con el
   texto "Lo elige el host".
4. **Gratis y cuando se quiera fuera de la calle**: en `OPENING` y `SUMMARY`, la pestaña **Empresa** de la tienda
   del cierre (`CompanyShopPanel`, D-0511.2) muestra las cuatro ranuras con tarjetas (las mismas `CustomizeSwatch`
   de `CosmeticsPanel`). No hay pantalla nueva (D-1925 sigue pospuesta). Lo bloqueado se ve en gris con el hito que
   lo da ("Se gana con: Manos limpias"), como las tarjetas del perfil.
5. **Se aplica enseguida** a todos los vehículos de la empresa que están en el galpón o en la dársena y a los
   empleados; un vehículo afuera lo toma al volver (no se repinta en la ruta).
6. **Lo que hay desde el día 1**: pintura **De fábrica** (cada vehículo con su color de fábrica, como hoy), franja
   **Ninguna**, logo **Inicial** (la primera letra del nombre de la empresa en un círculo; si no tiene nombre, una
   caja) y uniforme **Gris de galpón**.
7. **El uniforme de la empresa es opcional para los jugadores.** Los empleados lo llevan siempre. Cada jugador lo
   puede elegir en el vestuario (`CosmeticsPanel`, pestaña Uniforme) como una tarjeta más, "Uniforme de la
   empresa", que solo aparece en el modo Empresa. **No es el valor por defecto**: el color del equipo
   (`team_color`, N-226) sigue siendo lo que distingue a cada uno de lejos, y ocho jugadores del mismo color no se
   reconocen.
8. **Logo sin editor**: se elige de una lista cerrada (regla 6 y `logo_pack`). Nada de dibujar o subir imágenes
   (D-1828 pospuesta; además evita moderar lo que se ve en un lobby público).
9. **Trofeo del volcán**: con el hito 29 aparece una copa de lava sobre el tablero de hitos del galpón (D-0410). Es
   decorado fijo, no una pieza del modo construcción (la decoración, D-0922, está pospuesta).

## 3. Los 10 cosméticos y el resto de cada ranura

| id | Ranura | Hito (#) | Qué es |
|---|---|---|---|
| `paint_cream` | pintura | Manos limpias (4) | Crema `#E8DCC0`, la primera que se gana |
| `logo_pack` | logo | Marca conocida (13) | Abre 6 logos: caja, flecha, ala, ruta, estrella y hoja |
| `livery_stripes` | franja | Diez días sin roturas (17) | Una franja horizontal ancha a lo largo del costado, en el color del logo |
| `uniform_blue` | uniforme | Empresa mediana (21) | Azul `#3F6FB5` |
| `uniform_orange` | uniforme | Plantel completo (23) | Naranja de seguridad `#F08A24` |
| `paint_gold` | pintura | Logística seria (24) | Dorado `#C9A23A`, color plano (la carrocería no tiene metálico hoy; no se suma solo por esto) |
| `livery_premium` | franja | Centro logístico (25) | Franja doble fina con filete dorado |
| `uniform_overalls` | uniforme | Galpón en marcha (27) | Mameluco: pantalón y remera del mismo verde petróleo `#2F6B66`, sin modelo nuevo (color de las dos piezas) |
| `volcano_trophy` | — | Domador del volcán (29) | Copa sobre el tablero de hitos (regla 9) |
| `paint_national` | pintura | Logística Nacional (30) | Azul noche `#1E2A4A` con techo blanco: la flota del final |

Lo de la regla 6 completa cada ranura: pintura De fábrica, franja Ninguna, logo Inicial, uniforme Gris de galpón
(`#8A8F96`). Con todo ganado: 4 pinturas, 3 franjas, 7 logos y 4 uniformes. Colores elegidos para que la franja y
el logo (siempre blancos sobre pinturas oscuras, gris oscuro `#2B2F36` sobre claras) se lean a 30 m.

Los ids de cosmético usan el prefijo de su ranura (`paint_`, `livery_`, `logo_`, `uniform_`); los 6 logos del pack
son `logo_box`, `logo_arrow`, `logo_wing`, `logo_road`, `logo_star` y `logo_leaf`, y los de la regla 6 son
`paint_factory`, `livery_none`, `logo_initial` y `uniform_shed`.

## 4. Dónde se ve en cada vehículo (D-1234)

| Vehículo ([flota.md](flota.md)) | Pintura | Franja | Logo |
|---|---|---|---|
| Camionetas (`van_classic`, `van_agile`, `van_vintage`) y `offroad` | carrocería (la vintage conserva su moldura) | costados | las dos puertas delanteras y la puerta trasera |
| `bike` | cuadro | — | la caja de reparto |
| `cart` | chasis | — | los dos costados de la caja |
| `boat` | casco | costados del casco | proa, los dos lados |
| `plane` | fuselaje | fuselaje | cola, los dos lados |

- **Sin `Decal`**: el renderer GL Compatibility no los dibuja. El logo y la franja son mallas finas (un `QuadMesh`
  con textura y alfa, o una tira de caja) pegadas a la carrocería a 2-3 mm, hijas del vehículo y sin colisión.
- La pintura es el mismo camino que `vehicle.gd` `paint_id` ya usa en Partida rápida: el color de carrocería. La
  tabla de colores de la empresa vive en un catálogo de datos, no en `vehicle.gd PAINTS` (esa queda para el perfil).
- Un vehículo nuevo de la flota (D-0244, guía de contenido) declara en su escena los nodos donde van franja y logo
  (`LiveryAnchor`, `LogoAnchor*`); sin anclas, solo se pinta.

## 5. Datos, guardado y red (D-0437)

- **Catálogo**: un `.tres` por cosmético en `data/cosmetics/` (`CosmeticDefinition`: `id`, `slot`,
  `title_key`, `color`, `texture` opcional para logos y franjas, `milestone` que lo da o vacío si es de base). El
  validador de recursos (D-0245) comprueba ids únicos, ranura válida y que cada id `cosmetic` de los hitos exista.
- **Desbloqueados**: `CompanyCosmetics.unlocked(milestones_done)`, derivado; nunca se guarda.
- **Elegido**: `CompanyState.cosmetics: Dictionary` `{paint, livery, logo, uniform}` → id. Se guarda con la empresa
  (clave nueva con valor por defecto al cargar un save viejo: no pide migración). Un id bloqueado o que no existe
  al cargar vuelve al de base de su ranura.
- **Red**: solo el host escribe. Petición `company_cosmetic` `{slot, id, rid}` del host a sí mismo por el mismo
  camino de la tienda (`CompanyShopNet`), validada: fase `OPENING`/`SUMMARY`, ranura de las cuatro, id de esa ranura
  y desbloqueado. Los clientes reciben `cosmetics` en el snapshot de la empresa y un evento `company_cosmetics` con
  el diccionario entero (4 ids, menos de 100 bytes) cuando cambia. El que entra tarde lo trae en el snapshot.
- **El uniforme de cada jugador** (regla 7) es elección local guardada en su perfil como `uniform_company` y
  replicada como hoy se replica el uniforme (`player.gd`); el color lo resuelve cada peer con el `cosmetics` de la
  empresa, así un cambio del host le llega a todos los que lo eligieron sin otra petición.
- **Aviso al ganarlo**: la línea del hito en el cierre ya nombra la recompensa; el texto es `title_key` del
  cosmético (`UI_COSMETIC_<ID>` en `strings_ui.csv`, es y en).

## 6. Arte

Se pide desde D-0437/D-1234 en `arte-pendiente/` cuando se construyan; hasta entonces, placeholders por código:

| Asset | Placeholder |
|---|---|
| 6 logos del pack, 256×256 con alfa, silueta de un color | formas primitivas dibujadas en una `Image` por código (cuadrado, triángulo, etc.) |
| Logo Inicial | `Label3D` con la letra sobre un disco |
| Textura de franja premium (tira con filete) | dos tiras de caja de colores planos |
| Copa del volcán (≤ 800 tris) | `CylinderMesh` naranja sobre un `BoxMesh` |

## 7. Qué NO

- Logo dibujado o subido por el jugador, uniformes por rango, pantalla de personalización propia (pospuestos, P8).
- Pintura distinta por vehículo: una sola pintura para toda la flota (se lee como "la empresa", y son 4 opciones).
- Cosméticos comprables con plata del juego: la plata es para crecer; los cosméticos son de hitos.
- Cosméticos del modo Empresa que pasen al perfil o a Partida rápida (ni al revés): lo de Steam (logros, D-0138)
  va por otro lado.
- Efectos de juego de cualquier cosmético.

## 8. Qué construye cada tarea

| Tarea | Qué | Test |
|---|---|---|
| D-0437 | `CosmeticDefinition` y los 14 `.tres`; `CompanyCosmetics` (desbloqueados, base, validar); `CompanyState.cosmetics` con guardado; petición y evento de red; pestaña Empresa en `CompanyShopPanel`; tarjeta "Uniforme de la empresa" en el vestuario | `test_company_cosmetics` |
| D-1234 | Pintura, franja y logo en camionetas y 4x4 con anclas (bici, carrito, lancha y avioneta cuando existan sus escenas); copa del volcán en el tablero de hitos (cuando exista D-0410) | `test_company_livery` + captura con `revisor-visual` |
| D-1018 | Los empleados visten `cosmetics.uniform` | el suyo |
