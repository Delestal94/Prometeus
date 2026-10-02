"""Rubber-hose cartoon faces for the rounded character (N-506).

Original designs in the language of 1930s rubber-hose animation (the user's
reference, 2026-10-01): tall oval eyes set close together, "pie-cut" pupils
(a tall black pupil with a wedge of light cut out of it), short tick brows,
cheek brackets at the corners of the mouth, dark open mouths with a tongue,
one ink. Nothing is traced from any reference sheet.

Every feature shares one 512-square UV sheet (character_face.gd maps it onto
the head; the customisation screen crops it for its cards), so 2D and 3D use
the same files. Three layers per face:

  eyes_<id>.svg    whites, pupils, lids, lashes -- squashed onto the eye line to blink
  brows_<id>.svg   brows and extras (sweat drop) -- own layer, a blink leaves them be
  mouth_<id>.svg   mouth and cheek brackets

Eye centres stay at y=213 (v 0.416): the blink in character_face.gd
(EYE_LINE_V) and the card crops in face_catalog.gd (THUMB_EYES / THUMB_MOUTH)
are measured on this layout -- change them together.

Run: python art/rounded_character/build_faces.py
"""
import math
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / 'do-not-drop/assets/textures/characters/faces'
INK = '#1e2235'  # UiTheme.INK
WHITE = '#fffdf8'
TONGUE = '#f2727f'
SWEAT = '#8fd3f4'
LINE = 10  # outlines; accents are thinner
EYE_Y = 213
EYES_X = (214, 298)  # close together, rubber-hose style
EYE_RX = 36
EYE_RY = 58
## Drawn at these sizes, then scaled about the eye line / mouth centre: a
## caricature wants big features on the head.
EYE_SCALE = 1.15
MOUTH_SCALE = 1.22
MOUTH_Y = 350


def write(name, body):
    scale, pivot_y = (MOUTH_SCALE, MOUTH_Y) if name.startswith('mouth') else (EYE_SCALE, EYE_Y)
    transform = f'translate(256 {pivot_y}) scale({scale}) translate(-256 {-pivot_y})'
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">'
           f'<g transform="{transform}" stroke-linecap="round" stroke-linejoin="round">{body}</g></svg>')
    (OUT / (name + '.svg')).write_text(svg, encoding='utf-8')


def inward(x, side):
    """An x offset toward the nose for the left eye (side 0), mirrored for the right."""
    return x if side == 0 else -x


def stroke(d, width=LINE, color=INK):
    return f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}"/>'


def white(cx, cy=EYE_Y, rx=EYE_RX, ry=EYE_RY):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{WHITE}" stroke="{INK}" stroke-width="{LINE}"/>'


def pie_pupil(cx, cy, rx=19, ry=33):
    """Tall black pupil with the wedge of light cut out of its upper right
    (the same side on both eyes: one light)."""
    wedge = (f'M {cx + 2} {cy - ry * 0.18:.0f} L {cx + rx + 3} {cy - ry * 0.62:.0f} '
             f'L {cx + rx * 0.25:.0f} {cy - ry - 3} Z')
    return (f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{INK}"/>'
            f'<path d="{wedge}" fill="{WHITE}"/>')


def pie_eye(side, look=(5, 14), rx=19, ry=33):
    cx = EYES_X[side]
    return white(cx) + pie_pupil(cx + inward(look[0], side), EYE_Y + look[1], rx, ry)


def tick(side, lift=0, tilt=0, width=9, span=24):
    """A short arched brow over one eye. tilt > 0 raises the inner end."""
    cx = EYES_X[side]
    top = EYE_Y - EYE_RY - 20 - lift
    inner = cx + inward(span, side)
    outer = cx - inward(span, side)
    return stroke(f'M {outer} {top + tilt} Q {cx} {top - 13} {inner} {top - tilt}', width)


def both(make):
    return make(0) + make(1)


# --- Eyes and brows --------------------------------------------------------

def classic():
    write('eyes_classic', both(lambda s: pie_eye(s)))
    write('brows_classic', both(lambda s: tick(s)))


def joyful():
    # Shut tight with joy: tall arches, a lash flick at each outer corner.
    eyes = ''
    for side in (0, 1):
        cx = EYES_X[side]
        eyes += stroke(f'M {cx - 30} {EYE_Y + 22} C {cx - 30} {EYE_Y - 40} {cx + 30} {EYE_Y - 40} '
                       f'{cx + 30} {EYE_Y + 22}', 14)
        out = cx - inward(30, side)
        eyes += stroke(f'M {out} {EYE_Y + 4} L {out - inward(14, side)} {EYE_Y - 6}', 8)
    write('eyes_joyful', eyes)
    write('brows_joyful', both(lambda s: tick(s, 14)))


def sleepy():
    # Heavy lids: the eye's outline is whole, but above the lid is skin.
    eyes = ''
    lid = EYE_Y + 2
    for side in (0, 1):
        cx = EYES_X[side]
        eyes += (f'<path d="M {cx - EYE_RX} {lid} A {EYE_RX} {EYE_RY} 0 0 0 {cx + EYE_RX} {lid} Z" '
                 f'fill="{WHITE}"/>')
        px = cx + inward(4, side)
        eyes += (f'<path d="M {px - 18} {lid} A 18 26 0 0 0 {px + 18} {lid} Z" fill="{INK}"/>'
                 f'<circle cx="{px + 8}" cy="{lid + 9}" r="5" fill="{WHITE}"/>')
        eyes += f'<ellipse cx="{cx}" cy="{EYE_Y}" rx="{EYE_RX}" ry="{EYE_RY}" fill="none" stroke="{INK}" stroke-width="{LINE}"/>'
        eyes += stroke(f'M {cx - EYE_RX - 4} {lid} L {cx + EYE_RX + 4} {lid}', 13)
    write('eyes_sleepy', eyes)
    write('brows_sleepy', both(lambda s: tick(s, -6)))


def worried():
    write('eyes_worried', both(lambda s: pie_eye(s, (2, -4), 14, 24)))
    # Inner ends pulled up, and a drop of sweat at the temple.
    # Big enough to read on a teammate: a fat drop beside the right brow.
    drop = (f'<path d="M 356 104 Q 336 138 340 152 A 19 19 0 0 0 376 148 Q 378 134 356 104 Z" '
            f'fill="{SWEAT}" stroke="{INK}" stroke-width="7"/>'
            f'<ellipse cx="349" cy="140" rx="4" ry="7" fill="{WHITE}"/>')
    write('brows_worried', both(lambda s: tick(s, 4, 14)) + drop)


def wink():
    eyes = pie_eye(0)
    cx = EYES_X[1]
    # The shut eye: a ">"-ish fold toward the open one.
    eyes += stroke(f'M {cx + 30} {EYE_Y - 26} Q {cx - 6} {EYE_Y - 4} {cx - 28} {EYE_Y + 4} '
                   f'Q {cx - 4} {EYE_Y + 10} {cx + 30} {EYE_Y + 30}', 13)
    write('eyes_wink', eyes)
    write('brows_wink', tick(0, 12) + tick(1, -14, -6))


def lashes():
    eyes = ''
    for side in (0, 1):
        cx = EYES_X[side]
        eyes += pie_eye(side, (4, 12), 21, 35)
        # Three lashes fanning out of the top of each eye.
        for along, length in ((-0.55, 18), (-0.15, 20), (0.25, 18)):
            dx = inward(along * EYE_RX * -1, side)
            ox = cx + dx
            oy = EYE_Y - EYE_RY * (1.0 - 0.35 * along * along) + 2
            tx = ox + dx * 0.45
            ty = oy - length
            eyes += stroke(f'M {ox:.0f} {oy:.0f} L {tx:.0f} {ty:.0f}', 8)
    write('eyes_lashes', eyes)
    write('brows_lashes', both(lambda s: tick(s, 18)))


def determined():
    # Lids slanted down toward the nose; above the lid is skin.
    eyes = ''
    for side in (0, 1):
        cx = EYES_X[side]
        # Both ends of the lid sit on the eye's own ellipse, so the arc below
        # them is the eye's outline and keeps its centre.
        lid_in, lid_out = EYE_Y - 8, EYE_Y - 34
        inner_x = cx + inward(EYE_RX * math.sqrt(1.0 - ((EYE_Y - lid_in) / EYE_RY) ** 2), side)
        outer_x = cx - inward(EYE_RX * math.sqrt(1.0 - ((EYE_Y - lid_out) / EYE_RY) ** 2), side)
        # The long way round, through the bottom: clockwise from the right end.
        sweep = 1 if side == 0 else 0
        eyes += (f'<path d="M {outer_x:.1f} {lid_out} L {inner_x:.1f} {lid_in} '
                 f'A {EYE_RX} {EYE_RY} 0 1 {sweep} {outer_x:.1f} {lid_out} Z" fill="{WHITE}" '
                 f'stroke="{INK}" stroke-width="{LINE}"/>')
        eyes += pie_pupil(cx + inward(7, side), EYE_Y + 20, 17, 26)
        eyes += stroke(f"M {outer_x - inward(6, side):.1f} {lid_out - 3} L {inner_x + inward(4, side):.1f} {lid_in + 1}", 13)
    write('eyes_determined', eyes)
    write('brows_determined', both(lambda s: tick(s, -2, -12, 11)))


# --- Mouths ----------------------------------------------------------------

def bracket(x, y, side, size=13):
    """The little cheek bracket at a corner of the mouth; side -1 left, 1 right."""
    return stroke(f'M {x} {y - size} Q {x + side * size * 0.8:.0f} {y} {x} {y + size}', 8)


def mouths():
    write('mouth_smile',
          stroke('M 194 330 Q 256 386 318 330', 13) + bracket(190, 328, -1) + bracket(322, 328, 1))
    grin = 'M 186 318 Q 256 342 326 318 Q 324 384 256 388 Q 188 384 186 318 Z'
    write('mouth_grin',
          f'<path d="{grin}" fill="{WHITE}" stroke="{INK}" stroke-width="{LINE}"/>'
          + stroke('M 192 350 Q 256 366 320 350', 7)
          + stroke('M 222 332 L 221 380 M 256 336 L 256 388 M 290 332 L 291 380', 6)
          + bracket(178, 318, -1) + bracket(334, 318, 1))
    laugh = 'M 192 314 Q 256 336 320 314 Q 318 404 256 408 Q 194 404 192 314 Z'
    write('mouth_laugh',
          f'<path d="{laugh}" fill="{INK}"/>'
          f'<path d="M 202 322 Q 256 342 310 322 L 307 338 Q 256 354 205 338 Z" fill="{WHITE}"/>'
          f'<path d="M 216 396 Q 256 362 296 396 Q 256 410 216 396 Z" fill="{TONGUE}"/>'
          f'<path d="{laugh}" fill="none" stroke="{INK}" stroke-width="{LINE}"/>'
          + bracket(184, 314, -1) + bracket(328, 314, 1))
    write('mouth_surprised',
          f'<ellipse cx="256" cy="352" rx="24" ry="32" fill="{INK}"/>'
          f'<ellipse cx="256" cy="370" rx="14" ry="8" fill="{TONGUE}"/>')
    write('mouth_pout',
          stroke('M 214 366 Q 256 330 298 366', 11) + stroke('M 240 382 Q 256 390 272 382', 7)
          + bracket(208, 370, -1, 10) + bracket(304, 370, 1, 10))
    tongue_mouth = 'M 200 324 Q 256 350 312 324 Q 298 372 256 374 Q 214 372 200 324 Z'
    write('mouth_tongue',
          f'<path d="{tongue_mouth}" fill="{INK}" stroke="{INK}" stroke-width="{LINE}"/>'
          f'<path d="M 250 354 Q 248 404 274 404 Q 298 402 294 352 Z" fill="{TONGUE}" stroke="{INK}" '
          f'stroke-width="8"/>'
          + stroke('M 272 364 L 272 386', 5)
          + bracket(192, 322, -1) + bracket(320, 322, 1))
    write('mouth_smirk',
          stroke('M 214 352 Q 270 366 308 328', 13) + bracket(312, 326, 1))


def blank():
    write('eyes_none', '')
    write('mouth_none', '')


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    for build in (classic, joyful, sleepy, worried, wink, lashes, determined, mouths, blank):
        build()
    print('FACE_VECTORS', len(list(OUT.glob('*.svg'))))
