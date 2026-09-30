import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
import contextlib
import os
import re

spec = importlib.util.spec_from_file_location('cache', Path(__file__).with_name('rust-dist-cache.py'))
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class Distributions(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dist = self.root / 'dist'; self.dist.mkdir()
        self.key = 'a' * 64
        self.snapshot = self.root / 'cache' / self.key
        self.version = '1.96.0'; self.host = 'x86_64-unknown-linux-gnu'; self.target = 'aarch64-unknown-linux-musl'
        for name in cache.components(self.version, self.host, self.target):
            with tarfile.open(self.dist / name, 'w:gz') as archive:
                body = b'fixture; no executable compiler'
                entry = tarfile.TarInfo(name.removesuffix('.tar.gz') + '/fixture')
                entry.size = len(body); archive.addfile(entry, io.BytesIO(body))

    def capture(self):
        cache.capture(self.dist, self.snapshot, self.key, self.version, self.host, self.target)

    def check(self, key=None, target=None):
        return cache.check(self.snapshot, key or self.key, self.version, self.host, target or self.target)

    def test_complete_snapshot_roundtrip(self):
        self.capture()
        self.assertEqual(set(self.check()), {p.name for p in self.dist.iterdir()})

    def test_source_or_configuration_key_change_rejected(self):
        self.capture()
        with self.assertRaisesRegex(ValueError, 'identity'): self.check(key='b' * 64)

    def test_target_change_rejected(self):
        self.capture()
        with self.assertRaisesRegex(ValueError, 'identity'): self.check(target='x86_64-unknown-linux-musl')

    def test_truncated_archive_rejected(self):
        self.capture()
        archive = next(self.snapshot.glob('*.tar.gz')); archive.write_bytes(archive.read_bytes()[:-1])
        with self.assertRaisesRegex(ValueError, 'integrity'): self.check()

    def test_same_size_corruption_rejected(self):
        self.capture()
        archive = next(self.snapshot.glob('*.tar.gz')); data = bytearray(archive.read_bytes()); data[-1] ^= 1; archive.write_bytes(data)
        with self.assertRaisesRegex(ValueError, 'integrity'): self.check()

    def test_incomplete_build_not_captured(self):
        next(self.dist.glob('*rust-std*' + self.target + '*')).unlink()
        with self.assertRaisesRegex(ValueError, 'required'): self.capture()
        self.assertFalse(self.snapshot.exists())

    def test_missing_manifest_is_cold_miss(self):
        result = subprocess.run(['python3' if __import__('os').name != 'nt' else __import__('sys').executable,
            str(Path(cache.__file__)), 'restore', str(self.dist), str(self.snapshot),
            self.key, self.version, self.host, self.target, 'target-gcc'], capture_output=True)
        self.assertEqual(result.returncode, 1)

    def test_unsafe_snapshot_path_rejected(self):
        with self.assertRaisesRegex(ValueError, 'snapshot'):
            cache.capture(self.dist, self.root, '../bad', self.version, self.host, self.target)

    def test_extra_distribution_rejected(self):
        self.capture(); (self.snapshot / 'unknown.tar.gz').write_bytes(b'bad')
        with self.assertRaisesRegex(ValueError, 'unexpected'): self.check()

    def test_hashes_do_not_substitute_for_compiler_validation(self):
        self.capture()
        empty = self.root / 'output'
        # Valid archive hashes are insufficient: fixtures have no real installer/compiler.
        with self.assertRaises((OSError, subprocess.SubprocessError)):
            cache.restore(empty, self.snapshot, self.key, self.version, self.host, self.target, 'target-gcc')
        self.assertFalse(empty.exists())


@unittest.skipUnless(os.name == 'posix' and Path('/etc/os-release').exists(), 'Linux make integration')
class RecipeIntegration(unittest.TestCase):
    def test_cold_build_status_survives_make_eval(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'openwrt'; root.mkdir()
            feed = root / 'feeds/packages'; feed.mkdir(parents=True)
            for repo in (root, feed):
                subprocess.run(['git', 'init', '-q', str(repo)], check=True)
                subprocess.run(['git', '-C', str(repo), '-c', 'user.name=fixture', '-c',
                                'user.email=fixture@example.invalid', 'commit', '--allow-empty', '-qm', 'fixture'], check=True)
            recipe = feed / 'lang/rust/Makefile'; recipe.parent.mkdir(parents=True)
            recipe.write_text('PKG_VERSION:=1.96.0\ndefine Host/Compile\n\t$(PYTHON) -c "import sys; sys.exit($(COLD_RESULT))"\nendef\n')
            recipe.with_name('rust-values.mk').write_text('# fixture\n')
            (root / '.config').write_text('CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5c=y\n')
            with contextlib.redirect_stdout(io.StringIO()): cache.prepare(root, Path(temp) / 'cache')
            block = re.search(r'(?ms)^define Host/Compile\n.*?\nendef$', recipe.read_text()).group()
            mk = root / 'fixture.mk'
            mk.write_text('PYTHON:=python3\nPKG_VERSION:=1.96.0\nRUSTC_HOST_ARCH:=x86_64-unknown-linux-gnu\n'
                          'RUSTC_TARGET_ARCH:=aarch64-unknown-linux-musl\nTARGET_CC_NOCACHE:=false\n'
                          f'HOST_BUILD_DIR:={root}/build\n' + block + '\n'
                          'define HostBuild\nall:\n\t$(call Host/Compile)\nendef\n$(eval $(call HostBuild))\n')
            success = subprocess.run(['make', '-f', str(mk), 'COLD_RESULT=0'], capture_output=True, text=True)
            self.assertEqual(success.returncode, 0, success.stdout + success.stderr)
            failure = subprocess.run(['make', '-f', str(mk), 'COLD_RESULT=23'], capture_output=True, text=True)
            self.assertNotEqual(failure.returncode, 0)
            self.assertIn('Error 23', failure.stderr)


if __name__ == '__main__':
    unittest.main()
