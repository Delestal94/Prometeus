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
  real walk at 1.5 m/s for partial stick input; Run is the sprint at 6 m/s
  (N-115): the same 6 steps/s as Walk but 1 m strides, a long flight phase,
  a deeper bounce, a forward lean and wide pumping arms. Planted feet travel
  backward at exactly the authored speed (PlayerAnimator scales playback by
  actual speed).
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
    # The sprint (player_sprint.gd RUN_SPEED): 6 steps/s of 1 m, so a cycle
    # covers 2 m, one footfall sound (STEP_DISTANCE). Short contact, both
    # feet off the floor for ~0.09 s after each push. Same period as Walk,
    # so the animator's phase-keeping switch lands on the same foot.
    'Run':    dict(speed=6.0*BU, period=1/3, duty=.22, run=True, sprint=True),
}
IDLE_PERIOD = 6.0
# Gait arms, (lower, ext, extra ext swinging forward): out from the sides and
# turned out on the forward swing, so the fists pass the tummy. Tuned with
# check_clearance.py: turning the bent running arm out drove the fist in.
GAIT_ARMS = {'run': (52., -15., 40.), 'walk': (50., 0., 40.), 'sprint': (44., -12., 34.)}
# Two small steps per loop (2.5 steps/s, Walk takes 6).
TURN_PERIOD = .8
DURATIONS = {'Idle': IDLE_PERIOD, 'Walk': GAITS['Walk']['period'],
             'Stroll': GAITS['Stroll']['period'], 'Run': GAITS['Run']['period'], 'Jump': 1.6,
             'PickUpPackage': 1.6, 'PickUpHigh': 1.6, 'Sit': 4.0,
             'TurnInPlace': TURN_PERIOD, 'CarryWalk': GAITS['Walk']['period'],
             'ThrowPackage': 1.0, 'DropPackage': .9, 'Drive': 2.0,
             'EnterTruck': 1.2, 'ExitTruck': 1.2, 'RingDoorbell': 1.1,
             'Stumble': 1.2, 'Slip': 1.3, 'Pushed': .9, 'BoxHit': .8,
             'Scared': 1.0, 'Dizzy': 2.4, 'ShakeOffWater': 1.8,
             'Wave': 2.2, 'Clap': 2.4, 'Facepalm': 2.2, 'Shrug': 2.0,
             'Point': 2.0, 'ThumbsUp': 2.0, 'MeltAndReturn': 3.0,
             'ShakeLikeDog': 1.8, 'Pancake': 2.4, 'GumStretch': 2.8,
             'BallBounce': 2.4, 'SplitAndJoin': 3.2, 'ColdShiver': 2.0,
             'Inflate': 2.8}
PURE_GEL_CLIPS = ('Pancake', 'GumStretch', 'BallBounce', 'SplitAndJoin',
                  'ColdShiver', 'Inflate')
LOOPING = ('Idle', 'Walk', 'Stroll', 'Run', 'Sit', 'TurnInPlace', 'CarryWalk', 'Drive')

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

def polish_action_curves(action):
    """Keep dense authored samples smooth without allowing Bezier overshoot.

    The clips are sampled at 60 Hz so the exact authored pose still exists on
    every frame. Auto-clamped handles only soften the sub-frame path between
    those samples; unlike free handles they cannot introduce a new extremum
    that sinks a planted foot or flips an IK pole.
    """
    curve_count = 0
    key_count = 0
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    curve_count += 1
                    for key in curve.keyframe_points:
                        key.interpolation = 'BEZIER'
                        key.handle_left_type = 'AUTO_CLAMPED'
                        key.handle_right_type = 'AUTO_CLAMPED'
                        key_count += 1
    return {'curves': curve_count, 'keyframes': key_count}

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
# The tummy keeps the arms off the sides: they hang out a little, elbows
# soft, the upper arm turned out so the forearms clear it.
HANG = (52., 8., 18., 0., 15., 0.)
NEUTRAL = dict(
    px=0., py=0., pz=0., p_pitch=0., p_roll=0., p_yaw=0.,
    s_pitch=0., s_roll=0., s_yaw=0.,
    c_pitch=0., c_roll=0., c_yaw=0.,
    h_pitch=0., h_roll=0., h_yaw=0.,
    by=0., bz=0., bs=0.,
    s_scale=(1., 1., 1.), c_scale=(1., 1., 1.), h_scale=(1., 1., 1.),
    armL=HANG, armR=HANG,
    thumbL=5., thumbR=5.,
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

    def arm(self, side, a, thumb=5.):
        lower, swing, bend, twist, ext, shrug = a
        s = 1 if side == 'L' else -1
        self.fkm('clavicle.'+side, R('Y', -s*shrug))
        # ext rotates the upper arm about itself: + points a bent forearm outward.
        self.fkm('upper_arm.'+side, R('X', -swing) @ R('Y', s*lower) @ R('X', ext))
        # twist turns the forearm about its own axis (- brings the thumb up).
        self.fkm('forearm.'+side, R('Z', -s*bend) @ R('X', s*twist))
        self.fkm('thumb.'+side, R('Z', s*thumb))

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
        self.fk('pelvis', q['p_pitch'], q['p_roll'], q['p_yaw'],
                loc=(q['px'], q['py'], q['pz']))
        self.fk('spine', q['s_pitch'], q['s_roll'], q['s_yaw'], scale=q['s_scale'])
        self.fk('chest', q['c_pitch'], q['c_roll'], q['c_yaw'], scale=q['c_scale'])
        self.fk('head', q['h_pitch'], q['h_roll'], q['h_yaw'], scale=q['h_scale'])
        self.fkm('belly', None, loc=(0, q['by'], q['bz']),
                 scale=(1+q['bs'], 1, 1+q['bs']*.7))
        for side in 'LR':
            self.arm(side, q['arm'+side], q['thumb'+side])
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
        armL=(HANG[0]-1.5*breath+arm_sway, HANG[1]+.8*math.sin(w-.9), HANG[2]+2*breath, HANG[3], HANG[4], 1.2*breath),
        armR=(HANG[0]-1.5*breath-arm_sway, HANG[1]-.8*math.sin(w-.9), HANG[2]+2*breath, HANG[3], HANG[4], 1.2*breath),
        footL=(0, 0, 0, 0), footR=(0, 0, 0, 0),
    )

def gait(name, t):
    g = GAITS[name]
    T, D, v, run = g['period'], g['duty'], g['speed'], g['run']
    # Run (sprint) takes Walk's running numbers except where S() says otherwise.
    sprint = g.get('sprint', False)
    S = lambda walk_run, run_value: run_value if sprint else walk_run
    p = (t/T) % 1.
    a = TAU*p
    stride = v*T                    # BU travelled per full cycle
    stance = stride*D               # ground travelled by a planted foot
    centre = S(.03, .05) if run else .0     # stance centred slightly behind the hip
    lift = S(.26, .44) if run else .13
    # Roll angles at touchdown / toe-off.
    r_td = -3. if run else -14.
    r_to = S(38., 40.) if run else 30.
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
        pz = S(-.15, -.14) - S(.05, .075)*math.cos(phase2)
    else:
        pz = -.05 + .03*math.cos(phase2)
    # + when the left foot is loaded. Left stance centres on p=mid.
    load = math.cos(TAU*(p-mid))
    reach = math.cos(a)             # + left leg forward (touchdown at p=0)
    lag = .07 if run else .05
    arm_amp = S(27., 44.) if run else 18.
    bend = S(78., 84.) if run else 24.
    bend_amp = S(20., 22.) if run else 8.
    bias = S(7., 10.) if run else 3.         # arms swing further forward than back
    twist = -42. if run else -18.            # loose fists, thumbs up
    swing_l = bias-arm_amp*math.cos(a-TAU*lag)  # left arm back while left leg forward

    def arm(swing, forward):
        # Swinging forward the elbow flexes and the upper arm turns out, so
        # the fist passes beside the tummy, not through it. Swinging back
        # the elbow opens.
        f = (forward+1)/2
        lower, ext, ext_fwd = GAIT_ARMS['sprint' if sprint else 'run' if run else 'walk']
        return (lower, swing, bend+bend_amp*(2*f-1), twist, ext+ext_fwd*f, 0.)
    lean = S(7.5, 13.) if run else 2.5
    bounce_lag = math.cos(phase2-1.1)       # head and belly trail the bounce
    return dict(
        px=(.035 if run else .03)*load, py=0., pz=pz,
        p_pitch=S(2., 4.) if run else 0., p_roll=(S(-6., -5.) if run else -3.5)*load,
        p_yaw=(S(-7., -10.) if run else -5.)*reach,
        s_pitch=lean, s_roll=(2.5 if run else 1.4)*math.cos(TAU*(p-mid)-.5),
        s_yaw=(S(4., 5.) if run else 3.)*reach,
        c_pitch=S(2., 4.) if run else .5, c_roll=(1.8 if run else 1.)*math.cos(TAU*(p-mid)-.9),
        c_yaw=(S(8., 12.) if run else 5.)*math.cos(a-TAU*lag*.5),
        # The head keeps the gaze steady: it cancels most of the lean and
        # twist, and nods a beat after each bounce.
        h_pitch=-lean*.8 + (S(3.4, 4.5) if run else 1.4)*bounce_lag,
        h_roll=(2. if run else 1.)*math.cos(TAU*(p-mid)-1.4),
        h_yaw=-(5. if run else 4.)*math.cos(a-TAU*lag*1.5),
        # The tummy is heavy: it lags the bounce, swells as it lands and
        # sways a little toward the loaded side.
        by=(S(.022, .03) if run else .01)*math.sin(phase2-1.3),
        bz=(S(-.055, -.08) if run else -.022)*bounce_lag,
        bs=(S(.035, .05) if run else .015)*max(0., bounce_lag),
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
    # skeleton compresses into a landing pose and the head and arms keep
    # going. Gel squash and secondary wobble are runtime physics layers.
    air = jump(.84)
    base = blend(air, rest, smooth(.9, 1.06, t))
    u = clamp01((t-.9)/.1)
    squash = 1-(1-u)**3 if t < 1. else keys(t, [(1., 1.), (1.2, .26), (1.42, .04), (1.6, 0.)])
    head_nod = ramped(t, .93, 1., 2.6, 5.5)
    arm_swing = ramped(t, 1.0, 1., 1.8, 4.)
    P = dict(base)
    P.update(
        pz=base['pz']-.34*squash+.012*math.sin(math.pi*smooth(1.18, 1.5, t)),
        py=base['py']+.06*squash,
        s_pitch=base['s_pitch']+15*squash, c_pitch=base['c_pitch']+6*squash,
        h_pitch=base['h_pitch']-4*squash+9*head_nod,
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
    # One deliberate weight transfer and overshoot, not a repeating wobble:
    # SpringBoneSimulator3D owns all jelly motion on top of this acting pose.
    load_shift = keys(t, [(0., 0.), (.42, 0.), (.82, 1.), (1.18, -.28), (1.48, 0.), (1.6, 0.)])
    P = dict(rest)
    P.update(
        pz=rest['pz']+.025*rise-.43*down-.03*settle,
        py=.16*down,                                  # hips back: a squat, not a stoop
        s_pitch=rest['s_pitch']+24*down-6*effort*lift, c_pitch=rest['c_pitch']+8*down-3*effort,
        s_roll=rest['s_roll']+2.4*load_shift, c_roll=rest['c_roll']-1.5*load_shift,
        h_pitch=rest['h_pitch']+14*look*(1-lift)-10*down*(1-lift)-4*effort+2*settle,
        h_roll=rest['h_roll']+keys(t, [(0, 0.), (.3, -4.), (.9, 3.), (1.6, 0.)]),
        h_yaw=rest['h_yaw']*(1-look),
    )
    # Hands on arcs: out and down around the tummy to the box's sides, a
    # squeeze, then the box comes in toward the chest before going up.
    reach = c['reach']
    for side, s in (('L', 1), ('R', -1)):
        start, rot0 = HANDS0[side]
        width = s*(PICKUP_WIDTH-.04*hug)
        if t < .42:
            pos = bezier(start, (s*PICKUP_ARC, -.72, 1.25), (width, -.94, 1.02), reach)
        else:
            pos = bezier((width, -.94, 1.02), (width, -.92, 1.45), CARRY_HANDS(s), lift)
        P['hand'+side] = pos
        P['hrot'+side] = lerp(rot0, (-55., 0., -s*75.), reach)
        P['ik'+side] = 1.
        P['arm'+side] = tuple(rest['arm'+side][:5]) + (3*hug,)
    return P

# Where the hands meet the box in each pickup (wrist height, BU). player.gd
# blends the two clips by the box's grip height between these (x 0.5 m/BU).
PICKUP_GRAB_Z = {'PickUpPackage': 1.02, 'PickUpHigh': 1.85}
# Half the box's width at the grab, and where the hands hold it after the
# lift: in front of the chest, the tummy under it (the game's IK then takes
# the hands to the real box).
PICKUP_WIDTH = .72
CARRY_HANDS = lambda s: (s*PICKUP_WIDTH, -.95, 1.97)
# The hands leave the sides on an arc this far out, around the tummy.
PICKUP_ARC = 1.45

def pickup_high(t):
    """PickUpPackage for a box at the waist (a shelf, a table): same duration
    and the same grab/lift/settle times, so the two blend frame by frame.
    No squat: the knees only soften, the torso leans a little toward the
    box, the arms reach straight out in front and pull it in to the chest."""
    rest = IDLE0
    c = pickup_timing(t)
    look, rise, down, lift = c['look'], c['rise'], c['down'], c['lift']
    effort, settle, hug = c['effort'], c['settle'], c['hug']
    load_shift = keys(t, [(0., 0.), (.42, 0.), (.82, 1.), (1.18, -.22), (1.48, 0.), (1.6, 0.)])
    P = dict(rest)
    P.update(
        # A small dip, weight a little back as the arms reach forward.
        pz=rest['pz']+.02*rise-.06*down-.02*settle,
        py=.04*down,
        # Leans from the waist toward the box, then back a touch under the
        # weight as it comes in to the chest.
        s_pitch=rest['s_pitch']+9*down-5*effort*lift, c_pitch=rest['c_pitch']+4*down-2*effort,
        s_roll=rest['s_roll']+1.4*load_shift, c_roll=rest['c_roll']-.9*load_shift,
        h_pitch=rest['h_pitch']+9*look*(1-lift)-3*down*(1-lift)-2*effort+2*settle,
        h_roll=rest['h_roll']+keys(t, [(0, 0.), (.3, -3.), (.9, 2.), (1.6, 0.)]),
        h_yaw=rest['h_yaw']*(1-look),
    )
    reach = c['reach']
    for side, s in (('L', 1), ('R', -1)):
        start, rot0 = HANDS0[side]
        width = s*(PICKUP_WIDTH-.04*hug)
        grab = (width, -1.04, PICKUP_GRAB_Z['PickUpHigh'])
        if t < .42:
            # Out around the tummy and forward, rising to the box's sides.
            pos = bezier(start, (s*(PICKUP_ARC-.1), -.92, 1.45), grab, reach)
        else:
            # Pulled in toward the chest: the carry pose PickUpPackage ends in.
            pos = bezier(grab, (width, -.92, 2.02), CARRY_HANDS(s), lift)
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

HAND_ON_BELLY = (.78, -.58, .72)   # wrist, pelvis dropped 1.0 BU for the seat

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


# --- gameplay clips ------------------------------------------------------------

def _carry_arms(P, bob=0., reach=1.):
    """Keep both wrists on the box while the lower body supplies motion.

    CarryPose replaces these authored targets with the real package in game;
    the clip remains useful in previews and gives that runtime IK a stable,
    already bent starting pose.
    """
    rest = IDLE0
    for side, s in (('L', 1), ('R', -1)):
        start, rot0 = HANDS0[side]
        P['hand'+side] = lerp(start, (s*PICKUP_WIDTH, -.95, 1.97+bob), reach)
        P['hrot'+side] = lerp(rot0, (-55., 0., -s*75.), reach)
        P['pole'+side] = (s*1.55, -.65, 1.25)
        P['ik'+side] = reach
        P['arm'+side] = tuple(rest['arm'+side][:5]) + (2.*reach,)
    return P


def carry_walk(t):
    """Quick carrying gait: planted feet from Walk, quiet chest, fixed box."""
    P = gait('Walk', t)
    p = (t/GAITS['Walk']['period']) % 1.
    step = math.cos(2*TAU*p)
    # A carried box damps twist and makes the body lean under its weight.
    P.update(
        s_pitch=P['s_pitch']+5., c_pitch=P['c_pitch']+2.,
        p_yaw=P['p_yaw']*.3, s_yaw=P['s_yaw']*.2, c_yaw=P['c_yaw']*.15,
        h_yaw=P['h_yaw']*.35, by=P['by']-.012, bz=P['bz']-.018,
    )
    return _carry_arms(P, -.012*step)


def throw_package(t):
    """Two-handed shove: anticipation, release in front, then recover."""
    rest = IDLE0
    prepare = keys(t, [(0., 0.), (.2, 1.), (.32, 1.), (.48, 0.)])
    release = keys(t, [(0., 0.), (.22, 0.), (.45, 1.), (.58, 1.), (.82, 0.), (1., 0.)])
    follow = keys(t, [(0., 0.), (.48, 0.), (.62, 1.), (.78, -.3), (1., 0.)])
    recover = smooth(.58, 1., t)
    P = dict(rest)
    P.update(
        py=-.10*prepare+.08*release, pz=rest['pz']-.08*prepare+.035*release,
        s_pitch=rest['s_pitch']-8.*prepare+13.*release+3.*follow,
        c_pitch=rest['c_pitch']-5.*prepare+8.*release+4.*follow,
        h_pitch=rest['h_pitch']+5.*prepare-7.*release-6.*follow,
        c_yaw=rest['c_yaw']+2.5*follow,
        footL=(0., .08*prepare, 0., 8.*prepare),
        footR=(0., -.08*prepare, 0., 0.),
    )
    _carry_arms(P, 0., 1.-recover)
    for side, s in (('L', 1), ('R', -1)):
        if recover < 1.:
            target = (s*(PICKUP_WIDTH+.04*release), -(.95+.42*release),
                      1.97+.08*release)
            P['hand'+side] = lerp(P['hand'+side], target, release)
    return blend(P, rest, smooth(.82, 1., t))


def drop_package(t):
    """Lower the box clear of the tummy, release it, and open the hands."""
    rest = IDLE0
    lower = keys(t, [(0., 0.), (.18, 0.), (.55, 1.), (.66, 1.), (.9, 0.)])
    release = smooth(.58, .9, t)
    P = dict(rest)
    P.update(
        py=.08*lower, pz=rest['pz']-.10*lower,
        s_pitch=rest['s_pitch']+11.*lower, c_pitch=rest['c_pitch']+4.*lower,
        h_pitch=rest['h_pitch']+8.*lower,
        by=rest['by']-.012*lower, bz=rest['bz']-.018*lower,
    )
    _carry_arms(P, -.26*lower, 1.-release)
    return blend(P, rest, release)


def drive(t):
    """Seated driving base; runtime IK attaches hands to wheel and feet to pedals."""
    P = sit(t*2.)
    w = TAU*t/2.
    steer = math.sin(w)
    press = (1.-math.cos(w))/2.
    left_foot, right_foot = P['footL'], P['footR']
    P.update(
        s_pitch=-7.+1.5*press, c_pitch=-2., h_pitch=-2.+1.2*press,
        h_yaw=3.*steer, p_roll=1.2*steer, c_roll=-1.5*steer,
        # Keep the deformation-safe seated leg shape, then press the right
        # pedal with a small ankle translation. S-311.80 supplies the truck's
        # exact pedal target, just as its existing runtime IK does for hands.
        footL=(left_foot[0]+.03, left_foot[1]-.04, left_foot[2], left_foot[3]),
        footR=(right_foot[0]-.03, right_foot[1]-.06*press,
               right_foot[2]+.025*press, right_foot[3]-5.*press),
        groundL=0., groundR=0., toeL=0., toeR=0.,
    )
    return P


def enter_truck(t):
    """Step up, turn into the cab and settle into the driving pose."""
    rest = IDLE0
    end = drive(0.)
    u = smooth(0., 1.2, t)
    P = blend(rest, end, u)
    step = math.sin(math.pi*u)
    P.update(
        px=P['px']-.16*step, py=P['py']-.12*step, pz=P['pz']+.18*step,
        p_yaw=P.get('p_yaw', 0.)-20.*step, s_roll=P.get('s_roll', 0.)+6.*step,
        h_yaw=P['h_yaw']+10.*step,
    )
    return P


def exit_truck(t):
    """Reverse the cab climb and finish exactly in the standing idle pose."""
    return enter_truck(1.2-clamp01(t/1.2)*1.2)


def ring_doorbell(t):
    """Reach around the tummy with the right hand, press, return to Idle."""
    rest = IDLE0
    reach = keys(t, [(0., 0.), (.18, 0.), (.46, 1.), (.67, 1.), (1.02, 0.), (1.1, 0.)])
    press = keys(t, [(0., 0.), (.48, 0.), (.56, 1.), (.64, 0.), (1.1, 0.)])
    P = dict(rest)
    P.update(
        px=rest['px']-.035*reach, s_pitch=rest['s_pitch']+5.*reach,
        s_roll=rest['s_roll']+3.*reach, c_yaw=rest['c_yaw']-8.*reach,
        h_pitch=rest['h_pitch']-3.*reach, h_yaw=rest['h_yaw']-10.*reach,
    )
    # FK keeps the thickest body safe: the elbow travels outside the belly
    # instead of an IK wrist taking the shortest path through it.
    button_arm = (35., 68.+5.*press, 48.-8.*press, -24., 48., 5.)
    P['armR'] = lerp(rest['armR'], button_arm, reach)
    return P


# --- reaction clips ------------------------------------------------------------

def stumble(t):
    """Catch a forward trip with one hurried step and wide balancing arms."""
    rest = IDLE0
    lurch = keys(t, [(0., 0.), (.12, 1.), (.48, .72), (.9, 0.), (1.2, 0.)])
    step = math.sin(math.pi*smooth(.04, .78, t))
    P = dict(rest)
    P.update(
        py=rest['py']-.22*lurch, pz=rest['pz']-.12*lurch,
        p_pitch=rest['p_pitch']+5.*lurch, p_roll=rest['p_roll']-5.*lurch,
        s_pitch=rest['s_pitch']+22.*lurch, s_roll=rest['s_roll']+5.*lurch,
        c_pitch=rest['c_pitch']+8.*lurch,
        h_pitch=rest['h_pitch']-13.*lurch, h_roll=rest['h_roll']-4.*lurch,
        by=rest['by']-.025*lurch, bz=rest['bz']-.04*lurch,
        footL=(.05*step, -.30*step, .13*step, -7.*step), groundL=1.-step,
    )
    P['armL'] = lerp(rest['armL'], (30., 36., 44., -18., 28., 5.), lurch)
    P['armR'] = lerp(rest['armR'], (34., 25., 50., 18., 30., 4.), lurch)
    return blend(P, rest, smooth(.9, 1.2, t))


def slip(t):
    """One foot shoots forward while the torso and arms save a backward fall."""
    rest = IDLE0
    skid = keys(t, [(0., 0.), (.14, 1.), (.58, .9), (1.0, 0.), (1.3, 0.)])
    foot = math.sin(math.pi*smooth(.03, .92, t))
    P = dict(rest)
    P.update(
        py=rest['py']+.20*skid, pz=rest['pz']-.13*skid,
        p_pitch=rest['p_pitch']-7.*skid, p_roll=rest['p_roll']+4.*skid,
        s_pitch=rest['s_pitch']-17.*skid, s_roll=rest['s_roll']-4.*skid,
        c_pitch=rest['c_pitch']-8.*skid,
        h_pitch=rest['h_pitch']+10.*skid, h_roll=rest['h_roll']+4.*skid,
        by=rest['by']+.02*skid, bz=rest['bz']-.025*skid,
        footR=(-.04*foot, -.36*foot, .16*foot, -12.*foot), groundR=1.-foot,
        footL=(.02*skid, .07*skid, 0., 0.),
    )
    P['armL'] = lerp(rest['armL'], (28., -20., 38., -12., 32., 5.), skid)
    P['armR'] = lerp(rest['armR'], (26., -30., 44., 12., 34., 6.), skid)
    return blend(P, rest, smooth(1., 1.3, t))


def pushed(t):
    """A shove from the right displaces the body left before it regains balance."""
    rest = IDLE0
    hit = keys(t, [(0., 0.), (.08, 1.), (.38, .7), (.7, 0.), (.9, 0.)])
    brace = math.sin(math.pi*smooth(.03, .68, t))
    P = dict(rest)
    P.update(
        px=rest['px']+.24*hit, pz=rest['pz']-.07*hit,
        p_roll=rest['p_roll']-16.*hit, p_yaw=rest['p_yaw']-5.*hit,
        s_roll=rest['s_roll']-11.*hit, s_yaw=rest['s_yaw']+7.*hit,
        c_roll=rest['c_roll']+6.*hit,
        h_roll=rest['h_roll']+12.*hit, h_yaw=rest['h_yaw']+5.*hit,
        footL=(.14*brace, -.03*brace, .08*brace, 0.), groundL=1.-brace,
        footR=(-.03*hit, .02*hit, 0., 0.),
    )
    P['armL'] = lerp(rest['armL'], (34., -22., 38., -10., 28., 4.), hit)
    P['armR'] = lerp(rest['armR'], (44., 32., 54., 18., 24., 5.), hit)
    return blend(P, rest, smooth(.7, .9, t))


def box_hit(t):
    """A box to the upper body produces a compact, asymmetric protective flinch."""
    rest = IDLE0
    recoil = keys(t, [(0., 0.), (.06, 1.), (.32, .72), (.58, 0.), (.8, 0.)])
    P = dict(rest)
    P.update(
        py=rest['py']+.08*recoil, pz=rest['pz']-.08*recoil,
        p_pitch=rest['p_pitch']-4.*recoil, p_roll=rest['p_roll']+5.*recoil,
        s_pitch=rest['s_pitch']-10.*recoil, s_roll=rest['s_roll']-6.*recoil,
        c_pitch=rest['c_pitch']-7.*recoil, c_yaw=rest['c_yaw']+6.*recoil,
        h_pitch=rest['h_pitch']+15.*recoil, h_roll=rest['h_roll']-8.*recoil,
        by=rest['by']+.018*recoil, bz=rest['bz']-.03*recoil,
    )
    P['armL'] = lerp(rest['armL'], (22., 52., 78., -28., 42., 8.), recoil)
    P['armR'] = lerp(rest['armR'], (30., 38., 68., 24., 38., 7.), recoil)
    return blend(P, rest, smooth(.58, .8, t))


def scared(t):
    """An explosive surprise: duck, shoulders up, hands high, then recover."""
    rest = IDLE0
    fright = keys(t, [(0., 0.), (.07, 1.), (.42, .86), (.72, 0.), (1., 0.)])
    P = dict(rest)
    P.update(
        pz=rest['pz']-.18*fright, py=rest['py']+.05*fright,
        p_pitch=rest['p_pitch']+5.*fright,
        s_pitch=rest['s_pitch']+10.*fright, c_pitch=rest['c_pitch']-5.*fright,
        h_pitch=rest['h_pitch']-12.*fright, h_roll=rest['h_roll']+3.*fright,
        by=rest['by']-.02*fright, bz=rest['bz']-.035*fright,
        bs=rest['bs']+.025*fright,
        footL=(.04*fright, .04*fright, 0., 0.),
        footR=(-.04*fright, .04*fright, 0., 0.),
    )
    P['armL'] = lerp(rest['armL'], (18., 50., 66., -22., 42., 12.), fright)
    P['armR'] = lerp(rest['armR'], (20., 44., 72., 22., 44., 12.), fright)
    return blend(P, rest, smooth(.72, 1., t))


def dizzy(t):
    """Two slow, increasingly damped sways with the head lagging the body."""
    rest = IDLE0
    envelope = keys(t, [(0., 0.), (.22, 1.), (1.65, 1.), (2.4, 0.)])
    wave = math.sin(TAU*t/.9)
    lag = math.sin(TAU*t/.9-.85)
    P = dict(rest)
    P.update(
        px=rest['px']+.06*wave*envelope, py=rest['py']+.025*lag*envelope,
        p_roll=rest['p_roll']-6.*wave*envelope,
        s_roll=rest['s_roll']+10.*wave*envelope,
        c_roll=rest['c_roll']-6.*lag*envelope,
        h_roll=rest['h_roll']+15.*lag*envelope,
        h_yaw=rest['h_yaw']+12.*wave*envelope,
        h_pitch=rest['h_pitch']+4.*lag*envelope,
        by=rest['by']+.012*lag*envelope, bz=rest['bz']-.018*wave*envelope,
    )
    P['armL'] = lerp(rest['armL'], (40., -10.+8.*wave, 32., -8., 25., 3.), envelope)
    P['armR'] = lerp(rest['armR'], (42., 6.-8.*wave, 36., 8., 26., 3.), envelope)
    return blend(P, rest, smooth(2.05, 2.4, t))


def shake_off_water(t):
    """Dog-like whole-body shake with planted feet and loose, trailing arms."""
    rest = IDLE0
    envelope = keys(t, [(0., 0.), (.16, 1.), (1.42, 1.), (1.8, 0.)])
    shake = math.sin(TAU*5.*t)*envelope
    trail = math.sin(TAU*5.*t-.8)*envelope
    P = dict(rest)
    P.update(
        p_yaw=rest['p_yaw']+7.*shake, p_roll=rest['p_roll']+2.5*trail,
        s_yaw=rest['s_yaw']-13.*shake, s_roll=rest['s_roll']-4.*trail,
        c_yaw=rest['c_yaw']+16.*trail, c_roll=rest['c_roll']+5.*shake,
        h_yaw=rest['h_yaw']-22.*shake, h_roll=rest['h_roll']-7.*trail,
        by=rest['by']+.018*trail, bz=rest['bz']-.012*abs(shake),
        bs=rest['bs']+.018*abs(shake),
    )
    P['armL'] = lerp(rest['armL'], (38., 5.+10.*trail, 34., -10., 26., 3.), envelope)
    P['armR'] = lerp(rest['armR'], (40., 5.-10.*trail, 36., 10., 28., 3.), envelope)
    return blend(P, rest, smooth(1.55, 1.8, t))


# --- emote clips ---------------------------------------------------------------

def wave(t):
    """Raise one hand, greet with three loose waves, and settle to Idle."""
    rest = IDLE0
    show = keys(t, [(0., 0.), (.28, 1.), (1.72, 1.), (2.2, 0.)])
    oscillation = math.sin(TAU*2.25*max(0., t-.28))*show
    P = dict(rest)
    P.update(
        s_roll=rest['s_roll']-3.*show, c_yaw=rest['c_yaw']-5.*show,
        h_yaw=rest['h_yaw']-9.*show, h_roll=rest['h_roll']+3.*show,
    )
    P['armR'] = lerp(rest['armR'],
                     (20., 37.+8.*oscillation, 94.+12.*oscillation,
                      12., 42., 8.), show)
    return blend(P, rest, smooth(1.72, 2.2, t))


def clap(t):
    """Bring both hands together for three broad, readable claps."""
    rest = IDLE0
    show = keys(t, [(0., 0.), (.3, 1.), (1.96, 1.), (2.4, 0.)])
    beat = (1.-math.cos(TAU*1.8*max(0., t-.3)))*.5*show
    P = dict(rest)
    P.update(
        pz=rest['pz']-.025*beat, s_pitch=rest['s_pitch']+3.*show,
        h_pitch=rest['h_pitch']-5.*show,
    )
    # FK stays on Jump's already certified overhead Y arc. The upper arms and
    # elbows pulse inward without an IK solver folding either chain.
    P['armL'] = lerp(rest['armL'],
                     (-28.-10.*beat, 14., 30.+6.*beat, 0., 0., 8.), show)
    P['armR'] = lerp(rest['armR'],
                     (-28.-10.*beat, 14., 30.+6.*beat, 0., 0., 8.), show)
    return blend(P, rest, smooth(1.96, 2.4, t))


def facepalm(t):
    """Pause, cover the face with one hand, and slump in disbelief."""
    rest = IDLE0
    cover = keys(t, [(0., 0.), (.36, 1.), (1.55, 1.), (2.2, 0.)])
    P = dict(rest)
    P.update(
        py=rest['py']+.035*cover, pz=rest['pz']-.06*cover,
        s_pitch=rest['s_pitch']+10.*cover, c_pitch=rest['c_pitch']+8.*cover,
        c_yaw=rest['c_yaw']-5.*cover, h_pitch=rest['h_pitch']+20.*cover,
        h_roll=rest['h_roll']-10.*cover, h_yaw=rest['h_yaw']-8.*cover,
    )
    P['armR'] = lerp(rest['armR'], (20., 44., 72., 22., 44., 12.), cover)
    P['armL'] = lerp(rest['armL'], (63., 1., 26., -5., 18., 1.), cover)
    return blend(P, rest, smooth(1.55, 2.2, t))


def shrug(t):
    """Lift shoulders and open both hands in a clear 'who knows?' pose."""
    rest = IDLE0
    hold = keys(t, [(0., 0.), (.3, 1.), (1.38, 1.), (2., 0.)])
    P = dict(rest)
    P.update(
        pz=rest['pz']-.035*hold, s_pitch=rest['s_pitch']-3.*hold,
        c_roll=rest['c_roll']+2.*hold, h_roll=rest['h_roll']+8.*hold,
        h_yaw=rest['h_yaw']-5.*hold,
    )
    P['armL'] = lerp(rest['armL'], (38., 22., 72., -38., 48., 15.), hold)
    P['armR'] = lerp(rest['armR'], (38., 22., 72., 38., 48., 15.), hold)
    P['thumbL'] = lerp(rest['thumbL'], 24., hold)
    P['thumbR'] = lerp(rest['thumbR'], 24., hold)
    return blend(P, rest, smooth(1.38, 2., t))


def point(t):
    """Turn toward and decisively point forward with the right arm."""
    rest = IDLE0
    show = keys(t, [(0., 0.), (.3, 1.), (1.42, 1.), (2., 0.)])
    accent = spring(t, .3, 5., 3.2, 7.)*show
    P = dict(rest)
    P.update(
        p_yaw=rest['p_yaw']-4.*show, s_yaw=rest['s_yaw']-8.*show,
        c_yaw=rest['c_yaw']-10.*show, h_yaw=rest['h_yaw']-15.*show,
        h_pitch=rest['h_pitch']-3.*show,
    )
    P['armR'] = lerp(rest['armR'],
                     (69., 82.+accent, 8., 4., 42., 5.), show)
    P['armL'] = lerp(rest['armL'], (57., -3., 28., -8., 19., 1.), show)
    P['thumbR'] = lerp(rest['thumbR'], -18., show)
    return blend(P, rest, smooth(1.42, 2., t))


def thumbs_up(t):
    """Present one fist beside the face with an unmistakably raised thumb."""
    rest = IDLE0
    show = keys(t, [(0., 0.), (.3, 1.), (1.4, 1.), (2., 0.)])
    nod = math.sin(math.pi*smooth(.35, .9, t))*show
    P = dict(rest)
    P.update(
        c_yaw=rest['c_yaw']-5.*show, h_yaw=rest['h_yaw']-8.*show,
        h_pitch=rest['h_pitch']+5.*nod,
    )
    P['armR'] = lerp(rest['armR'], (20., 44., 72., 22., 44., 12.), show)
    P['thumbR'] = lerp(rest['thumbR'], 24., show)
    return blend(P, rest, smooth(1.4, 2., t))


def melt_and_return(t):
    """Collapse into a low gelatinous puddle pose, wobble, then reform."""
    rest = IDLE0
    melt = keys(t, [(0., 0.), (.62, 1.), (1.72, 1.), (3., 0.)])
    wobble = math.sin(TAU*2.4*max(0., t-.5))*melt*smooth(.5, .75, t)
    P = dict(rest)
    P.update(
        py=rest['py']+.06*melt, pz=rest['pz']-.75*melt,
        p_pitch=rest['p_pitch']+5.*melt, p_roll=rest['p_roll']+3.*wobble,
        s_pitch=rest['s_pitch']+6.*melt, s_roll=rest['s_roll']-6.*wobble,
        c_pitch=rest['c_pitch']+3.*melt, c_roll=rest['c_roll']+5.*wobble,
        h_pitch=rest['h_pitch']-8.*melt, h_roll=rest['h_roll']-5.*wobble,
        by=rest['by']-.06*melt, bz=rest['bz']-.04*melt, bs=rest['bs']+.05*melt,
        footL=(.12*melt, -.04*melt, -.75*melt, -5.*melt),
        footR=(-.12*melt, -.04*melt, -.75*melt, -5.*melt),
        groundL=1.-melt, groundR=1.-melt,
    )
    P['armL'] = lerp(rest['armL'], (82., -20., 18., -18., 10., 0.), melt)
    P['armR'] = lerp(rest['armR'], (82., -12., 24., 18., 12., 0.), melt)
    return blend(P, rest, smooth(1.72, 3., t))


def shake_like_dog(t):
    """A playful nose-to-tail shake, stronger and springier than a hit reaction."""
    rest = IDLE0
    envelope = keys(t, [(0., 0.), (.18, 1.), (1.38, 1.), (1.8, 0.)])
    shake = math.sin(TAU*6.2*t)*envelope
    trail = math.sin(TAU*6.2*t-1.05)*envelope
    P = dict(rest)
    P.update(
        pz=rest['pz']-.04*abs(shake), p_yaw=rest['p_yaw']+10.*shake,
        p_roll=rest['p_roll']+4.*trail, s_yaw=rest['s_yaw']-18.*shake,
        s_roll=rest['s_roll']-7.*trail, c_yaw=rest['c_yaw']+22.*trail,
        c_roll=rest['c_roll']+8.*shake, h_yaw=rest['h_yaw']-30.*shake,
        h_roll=rest['h_roll']-11.*trail, by=rest['by']+.025*trail,
        bz=rest['bz']-.018*abs(shake), bs=rest['bs']+.025*abs(shake),
    )
    P['armL'] = lerp(rest['armL'],
                     (42., 7.+14.*trail, 39., -14., 30., 4.), envelope)
    P['armR'] = lerp(rest['armR'],
                     (43., 7.-14.*trail, 41., 14., 31., 4.), envelope)
    return blend(P, rest, smooth(1.5, 1.8, t))


# --- pure gelatin clips ---------------------------------------------------------

def pancake(t):
    """Squash the body into a wide, low pancake and spring upright."""
    rest = IDLE0
    flat = keys(t, [(0., 0.), (.48, 1.), (1.35, 1.), (2.4, 0.)])
    wobble = math.sin(TAU*2.2*max(0., t-.42))*flat*.04
    P = dict(rest)
    P.update(
        pz=rest['pz']-.08*flat,
        s_scale=(1.+.18*flat, 1.-.20*flat, 1.+.12*flat),
        c_scale=(1.+.18*flat, 1.-.18*flat, 1.+.12*flat),
        h_scale=(1.+.24*flat, 1.-.20*flat, 1.+.15*flat),
        p_roll=rest['p_roll']+3.*wobble, c_roll=rest['c_roll']-4.*wobble,
        by=rest['by']-.05*flat, bz=rest['bz']-.05*flat, bs=rest['bs']+.08*flat,
    )
    P['armL'] = lerp(rest['armL'], (24., -6., 18., -8., 15., 0.), flat)
    P['armR'] = lerp(rest['armR'], (24., -6., 18., 8., 15., 0.), flat)
    return blend(P, rest, smooth(1.82, 2.4, t))


def gum_stretch(t):
    """Pull the character tall and thin like warm chewing gum."""
    rest = IDLE0
    stretch = keys(t, [(0., 0.), (.58, 1.), (1.65, 1.), (2.8, 0.)])
    sway = math.sin(TAU*1.25*max(0., t-.5))*stretch
    P = dict(rest)
    P.update(
        s_scale=(1.-.13*stretch, 1.+.18*stretch, 1.-.13*stretch),
        c_scale=(1.-.10*stretch, 1.+.13*stretch, 1.-.10*stretch),
        h_scale=(1.-.08*stretch, 1.+.14*stretch, 1.-.08*stretch),
        p_roll=rest['p_roll']+1.5*sway, h_roll=rest['h_roll']-3.*sway,
        by=rest['by']-.025*stretch, bs=rest['bs']-.06*stretch,
    )
    P['armL'] = lerp(rest['armL'], (10., 5., 16., -5., 16., 5.), stretch)
    P['armR'] = lerp(rest['armR'], (10., 5., 16., 5., 16., 5.), stretch)
    return blend(P, rest, smooth(2.0, 2.8, t))


def ball_bounce(t):
    """Compress, bounce three times like a rubber ball, and settle."""
    rest = IDLE0
    envelope = keys(t, [(0., 0.), (.18, 1.), (1.55, .65), (2.05, .3), (2.4, 0.)])
    phase = max(0., t-.18)/.58
    arc = abs(math.sin(math.pi*phase))*envelope
    impact = (1.-abs(math.sin(math.pi*phase)))**6*envelope
    height = .46*arc
    P = dict(rest)
    P.update(
        pz=rest['pz']+height-.05*impact,
        s_scale=(1.+.07*impact, 1.-.06*impact, 1.+.07*impact),
        c_scale=(1.+.06*impact, 1.-.05*impact, 1.+.06*impact),
        h_scale=(1.+.05*impact, 1.-.04*impact, 1.+.05*impact),
        by=rest['by']-.025*impact, bs=rest['bs']+.06*impact,
        footL=(0., 0., height, 0.), footR=(0., 0., height, 0.),
        groundL=1.-arc, groundR=1.-arc,
    )
    P['armL'] = lerp(rest['armL'], (42., -8., 26., -6., 18., 1.), arc)
    P['armR'] = lerp(rest['armR'], (42., -8., 26., 6., 18., 1.), arc)
    return blend(P, rest, smooth(2.05, 2.4, t))


def split_and_join(t):
    """Pull upper and lower halves apart, hover, then snap back together."""
    rest = IDLE0
    split = keys(t, [(0., 0.), (.62, 1.), (1.72, 1.), (2.75, 0.), (3.2, 0.)])
    tremor = math.sin(TAU*2.8*max(0., t-.55))*split
    reunion = spring(t, 2.42, .035, 3.2, 5.5)
    P = dict(rest)
    P.update(
        px=rest['px']-.08*split+reunion, pz=rest['pz']-.06*split,
        p_roll=rest['p_roll']-3.*split,
        s_roll=rest['s_roll']+4.*split+1.5*tremor,
        c_roll=rest['c_roll']-3.*split-1.2*tremor,
        h_roll=rest['h_roll']+2.*split,
        by=rest['by']-.03*split, bz=rest['bz']+.02*split,
    )
    P['armL'] = lerp(rest['armL'], (34., -7., 25., -8., 20., 3.), split)
    P['armR'] = lerp(rest['armR'], (34., -7., 25., 8., 20., 3.), split)
    return blend(P, rest, smooth(2.75, 3.2, t))


def cold_shiver(t):
    """Contract and vibrate rapidly as if the gel were freezing."""
    rest = IDLE0
    cold = keys(t, [(0., 0.), (.18, 1.), (1.52, 1.), (2., 0.)])
    shiver = math.sin(TAU*8.5*t)*cold
    echo = math.sin(TAU*8.5*t-.9)*cold
    P = dict(rest)
    P.update(
        pz=rest['pz']-.035*cold, p_yaw=rest['p_yaw']+3.*shiver,
        s_yaw=rest['s_yaw']-7.*shiver, s_roll=rest['s_roll']+3.*echo,
        c_yaw=rest['c_yaw']+9.*echo, c_roll=rest['c_roll']-4.*shiver,
        h_yaw=rest['h_yaw']-12.*shiver, h_roll=rest['h_roll']+5.*echo,
        by=rest['by']+.015*echo, bs=rest['bs']+.025*abs(shiver),
    )
    P['armL'] = lerp(rest['armL'], (45., 17.+8.*echo, 48., -14., 24., 9.), cold)
    P['armR'] = lerp(rest['armR'], (45., 17.-8.*echo, 48., 14., 24., 9.), cold)
    return blend(P, rest, smooth(1.52, 2., t))


def inflate(t):
    """Swallow air, inflate into a round balloon, wobble, and deflate."""
    rest = IDLE0
    full = keys(t, [(0., 0.), (.72, 1.), (1.72, 1.), (2.8, 0.)])
    wobble = math.sin(TAU*2.1*max(0., t-.65))*full
    P = dict(rest)
    P.update(
        pz=rest['pz']+.025*full,
        s_scale=(1.+.10*full, 1.+.035*full, 1.+.10*full),
        c_scale=(1.+.11*full, 1.+.035*full, 1.+.11*full),
        h_scale=(1.+.08*full, 1.+.025*full, 1.+.08*full),
        p_roll=rest['p_roll']+1.5*wobble, c_roll=rest['c_roll']-2.*wobble,
        h_roll=rest['h_roll']+2.5*wobble,
        by=rest['by']-.045*full, bz=rest['bz']+.01*full, bs=rest['bs']+.18*full,
    )
    P['armL'] = lerp(rest['armL'], (38., -5., 20., -8., 20., 3.), full)
    P['armR'] = lerp(rest['armR'], (38., -5., 20., 8., 20., 3.), full)
    return blend(P, rest, smooth(2.0, 2.8, t))

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
             'Run': lambda t: gait('Run', t),
             'Jump': jump, 'PickUpPackage': pickup, 'PickUpHigh': pickup_high, 'Sit': sit,
             'TurnInPlace': turn_in_place, 'CarryWalk': carry_walk,
             'ThrowPackage': throw_package, 'DropPackage': drop_package, 'Drive': drive,
             'EnterTruck': enter_truck, 'ExitTruck': exit_truck,
             'RingDoorbell': ring_doorbell, 'Stumble': stumble, 'Slip': slip,
             'Pushed': pushed, 'BoxHit': box_hit, 'Scared': scared, 'Dizzy': dizzy,
             'ShakeOffWater': shake_off_water, 'Wave': wave, 'Clap': clap,
             'Facepalm': facepalm, 'Shrug': shrug, 'Point': point,
             'ThumbsUp': thumbs_up, 'MeltAndReturn': melt_and_return,
             'ShakeLikeDog': shake_like_dog, 'Pancake': pancake,
             'GumStretch': gum_stretch, 'BallBounce': ball_bounce,
             'SplitAndJoin': split_and_join, 'ColdShiver': cold_shiver,
             'Inflate': inflate}
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
        # Dense samples preserve the authored arcs; clamped handles smooth the
        # sub-frame path without the overshoot of unrestricted Bezier curves.
        polish_action_curves(action)
    rig.animation_data.action = bpy.data.actions['Idle']
    poser.apply(idle(0.))
    return DURATIONS
