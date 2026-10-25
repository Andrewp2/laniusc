"""Independent JSON/Decimal + tomllib model. Production never uses Python."""
import datetime
import decimal
import json
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import time
import tomllib
from pathlib import Path

EXE = sys.argv[1]
ENV = {k: v for k, v in os.environ.items() if k not in ('SETTINGS_HOST', 'SETTINGS_PORT', 'SETTINGS_ENABLED')}
COUNT = 0
class Number(str):
    pass

def invoke(args=(), env=None, status=0):
    global COUNT
    COUNT += 1
    out = subprocess.run([EXE, *map(str, args)], env=ENV | (env or {}), capture_output=True, timeout=8)
    assert out.returncode == status, (args, env, out)
    if status:
        assert out.stdout == b'' and out.stderr == b'settings_inspect: error\n', (args, out)
    else:
        assert out.stderr == b'', (args, out)
    return out.stdout

def read_value(lines):
    kind, raw = next(lines).split(' ', 1)
    if kind in ('array', 'table'):
        count = int(raw)
        if kind == 'array':
            return [read_value(lines) for _ in range(count)]
        result = {}
        for _ in range(count):
            key, raw_key = next(lines).split(' ', 1)
            assert key == 'key'
            decoded = bytes.fromhex(raw_key).decode()
            assert decoded not in result
            result[decoded] = read_value(lines)
        return result
    if kind == 'null':
        assert not raw
        return None
    if kind == 'boolean':
        assert raw in ('0', '1')
        return raw == '1'
    if kind == 'text':
        return bytes.fromhex(raw).decode()
    if kind == 'decimal':
        text = bytes.fromhex(raw).decode()
        assert isinstance(json.loads(text, parse_int=Number, parse_float=Number), Number)  # Python Decimal itself caps exponent magnitude
        return Number(text)
    if kind in ('integer', 'unsigned'):
        return int(raw)
    if kind == 'float64':
        return struct.unpack('>d', int(raw).to_bytes(8, 'big'))[0]
    assert kind in ('offset-date-time', 'local-date-time', 'local-date', 'local-time'), kind
    text = bytes.fromhex(raw).decode()
    return tomllib.loads('v=' + text)['v']

def equivalent(actual, expected):
    if isinstance(expected, Number):
        assert isinstance(actual, Number) and actual == expected, (actual, expected)
    elif isinstance(expected, float):
        assert isinstance(actual, float), (actual, expected)
        if math.isnan(expected):
            assert math.isnan(actual) and math.copysign(1, actual) == math.copysign(1, expected)
        else:
            assert actual == expected and (expected != 0 or math.copysign(1, actual) == math.copysign(1, expected)), (actual, expected)
    elif isinstance(expected, dict):
        assert isinstance(actual, dict) and actual.keys() == expected.keys(), (actual, expected)
        for key in expected:
            equivalent(actual[key], expected[key])
    elif isinstance(expected, list):
        assert isinstance(actual, list) and len(actual) == len(expected)
        for a, e in zip(actual, expected):
            equivalent(a, e)
    else:
        assert type(actual) is type(expected) and actual == expected, (actual, expected)

def inspect(args, key, expected, origin, members=()):
    out = invoke([*args, '--get', key, *[item for m in members for item in ('--member', m)]])
    lines = iter(out.decode().splitlines())
    assert next(lines) == f'source {origin}', out
    equivalent(read_value(lines), expected)
    assert next(lines, None) is None, out

start = time.monotonic()
with tempfile.TemporaryDirectory(prefix='settings-oracle-') as directory:
    root = Path(directory)
    low = root / 'low.json'
    high = root / 'high.toml'
    low_text = '{"host":"json","port":8.1e1,"enabled":false,"nested":{"old":1,"keep":2},"nullish":null,"precise":123456789012345678901234567890.000000000001,"zero":-0e-99999999999999999999999,"huge":1e999999999999999999999,"text":"é\\u0000😀","array":[null,true,{"x":1e-10}],"a.b":5}'
    high_text = '''host='toml'
port=82
enabled=true
[nested]
keep=3
[types]
int=0xff
float=-0.0
nan=nan
inf=-inf
offset=1979-05-27T07:32:00.123456789123Z
local=1979-05-27 07:32:00
date=1979-05-27
time=07:32:00.123456789123
array=['x',1,true,{a='value'}]
'''
    low.write_text(low_text)
    high.write_text(high_text)
    lower = json.loads(low_text, parse_int=Number, parse_float=Number)
    higher = tomllib.loads(high_text)
    args = ['--json', low, '--toml', high]
    assert invoke() == b'host 6c6f63616c686f7374 source 0\nport 8080 source 0\nenabled 1 source 0\n'
    assert invoke(args) == b'host 746f6d6c source 2\nport 82 source 2\nenabled 1 source 2\n'
    for bits in range(8):
        env = {}
        options = []
        names = ('host', 'port', 'enabled')
        environment_values = ('environment', '83', 'false')
        cli_values = ('cli', '84', 'true')
        expected = []
        for i, name in enumerate(names):
            if bits & (1 << i):
                env['SETTINGS_' + name.upper()] = environment_values[i]
            if (bits ^ 5) & (1 << i):
                options += ['--' + name, cli_values[i]]
                value, origin = cli_values[i], 4
            elif bits & (1 << i):
                value, origin = environment_values[i], 3
            else:
                value, origin = ('toml', '82', 'true')[i], 2
            if name == 'host':
                value = value.encode().hex()
            if name == 'enabled':
                value = str(int(value == 'true'))
            expected.append(f'{name} {value} source {origin}\n')
        assert invoke([*args, *options], env) == ''.join(expected).encode()
    for key in lower | higher:
        origin = 2 if key in higher else 1
        value = higher.get(key) if key in higher else lower[key]
        inspect(args, key, value, origin)
    for key, value in higher['types'].items():
        inspect(args, 'types', value, 2, (key,))
    assert invoke([*args, '--get', 'nested', '--member', 'old']) == b'missing\n'
    assert invoke([*args, '--get', 'absent']) == b'missing\n'
    invoke([*args, '--get', 'port', '--member', 'child'], status=3)
    # Reversing files reverses winners; null masks, arrays/tables replace whole.
    inspect(['--toml', high, '--json', low], 'nested', lower['nested'], 2)
    inspect(['--toml', high, '--json', low], 'array', lower['array'], 2)
    # Fixed reproducible generated trees: inspect all native recursive types.
    rng = random.Random(0x5E771A65)
    def generated(depth):
        kinds = 6 if depth else 4
        kind = rng.randrange(kinds)
        if kind == 0: return None
        if kind == 1: return bool(rng.randrange(2))
        if kind == 2: return rng.randrange(-2**53, 2**53)
        if kind == 3: return rng.choice(['', 'é😀', 'x\0y', '\n\\"', 'key.value'])
        if kind == 4: return [generated(depth - 1) for _ in range(rng.randrange(4))]
        return {f'{i}é': generated(depth - 1) for i in range(rng.randrange(4))}
    for case in range(48):
        text = json.dumps({'value': generated(4)}, ensure_ascii=False, separators=(',', ':'))
        low.write_text(text)
        expected = json.loads(text, parse_int=Number, parse_float=Number)['value']
        inspect(['--json', low], 'value', expected, 1)
    # Schema rejects null, fractional exact numbers, float coercion and strings.
    for text in ('{"host":null}', '{"port":null}', '{"enabled":null}', '{"host":true}', '{"port":"81"}', '{"port":1.1}', '{"port":0}', '{"port":65536}', '{"port":1e99999}', '{"enabled":1}', '{"host":""}'):
        low.write_text(text)
        invoke(['--json', low], status=3)
    for number in ('1.0', '6.5535e4', '81e0'):
        low.write_text('{"port":' + number + '}')
        expected = int(decimal.Decimal(number))
        assert f'port {expected} source 1\n'.encode() in invoke(['--json', low])
    high.write_text('port=81.0\n')
    invoke(['--toml', high], status=3)
    low.write_text('{"host":"x","host":"y"}')
    invoke(['--json', low], status=3)
    low.write_text('[1]')
    invoke(['--json', low], status=3)
    for raw in (b'\xff', b'{', b'{}x', b'{"x":1,"x":2}'):
        low.write_bytes(raw)
        invoke(['--json', low], status=3)
    for raw in (b'\xff', b'x=', b'x=1\nx=2\n'):
        high.write_bytes(raw)
        invoke(['--toml', high], status=3)
    # Every argument/scalar/range contract is observable before opening files.
    bad_args = [['--unknown'], ['operand'], ['--json'], ['--port'], ['--port', 'x'], ['--port', '9223372036854775808'], ['--enabled', 'TRUE'], ['--enabled', '1'], ['--member', 'x'], ['--get', 'x', '--get', 'y'], ['--max-input', '-1'], ['--max-output', '16777217'], ['--max-nodes', 'bad'], ['--host', 'x' * 8193]]
    for a in bad_args: invoke(a, status=2)
    invoke(['--get', 'x'] + ['--member', 'x'] * 32, status=2) # argv-count cap first
    invoke(['--get=x'] + ['--member=x'] * 32, status=6)
    assert invoke(['--get=x'] + ['--member=x'] * 31) == b'missing\n'
    invoke(['--json', '/absent'] * 9, status=6)
    invoke(['--json', '/definitely-absent/settings.json'], status=5)
    for env in ({'SETTINGS_PORT': ''}, {'SETTINGS_PORT': '81.5'}, {'SETTINGS_PORT': '9223372036854775808'}, {'SETTINGS_ENABLED': 'TRUE'}, {'SETTINGS_HOST': ''}):
        invoke(env=env, status=3)
    invoke(env={'SETTINGS_HOST': 'x' * 4097}, status=6)
    invoke(env={'SETTINGS_HOST': '\udcff'}, status=3)
    invoke(['--host', 'x' * 257], status=3)
    low.write_bytes(b'{}')
    invoke(['--json', low, '--max-input', '1'], status=6)
    invoke(['--json', low, '--max-input', '2'])
    invoke(['--max-output', '0'], status=6)
    invoke(['--max-nodes', '0'], status=6)
    # Exact staged-output boundary.
    default = invoke()
    assert invoke(['--max-input', '0']) == default
    assert invoke(['--max-nodes', '3']) == default
    invoke(['--max-nodes', '2'], status=6)
    assert invoke(['--max-output', str(len(default))]) == default
    invoke(['--max-output', str(len(default) - 1)], status=6)
    assert invoke(['--help']).startswith(b'settings_inspect ')
    # Native execution timing excludes compilation. Large table lookup/report.
    low.write_text(json.dumps({'bulk': {f'key{i}': i for i in range(2000)}}))
    begin = time.monotonic()
    bulk = invoke(['--json', low, '--get', 'bulk'])
    elapsed = time.monotonic() - begin
    assert bulk.startswith(b'source 1\ntable 2000\n')
    assert len(bulk) > 50000 and elapsed < 8
    print(f'settings native cases={COUNT}; scale entries=2000 bytes={len(bulk)} runtime_ms={round(elapsed*1000)}; total_native_ms={round((time.monotonic()-start)*1000)}')
