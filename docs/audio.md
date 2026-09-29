# Mezcla de sonidos de trampas e interfaz

## Objetivos medibles

S-404 fija una referencia común para los sonidos del dominio de Slatex sin depender de ajustar
valores a oído:

- efectos de trampa: **−18 dBFS RMS** a la distancia de referencia del reproductor 3D;
- interfaz: **−24 dBFS RMS**;
- tolerancia automática: **±2 dB**;
- el pico también se informa para vigilar el margen antes de 0 dBFS.

`tests/audio_loudness_report.gd` genera las mismas instancias `AudioStreamWAV` que usa el juego,
mide cada muestra PCM y suma el `volume_db` configurado en el reproductor. Los niveles de trampa
viven en `PackageFeedback.TRAP_SOUND_LEVELS_DB`; cada ficha de `UiSounds` guarda el suyo.

## Ajuste de S-404 (2026-09-28)

Resultado = RMS del stream + nivel del reproductor. La medición anterior usa los valores que
estaban en el juego antes de S-404; la actual es la salida del reporte después del ajuste.

| Grupo | Sonido | Nivel antes | Resultado antes | Nivel actual | Resultado actual | Objetivo |
|---|---|---:|---:|---:|---:|---:|
| Trampa | Frágil | −8,0 | −25,3 | −0,7 | −18,0 | −18 |
| Trampa | Ruidoso (máximo riesgo) | −6,0 | −11,3 | −12,7 | −18,0 | −18 |
| Trampa | Peso creciente | −10,0 | −24,8 | −3,2 | −18,0 | −18 |
| Trampa | Líquido | −16,0 | −38,6 | +4,6 | −17,8 | −18 |
| Trampa | Explosivo | −14,0 | −29,3 | −2,7 | −18,0 | −18 |
| Trampa | Hostil | −13,0 | −33,5 | +2,5 | −18,2 | −18 |
| Trampa | Ruina general | −9,0 | −21,7 | −5,3 | −17,9 | −18 |
| Trampa | Ruina explosiva | −6,0 | −24,3 | 0,0 | −18,3 | −18 |
| UI | Hover | 0,0 | −26,7 | +2,7 | −24,0 | −24 |
| UI | Clic | 0,0 | −22,6 | −1,4 | −24,0 | −24 |
| UI | Abrir panel | 0,0 | −23,8 | −0,2 | −24,0 | −24 |
| UI | Cerrar panel | 0,0 | −24,7 | +0,7 | −24,0 | −24 |
| UI | Aviso | 0,0 | −25,1 | +1,1 | −24,0 | −24 |
| UI | Desbloqueo | 0,0 | −23,2 | −0,8 | −24,0 | −24 |
| UI | Voto | 0,0 | −24,1 | +0,1 | −24,0 | −24 |
| UI | Error | 0,0 | −21,8 | −2,2 | −24,0 | −24 |

Los 16 resultados quedan dentro de la tolerancia. El mayor pico final medido queda por debajo de
0 dBFS, por lo que el ajuste no recorta las muestras. La atenuación por distancia, buses y opciones
de volumen sigue aplicándose después de estos niveles base.
