# F2 · Grupo 08 — Pedidos de clientes (detalle)

> Carril 3 de la rutina `desarrollador`. Ampliación del grupo 08 que se construye de a una; el resto sigue en
> la tabla de [08-pedidos-de-clientes.md](../08-pedidos-de-clientes.md). Números de [supuestos.md](supuestos.md).

### D-0840 · Generador de nombres de clientes — B · Sonnet 5.5 · low · Aviso: no · F2
**[x] Hecho (2026-10-22, PR pendiente)** — `CustomerNames` (`scripts/gameplay/business/customer_names.gd`); `OrderGenerator` lo usa en lugar de la lista fija de 16 nombres; ampliado `test_order_generator`.
**Depende de:** D-0801 (`OrderGenerator`)
**Qué:** `class_name CustomerNames`, estático. 48 nombres y 32 apellidos que se leen igual en español e inglés = 1536 clientes distintos ("Marta Rojas"). `name_at(i)` (cualquier entero, da la vuelta), `count()` y `pick(rng)`, que usa **un solo** sorteo del generador del día para que el resto del día no se mueva.
Decisión: sin claves de traducción. El nombre es parte del pedido que sortea el host y todos muestran tal cual; si dependiera del idioma de cada peer, el mismo pedido se vería distinto en cada pantalla. "Localizado" se cumple con nombres que funcionan en es y en.
**Test** `test_order_generator` (`_test_customer_names`): al menos 1500 nombres, todos distintos, índice negativo da la vuelta, cada pedido de tres días lleva "Nombre Apellido" del pozo y se usan 20+ distintos.
**Hecho cuando:** la lista existe y el test pasa.
