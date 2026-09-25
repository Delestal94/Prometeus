"""Original vector expressions inspired by vintage rubber-hose cartoons.
All features share a 512-square UV sheet, so 2D and 3D use identical assets.
"""
from pathlib import Path

OUT=Path(__file__).resolve().parents[2]/'do-not-drop/assets/textures/characters/faces'
OUT.mkdir(parents=True,exist_ok=True)
INK='#191923'

def write(name,body):
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><g fill="{INK}" stroke="{INK}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">{body}</g></svg>'
    (OUT/(name+'.svg')).write_text(svg,encoding='utf-8')

def oval_eye(x,cy=213,rx=30,ry=55):
    return f'<ellipse cx="{x}" cy="{cy}" rx="{rx}" ry="{ry}" stroke="none"/><path d="M {x-4},{cy-ry+9} L {x+20},{cy-19} L {x-4},{cy-12} Z" fill="#fffaf0" stroke="none"/>'

def brows(left,right):
    return f'<path d="{left} M {right}" fill="none"/>'

write('eyes_classic',oval_eye(185)+oval_eye(327))
write('eyes_joyful','<path d="M 150 234 Q 185 169 221 234 M 292 234 Q 327 169 363 234" fill="none" stroke-width="12"/><path d="M 146 185 Q 185 154 222 181 M 291 181 Q 328 154 364 185" fill="none" stroke-width="5"/>')
write('eyes_sleepy','<path d="M 153 205 Q 185 283 216 205 Z M 296 205 Q 328 283 360 205 Z"/><path d="M 145 198 L 221 205 M 291 205 L 365 197" fill="none" stroke-width="10"/><path d="M 153 171 Q 185 159 215 176 M 298 176 Q 329 159 359 171" fill="none" stroke-width="5"/><path d="M 185 212 L 201 216 L 189 228 Z M 328 212 L 344 216 L 332 228 Z" stroke="none" fill="#fffaf0"/>')
write('eyes_worried',oval_eye(185,219,24,43)+oval_eye(327,219,24,43)+'<path d="M 147 170 Q 180 171 209 141 M 303 141 Q 332 171 365 170" fill="none"/>')
write('eyes_wink',oval_eye(185)+'<path d="M 294 220 Q 326 203 358 222 M 351 211 L 369 201" fill="none" stroke-width="11"/><path d="M 294 168 Q 326 150 357 174" fill="none" stroke-width="5"/>')
write('eyes_lashes',oval_eye(185,216,29,53)+oval_eye(327,216,29,53)+'<path d="M 164 169 L 154 148 M 184 161 L 183 138 M 204 169 L 215 150 M 306 169 L 296 148 M 326 161 L 327 138 M 346 169 L 358 151" fill="none" stroke-width="6"/>')
write('mouth_smile','<path d="M 181 321 Q 256 386 331 321" fill="none" stroke-width="9"/><path d="M 174 329 Q 174 314 190 312 M 322 312 Q 338 314 338 329" fill="none" stroke-width="5"/>')
write('mouth_grin','<path d="M 174 313 Q 256 348 338 313 Q 335 381 256 381 Q 178 381 174 313 Z" fill="#fffaf0"/><path d="M 181 344 Q 256 366 331 344 M 211 327 L 210 368 M 241 333 L 241 378 M 272 334 L 272 377 M 301 328 L 302 369" fill="none" stroke-width="4"/>')
write('mouth_surprised','<ellipse cx="256" cy="344" rx="27" ry="34"/><ellipse cx="255" cy="365" rx="15" ry="7" fill="#fffaf0" stroke="none"/>')
write('mouth_pout','<path d="M 214 350 Q 256 319 298 350" fill="none" stroke-width="9"/><path d="M 243 370 Q 256 373 270 370" fill="none" stroke-width="4"/>')
write('mouth_tongue','<path d="M 185 322 Q 251 365 327 315 Q 301 373 235 365 Q 199 359 185 322 Z"/><path d="M 254 355 Q 280 353 291 343 L 288 375 Q 278 405 259 382 Z" fill="#fffaf0" stroke-width="5"/><path d="M 275 361 L 273 382" fill="none" stroke-width="3"/>')
write('mouth_laugh','<path d="M 188 311 Q 256 338 324 311 Q 316 389 256 392 Q 196 389 188 311 Z"/><path d="M 200 318 Q 256 337 312 318 L 305 337 Q 256 349 207 337 Z" fill="#fffaf0" stroke="none"/><path d="M 231 380 Q 253 358 281 380" fill="#fffaf0" stroke="none"/>')
write('eyes_none','')
write('mouth_none','')
print('FACE_VECTORS',len(list(OUT.glob('*.svg'))))
