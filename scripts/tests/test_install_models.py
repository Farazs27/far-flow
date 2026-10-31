import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('install_models', Path(__file__).parents[1] / 'install_models.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.payload = b'pinned local model fixture'
        self.model = {'id': 'parakeet-v3', 'repository': 'fixture/model', 'revision': 'a' * 40,
                      'files': [{'path': 'weights.bin', 'bytes': len(self.payload), 'sha256': hashlib.sha256(self.payload).hexdigest()}]}
        self.manifest = self.root / 'FarFlow/Resources/ModelManifest.json'
        self.manifest.parent.mkdir(parents=True)
        self.manifest.write_text(json.dumps([self.model]))
        self.folder = self.root / 'data/Models/parakeet-v3'
        for context in (patch.object(installer, 'ROOT', self.root),
                        patch.dict('os.environ', {'FAR_FLOW_DATA_DIR': str(self.root / 'data')}),
                        patch.object(installer.subprocess, 'run')):
            mock = context.start()
            self.addCleanup(context.stop)
            if hasattr(mock, 'return_value'):
                mock.return_value.returncode = 1

    def run_install(self, args=(), payload=None):
        with patch('sys.argv', ['install_models.py', *args]), patch.object(installer.urllib.request, 'urlopen', return_value=io.BytesIO(self.payload if payload is None else payload)) as download:
            installer.main()
            return download.call_count

    def test_install_verifies_pinned_bytes_without_rewriting_manifest(self):
        before = self.manifest.read_bytes()
        self.assertEqual(self.run_install(), 1)
        self.assertEqual((self.folder / 'weights.bin').read_bytes(), self.payload)
        self.assertEqual(self.manifest.read_bytes(), before)
        self.assertEqual(self.run_install(['--verify']), 0)
        self.assertEqual(self.run_install(), 0)  # Valid installed files are reused.

    def test_corrupt_download_preserves_previous_installation(self):
        self.folder.mkdir(parents=True)
        previous = self.folder / 'weights.bin'
        previous.write_bytes(b'previous model')
        with self.assertRaisesRegex(RuntimeError, 'Checksum mismatch'):
            self.run_install(payload=b'corrupt')
        self.assertEqual(previous.read_bytes(), b'previous model')

    def test_verify_never_downloads_or_repairs_corruption(self):
        self.run_install()
        target = self.folder / 'weights.bin'
        target.write_bytes(b'damaged')
        with self.assertRaisesRegex(RuntimeError, 'missing or modified'):
            self.run_install(['--verify'])
        self.assertEqual(target.read_bytes(), b'damaged')

    def test_unsafe_manifest_path_is_rejected_before_writing(self):
        self.model['files'][0]['path'] = '../../escape'
        self.manifest.write_text(json.dumps([self.model]))
        with self.assertRaisesRegex(ValueError, 'Unsafe path'):
            self.run_install()
        self.assertFalse((self.root / 'data').exists())

if __name__ == '__main__':
    unittest.main()
