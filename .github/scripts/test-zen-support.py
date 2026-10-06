import importlib.util
import tarfile
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('support', Path(__file__).with_name('export-zen-support.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SupportTests(unittest.TestCase):
    def fixture(self, root):
        config = ['CONFIG_PACKAGE_' + name for name in module.REQUIRED]
        config += ['CONFIG_USE_APK']
        (root / '.config').write_text(''.join(name + '=y\n' for name in config))
        kernel = root / 'build_dir/target-aarch64/linux-rockchip_armv8/linux-6.12.108'
        kernel.mkdir(parents=True)
        (kernel / '.config').write_text('CONFIG_BPF_SYSCALL=y\nCONFIG_BPF_JIT=y\nCONFIG_NET_CLS_BPF=m\nCONFIG_NET_ACT_BPF=m\n')
        modules = root / 'bin/targets/rockchip/armv8/packages'
        modules.mkdir(parents=True)
        (modules / 'packages.adb').write_bytes(b'original signed index')
        for name in module.REQUIRED[3:]:
            (modules / (name + '-6.12.108-r1.apk')).write_bytes(b'matching module')
        packages = root / 'bin/packages/aarch64/new'
        packages.mkdir(parents=True)
        for name in module.REQUIRED[:3]:
            (packages / (name + '-0.2.0-r13.apk')).write_bytes(b'zen package')
        keys = root / 'build_dir/target-aarch64/root-rockchip/etc/apk/keys'
        keys.mkdir(parents=True)
        (keys / 'firmware.pem').write_bytes(b'-----BEGIN PUBLIC KEY-----\nfixture\n-----END PUBLIC KEY-----\n')
        (root / 'private-key.pem').write_bytes(b'never export')
        return modules

    def test_preserves_index_and_never_exports_private_key(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            with tarfile.open(module.export(root, 'rockchip/armv8')) as bundle:
                self.assertEqual(bundle.extractfile('target/packages.adb').read(), b'original signed index')
                self.assertIn('keys/firmware.pem', bundle.getnames())
                self.assertNotIn('private-key.pem', bundle.getnames())
                self.assertIn('zen-support.json', bundle.getnames())

    def test_missing_dependency_or_configuration_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            modules = self.fixture(root)
            with self.assertRaises(ValueError):
                module.export(root, '../escape')
            (modules / 'kmod-sched-bpf-6.12.108-r1.apk').unlink()
            with self.assertRaises(ValueError):
                module.export(root, 'rockchip/armv8')
            (root / '.config').write_text('CONFIG_USE_APK=y\n')
            with self.assertRaises(ValueError):
                module.check_config(root)

    def test_missing_kernel_bpf_support_stops_export(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.fixture(root)
            kernel = next((root / 'build_dir').glob('target-*/linux-*/linux-*/.config'))
            kernel.write_text('CONFIG_BPF_JIT=y\nCONFIG_NET_CLS_BPF=m\nCONFIG_NET_ACT_BPF=m\n')
            with self.assertRaisesRegex(ValueError, 'CONFIG_BPF_SYSCALL'):
                module.export(root, 'rockchip/armv8')
            self.assertFalse((root / 'bin/targets/rockchip/armv8/zen-support.tar.gz').exists())


if __name__ == '__main__':
    unittest.main()
