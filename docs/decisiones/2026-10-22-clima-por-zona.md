# Clima y temperatura por zona (D-0135) — 2026-10-22

## Decisión
El diseño está en `docs/expansion-distritos/diseno/distritos.md`, sección "Clima y temperatura por zona":
- **Dos capas**: la temperatura de la zona es fija (templada, fría en Nieve, caliente en Volcán) y el clima del
  día sale de la semilla.
- **Un clima por zona y por día**, constante todo el día, elegido por una función pura de semilla, día y zona.
  No se guarda y no necesita RPC.
- **Un frente compartido para el llano** (Parque Industrial, Centro, Suburbio, Campo, Puerto, Islas): una sola
  tirada con las probabilidades de hoy; donde el perfil no está permitido baja a `nublado`. Montaña, Nieve y
  Volcán tiran por separado.
- **Pronóstico a la apertura** (feed de la Jefa, tablero, portapapeles).
- **El clima no rompe cajas solo**: multiplica riesgos que ya existen. En F1 el único efecto nuevo es el agarre
  en lluvia (3,5 → 2,6 por `GripZones`); la niebla queda como hoy.
- **Volcán no tiene clima `calor`**: el calor es la temperatura de la zona; su clima variable es `ceniza`.
  En Nieve el perfil de nieve se llama `nevada` (para no confundirlo con el id de la zona).
- **Entrega y Endless no cambian**: el clima sigue siendo cosmético ahí.

## Por qué
- En un mapa continuo, climas independientes por zona dan cortes absurdos a 50 m de distancia; uno solo para todo
  el mapa no deja que Nieve y Volcán tengan el suyo. El frente del llano resuelve las dos cosas con una tirada.
- Sacarlo de la semilla y el día reusa lo que ya está replicado (semilla, día, posición): cero ancho de banda y
  nada nuevo en el save (`diseno/guardado.md`).
- Un clima que cambia a mitad del día o que rompe cosas por su cuenta es una sorpresa sin decisión; anunciado a
  la apertura, es una decisión de a dónde ir primero y con qué vehículo.
- El agarre es la única palanca real de manejo del motor (`GripZones`, ya usada por ripio y barro), así que la
  lluvia cuesta una línea por vehículo y no un sistema nuevo.

## Qué cambia
- `diseno/distritos.md`: sección nueva, columna "Clima permitido" de Nieve (`nevada`) y Volcán (`ceniza`), dos
  decisiones.
- D-0324 toma la parte de F1 (función, datos en `ZoneDefinition`, cruce de presentación, agarre, línea de la Jefa).
- D-1610, D-1617, D-1715, D-1321, D-1605, D-0738, D-0722 y D-1703 usan estas tablas.
