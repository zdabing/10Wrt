import hashlib
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('metadata', Path(__file__).with_name('firmware-update-metadata.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FirmwareTests(unittest.TestCase):
    def build_profiles(self, root, firmware, profiles, fail=False, retry=False):
        # 模拟顶层 world 生成镜像及 profiles.json，并保留失败传播检查。
        tools = root / 'tools'
        tools.mkdir()
        make = tools / 'make'
        make.write_text('''#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> make-calls.log
case "$1" in
    world)
        [ "$FAIL_OVERVIEW" = 0 ] || exit 23
        if [ "$RETRY_PARALLEL" = 1 ] && [ "$2" != -j1 ]; then exit 17; fi
        mkdir -p json_info_files
        cp image-fixture.json json_info_files/image.json
        cp json_info_files/image.json "$FIXTURE_FIRMWARE_DIR/profiles.json"
        ;;
    *) exit 99 ;;
esac
''', encoding='utf-8', newline='\n')
        make.chmod(0o755)
        (root / 'image-fixture.json').write_text(json.dumps(profiles), encoding='utf-8')
        script = root / 'build-firmware.sh'
        script.write_text(Path(__file__).with_name('build-firmware.sh').read_text(encoding='utf-8'),
                          encoding='utf-8', newline='\n')
        env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
                   BUILD_JOBS='2', RETRY_PARALLEL='1' if retry else '0', FIXTURE_FIRMWARE_DIR=firmware.as_posix(),
                   FAIL_OVERVIEW='1' if fail else '0',
                   GITHUB_STEP_SUMMARY=str(root / 'summary.md'))
        return subprocess.run(['bash', script.as_posix()], cwd=root, env=env,
                              capture_output=True, text=True, encoding='utf-8')

    def test_r5c_and_x86_exact_profile_images(self):
        for device, target, image_type, filename in [
            ('r5c', 'rockchip/armv8', 'sysupgrade', 'openwrt-r5c-squashfs-sysupgrade.img.gz'),
            ('x86_64', 'x86/64', 'combined-efi', 'openwrt-x86-64-generic-ext4-combined-efi.img.gz')
        ]:
            with self.subTest(device=device), tempfile.TemporaryDirectory() as directory:
                overlay, firmware = Path(directory) / 'files', Path(directory) / 'firmware'
                firmware.mkdir()
                identity = module.stamp(overlay, dict(GITHUB_REPOSITORY='zdabing/10Wrt', FIRMWARE_TAG='openwrt-'+device+'-2026.10.04-88', FIRMWARE_TARGET=target, BUILD_TARGET=device, GITHUB_RUN_NUMBER='88', GITHUB_SHA='a'*40))
                self.assertTrue((overlay / 'usr/share/10wrt/release.json').is_file())
                payload = b'firmware fixture'; digest = hashlib.sha256(payload).hexdigest()
                (firmware / filename).write_bytes(payload)
                profiles = dict(target=target, profiles={identity['profile']:dict(images=[dict(type=image_type,name=filename,sha256=digest,size=len(payload)),dict(type='rootfs',name='rootfs.img.gz')])})
                result = self.build_profiles(Path(directory), firmware, profiles)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                data = module.release(overlay, firmware)
                self.assertEqual([f['filename'] for f in data['files']], [filename])
                self.assertEqual(data['tag'], identity['tag'])
                self.assertIn('<!-- 10wrt-update-metadata', (firmware / '10wrt-update-notes.md').read_text())
                (firmware / filename).write_bytes(b'corrupt')
                with self.assertRaises(ValueError): module.release(overlay, firmware)
                profiles['target'] = 'wrong/target'
                (firmware / 'profiles.json').write_text(json.dumps(profiles))
                with self.assertRaises(ValueError): module.release(overlay, firmware)

    def test_parallel_failure_retries_serially(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            firmware = root / 'firmware'
            firmware.mkdir()
            result = self.build_profiles(root, firmware, {}, retry=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((root / 'make-calls.log').read_text().splitlines(),
                             ['world -j2 V=s', 'world -j1 V=s'])
            self.assertTrue((firmware / 'profiles.json').exists())

    def test_overview_generation_failure_stops_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            firmware = root / 'firmware'
            firmware.mkdir()
            result = self.build_profiles(root, firmware, {}, fail=True)
            self.assertEqual(result.returncode, 23, result.stdout + result.stderr)
            self.assertFalse((firmware / 'profiles.json').exists())


if __name__ == '__main__':
    unittest.main()
