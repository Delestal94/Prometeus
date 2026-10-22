# F2 · Grupo 08 — Pedidos de clientes (detalle)

> Carril 3 de la rutina `desarrollador`. Ampliación del grupo 08 que se construye de a una; el resto sigue en
> la tabla de [08-pedidos-de-clientes.md](../08-pedidos-de-clientes.md). Números de [supuestos.md](supuestos.md).

### D-0822 · Cartas y mensajes de clientes con pedidos raros y humor — C · Sonnet 5.5 · low · Aviso: no · F2
**[x] Hecho (2026-10-22, PR pendiente)** — las notas de `CustomerNote` pasan de 6 a 60 textos (48 comunes + 12 de regalo) en `strings_ui.csv` (es/en); `test_customer_note` ampliado.
**Depende de:** D-0731 (`CustomerNote`, `PackedBox.note_key`)
**Qué:** crecer la lista de notas del cliente de D-0731 a los 60 textos definitivos. Claves `UI_COMPANY_NOTE_1..48` y `UI_COMPANY_NOTE_GIFT_1..12`; `PLAIN_KEYS` y `GIFT_KEYS` las listan y `KEYS` es su suma (lo que `PackedBox.from_dict` acepta). Humor suave en argentino: perro suelto, timbre roto, suegra, tostadora que "no es una bomba". Sin cambios de lógica, de protocolo ni de snapshot: las cajas guardadas con las 6 claves de antes siguen cargando.
Decisión: las "cartas" son notas cortas (una línea) y no textos largos, porque van a la cara de la caja con el marcador (D-0731.b) y tienen que leerse de un vistazo. Decisión: 12 de regalo (20 %) porque solo los pedidos `gift` los usan, y esos son una minoría; con 12 no se repite una nota cada pocas cajas de regalo. Decisión: las notas se reparten por `String.hash` del id, igual que antes, para que todos los peers vean la misma sin red.
**Test** `test_customer_note`: hay 60 claves distintas, todas con texto en es y en (distintos entre sí), 1000 pedidos usan las 48 comunes y las 12 de regalo, y lo de D-0731 sigue verde.
**Hecho cuando:** los 60 textos existen y se traducen (el test pasa).
