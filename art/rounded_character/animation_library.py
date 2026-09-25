"""Five authored actions, sampled at 60 Hz. Blender axes, before game scale.

Foot contacts use linear backward travel (3.2 m/s after scale) and a Hermite
swing with matching endpoint velocity. Cyclic secondary motion has an exact
period; one-shots use quintic easing so acceleration is continuous at holds.
"""
import math
import bpy
from mathutils import Vector, Euler

FPS = 60
WALK_DURATION = .5
WALK_SPEED = 3.2
CONTACT = .36
DURATIONS = {'Idle': 4.0, 'Walk': WALK_DURATION, 'Jump': 1.6,
             'PickUpPackage': 1.6, 'Sit': 4.0}

def ease(t):
    t = max(0., min(1., t))
    return t*t*t*(t*(6*t-15)+10)

def interpolate(t, points):
    for (a, x), (b, y) in zip(points, points[1:]):
        if t <= b:
            f = ease((t-a)/(b-a))
            return x + (y-x)*f
    return points[-1][1]

def foot_path(phase):
    """Position offset from ankle rest and pitch, plus measured contact flag."""
    p = phase % 1.
    travel = WALK_SPEED * 2 * WALK_DURATION  # Blender units per cycle.
    half = travel*CONTACT/2
    if p < CONTACT:
        return (0, -half+travel*p, 0), 0., True
    u = (p-CONTACT)/(1-CONTACT)
    # Hermite: same forward velocity at both joins. Toe clears during swing.
    v = travel*(1-CONTACT)
    h00, h10 = 2*u**3-3*u*u+1, u**3-2*u*u+u
    h01, h11 = -2*u**3+3*u*u, u**3-u*u
    y = h00*half + h10*v - h01*half + h11*v
    lift = .16*math.sin(math.pi*u)**2
    pitch = -12*math.sin(math.pi*u)**2
    return (0, y, lift), pitch, False

def build(rig):
    rest = {p.name: p.bone.matrix_local.copy() for p in rig.pose.bones}
    hands_rest = [Vector((1.115,-.035,1.47)),Vector((-1.115,-.035,1.47))]
    for act in list(bpy.data.actions): bpy.data.actions.remove(act)
    rig.animation_data_create()
    for k in list(rig.keys()):
        if k.startswith('IK_'): rig[k] = 1.

    def reset():
        for p in rig.pose.bones:
            p.location=(0,0,0); p.rotation_mode='XYZ'
            p.rotation_euler=(0,0,0); p.scale=(1,1,1)

    def fk(name, rot=(0,0,0), loc=(0,0,0), scale=(1,1,1)):
        p=rig.pose.bones[name]; basis=rest[name].to_3x3()
        rotation=Euler(tuple(math.radians(a) for a in rot)).to_matrix()
        p.rotation_euler=(basis.inverted() @ rotation @ basis).to_euler('XYZ',p.rotation_euler)
        p.location=basis.inverted() @ Vector(loc); p.scale=scale

    def ik(name, position, rot=(0,0,0)):
        fk(name,rot,Vector(position)-rest[name].translation)

    def feet(left=(0,0,0),right=(0,0,0), pitch_l=0,pitch_r=0):
        for side,offset,pitch in [('L',left,pitch_l),('R',right,pitch_r)]:
            ik('CTRL_foot_IK.'+side,rest['CTRL_foot_IK.'+side].translation+Vector(offset),(pitch,0,0))

    def hands(left,right,rot_l=(0,78,0),rot_r=(0,-78,0), pole_z=1.6):
        for side,sign,pos,rot in [('L',1,left,rot_l),('R',-1,right,rot_r)]:
            ik('CTRL_hand_IK.'+side,pos,rot)
            ik('CTRL_elbow.'+side,(sign*1.35,.65,pole_z))
            fk('thumb.'+side,(0,0,sign*5))

    def idle(t):
        reset(); p=2*math.pi*t/4
        breath=(1-math.cos(p))/2
        sway=.012*math.sin(p)
        fk('pelvis',rot=(0,.65*math.sin(p),0),loc=(sway,0,-.065))
        fk('chest',rot=(-1.2*breath,0,.7*math.sin(p)))
        fk('head',rot=(.8*breath,0,1.5*math.sin(p+.1)-1.5*math.sin(.1)))
        fk('belly',loc=(0,-.018*breath,.008*breath),scale=(1+.018*breath,1,1+.012*breath))
        hands(hands_rest[0]+Vector((sway,0,.008*breath)),hands_rest[1]+Vector((sway,0,.01*breath)))
        feet()

    def walk(t):
        reset(); p=t/WALK_DURATION; a=math.tau*p
        left,pl,_=foot_path(p); right,pr,_=foot_path(p+.5)
        # A short-legged trot at full gameplay speed, with quiet shoulders.
        bob=.035*math.sin(2*a-.45)
        fk('pelvis',rot=(0,1.4*math.cos(a),3*math.cos(a)),loc=(.025*math.sin(a),0,-.285+bob))
        fk('spine',rot=(5,0,-1.4*math.cos(a)))
        fk('chest',rot=(-1.5,0,-4*math.cos(a-.12)))
        fk('head',rot=(-2.5,0,1.6*math.cos(a-.22)))
        fk('belly',loc=(0,.01*math.sin(2*a-.6),-.018*math.sin(2*a-.75)))
        h=.18*math.cos(a)
        hands(hands_rest[0]+Vector((.025,h,-.15+.025*math.sin(a))),
              hands_rest[1]+Vector((-.025,-h,-.15-.025*math.sin(a))),pole_z=1.5)
        feet(left,right,pl,pr)

    def jump(t):
        # Runtime samples 0..0.70 from vertical velocity; 0.90..1.6 on landing.
        reset()
        squash=interpolate(t,[(0,.06),(.09,-.005),(.35,.02),(.65,.035),(.88,.01),(.94,.21),(1.13,.11),(1.6,.065)])
        tuck=interpolate(t,[(0,0),(.12,.02),(.40,.19),(.60,.15),(.86,0),(1.6,0)])
        lift=interpolate(t,[(0,0),(.15,.3),(.42,.5),(.68,.38),(.90,.1),(1.15,.04),(1.6,0)])
        fk('pelvis',loc=(0,0,-squash))
        fk('spine',rot=(interpolate(t,[(0,2),(.2,-3),(.65,1),(.94,9),(1.6,0)]),0,0))
        fk('head',rot=(-2*math.sin(math.pi*min(1,t/1.6)),0,0))
        recoil=math.sin(max(0,t-.9)*18)*math.exp(-max(0,t-.9)*9) if t>.9 else 0
        fk('belly',loc=(0,-.008*recoil,-.027*recoil))
        hands(hands_rest[0]+Vector((.02,-.12*lift,lift)),hands_rest[1]+Vector((-.02,-.12*lift,lift)))
        feet((0,.04*tuck,tuck),(0,-.08*tuck,tuck*.85))

    def pickup(t):
        reset()
        bend=interpolate(t,[(0,0),(.18,.18),(.52,1),(.66,1),(.95,.62),(1.32,.05),(1.6,0)])
        raise_box=interpolate(t,[(0,0),(.65,0),(1.38,1),(1.6,1)])
        reach=interpolate(t,[(0,0),(.15,.05),(.52,1),(1.6,1)])
        fk('pelvis',loc=(0,.12*bend,-.065-.32*bend))
        fk('spine',rot=(26*bend,0,0)); fk('chest',rot=(9*bend,0,0))
        fk('head',rot=(4*bend-2*raise_box,0,0))
        # Fingers meet the near sides before the lift, with a short grip hold.
        width=1.115+(.62-1.115)*reach
        y=-.035+(-.76+.035)*reach
        z=1.47+(1.08-1.47)*reach+.91*raise_box
        hands((width,y,z),(-width,y,z),(-55*reach,78*(1-reach),-75*reach),
              (-55*reach,-78*(1-reach),75*reach),pole_z=1.5)
        fk('belly',loc=(0,-.008*bend,-.008*bend))
        feet()

    def sit(t):
        reset(); p=math.tau*t/4; b=(1-math.cos(p))/2
        fk('pelvis',loc=(0,.05,-1.0)); fk('spine',rot=(-3,0,0))
        fk('chest',rot=(-.8*b,0,0)); fk('head',rot=(.4*b,0,.7*math.sin(p)))
        fk('belly',loc=(0,-.012*b,0),scale=(1+.01*b,1,1+.01*b))
        # Almost horizontal thighs, dangling shins. Cushion height unchanged.
        for side,sign in [('L',1),('R',-1)]:
            ik('CTRL_knee.'+side,(sign*.46,-1.4,.20))
        feet((.025,-.535,-.435),(-.025,-.535,-.435))
        hands((.65,-.25,.225+.006*b),(-.65,-.25,.225+.006*b),
              (0,15,-80),(0,-15,80),pole_z=.60)

    poses={'Idle':idle,'Walk':walk,'Jump':jump,'PickUpPackage':pickup,'Sit':sit}
    for name,duration in DURATIONS.items():
        action=bpy.data.actions.new(name); action.use_fake_user=True
        rig.animation_data.action=action
        for frame in range(round(duration*FPS)+1):
            poses[name](frame/FPS)
            for pb in rig.pose.bones:
                pb.keyframe_insert('location',frame=frame,group=pb.name)
                pb.keyframe_insert('rotation_euler',frame=frame,group=pb.name)
                pb.keyframe_insert('scale',frame=frame,group=pb.name)
        action.frame_range=(0,round(duration*FPS)); action.use_frame_range=True
        # Dense sampling preserves authored velocities; Bezier overshoot can
        # otherwise sink toes between samples or overshoot knee pole targets.
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points: key.interpolation='LINEAR'
    rig.animation_data.action=bpy.data.actions['Idle']
    idle(0)
    return DURATIONS
