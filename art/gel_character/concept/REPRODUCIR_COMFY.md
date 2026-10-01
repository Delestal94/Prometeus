# Reproducir la hoja de concepto guiada S-311.6

## Por qué imagen-a-imagen

Las cinco rondas solo de texto produjeron material útil, pero añadieron orejas,
puños o dedos humanos en perfil. Por autorización del usuario se usa una guía
generada con imagegen, corregida visualmente antes de pasar por ComfyUI:
`concept_sheet_guidance_v3.png`. No se presenta esa guía como una imagen
producida originalmente por Z-Image: la entrega combina **guía imagegen +
variaciones imagen-a-imagen de Z-Image Turbo local**.

La guía contiene 14 figuras: Delgada frente/perfil/espalda, Flaca
frente/perfil/espalda, dos extremos conceptuales y seis Delgadas coloreadas.
En las vistas de espalda se distinguen talones más estrechos y el dorso del
cuerpo. Las dimensiones exactas se toman del JPG original y de `../LEEME.md`,
no se miden ni se aprueban sobre esta guía generativa.

## Entorno

ComfyUI local responde en `http://127.0.0.1:8188`. Nodos estándar, sin plugins
adicionales ni servicios de pago. Modelos:

- `diffusion_models/z_image_turbo_int8_convrot.safetensors`.
- `text_encoders/qwen_3_4b_fp8_mixed.safetensors`.
- `vae/ae.safetensors`.

`generate_guided.py` usa únicamente la biblioteca estándar de Python 3.10+ y
reutiliza `art/tools/comfy_generate.py` sin modificarlo. Los nombres de los
nodos y sus entradas se comprobaron contra `/object_info` del servidor.

## Comando desde la raíz del repositorio

```powershell
python art/gel_character/concept/generate_guided.py --source art/gel_character/concept/concept_sheet_guidance_v3.png --out art/gel_character/concept/comfy/guidance_v3 --denoise 0.15 --seeds 311071 311072 311073
```

La ejecución es secuencial; solo se encola una semilla por vez. Si el primer
proceso supera 900 segundos, conserva su ID y no duplica la generación:

```powershell
python art/gel_character/concept/generate_guided.py --out art/gel_character/concept/comfy/guidance_v3 --seeds 311071 --resume <prompt_id_del_manifest>
```

## Workflow exacto

```text
LoadImage(guía subida por /upload/image)
  -> ImageScale(lanczos, 1664 × 960, crop=disabled)
  -> VAEEncode(ae.safetensors)
  -> KSampler(latent_image, seed, denoise=0.15,
              steps=8, cfg=1, res_multistep, simple)
  -> VAEDecode(ae.safetensors)
  -> SaveImage

UNETLoader(z_image_turbo_int8_convrot, weight_dtype=default)
  -> ModelSamplingAuraFlow(shift=3) -> KSampler.model
CLIPLoader(qwen_3_4b_fp8_mixed, type=lumina2, device=default)
  -> CLIPTextEncode(PROMPT) -> KSampler.positive
  -> ConditioningZeroOut -> KSampler.negative
```

El texto exacto vive en la constante `PROMPT` del generador y se conserva
también dentro de cada `concept_guided_seed<semilla>.json`, junto con el
workflow completo enviado, la ruta de guía, semilla, denoise e ID del prompt.
Los PNG conservan además la metadata de ComfyUI.

## Inspección requerida

Comparar las tres semillas con la guía y el JPG original: conservar las
14 figuras, frente/perfil/dorso reconocibles, seis colores separados,
esferas sin rasgos, manoplas sin dedos, continuidad de material y pies,
translucidez, motas y reflejos. Una imagen meramente mejor que la anterior
no se acepta si introduce un rasgo obligatorio incorrecto. La selección
y sus reservas están en `seleccion_comfy.md`.

Las exploraciones fallidas se conservaron localmente en
`.beads/concept_explorations/`, fuera de la entrega versionada; sus prompts
R1–R5 sí permanecen para reproducir el historial. No cuentan como rondas del
bloque E ni como aprobación cuantitativa del personaje de Godot.
