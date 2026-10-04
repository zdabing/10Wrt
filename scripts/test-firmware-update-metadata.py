import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('metadata', Path(__file__).with_name('firmware-update-metadata.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FirmwareTests(unittest.TestCase):
    def test_r5c_and_x86_exact_profile_images(self):
        for device, target, image_type, filename in [
            ('r5c', 'rockchip/armv8', 'sysupgrade', 'openwrt-r5c-squashfs-sysupgrade.img.gz'),
            ('x86_64', 'x86/64', 'combined-efi', 'openwrt-x86-64-generic-ext4-combined-efi.img.gz')
        ]:
            with self.subTest(device=device), tempfile.TemporaryDirectory() as directory:
                overlay, firmware = Path(directory) / 'files', Path(directory) / 'firmware'
                firmware.mkdir()
                identity = module.stamp(overlay, dict(GITHUB_REPOSITORY='zdabing/10Wrt', FIRMWARE_TAG=device+'-2026.10.04-88', FIRMWARE_TARGET=target, BUILD_TARGET=device, GITHUB_RUN_NUMBER='88', GITHUB_SHA='a'*40))
                self.assertTrue((overlay / 'usr/share/10wrt/release.json').is_file())
                payload = b'firmware fixture'; digest = hashlib.sha256(payload).hexdigest()
                (firmware / filename).write_bytes(payload)
                profiles = dict(target=target, profiles={identity['profile']:dict(images=[dict(type=image_type,name=filename,sha256=digest,size=len(payload)),dict(type='rootfs',name='rootfs.img.gz')])})
                (firmware / 'profiles.json').write_text(json.dumps(profiles))
                data = module.release(overlay, firmware)
                self.assertEqual([f['filename'] for f in data['files']], [filename])
                self.assertEqual(data['tag'], identity['tag'])
                self.assertIn('<!-- 10wrt-update-metadata', (firmware / '10wrt-update-notes.md').read_text())
                (firmware / filename).write_bytes(b'corrupt')
                with self.assertRaises(ValueError): module.release(overlay, firmware)
                profiles['target'] = 'wrong/target'
                (firmware / 'profiles.json').write_text(json.dumps(profiles))
                with self.assertRaises(ValueError): module.release(overlay, firmware)


if __name__ == '__main__':
    unittest.main()
