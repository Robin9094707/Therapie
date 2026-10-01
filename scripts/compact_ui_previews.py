"""Keep downloadable screenshots and accessibility evidence separate from recordings."""
import json
import shutil
from pathlib import Path
from PIL import Image

source = Path('build/checkin-regression/previews')
destination = Path('build/checkin-regression/compact-previews')
if source.exists():
    for path in source.rglob('*'):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        if path.suffix.lower() == '.png':
            target = destination / relative.with_suffix('.jpg')
            target.parent.mkdir(parents=True, exist_ok=True)
            with Image.open(path) as image:
                image.thumbnail((1200, 1800))
                image.convert('RGB').save(target, quality=82)
        elif path.suffix.lower() in ('.txt', '.log'):
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
    manifest = source / 'manifest.json'
    if manifest.exists():
        entries = json.loads(manifest.read_text())
        for entry in entries:
            retained = []
            for attachment in entry.get('attachments', []):
                name = attachment['exportedFileName']
                if name.lower().endswith('.png'):
                    attachment['exportedFileName'] = str(Path(name).with_suffix('.jpg'))
                    retained.append(attachment)
                elif name.lower().endswith(('.txt', '.log')):
                    retained.append(attachment)
            entry['attachments'] = retained
        destination.mkdir(parents=True, exist_ok=True)
        (destination / 'manifest.json').write_text(json.dumps(entries, ensure_ascii=False, indent=2))
