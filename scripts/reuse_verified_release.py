"""Reuse a verified release only when the complete production inputs are unchanged."""
import pathlib
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

compiled_commit, ipa_path = sys.argv[1:]
changed = subprocess.check_output(['git', 'diff', '--name-only', compiled_commit, 'HEAD'], text=True).splitlines()
allowed = {'.github/workflows/build-ipa.yml', 'scripts/reuse_verified_release.py', 'TherapieUITests/TherapieUITests.swift', 'RELEASE-3013.md'}
assert set(changed).issubset(allowed), f'Production inputs changed; a new native build is required: {changed}'
subprocess.run(['git', 'diff', '--exit-code', compiled_commit, 'HEAD', '--', 'TherapieApp', 'TherapieLiveActivity', 'Shared', 'project.yml', 'scripts/generate_icon.py'], check=True)
destination = pathlib.Path('build/Build/Products/Release-iphoneos/Therapie.app')
with tempfile.TemporaryDirectory(prefix='verified-release-') as temporary:
    root = pathlib.Path(temporary)
    with zipfile.ZipFile(ipa_path) as archive:
        for entry in archive.infolist():
            path = pathlib.PurePosixPath(entry.filename)
            mode = entry.external_attr >> 16
            assert not path.is_absolute() and '..' not in path.parts and (path.parts == ('Payload',) and entry.is_dir() or path.parts[:2] == ('Payload', 'Therapie.app')), 'Unsafe or unexpected IPA path'
            assert not stat.S_ISLNK(mode), 'Unexpected IPA symlink'
            target = root.joinpath(*path.parts)
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(entry) as source, target.open('wb') as output:
                    shutil.copyfileobj(source, output, 1024 * 1024)
            if mode & 0o777:
                target.chmod(mode & 0o777)
    shutil.copytree(root / 'Payload/Therapie.app', destination, dirs_exist_ok=True)
assert (destination / 'Therapie').stat().st_mode & stat.S_IXUSR, 'Mach-O executable permissions lost'
print(f'Reused the verified native release from {compiled_commit}; all production inputs match. Bundle validation and focused UI tests still run.')
