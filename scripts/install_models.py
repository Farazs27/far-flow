#!/usr/bin/env python3
"""Install only the checked-in model manifest; never discover or rewrite versions."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tempfile
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    with path.open('rb') as source:
        result = hashlib.sha256()
        for block in iter(lambda: source.read(4 * 1024 * 1024), b''):
            result.update(block)
        return result.hexdigest()

def matches(path, item):
    return path.is_file() and path.stat().st_size == item['bytes'] and digest(path) == item['sha256']

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--speech-only', action='store_true', help='Install/verify speech only, for the smaller-memory profile')
    parser.add_argument('--verify', action='store_true', help='Read-only verification; no downloads or writes')
    args = parser.parse_args()
    destination = Path(os.environ.get('FAR_FLOW_DATA_DIR', Path.home() / 'Library/Application Support/FarFlow')) / 'Models'
    manifest = json.loads((ROOT / 'FarFlow/Resources/ModelManifest.json').read_text())
    if not args.verify and subprocess.run(['pgrep', '-x', 'Far Flow'], stdout=subprocess.DEVNULL).returncode == 0:
        parser.error('Quit Far Flow before changing model files, then run this command again.')
    for model in manifest:
        if args.speech_only and model['id'] != 'parakeet-v3':
            continue
        folder = destination / model['id']
        for item in model['files']:
            relative = PurePosixPath(item['path'])
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('Unsafe path in model manifest')
        if args.verify:
            if not (folder / 'farflow-model.json').is_file() or not all(matches(folder / item['path'], item) for item in model['files']):
                raise RuntimeError(f"{model['id']}: missing or modified files; run installation again")
            print(f"{model['id']}: all pinned files verified", flush=True)
            continue
        destination.mkdir(parents=True, exist_ok=True)
        required = sum(item['bytes'] for item in model['files']) + 512 * 1024 * 1024
        if shutil.disk_usage(destination).free < required:
            raise RuntimeError(f"{model['id']}: not enough free space for a verified staged installation")
        with tempfile.TemporaryDirectory(prefix='.install-', dir=destination) as staging:
            staged = Path(staging) / model['id']
            staged.mkdir()
            for item in model['files']:
                target = staged / item['path']
                target.parent.mkdir(parents=True, exist_ok=True)
                existing = folder / item['path']
                if matches(existing, item):
                    shutil.copyfile(existing, target)
                else:
                    url = f"https://huggingface.co/{model['repository']}/resolve/{model['revision']}/{item['path']}"
                    print(f"Downloading {model['id']}/{item['path']}", flush=True)
                    with urllib.request.urlopen(url, timeout=60) as response, target.open('wb') as output:
                        shutil.copyfileobj(response, output, 4 * 1024 * 1024)
                if not matches(target, item):
                    raise RuntimeError(f"Checksum mismatch: {item['path']}. Existing model preserved.")
            (staged / 'farflow-model.json').write_text(json.dumps(model, indent=2))
            # Keep rollback outside the disposable staging directory. Even a
            # failed rollback must not let context cleanup erase the old model.
            previous = destination / ('.previous-' + model['id'] + '-' + uuid.uuid4().hex)
            if folder.exists():
                folder.rename(previous)
            try:
                staged.rename(folder)
            except Exception:
                if previous.exists():
                    previous.rename(folder)
                raise
            if previous.exists():
                shutil.rmtree(previous)
        print(f"{model['id']}: installed and verified", flush=True)

if __name__ == '__main__':
    main()
