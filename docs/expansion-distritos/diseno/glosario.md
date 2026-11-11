# Glosario del modo Empresa (D-0129)

Una palabra por concepto en los textos de la expansión, en español (rioplatense, como el resto del
juego) y en inglés. Amplía `docs/glosario.md` (vehículo, caja, paquete, anfitrión), que sigue mandando
para lo que ya existía. Lo usan quien escribe claves nuevas en `translations/strings_ui.csv` /
`strings_world.csv` (y las líneas que viajan con `LocText`) y el agente `localizador`.

`test_ui_translations` (`_check_company_glossary`) lo comprueba sobre las tablas: si el español usa el
término de la columna ES, el inglés tiene que usar el de la columna EN; y los términos descartados no
pueden aparecer. Cada fila con "Test: sí" está en ese chequeo.

Se armó con lo que ya dicen las tablas (2026-10-22): donde había una sola forma en uso, esa quedó.

## Términos

| Concepto | ES | EN | Uso | Descartado | Test |
|---|---|---|---|---|---|
| El encargo de un cliente | pedido | order | Lo que entra al tablero, se arma y se entrega (`OrderBook`). "Hoja de pedido" / "Order sheet" en la mesa. | orden (de compra), encargo | sí |
| La compra de mercadería | pedido al proveedor | supplier order | Siempre con "al proveedor" la primera vez en una pantalla, para no confundirlo con el pedido del cliente. | orden de compra, purchase order | — |
| Quien vende la mercadería | proveedor | supplier | `SupplierDefinition`, "Distribuidora Central". | vendor, distribuidor (como término genérico) | sí |
| Quien recibe el paquete | cliente | customer | El vecino que hizo el pedido. "Client" queda solo para el rol de red (`HUD_NET_STATS_ROLE_CLIENT`). | client (para el comprador) | — |
| El papel que llega con el palet | remito | delivery note | Lo que se controla al recibir (`DeliveryNote`, D-0614): llegaron X de Y. | albarán, packing slip, factura | sí |
| La unidad de carga del proveedor | palet | pallet | Se descarga con la zorra y se cobra al recibirlo. | tarima, pallet (en español) | sí |
| La herramienta para mover palets | zorra | pallet jack | La del galpón (D-0103). El autoelevador del depósito es otra cosa. | transpaleta, carretilla, forklift (para la zorra) | sí |
| El vehículo con horquillas del depósito | autoelevador | forklift | Solo el del depósito de Partida rápida. | montacargas, clark | — |
| Las unidades que hay | stock | stock | "%d unidades en stock", tablero de stock. | existencias, inventario (en textos; `Inventory` es el nombre del código) | sí |
| Lo que se compra y se vende | mercadería | goods | En plural de productos, "productos" / "products". | — | — |
| El edificio de la empresa | galpón | shed | Donde se recibe, se guarda y se arma. | depósito (para el galpón), almacén, warehouse | sí |
| El hub de Partida rápida | depósito | depot | El del juego actual; nunca para el galpón. | — | — |
| Donde se guarda la mercadería | estante | shelf | En el galpón y en el depósito. Los del camión son "anaquel" / "rack". | góndola | — |
| Donde se arma la caja | mesa de armado | packing table | Un jugador o empleado por mesa. | estación de armado, puesto | sí |
| Puesto automático o asignado (F2) | estación | station | Para la automatización y los empleados (grupo 11). En la ruta es siempre "estación de servicio" / "service station". | puesto, workstation | — |
| Lo que va adentro alrededor del producto | relleno | filler | "Acolchado" / "padding" es otro insumo: el de los estantes del camión. | — | sí |
| Lo que cierra la caja | cinta | tape | "Cinta de embalar" / "packing tape" en textos largos. | precinto | — |
| Lo que dice a quién va | etiqueta | label | — | rótulo | sí |
| Marca especial de la caja | sello | stamp | "Frágil", "Este lado arriba"… | — | — |
| La unidad de juego de 08:00 a 20:00 | día | day | "Día %d", "Cierre del día". "Jornada" solo en boca de la Jefa o del diario. | turno (para el día) | — |
| El tramo de horario de un empleado (F2) | turno | shift | Solo para empleados: "turno mañana". | — | — |
| El paso de fin de día | cierre del día | day closing | La pantalla de plata y el guardado. | balance, liquidación | — |
| La persona contratada | empleado | employee | "Empleado novato / normal / experto". "Personal" / "staff" como grupo. | trabajador, operario, worker | sí |
| Lo que se paga a un empleado | sueldo | wage | Por día. | salario, jornal, salary | — |
| Lo que se paga por el galpón | alquiler | rent | Por día (`RENT_PER_DAY`). | — | — |
| La plata de todos | plata | money | En la UI y en voz de los personajes; "Caja del equipo" / "Team cash" es el saldo. | dinero (en textos nuevos) | — |
| Lo que se logra para avanzar | hito | milestone | Los 30 de `diseno/hitos.md`. | meta, objetivo, logro (para el hito) | sí |
| Lo de Steam | logro | achievement | Solo los de Steam (D-0138). | trofeo | — |
| El permiso para un vehículo o zona | licencia | license | Náutica, de vuelo, 4x4… (`diseno/hitos.md`). | carnet, permiso, licence | sí |
| La empresa del jugador | empresa | company | "Modo Empresa" / "Company mode" como nombre propio. | negocio, firma | sí |
| Cada parte del mapa | zona | zone | Nombre de jugador para los distritos (`DistrictDefinition`); "barrio" solo dentro del nombre ("Barrio Centro"). | distrito (en textos), district | — |
| Todos los vehículos de la empresa | flota | fleet | — | — | — |
| La que manda | la Jefa | the Boss | Sin cara (`diseno/narrativa-empresa.md`). | el jefe, gerente | — |

## Para el que escribe un texto

1. Buscá el concepto acá antes de elegir la palabra. Si no está, usá la palabra que ya dicen las
   tablas (`grep -i` en los dos CSV) y sumá la fila en el mismo PR.
2. Si un texto necesita la palabra descartada a propósito (un chiste, un cliente que habla raro),
   no lo hagas: el test no distingue intenciones. Reformulá.
3. Los nombres del código (`Inventory`, `DeliveryNote`, `OrderBook`) no son texto de pantalla: pueden
   seguir en inglés técnico aunque el texto diga otra cosa.
