"""Focused real-PNG consumer checks; the exact resize model is shared test code."""
from collections import Counter
import importlib.util
import io
import os
from pathlib import Path
import random
import re
import struct
import subprocess
import sys
import tempfile
import zlib
from PIL import Image

MODEL = Path(__file__).resolve().parents[1] / 'extended_image_resize_model' / 'oracle.py'
spec = importlib.util.spec_from_file_location('image_resize_reference', MODEL)
model = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = model
spec.loader.exec_module(model)
resize_rgba = model.resize_rgba

SIGNATURE = b'\x89PNG\r\n\x1a\n'
HELP = b'Usage: image-tool info [OPTIONS] <INPUT.png\n       image-tool transform [OPTIONS] <INPUT.png >OUTPUT.png\n'
TRACE = 'read,write,mmap,munmap,mremap,brk,openat,close'


def diagnostic(reason, stage):
    return f'image-tool: {reason} stage={stage}\n'.encode()


def chunk(name, data):
    return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data))


def raw_png(width, height, raw):
    return (SIGNATURE + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def image(width, height, seed=937):
    rng = random.Random(seed)
    data = bytearray(rng.randbytes(width * height * 4))
    for index in range(width * height):
        data[index * 4 + 3] = (0, 1, 127, 254, 255)[index % 5]
    return Image.frombytes('RGBA', (width, height), bytes(data))


def png(value):
    output = io.BytesIO(); value.save(output, format='PNG'); return output.getvalue()


def transformed(value, crop=None, turns=0, flip_x=False, flip_y=False):
    value = value.convert('RGBA')
    if crop:
        x, y, width, height = crop
        value = value.crop((x, y, x + width, y + height))
    if turns:
        value = value.transpose({1: Image.Transpose.ROTATE_270,
                                 2: Image.Transpose.ROTATE_180,
                                 3: Image.Transpose.ROTATE_90}[turns])
    if flip_x:
        value = value.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    if flip_y:
        value = value.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    return value


def expected(value, width, height, filter='area', **transforms):
    value = transformed(value, **transforms)
    return width, height, resize_rgba(value.tobytes(), *value.size, width, height, filter)


def check_png(encoded, wanted):
    assert encoded.startswith(SIGNATURE)
    at = 8; names = []
    while at < len(encoded):
        assert at + 12 <= len(encoded)
        length = int.from_bytes(encoded[at:at + 4], 'big')
        name = encoded[at + 4:at + 8]; end = at + 8 + length
        assert end + 4 <= len(encoded)
        assert int.from_bytes(encoded[end:end + 4], 'big') == zlib.crc32(encoded[at + 4:end])
        names.append(name); at = end + 4
        if name == b'IEND':
            assert length == 0 and at == len(encoded)
    assert names[0] == b'IHDR' and names[-1] == b'IEND' and names.count(b'IEND') == 1
    decoded = Image.open(io.BytesIO(encoded)); decoded.load()
    assert decoded.mode == 'RGBA' and decoded.size == wanted[:2], (decoded.mode, decoded.size, wanted[:2])
    assert decoded.tobytes() == wanted[2], (decoded.size, 'complete RGBA mismatch')


def ledger(text, *, admission=False, help_output=False):
    events = []; counts = Counter(); live = {}; arguments = None
    eof = False; input_address = None; input_retired = False
    started = False; output_owner = None; output_retired = False; last_alloc = None
    for line in text.splitlines():
        match = re.fullmatch(r'([a-z0-9_]+)\((.*)\)\s+=\s+(.*)', line)
        assert match and match[1] in TRACE.split(','), line
        name, args, answer = match.groups(); counts[name] += 1
        event = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        if name == 'mmap':
            assert not started, ('allocation after stdout', line)
            extent = int(args.split(',')[1]); event['extent'] = extent
            event['phase'] = 'arguments' if arguments is None else ('input' if not eof else ('postdecode' if input_retired else 'decode'))
            if answer.startswith('0x'):
                address = answer.split()[0]; assert address not in live
                live[address] = extent; last_alloc = address; event['address'] = address
            else:
                assert answer.startswith('-1 ENOMEM ') and 'INJECTED' in answer, line
        elif name == 'munmap':
            address, extent = args.split(','); address = address.strip()
            assert answer == '0' and live.pop(address, None) == int(extent), line
            if eof and not input_retired and address == input_address:
                # Later transforms may receive the retired virtual address.
                # This flag binds the EOF-era owner, not every future mapping.
                input_retired = True
            if address == output_owner:
                output_retired = True
            if started and arguments is not None and address in arguments:
                assert output_retired or help_output, ('argv retired before staged output', line)
        elif name in ('mremap', 'brk', 'openat', 'close'):
            raise AssertionError(('unexpected allocation/file service', line))
        elif name == 'read':
            assert not admission and not started and not eof and args.split(',')[0] == '0', line
            if arguments is None:
                arguments = set(live)
                assert len(arguments) == 2, ('argument snapshot must precede source', live)
            request = int(args.rsplit(',', 1)[1]); assert 0 < request <= 1024
            event['requested'] = request
            if answer.isdigit():
                received = int(answer); assert received <= request
                if received == 0:
                    eof = True
                    owners = set(live) - arguments
                    assert len(owners) == 1, ('input collector owner at EOF', live)
                    input_address = owners.pop()
        elif name == 'write':
            descriptor = int(args.split(',')[0]); event['descriptor'] = descriptor
            request = int(args.rsplit(',', 1)[1]); event['requested'] = request
            assert descriptor in (1, 2) and 0 < request <= 1024
            if descriptor == 1:
                if help_output:
                    assert not eof and not any(item['name'] == 'read' for item in events)
                else:
                    assert not admission and eof and input_retired and not output_retired
                    if not started:
                        output_owner = last_alloc
                    assert output_owner in live and set(live) == arguments | {output_owner}, ('only complete output and arguments may remain at publication', line, live)
                started = True
            else:
                assert not live, ('diagnostic before owner cleanup', line, live)
            if answer.isdigit():
                assert int(answer) <= request
        events.append(event)
    assert not live, ('unreleased mappings', live)
    if admission:
        assert not any(item['name'] == 'read' for item in events)
    return dict(events=events, eof=eof, input_retired=input_retired)


class Runner:
    def __init__(self, executable, group):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b'\x7fELF\x02\x01'
        assert int.from_bytes(header[16:18], 'little') == 2 and int.from_bytes(header[18:20], 'little') == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f'image-resize-tool-{group}-')); self.count = 0

    def run(self, label, source, args, *, status=0, stderr=b'', pixels=None, output=None,
            injections=(), admission=False, help_output=False, full_stdout=False):
        directory = self.directory / label; directory.mkdir()
        path = directory / 'input'; path.write_bytes(source)
        command = ['strace', '--kill-on-exit', '-qq', '-xx', '-s', '16', '-e', 'signal=none',
                   '-e', 'trace=' + TRACE, '-o', str(directory / 'trace')]
        for call, ordinal, change in injections:
            action = change if change.startswith('retval=') else 'error=' + change
            command += ['-e', f'inject={call}:{action}:when={ordinal}']
        command += [self.executable, *args]
        (directory / 'command').write_text(repr(command) + '\n')
        with path.open('rb') as incoming:
            if full_stdout:
                with open('/dev/full', 'wb') as sink:
                    result = subprocess.run(command, stdin=incoming, stdout=sink, stderr=subprocess.PIPE, timeout=60, check=False)
                result.stdout = b''
            else:
                result = subprocess.run(command, stdin=incoming, capture_output=True, timeout=60, check=False)
        (directory / 'stdout').write_bytes(result.stdout); (directory / 'stderr').write_bytes(result.stderr)
        (directory / 'status').write_text(str(result.returncode) + '\n')
        assert result.returncode == status and result.stderr == stderr, (label, result.returncode, status, result.stderr, stderr)
        if output is not None:
            assert result.stdout == output, (label, 'output mismatch', result.stdout[:100], output[:100])
        elif status != 0:
            assert result.stdout == b'', (label, result.stdout[:100])
        if pixels is not None:
            check_png(result.stdout, pixels)
        observed = ledger((directory / 'trace').read_text(), admission=admission, help_output=help_output)
        events = observed['events']; injected = []
        for call, ordinal, change in injections:
            options = {item['ordinal']: item for item in events if item['name'] == call}
            positions = range(int(ordinal[:-1]), max(options) + 1) if isinstance(ordinal, str) else [ordinal]
            for position in positions:
                assert position in options, (label, call, position, 'injection not reached')
                item = options[position]
                prefix = change.removeprefix('retval=') if change.startswith('retval=') else '-1 ' + change + ' '
                assert item['answer'].startswith(prefix) and 'INJECTED' in item['answer'], item
                injected.append(item)
        assert {item['line'] for item in events if 'INJECTED' in item['answer']} == {item['line'] for item in injected}
        for fd, actual in ((1, result.stdout), (2, result.stderr)):
            confirmed = sum(int(item['answer']) for item in events if item['name'] == 'write' and item['descriptor'] == fd and item['answer'].isdigit())
            assert confirmed == len(actual), (label, fd, confirmed, len(actual))
        assert path.read_bytes() == source
        if status == 0 and not help_output:
            assert observed['eof'] and observed['input_retired']
        self.count += 1; observed['stdout'] = result.stdout
        return observed


def pixel_cases():
    cases = []
    for sw, sh, dw, dh in ((1, 1, 3, 2), (7, 5, 3, 2), (3, 2, 7, 5), (1, 9, 7, 1), (5, 3, 5, 3)):
        value = image(sw, sh, sw + sh * 31)
        for filter in ('nearest', 'bilinear', 'area'):
            cases.append((f'{sw}x{sh}-{dw}x{dh}-{filter}', value,
                          ['transform', '--resize', f'{dw},{dh}', '--filter', filter], expected(value, dw, dh, filter)))
    value = image(9, 7)
    for filter in ('nearest', 'bilinear', 'area'):
        args = ['--resize', '4,7', '--flip-y', '--filter', filter, 'transform', '--rotate', '90', '--flip-x', '--crop', '1,2,7,4']
        cases.append((f'all-transforms-{filter}', value, args, expected(value, 4, 7, filter, crop=(1, 2, 7, 4), turns=1, flip_x=True, flip_y=True)))
    cases.append(('rotate270-flip', value, ['transform', '--resize', '6,4', '--rotate', '270', '--flip-x'], expected(value, 6, 4, turns=3, flip_x=True)))
    cases.append(('crop-flip-collapse', value, ['--resize', '1,1', 'transform', '--flip-y', '--crop', '2,1,5,5', '--filter', 'bilinear'], expected(value, 1, 1, 'bilinear', crop=(2, 1, 5, 5), flip_y=True)))
    value = image(9, 3)
    cases.append(('mixed-axes-default-area', value, ['transform', '--resize', '3,9'], expected(value, 3, 9)))
    cases.append(('default-area-reduction', value, ['transform', '--resize', '2,2'], expected(value, 2, 2)))
    rgb = image(5, 7).convert('RGB')
    cases.append(('rgb-to-bilinear', rgb, ['transform', '--resize', '3,4', '--filter', 'bilinear'], expected(rgb, 3, 4, 'bilinear')))
    palette = Image.frombytes('P', (5, 3), bytes(range(15)))
    palette.putpalette(bytes((i * 29 + 13) % 256 for i in range(768)))
    palette.info['transparency'] = bytes([0, 1, 127, 254, 255] * 3)
    cases.append(('palette-alpha-to-area', palette, ['transform', '--resize', '3,2'], expected(palette, 3, 2)))
    return cases


def pixels(runner):
    for label, value, args, wanted in pixel_cases():
        runner.run(label, png(value), args, pixels=wanted)


def cli_cases():
    bad = [(['transform', '--resize', value]) for value in
           ('', '1', '1,2,3', '1,', ',1', '0,1', '1,0', '-1,2', '1,+2', '1, 2', '１,2', '2147483648,1')]
    bad += [['transform', '--resize'], ['transform', '--filter']]
    bad += [['transform', '--resize', '2,3', '--filter', value] for value in ('', 'Nearest', 'linear', 'area ', '0')]
    bad += [['transform', '--filter', 'area'], ['--help', '--filter', 'nearest'],
            ['info', '--resize', '2,3'], ['info', '--filter', 'area'],
            ['info', '--resize', '2,3', '--help'],
            ['transform', '--resize', 'bad', '--resize', '2,3'],
            ['transform', '--resize', '2,3', '--filter', 'bad', '--filter', 'area'],
            ['--resize', '2,3']]
    return bad


def cli(runner):
    value = image(5, 3); source = png(value)
    for index, args in enumerate(cli_cases()):
        runner.run(f'invalid-{index}', source, args, status=2, stderr=diagnostic('invalid-arguments', 'arguments'), admission=True)
    good = [(['transform', '--resize', '0002,0003'], 'area'),
            (['transform', '--resize=2,3', '--filter=nearest'], 'nearest'),
            (['--filter', 'bilinear', '--resize', '2,3', 'transform'], 'bilinear'),
            (['transform', '--resize', '99,77', '--resize', '2,3'], 'area'),
            (['transform', '--resize', '2,3', '--filter', 'nearest', '--filter', 'bilinear'], 'bilinear')]
    for index, (args, filter) in enumerate(good):
        runner.run(f'valid-{index}', source, args, pixels=expected(value, 2, 3, filter))
    runner.run('valid-help-with-resize', source, ['--help', '--resize', '2,3', '--filter', 'area'], output=HELP, admission=True, help_output=True)
    runner.run('valid-help-with-mode', source, ['transform', '--resize', '2,3', '--help'], output=HELP, admission=True, help_output=True)


def limits(runner):
    value = image(7, 5); source = png(value); resize = ['transform', '--resize', '8,8']
    baseline = runner.run('exact-output-pixel-cap', source, resize + ['--max-pixels', '64'], pixels=expected(value, 8, 8))
    runner.run('excess-output-pixel-cap', source, resize + ['--max-pixels', '63'], status=3, stderr=diagnostic('resource-limit', 'transform'))
    runner.run('source-pixel-cap-before-downsize', source, ['transform', '--resize', '1,1', '--max-pixels', '34'], status=3, stderr=diagnostic('resource-limit', 'decode'))
    runner.run('earlier-crop-error-before-resize-cap', source, resize + ['--max-pixels', '63', '--crop', '7,0,1,1'], status=2, stderr=diagnostic('invalid-transform', 'transform'))
    late_crc = source[:-1] + bytes([source[-1] ^ 1])
    runner.run('late-crc-before-resize-cap', late_crc, resize + ['--max-pixels', '63'], status=2, stderr=diagnostic('invalid-png', 'decode'))
    raw = b''.join(b'\0' + value.tobytes()[row * 28:(row + 1) * 28] for row in range(5))
    late_filter = bytearray(raw); late_filter[-29] = 5
    runner.run('late-filter-before-resize', raw_png(7, 5, late_filter), resize, status=2, stderr=diagnostic('invalid-png', 'decode'))
    runner.run('trailing-before-resize', source + b'late', resize, status=2, stderr=diagnostic('invalid-png', 'decode'))
    runner.run('huge-dimensions-hit-transform-cap', source, ['transform', '--resize', '2147483647,2147483647'], status=3, stderr=diagnostic('resource-limit', 'transform'))
    size = len(baseline['stdout'])
    runner.run('exact-encoded-output-cap', source, resize + ['--max-output-bytes', str(size)], pixels=expected(value, 8, 8))
    runner.run('excess-encoded-output-before-stdout', source, resize + ['--max-output-bytes', str(size - 1)], status=3, stderr=diagnostic('resource-limit', 'encode'))


def faults(runner):
    value = image(32, 19, 1019); source = png(value)
    args = ['transform', '--crop', '2,1,27,17', '--rotate', '90', '--flip-x', '--flip-y', '--resize', '67,49', '--filter', 'area']
    wanted = expected(value, 67, 49, crop=(2, 1, 27, 17), turns=1, flip_x=True, flip_y=True)
    baseline = runner.run('allocation-baseline', source, args, pixels=wanted)
    mappings = [event for event in baseline['events'] if event['name'] == 'mmap']
    assert mappings and all(event['answer'].startswith('0x') for event in mappings)
    result_size = 67 * 49 * 4; raw_size = (67 * 4 + 1) * 49
    replacement = [index for index, event in enumerate(mappings) if event['phase'] == 'postdecode' and event['extent'] == result_size]
    assert len(replacement) == 1
    at = replacement[0]
    assert 0 < mappings[at + 1]['extent'] <= 512 * 4 * 8, 'Area bounded workspace follows result'
    encode_at = next(index for index in range(at + 2, len(mappings)) if mappings[index]['extent'] == raw_size)
    assert at + 2 == encode_at, 'only result and scratch between prior transforms and encoding'
    for index, event in enumerate(mappings):
        stage = event['phase']
        if stage == 'postdecode':
            stage = 'transform' if index < encode_at else 'encode'
        failed = runner.run(f'oom-{event["ordinal"]}', source, args, status=4, stderr=diagnostic('allocation-failure', stage), injections=(('mmap', event['ordinal'], 'ENOMEM'),))
        actual = [item for item in failed['events'] if item['name'] == 'mmap']
        assert [item['args'] for item in actual] == [item['args'] for item in mappings[:index + 1]]
    reads = [event for event in baseline['events'] if event['name'] == 'read']
    writes = [event for event in baseline['events'] if event['name'] == 'write' and event['descriptor'] == 1]
    assert len(reads) >= 3 and len(writes) >= 2
    for label, call, ordinal, error, stage in (
            ('read-first-eio', 'read', reads[0]['ordinal'], 'EIO', 'input'),
            ('read-after-prefix-eio', 'read', reads[1]['ordinal'], 'EIO', 'input'),
            ('read-would-block', 'read', reads[0]['ordinal'], 'EAGAIN', 'input'),
            ('write-first-eio', 'write', writes[0]['ordinal'], 'EIO', 'output'),
            ('write-zero', 'write', writes[0]['ordinal'], 'retval=0', 'output')):
        runner.run(label, source, args, status=5, stderr=diagnostic('io-failure', stage), injections=((call, ordinal, error),))
    prefix = int(writes[0]['answer']); assert prefix == 1024
    runner.run('write-after-confirmed-prefix', source, args, status=5, stderr=diagnostic('io-failure', 'output'), output=baseline['stdout'][:prefix], injections=(('write', writes[1]['ordinal'], 'EIO'),))
    runner.run('read-eintr', source, args, pixels=wanted, injections=(('read', reads[0]['ordinal'], 'EINTR'),))
    runner.run('write-eintr', source, args, pixels=wanted, injections=(('write', writes[0]['ordinal'], 'EINTR'),))
    runner.run('real-full-stdout', source, args, status=5, stderr=diagnostic('io-failure', 'output'), full_stdout=True)
    runner.run('failed-argument-diagnostic', source, ['transform', '--resize', '0,1'], status=5, stderr=b'', admission=True, injections=(('write', 1, 'EIO'),))
    runner.run('failed-output-diagnostic', source, args, status=5, stderr=b'', injections=(('write', '1+', 'EIO'),))
    return len(mappings)


def controls():
    cases = pixel_cases(); assert len(cases) == 24
    for _, _, _, wanted in cases:
        check_png(png(Image.frombytes('RGBA', wanted[:2], wanted[2])), wanted)
    assert len(cli_cases()) + 7 == 34
    assert len(HELP) == 105
    # The all-transform reference must distinguish resize-first and omitting
    # either flip, rather than merely generating identical symmetric images.
    value = image(9, 7)
    correct = expected(value, 4, 7, crop=(1, 2, 7, 4), turns=1, flip_x=True, flip_y=True)
    assert correct != expected(value, 4, 7, crop=(1, 2, 7, 4), turns=1, flip_y=True)
    assert correct != expected(value, 4, 7, crop=(1, 2, 7, 4), turns=1, flip_x=True)
    early = Image.frombytes('RGBA', (4, 7), resize_rgba(value.tobytes(), 9, 7, 4, 7, 'area'))
    wrong = transformed(early, crop=(1, 2, 7, 4), turns=1, flip_x=True, flip_y=True)
    assert correct != (*wrong.size, wrong.tobytes())
    trace = [
        'mmap(NULL, 80, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x100000000',
        'mmap(NULL, 8, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x200000000',
        'read(0, "abc", 1024) = 3',
        'mmap(NULL, 1024, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x300000000',
        'read(0, "", 1024) = 0',
        'mmap(NULL, 16, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x400000000',
        'munmap(0x300000000, 1024) = 0',
        'mmap(NULL, 90, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x500000000',
        'munmap(0x400000000, 16) = 0',
        'write(1, "png", 3) = 3', 'munmap(0x500000000, 90) = 0',
        'munmap(0x100000000, 80) = 0', 'munmap(0x200000000, 8) = 0',
    ]
    assert ledger('\n'.join(trace))['input_retired']
    bad = [trace[:-1], trace[:9] + [trace[11]] + trace[9:11] + trace[12:],
           trace[:9] + [trace[10]] + trace[9:10] + trace[11:],
           trace[:8] + trace[9:11] + [trace[8]] + trace[11:],
           trace[:-1] + [trace[-1].replace(', 8)', ', 7)')],
           trace[:9] + ['write(2, "error", 5) = 5'] + trace[9:]]
    for broken in bad:
        try:
            ledger('\n'.join(broken))
        except AssertionError:
            pass
        else:
            raise AssertionError('ledger admitted premature retirement/publication or a leak')
    corrupted = bytearray(cases[0][3][2]); corrupted[0] ^= 1
    try:
        check_png(png(Image.frombytes('RGBA', cases[0][3][:2], bytes(corrupted))), cases[0][3])
    except AssertionError:
        pass
    else:
        raise AssertionError('pixel oracle admitted a changed channel')
    print('image-resize-tool-controls pixels=24 cli=34 limits=10 faults=12+A (host-only; no native evidence)')


GROUPS = dict(pixels=pixels, cli=cli, limits=limits, faults=faults)
if __name__ == '__main__':
    if sys.argv[1:] == ['controls']:
        controls()
    else:
        assert len(sys.argv) == 3 and sys.argv[1] in GROUPS
        group = sys.argv[1]; runner = Runner(sys.argv[2], group)
        allocations = GROUPS[group](runner) or 0
        print(f'image-resize-tool-{group} cases={runner.count} reached_allocations={allocations} evidence={runner.directory}')
