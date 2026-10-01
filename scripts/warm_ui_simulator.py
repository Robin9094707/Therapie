"""Start the focused test device while core checks and the iPhone build run."""
import json
import subprocess
from pathlib import Path

output = Path('build/checkin-regression')
output.mkdir(parents=True, exist_ok=True)
try:
    listing = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True, timeout=30))
    phones = [device for runtime, devices in listing['devices'].items()
              if 'iOS-26' in runtime or 'iOS-27' in runtime
              for device in devices if 'iPhone' in device['name']]
    if phones:
        phone = next((device for device in phones if 'Pro Max' in device['name']), phones[0])
        with (output / 'warmup.log').open('w') as log:
            if phone['state'] != 'Booted':
                subprocess.Popen(['xcrun', 'simctl', 'boot', phone['udid']], stdout=log, stderr=subprocess.STDOUT)
            subprocess.Popen(['open', '-a', 'Simulator', '--args', '-CurrentDeviceUDID', phone['udid']],
                             stdout=log, stderr=subprocess.STDOUT)
        print('Warming focused UI device:', phone['name'])
except (subprocess.SubprocessError, OSError, ValueError) as error:
    print('Early warmup unavailable; focused verification will retry:', str(error))
