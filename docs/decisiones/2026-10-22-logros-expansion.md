# Logros de Steam de la expansión (D-0138) — 2026-10-22

## Decisión
La lista está en `docs/marketing/logros-expansion.md`; la construye D-0440.
- **30 logros `EXP_`**: 13 de progreso (entregar en cada zona, flota completa, campaña), 9 de habilidad coop y 8
  graciosos. **5 ocultos.** Los 15 del juego actual (S-907) usan `BASE_`.
- **Logros de equipo**: los decide el host y los reciben todos los peers presentes (también el que se quedó en el
  galpón), por un hecho `achievement_earned` de `CompanyNet`; cada peer desbloquea en su propio Steam. El que entra
  tarde no recibe lo anterior (un snapshot no dispara hechos).
- **Todos alcanzables con 1 y con 8 jugadores**, ninguno perdible, techo de conteo 100 entregas. Los modificadores
  de dificultad no bloquean; las banderas de desarrollo sí.
- **Dos stats del jugador** (`EXP_STAT_DELIVERIES` 0/100, `EXP_STAT_ZONES` 0/8), no de la empresa.
- **Íconos**: uno por logro desde la sesión de arte; la versión bloqueada en gris sale por código.

## Por qué
Steam solo deja desbloquear logros del usuario local, así que el único camino es que el host avise y cada cliente
lo haga. Logros de progreso que piden *entregar* y no *abrir* una zona no se pueden comprar. Pocos ocultos dejan
que la lista de la página de Steam venda el juego.

## Alternativas descartadas
- Copiar los 30 hitos como logros: duplica lo que el juego ya muestra y no vende nada.
- Los 8 ocultos de D-0421: esconden demasiado de la lista pública.
- Dar al que entra tarde lo que la empresa ya logró: regala logros y necesita un caso aparte en el snapshot.
- Logros de lo recortado o pospuesto (rival, sabotaje, clientes recurrentes, mercado de proveedores).
