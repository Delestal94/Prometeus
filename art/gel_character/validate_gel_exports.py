"""Validate all final gel GLBs, including finite animated morph samples.

python art/gel_character/validate_gel_exports.py --output <report.json>
This is a finite 405-sample gate, not proof over continuous poses or morphs.
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
             'Sit': 4., 'TurnInPlace': .8}


def validate_exports(directory):
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
            failures, report = check_poses(path, lod, morph_weights=weights)
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
    result['valid'] = not errors and result['sample_count'] == 405
    if result['sample_count'] != 405:
        result['errors'].append(
            f"Expected 405 animated samples, got {result['sample_count']}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=DEFAULT_DIRECTORY)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    report = validate_exports(args.directory)
    encoded = json.dumps(report, indent=2)+'\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding='utf-8')
    print(encoded, end='')
    return 0 if report['valid'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
