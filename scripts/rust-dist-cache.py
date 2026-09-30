#!/usr/bin/env python3
"""Reuse complete, matching OpenWrt-built Rust distributions, never build stamps."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def components(version, host, target):
    return [f'rustc-{version}-{host}.tar.gz', f'cargo-{version}-{host}.tar.gz',
            f'rust-std-{version}-{host}.tar.gz', f'rust-std-{version}-{target}.tar.gz']


def check(cache, key, version, host, target):
    manifest = json.loads((cache / 'manifest.json').read_text())
    if manifest['key'] != key or manifest['version'] != version or manifest['host'] != host or manifest['target'] != target:
        raise ValueError('cache identity mismatch')
    entries = manifest['files']
    names = [entry['name'] for entry in entries]
    if len(set(names)) != len(names) or not set(components(version, host, target)).issubset(names):
        raise ValueError('missing or duplicate Rust components')
    if set(cache.glob('*.tar.gz')) != {cache / name for name in names}:
        raise ValueError('unexpected Rust distribution archive')
    for entry in entries:
        name = entry['name']
        if Path(name).name != name or not name.endswith('.tar.gz'):
            raise ValueError('invalid archive name')
        path = cache / name
        if path.is_symlink() or path.stat().st_size != entry['size'] or sha(path) != entry['sha256']:
            raise ValueError('Rust archive integrity failure')
    return names


def verify_compiler(cache, version, host, target, linker):
    # Real installation + native execution + target linking precede a cache hit.
    # The normal OpenWrt Host/Install still performs the final installation.
    with tempfile.TemporaryDirectory(prefix='rust-cache-verify-') as temp:
        root = Path(temp)
        prefix = root / 'installed'
        for name in components(version, host, target):
            with tarfile.open(cache / name) as archive:
                archive.extractall(root, filter='data')
            component = root / name.removesuffix('.tar.gz')
            subprocess.run(['bash', str(component / 'install.sh'), '--prefix=' + str(prefix),
                            '--disable-ldconfig'], check=True, stdout=subprocess.DEVNULL, timeout=120)
        rustc = prefix / 'bin/rustc'
        cargo = prefix / 'bin/cargo'
        for exe, label in ((rustc, 'rustc'), (cargo, 'cargo')):
            value = subprocess.check_output([str(exe), '--version'], text=True, timeout=20)
            if not value.startswith(f'{label} {version} '):
                raise ValueError('cached compiler version mismatch')
        source = root / 'smoke.rs'
        source.write_text('fn main() { println!("{}", std::thread::spawn(|| 42).join().unwrap()); }\n')
        native = root / 'native'
        subprocess.run([str(rustc), str(source), '-o', str(native)], check=True, timeout=60)
        if subprocess.check_output([str(native)], text=True, timeout=10).strip() != '42':
            raise ValueError('cached host std execution failed')
        cross = root / 'target'
        subprocess.run([str(rustc), str(source), '--target', target,
                        '-Ctarget-feature=-crt-static', '-Clinker=' + linker,
                        '-o', str(cross)], check=True, timeout=60)
        elf = cross.read_bytes()[:20]
        machine = 183 if target.startswith('aarch64-') else 62
        if elf[:6] != b'\x7fELF\x02\x01' or int.from_bytes(elf[18:20], 'little') != machine:
            raise ValueError('cached target std link architecture mismatch')


def restore(dist, cache, key, version, host, target, linker):
    names = check(cache, key, version, host, target)
    if list(dist.glob('*.tar.gz')):
        raise ValueError('existing dist output; use normal Rust build')
    verify_compiler(cache, version, host, target, linker)
    dist.mkdir(parents=True, exist_ok=True)
    for name in names:
        shutil.copy2(cache / name, dist / name)


def capture(dist, cache, key, version, host, target):
    if cache.name != key or not re.fullmatch('[0-9a-f]{64}', key):
        raise ValueError('invalid snapshot path')
    files = sorted(dist.glob('*.tar.gz'))
    if not set(components(version, host, target)).issubset(p.name for p in files):
        raise ValueError('source build did not produce required distributions')
    cache.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='rust-dist-', dir=cache.parent) as temp:
        pending = Path(temp)
        entries = []
        for path in files:
            if path.is_symlink():
                raise ValueError('unexpected distribution symlink')
            shutil.copy2(path, pending / path.name)
            entries.append({'name': path.name, 'size': path.stat().st_size, 'sha256': sha(path)})
        manifest = {'key': key, 'version': version, 'host': host, 'target': target, 'files': entries}
        (pending / 'manifest.json').write_text(json.dumps(manifest, indent=2))
        check(pending, key, version, host, target)
        # Only remove the dedicated snapshot identified by its SHA256 key.
        if cache.exists():
            shutil.rmtree(cache)
        shutil.copytree(pending, cache)


def prepare(root, cache_root):
    recipe = root / 'feeds/packages/lang/rust/Makefile'
    original = recipe.read_text()
    if '# 10Wrt Rust distribution cache' in original:
        raise ValueError('recipe already patched; prepare from a fresh checkout')
    if 'CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5c=y' not in (root / '.config').read_text().splitlines():
        raise ValueError('Rust cache currently covers R5C only')
    match = re.search(r'(?ms)^define Host/Compile\n(.*?)\nendef$', original)
    if not match:
        raise ValueError('unrecognized Rust Host/Compile recipe')
    identity = {
        'format': 1, 'config': sha(root / '.config'), 'recipe': sha(recipe),
        'rust_values': sha(recipe.with_name('rust-values.mk')),
        'openwrt': subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
        'packages': subprocess.check_output(['git', '-C', str(root / 'feeds/packages'), 'rev-parse', 'HEAD'], text=True).strip(),
        'local_toolchain_changes': subprocess.check_output(['git', '-C', str(root), 'diff', '--', 'include', 'toolchain', 'target'], text=True),
        'os': Path('/etc/os-release').read_text(), 'arch': os.uname().machine,
        'glibc': subprocess.check_output(['ldd', '--version'], text=True),
        'gcc': subprocess.check_output(['gcc', '--version'], text=True),
    }
    key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    helper = Path(__file__).resolve()
    cache = cache_root.resolve() / key
    for path in (helper, cache):
        if any(c in str(path) for c in "'\n\r$"):
            raise ValueError('unsupported build/cache path')
    args = f"'$(HOST_BUILD_DIR)/build/dist' '{cache}' '{key}' '$(PKG_VERSION)' '$(RUSTC_HOST_ARCH)' '$(RUSTC_TARGET_ARCH)'"
    cold = match.group(1).strip()
    body = ("define Host/Compile\n\t# 10Wrt Rust distribution cache: actual archives, no forged stamps\n"
            f"\t+if python3 '{helper}' restore {args} '$(TARGET_CC_NOCACHE)'; then \\\n"
            "\t\techo 'Verified OpenWrt Rust distribution cache hit'; \\\n"
            "\telse \\\n\t\t" + cold + "; \\\n"
            "\t\tresult=$$$$?; [ $$$$result -eq 0 ] || exit $$$$result; \\\n"
            f"\t\tpython3 '{helper}' capture {args} || echo 'Rust cache capture skipped'; \\\n"
            "\tfi\nendef")
    recipe.write_text(original[:match.start()] + body + original[match.end():])
    print('key=' + key)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='mode', required=True)
    prep = sub.add_parser('prepare'); prep.add_argument('root', type=Path); prep.add_argument('cache_root', type=Path)
    for mode in ('capture', 'restore'):
        cmd = sub.add_parser(mode)
        cmd.add_argument('dist', type=Path); cmd.add_argument('cache', type=Path)
        for name in ('key', 'version', 'host', 'target'): cmd.add_argument(name)
        if mode == 'restore': cmd.add_argument('linker')
    a = p.parse_args()
    try:
        if a.mode == 'prepare': prepare(a.root, a.cache_root)
        elif a.mode == 'capture': capture(a.dist, a.cache, a.key, a.version, a.host, a.target)
        else: restore(a.dist, a.cache, a.key, a.version, a.host, a.target, a.linker)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError, tarfile.TarError) as error:
        print('Rust distribution cache: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
