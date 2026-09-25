"""Authored actions for the rounded character, sampled at 60 Hz.

Blender axes, before the game export's 0.5 scale: front is -Y, up is +Z and
the character's left is +X. 1 Blender unit (BU) = 0.5 m in game.

Every clip is a function of time returning a pose: a flat dict of named
parameters (see NEUTRAL). Poses are plain numbers, so clips can blend into
each other exactly -- Jump and PickUpPackage settle into Idle's first frame,
and PickUpHigh shares PickUpPackage's timing so the game blends them by the
box's height. TurnInPlace starts and ends on Idle's first frame too.

- Arms are FK (IK_brazo = 0) so they hang from the chest, follow the torso
  and swing on arcs with follow-through. The pickups switch them to IK
  while the hands must meet a box.
- Legs stay IK. Feet roll about the ball (heel up) or the heel (toe up), so
  the point touching the ground does not slide while the foot pitches.
- Walk is a short-legged scurry authored at the game's 3.6 m/s; Stroll is a
  real walk at 1.5 m/s for partial stick input. Planted feet travel backward
  at exactly the authored speed (player.gd scales playback by actual speed).
"""
import math
import bpy
from mathutils import Vector, Euler, Matrix

FPS = 60
TAU = math.tau
# Game metres/second -> Blender units/second.
BU = 2.0
GAITS = {
    # Fast little steps: 6 steps/s, 0.6 m each, a short flight phase.
    'Walk':   dict(speed=3.6*BU, period=1/3, duty=.34, run=True),
    # A true walk: double support, heel strike, inverted-pendulum hips.
    'Stroll': dict(speed=1.5*BU, period=.6, duty=.62, run=False),
}
IDLE_PERIOD = 6.0
# Two small steps per loop (2.5 steps/s, Walk takes 6).
TURN_PERIOD = .8
DURATIONS = {'Idle': IDLE_PERIOD, 'Walk': GAITS['Walk']['period'],
             'Stroll': GAITS['Stroll']['period'], 'Jump': 1.6,
             'PickUpPackage': 1.6, 'PickUpHigh': 1.6, 'Sit': 4.0,
             'TurnInPlace': TURN_PERIOD}
LOOPING = ('Idle', 'Walk', 'Stroll', 'Sit', 'TurnInPlace')

# Foot geometry, relative to the ankle (IK target) at rest.
BALL = Vector((0, -.245, -.227))   # ball of the foot on the ground
HEEL = Vector((0, .24, -.225))     # back edge of the sole

# --- curves -------------------------------------------------------------------

def clamp01(t):
    return max(0., min(1., t))

def ease(t):
    """Quintic smoothstep: zero velocity and acceleration at both ends."""
    t = clamp01(t)
    return t*t*t*(t*(6*t-15)+10)

def smooth(a, b, t):
    return ease((t-a)/(b-a)) if b != a else float(t >= b)

def keys(t, points):
    """Eased piecewise curve through (time, value) keys; holds at the ends."""
    if t <= points[0][0]:
        return points[0][1]
    for (a, x), (b, y) in zip(points, points[1:]):
        if t <= b:
            return x + (y-x)*ease((t-a)/(b-a))
    return points[-1][1]

def spring(t, t0, amp, freq, decay):
    """Damped oscillation that starts at t0 with zero offset, moving +amp first."""
    if t <= t0:
        return 0.
    u = t-t0
    return amp*math.sin(TAU*freq*u)*math.exp(-decay*u)

def lerp(a, b, f):
    if isinstance(a, (tuple, list)):
        return tuple(lerp(x, y, f) for x, y in zip(a, b))
    return a + (b-a)*f

def blend(p, q, f):
    """Pose p blended toward pose q by f (0..1). Missing keys use NEUTRAL."""
    if f <= 0: return dict(p)
    if f >= 1: return dict(q)
    out = {}
    for k in set(p) | set(q):
        out[k] = lerp(p.get(k, NEUTRAL[k]), q.get(k, NEUTRAL[k]), f)
    return out

# --- pose parameters ------------------------------------------------------------
# Angles in degrees, about world axes at rest: +pitch leans forward, +roll
# tilts toward the character's left, +yaw turns toward the character's left.
# Arm tuple: (lower, swing, bend, twist, ext, shrug) -- lower 0 is the rest
# T-pose, 90 straight down; +swing is forward; bend is elbow flexion;
# twist rolls the forearm about itself; ext turns the upper arm outward;
# shrug lifts the shoulder.
# Foot tuple: (x, y, z, roll) offsets from the rest ankle, roll + is heel up
# about the ball, - is toe up about the heel. 'ground' pivots at the contact
# point when true; a raised foot (ground 0) pitches about the ankle.
HANG = (64., 4., 16., 0., 0., 0.)
NEUTRAL = dict(
    px=0., py=0., pz=0., p_pitch=0., p_roll=0., p_yaw=0.,
    s_pitch=0., s_roll=0., s_yaw=0.,
    c_pitch=0., c_roll=0., c_yaw=0.,
    h_pitch=0., h_roll=0., h_yaw=0.,
    by=0., bz=0., bs=0.,
    armL=HANG, armR=HANG,
    ikL=0., ikR=0., handL=(1.115, -.035, 1.47), handR=(-1.115, -.035, 1.47),
    hrotL=(0., 78., 0.), hrotR=(0., -78., 0.),
    footL=(0., 0., 0., 0.), footR=(0., 0., 0., 0.), groundL=1., groundR=1.,
    toeL=0., toeR=0.,
    kneeL=(.42, -.85, .555), kneeR=(-.42, -.85, .555),
    poleL=(1.35, .65, 1.5), poleR=(-1.35, .65, 1.5),   # IK elbow direction
)

# --- applying a pose to the rig -------------------------------------------------

def rad(d):
    return math.radians(d)

def R(axis, deg):
    return Matrix.Rotation(rad(deg), 3, axis)

class Poser:
    def __init__(self, rig):
        self.rig = rig
        self.rest = {p.name: p.bone.matrix_local.copy() for p in rig.pose.bones}

    def reset(self):
        for p in self.rig.pose.bones:
            p.location = (0, 0, 0); p.rotation_mode = 'XYZ'
            p.rotation_euler = (0, 0, 0); p.scale = (1, 1, 1)

    def fkm(self, name, m=None, loc=(0, 0, 0), scale=(1, 1, 1)):
        """World-axis rotation matrix m about the bone's head, at rest frame."""
        p = self.rig.pose.bones[name]; basis = self.rest[name].to_3x3()
        if m is None: m = Matrix.Identity(3)
        p.rotation_euler = (basis.inverted() @ m @ basis).to_euler('XYZ', p.rotation_euler)
        p.location = basis.inverted() @ Vector(loc); p.scale = scale

    def fk(self, name, pitch=0., roll=0., yaw=0., loc=(0, 0, 0), scale=(1, 1, 1)):
        # Yaw, then roll, then pitch last so a leaning torso keeps its twist.
        self.fkm(name, R('X', pitch) @ R('Y', -roll) @ R('Z', yaw), loc, scale)

    def ik(self, name, position, rot=(0, 0, 0)):
        m = Euler(tuple(rad(a) for a in rot)).to_matrix()
        self.fkm(name, m, Vector(position)-self.rest[name].translation)

    def arm(self, side, a):
        lower, swing, bend, twist, ext, shrug = a
        s = 1 if side == 'L' else -1
        self.fkm('clavicle.'+side, R('Y', -s*shrug))
        # ext rotates the upper arm about itself: + points a bent forearm outward.
        self.fkm('upper_arm.'+side, R('X', -swing) @ R('Y', s*lower) @ R('X', ext))
        # twist turns the forearm about its own axis (- brings the thumb up).
        self.fkm('forearm.'+side, R('Z', -s*bend) @ R('X', s*twist))
        self.fkm('thumb.'+side, R('Z', s*5))

    def foot(self, side, f, ground, toe):
        x, y, z, roll = f
        rest = self.rest['CTRL_foot_IK.'+side].translation
        ankle = Vector((x, y, z))
        if ground > 0 and roll != 0:
            pivot = BALL if roll > 0 else HEEL
            # The contact point stays put; the ankle orbits it.
            ankle += (pivot + R('X', roll) @ (-pivot))*ground
        self.ik('CTRL_foot_IK.'+side, rest+ankle, (roll, 0, 0))
        self.fkm('toe.'+side, R('X', -toe))

    def apply(self, P):
        q = dict(NEUTRAL); q.update(P)
        self.reset()
        self.fk('pelvis', q['p_pitch'], q['p_roll'], q['p_yaw'], loc=(q['px'], q['py'], q['pz']))
        self.fk('spine', q['s_pitch'], q['s_roll'], q['s_yaw'])
        self.fk('chest', q['c_pitch'], q['c_roll'], q['c_yaw'])
        self.fk('head', q['h_pitch'], q['h_roll'], q['h_yaw'])
        self.fkm('belly', None, loc=(0, q['by'], q['bz']),
                 scale=(1+q['bs'], 1, 1+q['bs']*.7))
        for side in 'LR':
            self.arm(side, q['arm'+side])
            self.rig['IK_brazo.'+side] = q['ik'+side]
            s = 1 if side == 'L' else -1
            self.ik('CTRL_hand_IK.'+side, q['hand'+side], q['hrot'+side])
            self.ik('CTRL_elbow.'+side, q['pole'+side])
            self.ik('CTRL_knee.'+side, q['knee'+side])
            self.foot(side, q['foot'+side], q['ground'+side], q['toe'+side])
        for side in 'LR':
            self.rig['IK_pierna.'+side] = 1.

# --- clips ----------------------------------------------------------------------

def idle(t):
    """Standing, alive: two breaths and one slow weight shift per loop."""
    w = TAU*t/IDLE_PERIOD           # weight shift and look, once per loop
    b = TAU*t/(IDLE_PERIOD/2)       # breathing, twice per loop
    breath = (1-math.cos(b))/2      # 0 exhale .. 1 inhale
    shift = math.sin(w)             # + weight over the left foot
    look = math.sin(w-.9)
    # Pelvis carries the weight shift; the loaded side's hip rises a little.
    # The chest counters it and the head counters the chest, a beat later.
    arm_sway = 1.4*math.sin(w-.7)   # arms hang like pendulums behind the hips
    return dict(
        px=.035*shift, pz=-.06+.008*breath, p_roll=-1.3*shift, p_yaw=.8*math.sin(w+.4),
        s_roll=.9*math.sin(w-.25), s_pitch=.5-.6*breath,
        c_pitch=-1.4*breath, c_roll=.6*math.sin(w-.45), c_yaw=-.8*math.sin(w+.2),
        h_pitch=.9*breath-1.5+1.2*math.sin(2*w+.6)*.5, h_roll=2.2*math.sin(w-1.1),
        h_yaw=4.5*look,
        by=-.02*breath, bz=.006*breath, bs=.02*breath,
        armL=(64-1.5*breath+arm_sway, 4+.8*math.sin(w-.9), 16+2*breath, 0, 0, 1.2*breath),
        armR=(64-1.5*breath-arm_sway, 4-.8*math.sin(w-.9), 16+2*breath, 0, 0, 1.2*breath),
        footL=(0, 0, 0, 0), footR=(0, 0, 0, 0),
    )

def gait(name, t):
    g = GAITS[name]
    T, D, v, run = g['period'], g['duty'], g['speed'], g['run']
    p = (t/T) % 1.
    a = TAU*p
    stride = v*T                    # BU travelled per full cycle
    stance = stride*D               # ground travelled by a planted foot
    centre = .03 if run else .0     # stance centred slightly behind the hip
    lift = .26 if run else .13
    # Roll angles at touchdown / toe-off.
    r_td = -3. if run else -14.
    r_to = 38. if run else 30.
    heel_rise = (.45 if run else .55)   # fraction of stance before the heel lifts

    def foot(u):
        u %= 1.
        if u < D:
            s = u/D
            y = -stance/2 + centre + stance*s
            if s < .25:
                roll = r_td*(1-ease(s/.25))
            else:
                roll = r_to*ease((s-heel_rise)/(1-heel_rise)) if s > heel_rise else 0.
            toe = roll if roll > 0 else 0.
            return (0., y, 0., roll), 1., toe
        s = (u-D)/(1-D)
        # Positions of the ankle at the two ends of the swing (ground pivots applied).
        def planted(y, roll):
            ankle = Vector((0, y, 0))
            pivot = BALL if roll > 0 else HEEL
            return ankle + pivot + R('X', roll) @ (-pivot)
        start = planted(stance/2+centre, r_to)
        end = planted(-stance/2+centre, r_td)
        # Hermite in y: leaves moving backward with the ground, arrives
        # retracting (moving backward) so touchdown has no forward scuff.
        m = stride*(1-D)
        h00, h10 = 2*s**3-3*s*s+1, s**3-2*s*s+s
        h01, h11 = -2*s**3+3*s*s, s**3-s*s
        y = h00*start.y + h10*m + h01*end.y + h11*m
        # Heel flicks up early in the swing, the knee comes through, the foot
        # reaches and settles.
        shape = math.sin(math.pi*s**(.8 if run else 1.))**(1.6 if run else 2.)
        z = start.z*(1-ease(s*1.6)) + end.z*ease((s-.6)/.4) + lift*shape
        roll = keys(s, [(0, r_to), (.3, r_to*.55 if run else 8.), (.75, -8. if run else -16.), (1., r_td)])
        toe = r_to*(1-ease(s/.35))
        return (0., y, z, roll), 0., toe

    fl, gl, tl = foot(p)
    fr, gr, tr = foot(p+.5)
    # Hips: lowest at mid-stance when running (the leg is a spring), highest
    # at mid-stance when walking (the leg vaults over the planted foot).
    mid = D/2
    phase2 = 2*TAU*(p-mid)
    if run:
        pz = -.15 - .05*math.cos(phase2)
    else:
        pz = -.05 + .03*math.cos(phase2)
    # + when the left foot is loaded. Left stance centres on p=mid.
    load = math.cos(TAU*(p-mid))
    reach = math.cos(a)             # + left leg forward (touchdown at p=0)
    lag = .07 if run else .05
    arm_amp = 27. if run else 18.
    bend = 78. if run else 24.
    bend_amp = 20. if run else 8.
    bias = 7. if run else 3.                 # arms swing further forward than back
    twist = -42. if run else -18.            # loose fists, thumbs up
    swing_l = bias-arm_amp*math.cos(a-TAU*lag)  # left arm back while left leg forward

    def arm(swing, forward):
        # Swinging forward the elbow flexes and the upper arm turns out, so
        # the fist passes beside the tummy, not through it. Swinging back
        # the elbow opens.
        f = (forward+1)/2
        return (60. if run else 66., swing, bend+bend_amp*(2*f-1), twist, (40. if run else 12.)*f, 0.)
    lean = 7.5 if run else 2.5
    bounce_lag = math.cos(phase2-1.1)       # head and belly trail the bounce
    return dict(
        px=(.035 if run else .03)*load, py=0., pz=pz,
        p_pitch=2. if run else 0., p_roll=(-4.5 if run else -2.5)*load,
        p_yaw=(-7. if run else -5.)*reach,
        s_pitch=lean, s_roll=(2.5 if run else 1.4)*math.cos(TAU*(p-mid)-.5),
        s_yaw=(4. if run else 3.)*reach,
        c_pitch=2. if run else .5, c_roll=(1.8 if run else 1.)*math.cos(TAU*(p-mid)-.9),
        c_yaw=(8. if run else 5.)*math.cos(a-TAU*lag*.5),
        # The head keeps the gaze steady: it cancels most of the lean and
        # twist, and nods a beat after each bounce.
        h_pitch=-lean*.8 + (2.4 if run else 1.)*bounce_lag,
        h_roll=(2. if run else 1.)*math.cos(TAU*(p-mid)-1.4),
        h_yaw=-(5. if run else 4.)*math.cos(a-TAU*lag*1.5),
        by=(.012 if run else .006)*math.sin(phase2-1.3),
        bz=(-.03 if run else -.012)*bounce_lag,
        armL=arm(swing_l, math.cos(a-TAU*lag+math.pi)),
        armR=arm(2*bias-swing_l, math.cos(a-TAU*lag)),
        footL=fl, footR=fr, groundL=gl, groundR=gr, toeL=tl, toeR=tr,
    )

IDLE0 = None   # filled in build(): Idle's first frame, the pose to return to.
HANDS0 = {}    # filled in build(): wrist position/rotation of IDLE0 per side,
               # so IK arms start exactly where the FK arms hang.

def bezier(p0, p1, p2, f):
    """Quadratic Bezier: an arc from p0 to p2 bowed toward p1."""
    return tuple((1-f)**2*a + 2*(1-f)*f*b + f*f*c for a, b, c in zip(p0, p1, p2))

def ramped(t, t0, amp, freq, decay, ramp=.05):
    """spring() that eases in, so the reaction starts without a velocity step."""
    return spring(t, t0, amp, freq, decay)*ease((t-t0)/ramp)

def arm_air(t, delay):
    t = max(0., t-delay)
    flap = 6.*math.sin(TAU*5.*max(0., t-.46))*smooth(.44, .56, t)
    # t=0: the arms are still low and behind, whipping forward: that swing
    # is what launched the jump.
    return (keys(t, [(0, 70.), (.12, 32.), (.24, -30.), (.4, -38.), (.62, -30.), (.84, -18.)])+flap,
            keys(t, [(0, -28.), (.12, 42.), (.24, 28.), (.4, 14.), (.84, 10.)]),
            keys(t, [(0, 22.), (.12, 40.), (.24, 28.), (.4, 36.), (.84, 22.)]), 0., 0.,
            keys(t, [(0, 4.), (.22, 10.), (.4, 8.), (.84, 6.)]))

def jump(t):
    """player.gd seeks this by physics: 0..0.4 ascent (by vertical speed),
    0.4..0.84 fall, 0.9 touchdown, then real time until Idle's first frame."""
    rest = IDLE0
    if t <= .9:
        t = min(t, .84)  # 0.84..0.9 is skipped by the runtime; hold the reach
        # Legs: pushing off at launch (balls still on the floor), tucked at
        # the apex, reaching for the floor before touchdown.
        tuck = keys(t, [(0, 0.), (.10, .25), (.36, 1.), (.52, .85), (.76, .08), (.84, 0.)])
        toes = keys(t, [(0, 30.), (.2, 14.), (.5, 4.), (.72, -5.), (.84, 0.)])
        ground = keys(t, [(0, 1.), (.07, 0.)])
        return dict(
            pz=keys(t, [(0, .03), (.4, .02), (.84, rest['pz'])]),
            py=keys(t, [(0, .02), (.84, 0.)]),
            s_pitch=keys(t, [(0, -6.), (.3, 3.), (.6, 5.), (.84, rest['s_pitch']+2)]),
            c_pitch=keys(t, [(0, -4.), (.3, 1.), (.84, rest['c_pitch'])]),
            h_pitch=keys(t, [(0, -9.), (.35, -4.), (.7, 2.), (.84, rest['h_pitch']+5)]),
            h_roll=keys(t, [(0, 0.), (.4, 3.), (.84, 0.)]),
            # Arms swing up in front on the push, open into a cheering "Y" at
            # the apex and flap a little on the way down, as if that could
            # slow the fall. The right side trails the left slightly: perfect
            # symmetry reads as mechanical.
            armL=arm_air(t, 0.), armR=arm_air(t, .025),
            footL=(0., .04-.14*tuck, .36*tuck, toes),
            footR=(0., .05-.10*tuck, .30*tuck, toes+4*tuck),
            groundL=ground, groundR=ground, toeL=toes*ground, toeR=toes*ground,
            by=keys(t, [(0, .01), (.4, -.01), (.84, .01)]),
            bz=keys(t, [(0, -.02), (.4, .012), (.84, .02)]),
        )
    # Touchdown: the air pose hands over to Idle's first frame while the
    # impact adds a squash, and the heavy head, tummy and arms keep going.
    air = jump(.84)
    base = blend(air, rest, smooth(.9, 1.06, t))
    u = clamp01((t-.9)/.1)
    squash = 1-(1-u)**3 if t < 1. else keys(t, [(1., 1.), (1.2, .26), (1.42, .04), (1.6, 0.)])
    head_nod = ramped(t, .93, 1., 2.6, 5.5)
    belly_jig = ramped(t, .92, 1., 4.2, 6.5)
    arm_swing = ramped(t, 1.0, 1., 1.8, 4.)
    P = dict(base)
    P.update(
        pz=base['pz']-.34*squash+.012*math.sin(math.pi*smooth(1.18, 1.5, t)),
        py=base['py']+.06*squash,
        s_pitch=base['s_pitch']+15*squash, c_pitch=base['c_pitch']+6*squash,
        h_pitch=base['h_pitch']-4*squash+9*head_nod,
        bz=base['bz']-.035*belly_jig, by=base['by']-.01*belly_jig,
        bs=base['bs']+.03*squash,
        footL=lerp(base['footL'], (.03, 0., 0., 0.), squash),
        footR=lerp(base['footR'], (-.03, 0., 0., 0.), squash),
        groundL=1., groundR=1., toeL=0., toeR=0.,
    )
    for side in 'LR':
        # Arms drag: they come down after the body has already landed.
        a = lerp(air['arm'+side], rest['arm'+side], smooth(.94, 1.22, t))
        P['arm'+side] = (a[0]-12*squash, a[1]+14*squash-8*arm_swing, a[2]+18*squash, a[3], a[4], a[5])
    return blend(P, rest, smooth(1.4, 1.6, t))

def pickup_timing(t):
    """The curves both pickups share, so PickUpPackage and PickUpHigh stay in
    step and player.gd can blend them by the box's height: the grab at
    0.42 s, the lift until 1.3 s, the settle."""
    return dict(
        look=keys(t, [(0, 0.), (.1, 1.)]),                       # the eyes lead
        rise=keys(t, [(0, 0.), (.07, 1.), (.13, 0.)]),           # a tiny lift before going down
        down=keys(t, [(0, 0.), (.08, 0.), (.42, 1.), (.50, 1.05), (.58, 1.), (1.3, 0.)]),
        lift=smooth(.52, 1.3, t),
        effort=keys(t, [(.5, 0.), (.75, 1.), (1.15, 1.), (1.45, 0.)]),
        settle=ramped(t, 1.28, 1., 2.2, 6.),
        hug=keys(t, [(.34, 0.), (.48, 1.)]),
        reach=keys(t, [(0, 0.), (.42, 1.)]),
    )

def pickup(t):
    """Timed to player.gd: hands take the box at 0.42 s, it rises until 1.3 s.
    In the game the hands then follow the real box by IK; these arcs matter
    while that IK blends in, and in any preview."""
    rest = IDLE0
    c = pickup_timing(t)
    look, rise, down, lift = c['look'], c['rise'], c['down'], c['lift']
    effort, settle, hug = c['effort'], c['settle'], c['hug']
    wobble = effort*math.sin(TAU*3.2*(t-.5))
    P = dict(rest)
    P.update(
        pz=rest['pz']+.025*rise-.43*down-.03*settle,
        py=.16*down,                                  # hips back: a squat, not a stoop
        s_pitch=rest['s_pitch']+24*down-6*effort*lift, c_pitch=rest['c_pitch']+8*down-3*effort,
        s_roll=rest['s_roll']+1.8*wobble, c_roll=rest['c_roll']-1.2*wobble,
        h_pitch=rest['h_pitch']+14*look*(1-lift)-10*down*(1-lift)-4*effort+2*settle,
        h_roll=rest['h_roll']+keys(t, [(0, 0.), (.3, -4.), (.9, 3.), (1.6, 0.)]),
        h_yaw=rest['h_yaw']*(1-look),
        by=rest['by']-.02*down, bz=rest['bz']-.02*down-.02*settle,
    )
    # Hands on arcs: out and down around the tummy to the box's sides, a
    # squeeze, then the box comes in toward the chest before going up.
    reach = c['reach']
    for side, s in (('L', 1), ('R', -1)):
        start, rot0 = HANDS0[side]
        width = s*(.60-.04*hug)
        if t < .42:
            pos = bezier(start, (s*1.2, -.55, 1.25), (width, -.78, 1.02), reach)
        else:
            pos = bezier((width, -.78, 1.02), (width, -.66, 1.45), (width, -.62, 1.97), lift)
        P['hand'+side] = pos
        P['hrot'+side] = lerp(rot0, (-55., 0., -s*75.), reach)
        P['ik'+side] = 1.
        P['arm'+side] = tuple(rest['arm'+side][:5]) + (3*hug,)
    return P

# Where the hands meet the box in each pickup (wrist height, BU). player.gd
# blends the two clips by the box's grip height between these (x 0.5 m/BU).
PICKUP_GRAB_Z = {'PickUpPackage': 1.02, 'PickUpHigh': 1.85}

def pickup_high(t):
    """PickUpPackage for a box at the waist (a shelf, a table): same duration
    and the same grab/lift/settle times, so the two blend frame by frame.
    No squat: the knees only soften, the torso leans a little toward the
    box, the arms reach straight out in front and pull it in to the chest."""
    rest = IDLE0
    c = pickup_timing(t)
    look, rise, down, lift = c['look'], c['rise'], c['down'], c['lift']
    effort, settle, hug = c['effort'], c['settle'], c['hug']
    wobble = effort*math.sin(TAU*3.2*(t-.5))
    P = dict(rest)
    P.update(
        # A small dip, weight a little back as the arms reach forward.
        pz=rest['pz']+.02*rise-.06*down-.02*settle,
        py=.04*down,
        # Leans from the waist toward the box, then back a touch under the
        # weight as it comes in to the chest.
        s_pitch=rest['s_pitch']+9*down-5*effort*lift, c_pitch=rest['c_pitch']+4*down-2*effort,
        s_roll=rest['s_roll']+1.*wobble, c_roll=rest['c_roll']-.7*wobble,
        h_pitch=rest['h_pitch']+9*look*(1-lift)-3*down*(1-lift)-2*effort+2*settle,
        h_roll=rest['h_roll']+keys(t, [(0, 0.), (.3, -3.), (.9, 2.), (1.6, 0.)]),
        h_yaw=rest['h_yaw']*(1-look),
        by=rest['by']-.01*down, bz=rest['bz']-.01*down-.015*settle,
    )
    reach = c['reach']
    for side, s in (('L', 1), ('R', -1)):
        start, rot0 = HANDS0[side]
        width = s*(.60-.04*hug)
        grab = (width, -.92, PICKUP_GRAB_Z['PickUpHigh'])
        if t < .42:
            # Out around the tummy and forward, rising to the box's sides.
            pos = bezier(start, (s*1.1, -.75, 1.45), grab, reach)
        else:
            # Pulled in toward the chest: the carry pose PickUpPackage ends in.
            pos = bezier(grab, (width, -.78, 2.02), (width, -.62, 1.97), lift)
        P['hand'+side] = pos
        P['hrot'+side] = lerp(rot0, (-55., 0., -s*75.), reach)
        P['ik'+side] = 1.
        P['arm'+side] = tuple(rest['arm'+side][:5]) + (3*hug,)
    return P

# Each foot's step in TurnInPlace, as fractions of the loop: the weight goes
# over the other foot first, then this one peels off, lifts and sets down.
TURN_STEPS = {'L': (.08, .42), 'R': (.58, .92)}

def turn_step(u, s):
    """One small step in place, u 0..1 across the step window (planted
    outside it): the heel peels up about the ball, the foot lifts a hand's
    width, drifts a touch outward and sets back down
    heel first under the hip, where it started. Returns foot, toe, lift."""
    if u <= 0. or u >= 1.:
        return (0., 0., 0., 0.), 0., 0.
    lift = math.sin(math.pi*smooth(.12, .9, u))
    roll = keys(u, [(0, 0.), (.22, 24.), (.5, 6.), (.82, -7.), (.94, -2.), (1., 0.)])
    toe = max(0., roll)*(1-smooth(.18, .42, u))    # flat on the floor while the heel peels
    return (s*.035*lift, -.02*lift, .15*lift, roll), toe, lift

def turn_in_place(t):
    """Feet catching up with a body that turns standing still: player.gd
    plays it while the player looks around without walking. Two small steps
    per loop, left then right, each with the weight shifted over the other
    foot first. Starts and ends on IDLE0, so it blends in and out of Idle.
    No yaw of its own: the body turns either way, the feet just re-plant."""
    rest = IDLE0
    p = (t/TURN_PERIOD) % 1.
    # + weight over the left foot: onto the right before the left steps.
    w = keys(p, [(0, 0.), (.08, -1.), (.40, -1.), (.58, 1.), (.90, 1.), (1., 0.)])
    P = dict(rest)
    lifts = {}
    for side, s in (('L', 1), ('R', -1)):
        a, b = TURN_STEPS[side]
        foot, toe, lift = turn_step((p-a)/(b-a), s)
        P['foot'+side], P['toe'+side], P['ground'+side] = foot, toe, 1.
        lifts[side] = lift
    step = lifts['L'] + lifts['R']
    swap = lifts['L'] - lifts['R']          # + while the left foot is up
    P.update(
        # The loaded hip carries the weight and the knee under it softens.
        px=rest['px']+.05*w, pz=rest['pz']-.03*step,
        p_roll=rest['p_roll']-2.5*w, p_yaw=rest['p_yaw']+3.*swap,
        s_pitch=rest['s_pitch']+1.5*step, s_roll=rest['s_roll']+1.6*w,
        c_roll=rest['c_roll']+.8*w, c_yaw=rest['c_yaw']-2.*swap,
        h_roll=rest['h_roll']-1.2*w, h_pitch=rest['h_pitch']-1.*step,
        bz=rest['bz']-.012*step,
    )
    # Arms out a little for balance on each step, the one opposite the lifted
    # foot swinging slightly forward, the other back.
    for side, s in (('L', 1), ('R', -1)):
        a = rest['arm'+side]
        P['arm'+side] = (a[0]-4*step, a[1]-5*s*swap, a[2]+4*step, a[3], a[4], a[5])
    return P

HAND_ON_BELLY = (.70, -.42, .72)   # wrist, pelvis dropped 1.0 BU for the seat

def belly_hand_rot(s):
    """Fingers inward (Rz 180), palm turned onto the tummy and thumb up (Rx 90),
    then yawed to follow the belly's curve and tipped slightly down."""
    m = R('Z', s*28.) @ R('Y', s*12.) @ R('X', 90.) @ R('Z', 180.)
    return tuple(math.degrees(a) for a in m.to_euler('XYZ'))

def sit(t):
    """Seated passenger: hands rest on the tummy, feet swing like a kid's."""
    w = TAU*t/4
    breath = (1-math.cos(2*w))/2        # two breaths per loop
    look = math.sin(w-.6)
    # Cubed so each swing starts and stops without a jolt.
    kick_l = max(0., math.sin(w))**3
    kick_r = max(0., math.sin(w+math.pi*.9))**3
    P = dict(
        px=0., py=.05, pz=-1.0,
        s_pitch=-3., c_pitch=-1.2*breath, h_pitch=.6*breath+1.,
        h_yaw=6.*look, h_roll=2.*math.sin(w-1.4),
        by=-.016*breath, bz=.004*breath, bs=.016*breath,
        armL=HANG, armR=HANG, ikL=1., ikR=1.,
        kneeL=(.46, -1.4, .20), kneeR=(-.46, -1.4, .20),
        groundL=0., groundR=0., toeL=0., toeR=0.,
    )
    # Thighs almost level, shins dangling; each foot swings forward in turn.
    for side, s, k in (('L', 1, kick_l), ('R', -1, kick_r)):
        P['foot'+side] = (s*.025, -.535-.16*k, -.435+.12*k, -6-10*k)
    # Hands rest on the tummy: palms on it, thumbs up, fingers following
    # its curve toward the middle. Each breath lifts them.
    for side, s in (('L', 1), ('R', -1)):
        P['hand'+side] = (s*HAND_ON_BELLY[0], HAND_ON_BELLY[1]-.016*breath, HAND_ON_BELLY[2]+.008*breath)
        P['hrot'+side] = belly_hand_rot(s)
        P['pole'+side] = (s*1.7, -.5, .9)   # elbows out and forward: the arm wraps the tummy
    return P

# --- build ----------------------------------------------------------------------

def build(rig):
    global IDLE0
    for act in list(bpy.data.actions): bpy.data.actions.remove(act)
    rig.animation_data_create()
    poser = Poser(rig)
    IDLE0 = dict(NEUTRAL); IDLE0.update(idle(0.))
    # Where the FK hands actually are in IDLE0, as IK targets and rotations.
    rig.animation_data.action = None
    poser.apply(IDLE0)
    bpy.context.view_layer.update()
    for side in 'LR':
        m = rig.pose.bones['hand.'+side].matrix
        rot = (m.to_3x3().normalized() @ poser.rest['hand.'+side].to_3x3().inverted()).to_euler('XYZ')
        HANDS0[side] = (tuple(m.translation), tuple(math.degrees(x) for x in rot))
    clips = {'Idle': idle, 'Walk': lambda t: gait('Walk', t), 'Stroll': lambda t: gait('Stroll', t),
             'Jump': jump, 'PickUpPackage': pickup, 'PickUpHigh': pickup_high, 'Sit': sit,
             'TurnInPlace': turn_in_place}
    for name, duration in DURATIONS.items():
        action = bpy.data.actions.new(name); action.use_fake_user = True
        rig.animation_data.action = action
        last = round(duration*FPS)
        for frame in range(last+1):
            t = frame/FPS
            # Loops sample their exact start at the end so they close.
            if name in LOOPING and frame == last: t = 0.
            poser.apply(clips[name](t))
            for pb in rig.pose.bones:
                pb.keyframe_insert('location', frame=frame, group=pb.name)
                pb.keyframe_insert('rotation_euler', frame=frame, group=pb.name)
                pb.keyframe_insert('scale', frame=frame, group=pb.name)
            for side in 'LR':
                rig.keyframe_insert('["IK_brazo.%s"]' % side, frame=frame)
                rig.keyframe_insert('["IK_pierna.%s"]' % side, frame=frame)
        action.frame_range = (0, last); action.use_frame_range = True
        # Dense sampling preserves authored velocities; Bezier overshoot can
        # otherwise sink toes between samples or overshoot knee pole targets.
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points: key.interpolation = 'LINEAR'
    rig.animation_data.action = bpy.data.actions['Idle']
    poser.apply(idle(0.))
    return DURATIONS
