"""Preserve this firmware's APK kernel repository, public keys and Zen packages."""
import argparse
import hashlib
import json
import re
import tarfile
from pathlib import Path

REQUIRED = ('zen-traffic', 'luci-app-zen-traffic', 'luci-theme-zen',
            'kmod-sched-bpf', 'kmod-sched-core')


def check_config(root):
    config = (root / '.config').read_text(encoding='utf-8')
    symbols = ['CONFIG_PACKAGE_' + name for name in REQUIRED]
    symbols += ['CONFIG_USE_APK']
    missing = [symbol for symbol in symbols if not re.search(r'^' + re.escape(symbol) + r'=y\s*$', config, re.M)]
    if missing:
        raise ValueError('Required Zen configuration missing: ' + ', '.join(missing))


def export(root, target):
    check_config(root)
    if not re.fullmatch(r'[a-z0-9_-]+/[a-z0-9_-]+', target):
        raise ValueError('Invalid target')
    output = root / 'bin/targets' / target
    kernels = list((root / 'build_dir').glob('target-*/linux-*/linux-*/.config'))
    if len(kernels) != 1:
        raise ValueError('Missing or ambiguous built kernel configuration')
    kernel_config = kernels[0].read_text(encoding='utf-8')
    for symbol in ('CONFIG_BPF_SYSCALL', 'CONFIG_BPF_JIT', 'CONFIG_NET_CLS_BPF', 'CONFIG_NET_ACT_BPF'):
        if not re.search(r'^' + symbol + r'=[ym]\s*$', kernel_config, re.M):
            raise ValueError('Kernel lacks required capability: ' + symbol)
    modules = output / 'packages'
    if not (modules / 'packages.adb').is_file():
        raise ValueError('Matching kernel APK repository missing')
    for name in REQUIRED[3:]:
        if len(list(modules.glob(name + '-[0-9]*.apk'))) != 1:
            raise ValueError('Missing or ambiguous kernel package: ' + name)
    keys = list((root / 'build_dir').glob('target-*/root-*/etc/apk/keys/*.pem'))
    if not keys:
        raise ValueError('Firmware APK public keys missing')
    if any(b'-----BEGIN PUBLIC KEY-----' not in file.read_bytes() or b'PRIVATE KEY' in file.read_bytes() for file in keys):
        raise ValueError('Unexpected non-public key in firmware APK key directory')
    files = [(file, 'target/' + file.name) for file in modules.iterdir() if file.is_file() and file.suffix in ('.apk', '.adb')]
    for name in REQUIRED[:3]:
        packages = list((root / 'bin/packages').rglob(name + '-[0-9]*.apk'))
        if len(packages) != 1:
            raise ValueError('Missing or ambiguous Zen APK: ' + name)
        files.append((packages[0], 'zen/' + packages[0].name))
    for file in keys:
        files.append((file, 'keys/' + file.name))
    files.append((root / '.config', 'firmware.config'))
    files.append((kernels[0], 'kernel.config'))
    records = []
    seen = set()
    for file, name in files:
        if name in seen:
            raise ValueError('Ambiguous archive path: ' + name)
        seen.add(name)
        records.append(dict(path=name, sha256=hashlib.sha256(file.read_bytes()).hexdigest()))
    manifest = output / 'zen-support.json'
    manifest.write_text(json.dumps(dict(schema=1, target=target, files=records), indent=2) + '\n', encoding='utf-8')
    archive = output / 'zen-support.tar.gz'
    with tarfile.open(archive, 'w:gz', dereference=True) as bundle:
        for file, name in files:
            bundle.add(file, arcname=name, recursive=False)
        bundle.add(manifest, arcname='zen-support.json')
    return archive


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--target')
    parser.add_argument('--check-config', action='store_true')
    args = parser.parse_args()
    if args.check_config:
        check_config(args.root)
    elif args.target:
        print(export(args.root, args.target))
    else:
        parser.error('--target or --check-config is required')
