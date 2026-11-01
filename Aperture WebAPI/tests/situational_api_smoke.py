"""Run only via Run-SituationalApiTests.ps1 against its disposable local services."""
import argparse
import datetime as dt
import json
import subprocess
import time
import urllib.error
import urllib.request
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, required=True)
parser.add_argument('--mysql-port', type=int, required=True)
parser.add_argument('--mysql', required=True)
args = parser.parse_args()
base = f'http://localhost:{args.port}/api'
mysql = [args.mysql, '--no-defaults', '--host=127.0.0.1', f'--port={args.mysql_port}', '--user=root', '--database=APERTURE_DB', '--batch', '--skip-column-names']

def sql(statement):
    result = subprocess.run(mysql, input=statement, text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(result.stderr)
    return result.stdout.strip()

def request(path, body=None, token=None, expected=200, fix=None, method=None):
    headers = {'Accept': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if fix:
        headers.update({'X-Client-Latitude': str(fix[0]), 'X-Client-Longitude': str(fix[1])})
    data = None if body is None else json.dumps(body).encode()
    if data is not None:
        headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            status, text = response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        status, text = error.code, error.read().decode()
    assert status == expected, (path, status, text[:1500])
    return json.loads(text) if text else None

for attempt in range(60):
    try:
        request('/content/capabilities', expected=401)
        break
    except (OSError, AssertionError):
        time.sleep(1)
else:
    raise AssertionError('Disposable IIS Express API did not become ready.')

stamp = uuid.uuid4().hex[:8]
def account(name):
    username = name + stamp
    request('/register', {'FirstName': name, 'LastName': 'Test', 'Username': username, 'Password': 'testing-password'})
    login = request('/auth/login', {'Username': username, 'Password': 'testing-password'})
    return username, login['Token']

owner, sender = account('sender')
recipient, viewer = account('viewer')
_, stranger = account('stranger')
request('/register', {'FirstName':'Duplicate','LastName':'Test','Username':owner,'Password':'testing-password'}, expected=409)
assert request('/content/capabilities', token=sender)['CameraPolicyVersion'] == 1
camera = {'Enabled':True, 'BlockPhones':True, 'BlockMultiplePeople':True, 'RequireViewer':True}
def share(**changes):
    body = {'Title':'Situational test', 'Recipient':recipient, 'Body':'protected text', 'MaxViews':1,
            'Latitude':26.37, 'Longitude':-80.1, 'RadiusMeters':500, 'CameraRestrictions':camera}
    body.update(changes)
    return request('/content', body, sender)['id']

request('/content', {'Title':'Invalid', 'Recipient':recipient, 'Body':'x','Latitude':26.37}, sender, expected=400)
content = share()
assert request('/content',token=viewer)[0]['Latitude'] == 26.37
request(f'/situational/content/{content}/time', token=stranger, expected=404)
request(f'/situational/content/{content}/time', {'ExpiresAt':None}, viewer, expected=404)
request(f'/situational/content/{content}/location', {'Latitude':0,'Longitude':0,'RadiusMeters':1},viewer,expected=404)
request(f'/situational/content/{content}/location', {'Latitude':91,'Longitude':0,'RadiusMeters':1},sender,expected=400)
request(f'/content/{content}/sessions', {'DeviceKey':str(uuid.uuid4()),'CameraPolicyVersion':0},viewer,expected=403,fix=(26.37,-80.1))
key = str(uuid.uuid4())
request('/devices',{'DeviceKey':key,'DeviceName':'Smoke test'},viewer)
request('/devices',{'DeviceKey':key,'DeviceName':'Smoke test'},viewer)
assert sql("SELECT COUNT(*) FROM TrustedDevices;") == '1'
opened = request(f'/content/{content}/sessions',{'DeviceKey':key,'CameraPolicyVersion':1},viewer,fix=(26.37,-80.1))
assert opened['AccessGranted'] and opened['Body'] == 'protected text'
sid = opened['SessionId']
request(f'/situational/sessions/{sid}/suspend',{'DurationSeconds':1},stranger,expected=404)
outside = request(f'/content/sessions/{sid}/check',{},viewer,fix=(26.4,-80.1))
assert not outside['AccessGranted'] and outside['Suspended'] and not outside['SessionEnded']
assert 'Body' not in outside and outside['SessionId'] == sid
assert request(f'/situational/sessions/{sid}/suspension',token=viewer)['Suspended']
inside = request(f'/content/sessions/{sid}/check',{},viewer,fix=(26.37,-80.1))
assert inside['AccessGranted'] and inside['SessionId'] == sid
assert sql('SELECT COUNT(*) FROM ViewingSession;') == '1', 'Recovery consumed an extra view'
missing = request(f'/content/sessions/{sid}/check',{},viewer)
assert missing['Suspended'] and not missing['AccessGranted']
request(f'/situational/sessions/{sid}/suspend',{'Reason':'Brief pause','DurationSeconds':1},sender)
held = request(f'/content/sessions/{sid}/check',{},viewer,fix=(26.37,-80.1))
assert held['Suspended'] and held['Message'].startswith('Session suspended')
time.sleep(1.1)
assert request(f'/content/sessions/{sid}/check',{},viewer,fix=(26.37,-80.1))['AccessGranted']
# Test the grace period without waiting five minutes. Fixture writes affect only the disposable DB.
sql(f"UPDATE AccessPolicy SET Requirements=JSON_SET(Requirements,'$.ExpiresAt',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 10 SECOND,'%Y-%m-%dT%H:%i:%sZ')) WHERE ContentID={content};")
expired = request(f'/content/sessions/{sid}/check',{},viewer,fix=(26.37,-80.1))
assert expired['Suspended'] and 'Waiting for the sender' in expired['Message']
future = (dt.datetime.now(dt.timezone.utc)+dt.timedelta(hours=1)).isoformat()
request(f'/situational/content/{content}/time',{'StartTime':None,'ExpiresAt':future},sender)
assert request(f'/situational/content/{content}/time',token=viewer)['passed']
request(f'/situational/content/{content}/location',{'Latitude':26.37,'Longitude':-80.1,'RadiusMeters':600},sender)
stored = json.loads(sql(f'SELECT Requirements FROM AccessPolicy WHERE ContentID={content};'))
assert stored['CameraRestrictions'] == camera and stored['MaxViews'] == 1 and stored['Location']['RadiusMeters'] == 600
assert request(f'/content/sessions/{sid}/check',{},viewer,fix=(26.37,-80.1))['AccessGranted']
# A manual hold cannot postpone terminal expiry forever.
request(f'/situational/sessions/{sid}/suspend',{'DurationSeconds':30},sender)
sql(f"UPDATE AccessPolicy SET Requirements=JSON_SET(Requirements,'$.ExpiresAt',DATE_FORMAT(UTC_TIMESTAMP()-INTERVAL 301 SECOND,'%Y-%m-%dT%H:%i:%sZ')) WHERE ContentID={content};")
ended = request(f'/content/sessions/{sid}/check',{},viewer,fix=(26.37,-80.1))
assert ended['SessionEnded'] and not ended['Suspended'] and not ended['AccessGranted']
request(f'/content/sessions/{sid}/check',{},viewer,expected=403)
# Revocation, invalid JSON policy versions and one-view enforcement remain terminal.
request(f'/situational/content/{content}/time',{'StartTime':None,'ExpiresAt':future},sender)
request(f'/content/{content}/sessions',{'DeviceKey':key,'CameraPolicyVersion':1},viewer,expected=403,fix=(26.37,-80.1))
second = share(MaxViews=None)
opened = request(f'/content/{second}/sessions',{'DeviceKey':key,'CameraPolicyVersion':1},viewer,fix=(26.37,-80.1))
request(f'/content/{second}/revoke',{},sender)
request(f"/content/sessions/{opened['SessionId']}/check",{},viewer,expected=404)
third = share(MaxViews=None)
sql(f"UPDATE AccessPolicy SET Requirements=JSON_SET(Requirements,'$.Version',2) WHERE ContentID={third};")
request(f'/content/{third}/sessions',{'DeviceKey':key,'CameraPolicyVersion':1},viewer,expected=403,fix=(26.37,-80.1))
assert int(sql('SELECT COUNT(*) FROM EnvironmentCheck;')) >= 8
print('HTTP integration passed: registration/auth, ownership, atomic GPS sharing, camera compatibility, suspension/recovery, manual holds, view counts, expiry extension/grace, JSON preservation and revocation.')
