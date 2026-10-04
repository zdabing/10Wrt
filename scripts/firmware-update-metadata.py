"""Stamp immutable firmware identity and publish matching sysupgrade metadata.

Run stamp BEFORE building images, release AFTER create-build-records.sh.
Identity in /usr/share avoids restoring an obsolete version with /etc backups.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path

PROFILES = {'r5c': 'friendlyarm_nanopi-r5c', 'x86_64': 'generic'}


def stamp(overlay, env):
    data = dict(schema=1, repo=env['GITHUB_REPOSITORY'], tag=env['FIRMWARE_TAG'],
                target=env['FIRMWARE_TARGET'], profile=PROFILES[env['BUILD_TARGET']],
                build_number=int(env['GITHUB_RUN_NUMBER']), config_commit=env['GITHUB_SHA'])
    if data['repo'] != 'zdabing/10Wrt' or data['build_number'] < 1:
        raise ValueError('Unexpected repository or build number')
    file = overlay / 'usr/share/10wrt/release.json'
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(json.dumps(data, separators=(',', ':')) + '\n', encoding='utf-8')
    return data


def release(overlay, firmware_dir):
    data = json.loads((overlay / 'usr/share/10wrt/release.json').read_text(encoding='utf-8'))
    profiles = json.loads((firmware_dir / 'profiles.json').read_text(encoding='utf-8'))
    if profiles.get('target') != data['target']:
        raise ValueError('profiles.json target differs from the installed identity')
    images = profiles['profiles'][data['profile']]['images']
    files = []
    for image in images:
        allowed = ('sysupgrade', 'combined', 'combined-efi') if data['target'] == 'x86/64' else ('sysupgrade',)
        if image.get('type') not in allowed:
            continue
        filename = image['name']
        if Path(filename).name != filename:
            raise ValueError('Invalid image filename')
        file = firmware_dir / filename
        with file.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        if digest != image['sha256'] or file.stat().st_size == 0 or file.stat().st_size != image['size']:
            raise ValueError(f'Image checksum mismatch: {filename}')
        files.append(dict(filename=filename, size=file.stat().st_size, sha256=digest,
                          filesystem=image.get('filesystem', '')))
    if not files:
        raise ValueError('No sysupgrade images for the selected profile')
    data['files'] = files
    body = json.dumps(data, separators=(',', ':'))
    (firmware_dir / '10wrt-update.json').write_text(body + '\n', encoding='utf-8')
    (firmware_dir / '10wrt-update-notes.md').write_text('\n<!-- 10wrt-update-metadata\n' + body + '\n-->\n', encoding='utf-8')
    return data


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('stamp', 'release'))
    parser.add_argument('--overlay', type=Path, default=Path('openwrt/files'))
    parser.add_argument('--firmware-dir', type=Path)
    args = parser.parse_args()
    if args.mode == 'stamp':
        stamp(args.overlay, os.environ)
    elif args.firmware_dir:
        release(args.overlay, args.firmware_dir)
    else:
        parser.error('release requires --firmware-dir')
