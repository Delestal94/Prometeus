# 2026-10-21 · Hitos del modo Empresa (D-0118)

Decidido por la rutina desarrollador (carril 1), regla 3 del README de rutinas. Detalle completo en
[diseno/hitos.md](../expansion-distritos/diseno/hitos.md), sección "Decisiones".

- **Decisión: 30 hitos con ids estables** (`deliveries_25`, `reputation_60`, `deliveries_50` y los que ya
  guardan `data/gates/` no cambian) porque los bloqueos y la flota ya los nombran.
- **Decisión: Suburbio pide además un permiso de 1 200** porque la curva de D-0117 ya lo cobra el día 5-6.
- **Decisión: en Empresa F2 Campo arranca cerrado (reputación 60) y abre antes que Suburbio**; F1 lo deja
  abierto como dice el corte vertical.
- **Decisión: dos ramas paralelas (agua: Puerto → Islas; aire: Montaña → Nieve → Volcán)** porque el mapa
  continuo deja entrar a Montaña con la avioneta sin pasar por Islas.
- **Decisión: se suma el tipo de recompensa `shop_item`** (licencias, equipo, etapas del galpón,
  contratación) porque no entra en los siete tipos de D-0403.
- **Decisión: D-0413, D-0416, D-0417 y D-0418 quedan reescritas por la tabla** (primer empleado por plata,
  primera máquina por tener un empleado, 4x4 con `campo_25`, aeródromo y licencia de vuelo con Montaña).

Revisar al final: [revisar/D-0118.md](../expansion-distritos/revisar/D-0118.md).
