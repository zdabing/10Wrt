"""Exercise release publication without making any GitHub requests."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name('publish-firmware.sh').resolve()
BASH = os.environ.get('BASH_BIN') or shutil.which('bash') or '/bin/bash'


class PublicationTests(unittest.TestCase):
    def publish(self, device='r5c', assets=True, fail_tag=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            firmware = root / 'firmware with spaces'
            firmware.mkdir()
            if assets:
                (firmware / 'firmware.img.gz').write_bytes(b'firmware')
                for name in ('SHA256SUMS','10wrt-packages.manifest','10wrt-sources.tsv','10wrt-update.json','10wrt-update-notes.md'):
                    (firmware / name).write_text('metadata',encoding='utf-8')
            log, summary = root / 'calls', root / 'summary'
            log.touch()
            mocks = root / 'bin'
            mocks.mkdir()
            scripts = {
                'date': '''#!/usr/bin/env bash
if [[ "$*" == '+%s' ]]; then echo 1791222227; else /usr/bin/date "$@"; fi
''',
                'gh': '''#!/usr/bin/env bash
printf '%s\\0' "$@" >> "$TEST_LOG"
printf '\\0' >> "$TEST_LOG"
if [[ "$*" == *'/git/tags'* ]]; then
  [[ "$FAIL_TAG" != 1 ]] || exit 1
  echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
fi
''',
            }
            for name, body in scripts.items():
                path = mocks / name
                path.write_text(body, encoding='utf-8', newline='\n')
                path.chmod(0o755)
            env = dict(os.environ, TEST_LOG=log.as_posix(), FAIL_TAG=str(int(fail_tag)),
                       GITHUB_REPOSITORY='owner/repo', GITHUB_SHA='b' * 40,
                       FIRMWARE_TAG=f'v2026.10.6-t010000-openwrt-{device}-73-2', GITHUB_RUN_NUMBER='73', GITHUB_RUN_ATTEMPT='2',
                       GITHUB_RUN_ID='37331650703', GITHUB_STEP_SUMMARY=summary.as_posix())
            # Set PATH inside Bash so Windows cannot rewrite its separators.
            result = subprocess.run(
                [BASH, '-c', 'mock_bin="$1"; if command -v cygpath >/dev/null; then mock_bin=$(cygpath -u "$mock_bin"); fi; export PATH="$mock_bin:$PATH"; bash "$2" "$3" "$4"',
                 'test', mocks.as_posix(), SCRIPT.as_posix(), device, firmware.as_posix()],
                env=env, capture_output=True, text=True, encoding='utf-8')
            calls = [row.decode().split('\0') for row in log.read_bytes().split(b'\0\0') if row]
            return result, calls, summary.read_text(encoding='utf-8') if summary.exists() else ''

    def test_both_devices_use_build_date_and_annotated_tag(self):
        for device in ('r5c', 'x86_64'):
            with self.subTest(device=device):
                result, calls, summary = self.publish(device)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(len(calls), 3)
                tag = f'v2026.10.6-t010000-openwrt-{device}-73-2'
                self.assertIn('tag=' + tag, calls[0])
                self.assertIn('object=' + 'b' * 40, calls[0])
                self.assertIn('tagger[date]=2026-10-05T17:43:47Z', calls[0])
                self.assertIn('ref=refs/tags/' + tag, calls[1])
                self.assertIn('sha=' + 'a' * 40, calls[1])
                self.assertEqual(calls[2][:3], ['release', 'create', tag])
                self.assertIn('--verify-tag', calls[2])
                self.assertIn('--latest', calls[2])
                self.assertIn('--notes-file', calls[2])
                self.assertTrue(any(arg.endswith('/10wrt-update.json') for arg in calls[2]))
                self.assertTrue(any('firmware with spaces/firmware.img.gz' in arg for arg in calls[2]))
                self.assertIn('2026-10-06 01:43:47 (UTC+8)', summary)
                self.assertIn('/releases/tag/' + tag, summary)

    def test_empty_output_does_not_create_tag_or_release(self):
        result, calls, _ = self.publish(assets=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_failed_tag_creation_does_not_publish_release(self):
        result, calls, _ = self.publish(fail_tag=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)

    def test_unknown_device_is_rejected(self):
        result, calls, _ = self.publish(device='unknown')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
