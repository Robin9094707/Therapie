"""Exercise real text-field callbacks and removal buttons on one native iPhone simulator."""
import json
import subprocess
from pathlib import Path

output = Path('build/checkin-regression')
output.mkdir(parents=True, exist_ok=True)

def run(*args, timeout=60, check=True):
    return subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          timeout=timeout, check=check).stdout

listing = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))
phones = [device for runtime, devices in listing['devices'].items()
          if 'iOS-26' in runtime or 'iOS-27' in runtime
          for device in devices if 'iPhone' in device['name']]
if not phones:
    (output / 'status.json').write_text(json.dumps({'status': 'unavailable', 'reason': 'No compatible simulator'}))
    raise SystemExit(75)
phone = next((device for device in phones if 'Pro Max' in device['name']), phones[0])
udid = phone['udid']
try:
    if phone['state'] != 'Booted':
        run('xcrun', 'simctl', 'boot', udid)
    run('open', '-a', 'Simulator', '--args', '-CurrentDeviceUDID', udid, check=False)
    boot = run('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=120)
    (output / 'boot.log').write_text(boot)
except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
    captured = error.stdout or ''
    if isinstance(captured, bytes):
        captured = captured.decode(errors='replace')
    (output / 'boot.log').write_text(captured)
    (output / 'status.json').write_text(json.dumps({'status': 'unavailable', 'reason': 'Simulator did not boot'}))
    raise SystemExit(75)

command = ['xcodebuild', '-project', 'Therapie.xcodeproj', '-scheme', 'TherapieApp',
           '-configuration', 'Debug', '-destination', 'platform=iOS Simulator,id=' + udid,
           '-destination-timeout', '60', '-parallel-testing-enabled', 'NO',
           '-derivedDataPath', 'build-checkin-ui', '-resultBundlePath', str(output / 'CheckInTests.xcresult'),
           '-only-testing:TherapieUITests/TherapieUITests/testCheckInTaskRemovalWithKeyboardAndMultipleRows',
           'CODE_SIGNING_ALLOWED=NO', 'test']
print('Testing real task removal on', phone['name'], flush=True)
with (output / 'test.log').open('w') as log:
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    try:
        code = process.wait(timeout=420)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
        code = 1
        log.write('\nFocused UI test timed out; runtime verification failed.\n')
(output / 'status.json').write_text(json.dumps({'status': 'passed' if code == 0 else 'failed', 'device': phone['name']}))
run('xcrun', 'simctl', 'shutdown', udid, check=False)
if code:
    print((output / 'test.log').read_text()[-16000:], flush=True)
    raise SystemExit(1)
print('Check-in task removal UI regression passed: focused keyboard, first/last/all rows, repeat add/remove, saved draft resume.', flush=True)
