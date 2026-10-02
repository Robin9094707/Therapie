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
    boot = run('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=300)
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
           '-only-testing:TherapieUITests/TherapieUITests/testSavedCheckInOpensReadOnlyAndEditsExplicitly',
           '-only-testing:TherapieUITests/TherapieUITests/testNoteAttachmentsKeepParentOpenAndReopenReadOnly',
           '-only-testing:TherapieUITests/TherapieUITests/testTherapyCancellationAndRestore',
           '-only-testing:TherapieUITests/TherapieUITests/testTodayCustomizationRoutineConfirmationAndArchiveFilters',
           '-only-testing:TherapieUITests/TherapieUITests/testAIBuddyNativeActionsAndJournal',
           '-only-testing:TherapieUITests/TherapieUITests/testChatSendWithKeyboardNewChatAndReopen',
           '-only-testing:TherapieUITests/TherapieUITests/testGuidedAIKeepsDraftWhenSwitchingToNormal',
           'CODE_SIGNING_ALLOWED=NO', 'test']
print('Testing saved overview and real task removal on', phone['name'], flush=True)
with (output / 'test.log').open('w') as log:
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    try:
        code = process.wait(timeout=1200)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
        code = 1
        log.write('\nFocused UI test timed out; runtime verification failed.\n')
(output / 'status.json').write_text(json.dumps({'status': 'passed' if code == 0 else 'failed', 'device': phone['name']}))
try:
    previews = run('xcrun', 'xcresulttool', 'export', 'attachments', '--path',
                   str(output / 'CheckInTests.xcresult'), '--output-path', str(output / 'previews'),
                   timeout=30, check=False)
    (output / 'preview-export.log').write_text(previews)
except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
    print('Preview export unavailable; preserving the actual test result.', flush=True)

try:
    run('xcrun', 'simctl', 'shutdown', udid, timeout=15, check=False)
except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
    print('Simulator cleanup did not finish; preserving the actual test result.', flush=True)
if code:
    print((output / 'test.log').read_text()[-16000:], flush=True)
    raise SystemExit(1)
print('Check-in UI regressions passed: read-only overview, explicit edit/save, focused keyboard, first/last/all rows, repeat add/remove, saved draft resume, nested audio/archive/media windows, saved-note attachments and therapy cancellation/restore.', flush=True)
