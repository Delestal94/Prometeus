"""Validate all final gel GLBs, including finite animated morph samples.

python art/gel_character/validate_gel_exports.py --output <report.json>
This is a finite sample gate, not proof over continuous poses or morphs.
"""
import argparse
import json
from pathlib import Path

from gel_body_validation import MORPH_NAMES
from gel_pose_validation import check as check_poses
from validate_glb import validate_gel_body


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DEFAULT_DIRECTORY = ROOT/'do-not-drop/assets/models/characters/gel'
DURATIONS = {'Idle': 6., 'Walk': 1/3, 'Stroll': .6, 'Run': 1/3,
             'Jump': 1.6, 'PickUpPackage': 1.6, 'PickUpHigh': 1.6,
             'Sit': 4., 'TurnInPlace': .8, 'CarryWalk': 1/3,
             'ThrowPackage': 1., 'DropPackage': .9, 'Drive': 2.,
             'EnterTruck': 1.2, 'ExitTruck': 1.2, 'RingDoorbell': 1.1,
             'Stumble': 1.2, 'Slip': 1.3, 'Pushed': .9, 'BoxHit': .8,
             'Scared': 1., 'Dizzy': 2.4, 'ShakeOffWater': 1.8,
             'Wave': 2.2, 'Clap': 2.4, 'Facepalm': 2.2, 'Shrug': 2.,
             'Point': 2., 'ThumbsUp': 2., 'MeltAndReturn': 3.,
             'ShakeLikeDog': 1.8, 'Pancake': 2.4, 'GumStretch': 2.8,
             'BallBounce': 2.4, 'SplitAndJoin': 3.2, 'ColdShiver': 2.,
             'Inflate': 2.8, 'InspectHand': 3.4, 'BlowBubble': 3.2,
             'IdleBounce': 2.6, 'SimpleStep': 2.4, 'Robot': 2.4,
             'Disco': 2.8, 'FloorWorm': 3.2, 'Headbang': 1.6,
             'VictoryDance': 2.8, 'Defeat': 3., 'Flan': 2.4, 'Conga': 2.4}
EXPECTED_SAMPLES = len(DURATIONS) * 5 * 3 * 3


def validate_exports(directory, animation_names=None):
    states = {
        'base': [0.]*len(MORPH_NAMES),
        'general_thickness+1': [
            1. if name == 'general_thickness' else 0. for name in MORPH_NAMES],
        'leg_thickness+1': [
            1. if name == 'leg_thickness' else 0. for name in MORPH_NAMES],
    }
    result = {'static': [], 'animated': [], 'sample_count': 0}
    errors = []
    for lod in range(3):
        path = directory/f'gel_body_lod{lod}.glb'
        static = validate_gel_body(path, lod)
        details = static.get('gel_body', {})
        actual = {row.get('name'): row.get('duration_seconds')
                  for row in static.get('animations', [])}
        animation_errors = []
        if set(actual) != set(DURATIONS):
            animation_errors.append(
                f'Animation names differ: expected {sorted(DURATIONS)}, got {sorted(actual)}')
        for name in set(actual) & set(DURATIONS):
            if actual[name] is None or abs(actual[name]-DURATIONS[name]) >= .02:
                animation_errors.append(
                    f'{name} duration differs: expected {DURATIONS[name]:g}, got {actual[name]}')
        static_errors = list(static['errors'])+animation_errors
        result['static'].append({
            'lod': lod, 'valid': static['valid'] and not animation_errors,
            'errors': static_errors,
            'triangles': static.get('triangles'),
            'morph_samples': details.get('sample_count', 0),
        })
        errors.extend(f'LOD{lod} static: {error}' for error in static_errors)
        for state, weights in states.items():
            failures, report = check_poses(
                path, lod, morph_weights=weights,
                animation_names=animation_names)
            samples = report.get('samples', [])
            result['sample_count'] += len(samples)
            result['animated'].append({
                'lod': lod, 'state': state, 'samples': len(samples),
                'errors': failures,
                'max_contacts': max((sample['contacts'] for sample in samples), default=None),
                'max_orientation_failures': max(
                    (sample['orientation_failures'] for sample in samples), default=None),
            })
            errors.extend(f'LOD{lod} {state}: {error}' for error in failures)
    result['errors'] = errors
    expected_samples = (len(animation_names) if animation_names is not None
                        else len(DURATIONS)) * 5 * 3 * 3
    result['valid'] = not errors and result['sample_count'] == expected_samples
    if result['sample_count'] != expected_samples:
        result['errors'].append(
            f"Expected {expected_samples} animated samples, got {result['sample_count']}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=DEFAULT_DIRECTORY)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--clips', nargs='+', choices=sorted(DURATIONS),
                        help='validate only these clips across every LOD/morph state')
    args = parser.parse_args()
    report = validate_exports(args.directory, args.clips)
    encoded = json.dumps(report, indent=2)+'\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding='utf-8')
    print(encoded, end='')
    return 0 if report['valid'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
