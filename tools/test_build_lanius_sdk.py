#!/usr/bin/env python3
"""Host-only SDK packaging controls; fake compilers supply no native evidence."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_lanius_sdk as sdk
import lanius_sdk_launchers as launchers
import lanius_sdk_payload as payload


RECORD = r'''import json, os, pathlib, sys
observed = {"argv": sys.argv[1:], "cwd": os.getcwd(),
            "environment": {key: os.environ.get(key) for key in (
                "LANIUSC", "LANIUS_STDLIB_ROOT", "LANIUS_SOURCE_ROOT",
                "LANIUS_SHADER_ARTIFACT_ROOT")}}
print(json.dumps(observed, ensure_ascii=True, sort_keys=True))
if os.environ.get("SDK_FAKE_LOG"):
    with open(os.environ["SDK_FAKE_LOG"], "a") as stream:
        stream.write("invoked\n")
'''


def write(path: Path, content: bytes | str, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content.encode() if isinstance(content, str) else content)
    path.chmod(mode)


def digest(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def state(root: Path):
    """Independent complete regular-file observation, including permission bits."""
    return {path.relative_to(root).as_posix(): (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
            for path in sorted(root.rglob('*')) if path.is_file() and not path.is_symlink()}


class LauncherTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='lanius-sdk-host-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.stage = self.root / "initial sdk ' $ [ ] ; Ω"
        self.stage.mkdir()
        self.cwd = self.root / 'unrelated working directory'
        self.cwd.mkdir()
        write(self.stage / 'libexec/laniusc', '#!' + sys.executable + '\n' + RECORD, 0o755)
        for name in ('lanius-test', 'vendor_lanius.py', 'build_lanius_sdk.py'):
            write(self.stage / 'share/lanius/tools' / name,
                  '#!' + sys.executable + '\n' + RECORD, 0o755)
        (self.stage / 'shaders').mkdir()
        launchers.install_launchers(self.stage)
        self.environment = {key: value for key, value in os.environ.items()
                            if key not in ('LANIUSC', 'LANIUS_STDLIB_ROOT', 'LANIUS_SOURCE_ROOT',
                                           'LANIUS_SHADER_ARTIFACT_ROOT', 'SDK_FAKE_LOG')}

    def run_launcher(self, name, args=(), updates=None, prefix=None):
        prefix = prefix or self.stage
        result = subprocess.run([str(prefix / 'bin' / name), *args], cwd=self.cwd,
                                env={**self.environment, **(updates or {})},
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, b'')
        return json.loads(result.stdout)

    def test_compiler_is_transparent_after_relocation_and_path_symlink_invocation(self):
        moved = self.root / "relocated sdk ' $(touch SHOULD_NOT_EXIST) ; Ω\n"
        self.stage.rename(moved)
        arguments = ['', ' leading and trailing ', 'one\ntwo', '--package-manifest',
                     "project ' $ ;.json", '--source-root=caller root', '--', '-literal']
        observed = self.run_launcher('laniusc', arguments,
                                     {'LANIUS_SHADER_ARTIFACT_ROOT': '/wrong/shaders'}, moved)
        self.assertEqual(observed['argv'], arguments)
        self.assertEqual(observed['cwd'], str(self.cwd))
        self.assertEqual(observed['environment']['LANIUS_SHADER_ARTIFACT_ROOT'], str(moved / 'shaders'))
        self.assertFalse(self.stage.exists())
        self.assertFalse((self.cwd / 'SHOULD_NOT_EXIST').exists())
        links = self.root / 'external links'
        links.mkdir()
        (links / 'second').symlink_to(moved / 'bin/laniusc')
        (links / 'compiler-alias').symlink_to('second')
        for command, search in ((str(links / 'compiler-alias'), self.environment['PATH']),
                                ('laniusc', str(moved / 'bin') + os.pathsep + self.environment['PATH'])):
            result = subprocess.run([command, *arguments], cwd=self.cwd,
                                    env={**self.environment, 'PATH': search},
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, b'')
            observed = json.loads(result.stdout)
            self.assertEqual(observed['argv'], arguments)
            self.assertEqual(observed['cwd'], str(self.cwd))
            self.assertEqual(observed['environment']['LANIUS_SHADER_ARTIFACT_ROOT'], str(moved / 'shaders'))

    def test_suite_and_vendor_defaults_preserve_explicit_caller_environment(self):
        expected = {'LANIUSC': str(self.stage / 'bin/laniusc'),
                    'LANIUS_STDLIB_ROOT': str(self.stage / 'share/lanius/stdlib'),
                    'LANIUS_SOURCE_ROOT': str(self.stage / 'share/lanius/extended')}
        for empty in ({}, {key: '' for key in expected}):
            observed = self.run_launcher('lanius-test', ('--list', 'a b'), empty)
            self.assertEqual(observed['argv'], ['--list', 'a b'])
            for key, value in expected.items(): self.assertEqual(observed['environment'][key], value)
            self.assertEqual(observed['cwd'], str(self.cwd))
        explicit = {key: f"caller {key} ' $" for key in expected}
        observed = self.run_launcher('lanius-test', ('--filter', 'x'), explicit)
        for key, value in explicit.items(): self.assertEqual(observed['environment'][key], value)
        observed = self.run_launcher('lanius-vendor', ('--manifest', 'a b'))
        self.assertEqual(observed['argv'], ['--manifest', 'a b'])
        self.assertEqual(observed['environment']['LANIUSC'], expected['LANIUSC'])
        self.assertIsNone(observed['environment']['LANIUS_STDLIB_ROOT'])
        self.assertIsNone(observed['environment']['LANIUS_SOURCE_ROOT'])
        observed = self.run_launcher('lanius-vendor', (), explicit)
        for key, value in explicit.items(): self.assertEqual(observed['environment'][key], value)

    def test_verifier_supplies_only_derived_prefix_and_rejects_extra_arguments(self):
        observed = self.run_launcher('lanius-sdk-verify')
        self.assertEqual(observed['argv'], ['--verify', str(self.stage)])
        log = self.root / 'must-not-invoke-helper'
        for arguments in (('other',), ('--verify', '/somewhere'), ('',)):
            result = subprocess.run([str(self.stage / 'bin/lanius-sdk-verify'), *arguments],
                                    env={**self.environment, 'SDK_FAKE_LOG': str(log)},
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(log.exists())

    def test_launcher_installation_refuses_existing_owned_files_and_symlinks(self):
        before = state(self.stage)
        with self.assertRaises((OSError, ValueError, RuntimeError)):
            launchers.install_launchers(self.stage)
        self.assertEqual(state(self.stage), before)
        other = self.root / 'other'
        other.mkdir()
        (other / 'bin').symlink_to(self.stage / 'bin', target_is_directory=True)
        with self.assertRaises((OSError, ValueError, RuntimeError)):
            launchers.install_launchers(other)
        self.assertEqual(state(self.stage), before)


HELPERS = ('build_lanius_sdk.py', 'pin_laniusc.py', 'lanius_sdk_launchers.py',
           'lanius_sdk_payload.py', 'lanius-test', 'vendor_lanius.py')
LAUNCHER_NAMES = ('laniusc', 'lanius-test', 'lanius-vendor', 'lanius-sdk-verify')
FIXTURE_PAYLOAD = {
    'stdlib/core/value.lani': b'module core::value;\n',
    'stdlib/core/value/nested.lani': b'module core::value::nested;\n',
    'extended/ext/sample.lani': b'module ext::sample;\n',
    'docs/library-sdk.md': b'# Synthetic SDK packaging fixture\n',
    'LICENSE-MIT': b'Synthetic MIT notice\n',
    'LICENSE-APACHE': b'Synthetic Apache notice\n',
    'calculator.package.json': b'{"package":"fixture","roots":["extended"]}\n',
}


def input_snapshot(path):
    info = path.stat()
    return {'path': str(path), 'size': info.st_size, 'mtime_ns': info.st_mtime_ns,
            'device': info.st_dev, 'inode': info.st_ino, 'sha256': digest(path.read_bytes()),
            'mode': stat.S_IMODE(info.st_mode)}


def fixture_shaders():
    """Structurally admitted fake headers/reflections, never loadable GPU proof."""
    header = struct.pack('<5I', 0x07230203, 0x00010000, 0, 1, 0)
    pairs = {'parse': (header, b'{"parameters":[]}\n'),
             'parse/nested': (header + b'\0\0\0\0', b'{"parameters":[{"name":"data"}]}\n')}
    # The format is independently specified by laniusc-shaders/build.rs. Hash
    # a fully materialized transcript, unlike the builder's streaming updates.
    transcript = b''.join(name.encode() + b'\0' + code + b'\0' + reflection + b'\xff'
                          for name, (code, reflection) in sorted(pairs.items(), key=lambda item: item[0] + '.slang'))
    from vendor_lanius import fnv1a64
    value = fnv1a64(transcript).split(':', 1)[1]
    result = {name + suffix: payload for name, pair in pairs.items()
              for suffix, payload in zip(('.spv', '.reflect.json'), pair)}
    result['parse.stamp'] = b'fixed synthetic build stamp\n'
    result['artifacts.env'] = (f'digest={value}\ncount=2\nmax_spv_bytes=24\n'
                               'max_spv_name=parse/nested\nsize_guard_status=enforced\n'
                               'size_guard_max_bytes=1024\n').encode()
    return result, value


class BuilderTests(unittest.TestCase):
    """Exercise real builder/pin/verifier, with a tiny explicit payload copier.

    The payload copier is isolated here; PayloadTests below exercise the real
    source/notice helper. No fake compiler parses or compiles Lanius.
    """
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='lanius-sdk-builder-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / 'source tree'
        self.target = self.root / 'compiler target'
        self.outputs = self.root / 'outputs'
        self.outputs.mkdir()
        self.cargo = self.root / 'cargo metadata.json'
        write(self.cargo, '{}\n')
        self.sysroot = self.root / 'rust sysroot'
        self.sysroot.mkdir()
        for name, content in FIXTURE_PAYLOAD.items(): write(self.source / name, content)
        tools = Path(__file__).resolve().parent
        for name in HELPERS: write(self.source / 'tools' / name, (tools / name).read_bytes(), 0o640)
        self.shader_root = self.target / 'laniusc-shader-artifacts/debug/shaders'
        self.shader_bytes, self.shader_digest = fixture_shaders()
        for name, content in self.shader_bytes.items(): write(self.shader_root / name, content)
        self.binary = self.target / 'debug/laniusc'
        self.write_compiler()

    def write_compiler(self, honor=True, exit_status=0):
        compiler = '#!' + sys.executable + '\n' + f'''import os, pathlib, sys
if sys.argv[1:] == ["--version"]:
    root = os.environ.get("LANIUS_SHADER_ARTIFACT_ROOT") if {honor!r} else None
    root = root or {str(self.shader_root)!r}
    try:
        fields = dict(line.split("=", 1) for line in (pathlib.Path(root) / "artifacts.env").read_text().splitlines())
    except OSError:
        fields = {{}}
    print("laniusc fake-packaging-fixture")
    print("shader-artifact-digest: " + fields.get("digest", "unknown"))
    print("shader-artifact-count: " + fields.get("count", "unknown"))
    if os.environ.get("SDK_FAKE_LOG"):
        with open(os.environ["SDK_FAKE_LOG"], "a") as stream: stream.write("version\\n")
    sys.exit({exit_status})
''' + RECORD
        write(self.binary, compiler, 0o755)
        newest = max(path.stat().st_mtime_ns for path in self.shader_root.rglob('*') if path.is_file())
        os.utime(self.binary, ns=(newest + 5_000_000_000, newest + 5_000_000_000))

    def populate(self, source, stage, cargo, sysroot):
        self.assertEqual((source, cargo, sysroot), (self.source, self.cargo, self.sysroot))
        snapshots = []
        for name in FIXTURE_PAYLOAD:
            path = source / name
            snapshots.append(input_snapshot(path))
            write(stage / 'share/lanius' / name, path.read_bytes(), 0o600)
        write(stage / 'notices/dependency.txt', 'Synthetic dependency notice\n', 0o600)
        return {'source': {'revision': '0' * 40, 'dirty': False},
                'source_snapshots': snapshots, 'source_inputs': [row['path'] for row in snapshots],
                'notices': {'scope': 'synthetic test notice inputs'}}

    def build(self, name='sdk', populate=None):
        output = self.outputs / name
        with patch.object(sdk, 'populate_payload', side_effect=populate or self.populate):
            metadata = sdk.build(self.target, 'debug', output, self.cargo, self.sysroot, self.source)
        return output, metadata

    def assert_clean_failure(self, operation, expected=(sdk.SdkError, OSError, ValueError)):
        marker = self.outputs / 'unrelated-owner'
        write(marker, b'keep this owner\n')
        with self.assertRaises(expected): operation()
        self.assertEqual(state(self.outputs), {'unrelated-owner': (b'keep this owner\n', 0o644)})
        self.assertEqual(sorted(path.name for path in self.outputs.iterdir()), ['unrelated-owner'])

    def test_exact_payload_records_hashes_modes_and_identity(self):
        output, metadata = self.build()
        expected = ({'share/lanius/' + name for name in FIXTURE_PAYLOAD}
                    | {'share/lanius/tools/' + name for name in HELPERS}
                    | {'shaders/' + name for name in self.shader_bytes}
                    | {'bin/' + name for name in LAUNCHER_NAMES}
                    | {'notices/dependency.txt', 'libexec/laniusc', 'SDK.txt'})
        observed = state(output)
        self.assertEqual(set(observed), expected | {'SDK.json', 'SHA256SUMS'})
        self.assertTrue({'schema', 'profile', 'binary_sha256', 'shader_digest',
                         'shader_count', 'compiler_version', 'payload', 'files', 'content_id'} <= set(metadata))
        self.assertEqual(metadata['schema'], 'lanius.sdk.v1')
        self.assertEqual(metadata['shader_digest'], self.shader_digest)
        self.assertEqual(metadata['shader_count'], 2)
        self.assertEqual(metadata['binary_sha256'], digest(self.binary.read_bytes()))
        self.assertEqual(metadata['compiler_version'], 'laniusc fake-packaging-fixture\n'
                         f'shader-artifact-digest: {self.shader_digest}\nshader-artifact-count: 2\n')
        self.assertNotIn('source_snapshots', metadata['payload'])
        self.assertNotIn('source_inputs', metadata['payload'])
        records = []
        for name in sorted(expected):
            data, mode = observed[name]
            executable = name.startswith('bin/') or name == 'libexec/laniusc' or name.startswith('share/lanius/tools/')
            self.assertEqual(mode, 0o755 if executable else 0o644, name)
            records.append({'path': name, 'size': len(data), 'sha256': digest(data), 'mode': mode})
        self.assertEqual(metadata['files'], records)
        packed = json.dumps(records, sort_keys=True, ensure_ascii=True, separators=(',', ':')).encode()
        self.assertEqual(metadata['content_id'], 'sha256:' + digest(packed))
        inventory = ''.join(digest(observed[name][0]) + '  ' + name + '\n'
                            for name in sorted(expected | {'SDK.json'}))
        self.assertEqual(observed['SHA256SUMS'], (inventory.encode(), 0o644))
        for name, data in FIXTURE_PAYLOAD.items(): self.assertEqual(observed['share/lanius/' + name][0], data)
        for name, data in self.shader_bytes.items(): self.assertEqual(observed['shaders/' + name][0], data)
        self.assertEqual(sdk.verify(output), (len(expected) + 1, sum(len(observed[name][0]) for name in expected | {'SDK.json'})))

    def test_identical_payload_identity_ignores_destination_and_source_mtimes(self):
        first, one = self.build('one')
        for path in self.source.rglob('*'):
            if path.is_file(): os.utime(path, ns=(1_600_000_000_000_000_000,) * 2)
        second, two = self.build("different ' destination")
        self.assertEqual(one['content_id'], two['content_id'])
        self.assertEqual(one['files'], two['files'])
        # Provenance can record distinct initial SDK paths; it is intentionally
        # outside content_id, while every delivered nonmetadata byte must match.
        self.assertEqual({name: value for name, value in state(first).items() if name not in ('SDK.json', 'SHA256SUMS')},
                         {name: value for name, value in state(second).items() if name not in ('SDK.json', 'SHA256SUMS')})
        write(self.source / 'stdlib/core/value.lani', b'module core::value; // changed\n')
        _, three = self.build('changed-source')
        self.assertNotEqual(one['content_id'], three['content_id'])
        with self.binary.open('a') as stream: stream.write('\n# changed fake compiler bytes\n')
        _, four = self.build('changed-compiler')
        self.assertNotEqual(three['content_id'], four['content_id'])
        write(self.shader_root / 'parse.stamp', 'changed build stamp\n')
        newest = max(path.stat().st_mtime_ns for path in self.shader_root.rglob('*') if path.is_file())
        os.utime(self.binary, ns=(newest + 5_000_000_000,) * 2)
        _, five = self.build('changed-shader-payload')
        self.assertNotEqual(four['content_id'], five['content_id'])

    def test_installed_verifier_is_read_only_after_relocation_without_original_inputs(self):
        output, _ = self.build()
        moved = self.root / "installed ' $ sdk"
        output.rename(moved)
        shutil.rmtree(self.source)
        shutil.rmtree(self.target)
        log = self.root / 'compiler-must-not-run'
        before = state(moved)
        # Deliberately no -B or PYTHONDONTWRITEBYTECODE: installed verification
        # must not create __pycache__ inside its own immutable installation.
        environment = {key: value for key, value in os.environ.items()
                       if key not in ('PYTHONDONTWRITEBYTECODE', 'PYTHONPATH')}
        result = subprocess.run([str(moved / 'bin/lanius-sdk-verify')], cwd=self.root,
                                env={**environment, 'SDK_FAKE_LOG': str(log)},
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, b'')
        self.assertRegex(result.stdout.decode(), r'^verified \d+ payload files \(\d+ bytes\)\n$')
        self.assertFalse(log.exists())
        self.assertEqual(state(moved), before)
        self.assertFalse(list(moved.rglob('__pycache__')))

    def test_all_payload_and_metadata_corruptions_reject(self):
        output, _ = self.build()
        for name in ('libexec/laniusc', 'shaders/parse.spv', 'shaders/parse.reflect.json',
                     'share/lanius/stdlib/core/value.lani', 'notices/dependency.txt',
                     'SDK.txt', 'SDK.json', 'SHA256SUMS'):
            with self.subTest(name=name):
                path = output / name
                original = path.read_bytes()
                path.write_bytes(original + b'!')
                with self.assertRaises((sdk.SdkError, ValueError)): sdk.verify(output)
                path.write_bytes(original)
        original = (output / 'bin/laniusc').stat().st_mode
        (output / 'bin/laniusc').chmod(0o644)
        with self.assertRaises(sdk.SdkError): sdk.verify(output)
        (output / 'bin/laniusc').chmod(stat.S_IMODE(original))
        self.assertTrue(sdk.verify(output))

    def test_missing_extra_symlink_and_fifo_payloads_reject(self):
        output, _ = self.build()
        path = output / 'share/lanius/extended/ext/sample.lani'
        original = path.read_bytes()
        path.unlink()
        with self.assertRaises(sdk.SdkError): sdk.verify(output)
        write(path, original)
        write(output / 'extra', 'extra')
        with self.assertRaises(sdk.SdkError): sdk.verify(output)
        (output / 'extra').unlink()
        path.unlink(); path.symlink_to(output / 'SDK.txt')
        with self.assertRaises(sdk.SdkError): sdk.verify(output)
        path.unlink(); os.mkfifo(path)
        with self.assertRaises(sdk.SdkError): sdk.verify(output)
        path.unlink(); write(path, original)
        (output / 'linked-directory').symlink_to(self.source, target_is_directory=True)
        with self.assertRaises(sdk.SdkError): sdk.verify(output)

    def test_inventory_paths_duplicates_order_and_metadata_identity_reject(self):
        output, _ = self.build()
        path = output / 'SHA256SUMS'
        original = path.read_text()
        rows = original.splitlines(True)
        for invalid in ('../outside', '/absolute', 'a/../../b', 'a//b', 'a/./b', 'a\\b',
                        'bad\tname', 'SHA256SUMS'):
            with self.subTest(path=invalid):
                path.write_text(original + '0' * 64 + '  ' + invalid + '\n')
                with self.assertRaises(sdk.SdkError): sdk.verify(output)
        for changed in (original + rows[-1], ''.join(reversed(rows)), 'g' * 64 + '  SDK.json\n'):
            path.write_text(changed)
            with self.assertRaises(sdk.SdkError): sdk.verify(output)
        path.write_text(original)
        metadata_path = output / 'SDK.json'
        metadata = json.loads(metadata_path.read_text())
        original_metadata = metadata_path.read_bytes()
        for field, bad in (('content_id', 'sha256:' + '0' * 64), ('binary_sha256', '0' * 64),
                           ('shader_count', 7), ('shader_digest', '0' * 16), ('schema', 'unknown')):
            with self.subTest(field=field):
                changed = {**metadata, field: bad}
                metadata_path.write_text(json.dumps(changed))
                # Rehash outer inventory so the semantic metadata check matters.
                path.write_text(''.join((digest(metadata_path.read_bytes()) + '  SDK.json\n')
                                        if row.endswith('  SDK.json\n') else row for row in rows))
                with self.assertRaises(sdk.SdkError): sdk.verify(output)
        metadata_path.write_bytes(original_metadata); path.write_text(original)
        self.assertTrue(sdk.verify(output))

    def test_existing_destinations_are_untouched_and_never_probe_compiler(self):
        owned = self.outputs / 'directory'
        write(owned / 'keep', b'original owner\n')
        write(self.outputs / 'file', b'original file\n')
        (self.outputs / 'link').symlink_to(owned, target_is_directory=True)
        (self.outputs / 'dangling').symlink_to(self.root / 'absent')
        before = state(self.outputs)
        with patch.object(sdk, 'pin', side_effect=AssertionError('must not probe')):
            for name in ('directory', 'file', 'link', 'dangling'):
                with self.subTest(name=name), self.assertRaises(sdk.SdkError): self.build(name)
        self.assertEqual(state(self.outputs), before)
        self.assertEqual(os.readlink(self.outputs / 'link'), str(owned))
        self.assertEqual(os.readlink(self.outputs / 'dangling'), str(self.root / 'absent'))

    def test_ordinary_partial_payload_and_launcher_failures_remove_only_staging(self):
        def failing(*args):
            self.populate(*args)
            raise sdk.SdkError('deliberate partial payload failure')
        self.assert_clean_failure(lambda: self.build(populate=failing))
        with patch.object(sdk, 'install_launchers', side_effect=sdk.SdkError('deliberate launcher failure')):
            self.assert_clean_failure(self.build)

    def test_failed_version_and_ignored_override_probes_leave_no_output(self):
        self.write_compiler(exit_status=7)
        self.assert_clean_failure(self.build)
        self.write_compiler(honor=False)
        self.assert_clean_failure(self.build)

    def test_publication_error_and_concurrently_created_destination_preserve_other_owner(self):
        with patch.object(sdk, 'publish', side_effect=OSError('deliberate publication failure')):
            self.assert_clean_failure(self.build)
        publish = sdk.publish
        def race(stage, output):
            write(output / 'racing-owner', b'owned by somebody else\n')
            return publish(stage, output)
        with patch.object(sdk, 'publish', side_effect=race), self.assertRaises(OSError):
            self.build('concurrent')
        self.assertEqual(state(self.outputs / 'concurrent'), {'racing-owner': (b'owned by somebody else\n', 0o644)})
        self.assertEqual(sorted(path.name for path in self.outputs.iterdir()), ['concurrent', 'unrelated-owner'])

    def test_verification_bounds_inventory_file_count_and_payload_bytes(self):
        output, _ = self.build()
        for name, value in (('MAX_FILES', 2), ('MAX_BYTES', 2)):
            with patch.object(sdk, name, value), self.assertRaises(sdk.SdkError): sdk.verify(output)
        path = output / 'SHA256SUMS'
        path.write_bytes(b'x' * (8 * 1024 * 1024 + 1))
        with self.assertRaises(sdk.SdkError): sdk.verify(output)

    def test_source_and_build_content_races_reject_even_with_restored_mtime(self):
        for target in (self.source / 'stdlib/core/value.lani', self.binary, self.shader_root / 'parse.stamp'):
            with self.subTest(target=target):
                saved, info = target.read_bytes(), target.stat()
                def changed(*args):
                    metadata = self.populate(*args)
                    payload = bytearray(saved); payload[-2] ^= 1
                    target.write_bytes(payload)
                    os.utime(target, ns=(info.st_atime_ns, info.st_mtime_ns))
                    return metadata
                self.assert_clean_failure(lambda: self.build(populate=changed))
                target.write_bytes(saved); os.utime(target, ns=(info.st_atime_ns, info.st_mtime_ns))

    def test_new_library_file_after_payload_scan_is_detected(self):
        def added(*args):
            metadata = self.populate(*args)
            write(self.source / 'extended/ext/added.lani', 'module ext::added;\n')
            return metadata
        self.assert_clean_failure(lambda: self.build(populate=added))

    def test_shader_assets_and_declared_metadata_cannot_silently_go_missing(self):
        for name, changed in (('parse.spv', None), ('parse.reflect.json', None),
                              ('artifacts.env', b'digest=unknown\ncount=2\n'),
                              ('parse.spv', b'not a SPIR-V header'),
                              ('parse.reflect.json', b'{"parameters":null}')):
            with self.subTest(name=name, changed=changed):
                path = self.shader_root / name; original = path.read_bytes()
                if changed is None: path.unlink()
                else: path.write_bytes(changed)
                self.assert_clean_failure(self.build)
                write(path, original)
        path = self.shader_root / 'artifacts.env'; original = path.read_bytes()
        for changed in (original.replace(b'count=2', b'count=1'), original + b'count=2\n',
                        original.replace(self.shader_digest.encode(), b'0' * 16)):
            path.write_bytes(changed)
            self.assert_clean_failure(self.build)
        write(path, original)

    def test_unsafe_profile_and_nonregular_binary_are_rejected_before_publication(self):
        for profile in ('../debug', '/debug', 'a/b', '', 'debug\n'):
            with self.subTest(profile=profile), self.assertRaises(sdk.SdkError):
                sdk.build(self.target, profile, self.outputs / 'sdk', self.cargo, self.sysroot, self.source)
        original = self.binary.read_bytes()
        self.binary.unlink(); self.binary.symlink_to(self.cargo)
        self.assert_clean_failure(self.build)
        self.binary.unlink(); os.mkfifo(self.binary)
        self.assert_clean_failure(self.build)
        self.binary.unlink(); write(self.binary, original, 0o644)
        self.assert_clean_failure(self.build)


SOURCE_NOTICES = ('LICENSE-MIT', 'LICENSE-APACHE', 'data/unicode/17.0.0/LICENSE.txt',
                  'third_party/rust-dec2flt/LICENSE-MIT', 'third_party/rust-dec2flt/LICENSE-APACHE',
                  'third_party/rust-dec2flt/NOTICE.md')
DOCUMENTS = ('docs/library-sdk.md', 'docs/library-distribution.md', 'docs/library-overview.md',
             'docs/library-roadmap.md', 'docs/library-dependencies.md', 'docs/library-api-conventions.md',
             'docs/library-api-reference.md', 'docs/stdlib-development.md', 'stdlib/README.md',
             'extended/README.md', 'docs/guide.md', 'docs/linked.md', 'docs/api/value.md')
EXAMPLE_SOURCES = {'calculator': 'sample_programs/library/expr_calc.lani',
                   'hash': 'sample_programs/library/openssl_hash.lani',
                   'suite': 'sample_programs/library/sdk_suite.lani'}
RUST_NOTICES = ('share/doc/rust/COPYRIGHT.html', 'share/doc/rust/COPYRIGHT-library.html',
                'share/doc/rust/licenses/LICENSE-TEST')


class PayloadTests(unittest.TestCase):
    """Real source/notice helper, using a temporary Git repository only."""
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='lanius-sdk-payload-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        self.stage = self.root / 'stage'
        self.stage.mkdir()
        self.sysroot = self.root / 'rust'
        self.cargo = self.root / 'cargo.json'
        self.sources = {'stdlib/core/value.lani': b'module core::value;\n',
                        'stdlib/core/value/nested.lani': b'module core::value::nested;\n',
                        'extended/ext/example.lani': b'module ext::example;\n',
                        'extended/support.bash': b'#!/usr/bin/env bash\n# fixture support\n'}
        for name, data in self.sources.items(): write(self.source / name, data)
        for name in SOURCE_NOTICES: write(self.source / name, 'fixture notice ' + name + '\n')
        for name in DOCUMENTS: write(self.source / name, '# ' + name + '\n')
        write(self.source / 'docs/guide.md',
              '# Guide\n[local](linked.md)\n[source](../stdlib/core/value.lani)\n'
              '[committed evidence](../tests/evidence.rs#L2)\n'
              '[unpublished artifact](../target/absent.log)\n[uncommitted](../scratch.txt)\n')
        write(self.source / 'tools/library_reference_metadata.json',
              json.dumps({'modules': {'core::value': {'guides': ['docs/guide.md']}}}))
        for name, path in EXAMPLE_SOURCES.items(): write(self.source / path, '// ' + name + '\nmodule app::main;\n')
        write(self.source / 'tests/evidence.rs', '// committed source evidence\n')
        write(self.source / 'Cargo.lock', 'version = 4\n\n[[package]]\n'
              'name = "fixture"\nversion = "1.0.0"\nsource = "registry+fixture"\n')
        self.crate = self.root / 'crate'
        write(self.crate / 'Cargo.toml', '[package]\nname="fixture"\nversion="1.0.0"\n')
        write(self.crate / 'LICENSE-MIT', 'external crate license bytes\n')
        self.package = {'name': 'fixture', 'version': '1.0.0', 'id': 'registry+fixture#1.0.0',
                        'source': 'registry+fixture', 'license': 'MIT', 'license_file': None,
                        'manifest_path': str(self.crate / 'Cargo.toml')}
        self.metadata = {'version': 1, 'packages': [self.package], 'workspace_members': [],
                         'resolve': {'root': self.package['id'], 'nodes': [
                             {'id': self.package['id'], 'dependencies': [], 'deps': []}]}}
        write(self.cargo, json.dumps(self.metadata))
        for name in RUST_NOTICES: write(self.sysroot / name, 'rust fixture notice ' + name + '\n')
        self.git('init', '-q')
        self.git('config', 'user.email', 'sdk-fixture@example.invalid')
        self.git('config', 'user.name', 'SDK fixture')
        self.git('config', 'core.hooksPath', str(self.root / 'no-hooks'))
        self.git('remote', 'add', 'origin', 'https://github.com/example/sdk-fixture.git')
        self.git('add', '.')
        # This commit is confined to the temporary fixture, never the workspace.
        self.git('-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture input')
        self.revision = self.git('rev-parse', 'HEAD').decode().strip()
        write(self.source / 'scratch.txt', 'uncommitted input must not become published evidence\n')

    def git(self, *arguments):
        result = subprocess.run(['git', '-C', str(self.source), *arguments],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10,
                                env={**os.environ, 'GIT_AUTHOR_DATE': '2000-01-01T00:00:00Z',
                                     'GIT_COMMITTER_DATE': '2000-01-01T00:00:00Z'})
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def populate(self):
        return payload.populate_payload(self.source, self.stage, self.cargo, self.sysroot)

    def fresh_stage(self):
        shutil.rmtree(self.stage)
        self.stage.mkdir()

    def test_real_payload_exact_files_source_bytes_relative_examples_and_notice_identity(self):
        metadata = self.populate()
        package_key = 'fixture-1.0.0-' + digest(self.package['id'].encode())[:8]
        expected = ({'share/lanius/' + name for name in self.sources}
                    | {'share/lanius/' + name for name in SOURCE_NOTICES}
                    | {'share/lanius/' + name for name in DOCUMENTS}
                    | {'share/lanius/examples/' + name + '/app/main.lani' for name in EXAMPLE_SOURCES}
                    | {'share/lanius/' + name + '.package.json' for name in EXAMPLE_SOURCES}
                    | {'share/lanius/docs/sdk-unbundled-references.json', 'notices/cargo/Cargo.lock',
                       'notices/cargo/index.json', 'notices/rust/index.json',
                       'notices/cargo/packages/' + package_key + '/Cargo.toml',
                       'notices/cargo/packages/' + package_key + '/files/LICENSE-MIT'}
                    | {'notices/rust/' + name for name in RUST_NOTICES})
        observed = state(self.stage)
        self.assertEqual(set(observed), expected)
        self.assertTrue(all(mode == 0o644 for _, mode in observed.values()))
        for name, data in self.sources.items(): self.assertEqual(observed['share/lanius/' + name][0], data)
        for name in SOURCE_NOTICES: self.assertEqual(observed['share/lanius/' + name][0], (self.source / name).read_bytes())
        for name in RUST_NOTICES: self.assertEqual(observed['notices/rust/' + name][0], (self.sysroot / name).read_bytes())
        self.assertEqual(observed['notices/cargo/packages/' + package_key + '/files/LICENSE-MIT'][0],
                         b'external crate license bytes\n')
        for name, source in EXAMPLE_SOURCES.items():
            entry = 'examples/' + name + '/app/main.lani'
            self.assertEqual(observed['share/lanius/' + entry][0], (self.source / source).read_bytes())
            manifest = json.loads(observed['share/lanius/' + name + '.package.json'][0])
            self.assertEqual(manifest, {'package': 'sdk.' + name, 'roots': ['extended', 'examples/' + name],
                                        'stdlib_root': 'stdlib', 'entry': entry})
            for path in [*manifest['roots'], manifest['stdlib_root'], manifest['entry']]:
                self.assertFalse(Path(path).is_absolute())
                self.assertNotIn('..', Path(path).parts)
        self.assertEqual(metadata['source']['revision'], self.revision)
        self.assertTrue(metadata['source']['dirty'])
        self.assertEqual(metadata['libraries'], {'source_files': 3,
                                               'source_bytes': sum(len(data) for name, data in self.sources.items() if name.endswith('.lani')),
                                               'support_files': 1})
        self.assertEqual(metadata['notices']['cargo_packages'], 1)
        self.assertEqual(metadata['notices']['rust_notice_files'], 3)
        self.assertEqual(metadata['notices']['gaps'], [])
        cargo_index = json.loads(observed['notices/cargo/index.json'][0])
        self.assertEqual(cargo_index['metadata_sha256'], digest(self.cargo.read_bytes()))
        self.assertEqual(cargo_index['lock_sha256'], digest((self.source / 'Cargo.lock').read_bytes()))
        self.assertEqual(cargo_index['locked_outside_supplied_resolution'], [])
        self.assertEqual(metadata['notices']['locked_outside_supplied_resolution'], 0)

    def test_documentation_keeps_local_links_and_distinguishes_published_evidence(self):
        metadata = self.populate()
        guide = (self.stage / 'share/lanius/docs/guide.md').read_text()
        self.assertIn('[local](linked.md)', guide)
        self.assertIn('[source](../stdlib/core/value.lani)', guide)
        self.assertIn(f'https://github.com/example/sdk-fixture/blob/{self.revision}/tests/evidence.rs#L2', guide)
        self.assertNotIn('/blob/' + self.revision + '/target/', guide)
        self.assertNotIn('/blob/' + self.revision + '/scratch.txt', guide)
        self.assertEqual(guide.count('(library-sdk.md#documentation-boundaries)'), 2)
        boundaries = json.loads((self.stage / 'share/lanius/docs/sdk-unbundled-references.json').read_text())
        self.assertEqual(boundaries, [{'document': 'docs/guide.md', 'reference': '../target/absent.log'},
                                      {'document': 'docs/guide.md', 'reference': '../scratch.txt'}])
        self.assertEqual(metadata['documentation']['online_references'], 1)
        self.assertEqual(metadata['documentation']['unbundled_references'], 2)

    def test_modified_omitted_tracked_evidence_does_not_link_to_old_revision(self):
        write(self.source / 'tests/evidence.rs', '// modified evidence is not committed evidence\n')
        metadata = self.populate()
        guide = (self.stage / 'share/lanius/docs/guide.md').read_text()
        self.assertIn('[committed evidence](library-sdk.md#documentation-boundaries)', guide)
        self.assertNotIn('/blob/' + self.revision + '/tests/evidence.rs', guide)
        boundaries = json.loads((self.stage / 'share/lanius/docs/sdk-unbundled-references.json').read_text())
        self.assertEqual(boundaries, [{'document': 'docs/guide.md', 'reference': '../tests/evidence.rs#L2'},
                                      {'document': 'docs/guide.md', 'reference': '../target/absent.log'},
                                      {'document': 'docs/guide.md', 'reference': '../scratch.txt'}])
        self.assertEqual(metadata['documentation']['online_references'], 0)
        self.assertEqual(metadata['documentation']['unbundled_references'], 3)

    def test_selected_resolution_cannot_silently_omit_packages_or_lock_identities(self):
        other_crate = self.root / 'other-crate'
        write(other_crate / 'Cargo.toml', '[package]\nname="other"\nversion="1.0.0"\n')
        write(other_crate / 'LICENSE-MIT', 'other dependency license\n')
        other = {**self.package, 'name': 'other', 'id': 'registry+fixture#other@1.0.0',
                 'manifest_path': str(other_crate / 'Cargo.toml')}
        self.metadata['packages'].append(other)
        self.metadata['resolve']['nodes'][0]['dependencies'] = [other['id']]
        self.metadata['resolve']['nodes'][0]['deps'] = [{'name': 'other', 'pkg': other['id'], 'dep_kinds': []}]
        self.metadata['resolve']['nodes'].append({'id': other['id'], 'dependencies': [], 'deps': []})
        lock = (self.source / 'Cargo.lock').read_text()
        write(self.source / 'Cargo.lock', lock + '\n[[package]]\nname = "other"\n'
              'version = "1.0.0"\nsource = "registry+fixture"\n')
        notice = b'independent overlay notice\n'
        write(self.source / 'data/sdk-notices/fixture/NOTICE', notice)
        write(self.source / 'data/sdk-notices/provenance.json', json.dumps({
            'format_version': 1, 'packages': [{'name': 'fixture', 'version': '1.0.0', 'files': [
                {'path': 'fixture/NOTICE', 'sha256': digest(notice)}]}]}))
        write(self.cargo, json.dumps(self.metadata))
        self.assertEqual(self.populate()['notices']['cargo_packages'], 2)
        self.fresh_stage()
        mutations = {
            'missing selected package': lambda data: data['packages'].pop(),
            'missing selected node': lambda data: data['resolve']['nodes'].pop(),
            'missing edge target': lambda data: data['resolve']['nodes'][0]['dependencies'].append('omitted'),
            'missing named edge target': lambda data: data['resolve']['nodes'][0]['deps'].append({'pkg': 'omitted'}),
            'unlocked identity': lambda data: data['packages'][1].update(version='2.0.0'),
        }
        for label, mutate in mutations.items():
            with self.subTest(case=label):
                data = json.loads(json.dumps(self.metadata)); mutate(data)
                write(self.cargo, json.dumps(data))
                with self.assertRaises(payload.PayloadError): self.populate()
                self.fresh_stage()

    def test_locked_packages_outside_resolution_are_reported_without_fabricated_notices(self):
        lock = (self.source / 'Cargo.lock').read_text()
        write(self.source / 'Cargo.lock', lock + '\n[[package]]\nname = "unselected"\n'
              'version = "2.3.4"\nsource = "registry+outside"\n')
        metadata = self.populate()
        index = json.loads((self.stage / 'notices/cargo/index.json').read_text())
        self.assertEqual(index['locked_outside_supplied_resolution'], [
            {'name': 'unselected', 'version': '2.3.4', 'source': 'registry+outside'}])
        self.assertEqual(metadata['notices']['locked_outside_supplied_resolution'], 1)
        self.assertEqual([row['id'] for row in index['packages']], [self.package['id']])
        self.assertEqual(metadata['notices']['cargo_packages'], 1)
        self.assertEqual(index['gaps'], [])
        self.assertFalse(any('unselected' in name for name in state(self.stage)))

    def test_missing_required_source_document_example_and_toolchain_notice_reject(self):
        for path in (self.source / 'LICENSE-MIT', self.source / 'docs/library-sdk.md',
                     self.source / EXAMPLE_SOURCES['suite'], self.source / 'Cargo.lock',
                     self.sysroot / RUST_NOTICES[0], self.sysroot / RUST_NOTICES[-1]):
            with self.subTest(path=path):
                original = path.read_bytes(); path.unlink()
                with self.assertRaises((payload.PayloadError, OSError)): self.populate()
                write(path, original); self.fresh_stage()

    def test_rust_copyright_size_exception_is_bounded_and_does_not_expand_metadata(self):
        ordinary_limit = 8 * 1024 * 1024
        copyright_limit = 32 * 1024 * 1024
        large_notice = b'R' * (ordinary_limit + 1)
        for relative in RUST_NOTICES[:2]:
            with self.subTest(copyright=relative):
                source = self.sysroot / relative
                original = source.read_bytes()
                write(source, large_notice)
                metadata = self.populate()
                destination = 'notices/rust/' + relative
                self.assertEqual((self.stage / destination).read_bytes(), large_notice)
                index = json.loads((self.stage / 'notices/rust/index.json').read_text())
                self.assertIn({'path': destination, 'sha256': digest(large_notice)}, index['files'])
                self.assertEqual(metadata['notices']['rust_notice_files'], 3)
                self.fresh_stage()
                # Sparse oversized input exercises preflight without a 32 MiB allocation.
                with source.open('wb') as stream:
                    stream.truncate(copyright_limit + 1)
                with self.assertRaisesRegex(payload.PayloadError, 'input exceeds'):
                    self.populate()
                write(source, original); self.fresh_stage()
        metadata_bytes = self.cargo.read_bytes()
        write(self.cargo, metadata_bytes + b' ' * (ordinary_limit + 1 - len(metadata_bytes)))
        with self.assertRaisesRegex(payload.PayloadError, 'input exceeds'):
            self.populate()

    def test_dependency_notice_gap_is_reported_and_missing_declared_notice_rejects(self):
        (self.crate / 'LICENSE-MIT').unlink()
        metadata = self.populate()
        self.assertEqual(len(metadata['notices']['gaps']), 1)
        self.assertEqual(metadata['notices']['gaps'][0]['name'], 'fixture')
        self.fresh_stage()
        self.package['license_file'] = 'missing-license'
        write(self.cargo, json.dumps(self.metadata))
        with self.assertRaises((payload.PayloadError, OSError)): self.populate()

    def test_symlink_library_and_required_notice_are_rejected(self):
        for path in (self.source / 'stdlib/core/value.lani', self.source / 'LICENSE-MIT'):
            with self.subTest(path=path):
                original = path.read_bytes(); path.unlink(); path.symlink_to(self.cargo)
                with self.assertRaises(payload.PayloadError): self.populate()
                path.unlink(); write(path, original); self.fresh_stage()

    def test_fifo_notice_and_metadata_are_rejected_without_waiting_for_a_writer(self):
        # A child deadline turns a blocking open regression into a bounded failure.
        program = '''import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import lanius_sdk_payload as payload
try:
    payload.populate_payload(*(Path(value) for value in sys.argv[2:]))
except (payload.PayloadError, OSError):
    print("rejected nonregular input")
else:
    raise SystemExit("unexpected successful payload")
'''
        for path in (self.source / 'LICENSE-MIT', self.cargo):
            with self.subTest(path=path):
                original = path.read_bytes(); path.unlink(); os.mkfifo(path)
                result = subprocess.run(
                    [sys.executable, '-B', '-c', program, str(Path(__file__).resolve().parent),
                     str(self.source), str(self.stage), str(self.cargo), str(self.sysroot)],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, b'rejected nonregular input\n')
                self.assertEqual(result.stderr, b'')
                path.unlink(); write(path, original); self.fresh_stage()

    def test_source_content_change_during_copy_is_rejected(self):
        original_write = payload._write
        changed = False
        target = self.source / 'stdlib/core/value.lani'
        def mutate(stage, relative, data):
            nonlocal changed
            original_write(stage, relative, data)
            if relative == 'share/lanius/stdlib/core/value.lani' and not changed:
                changed = True
                original, info = target.read_bytes(), target.stat()
                target.write_bytes(original.replace(b'value', b'other'))
                os.utime(target, ns=(info.st_atime_ns, info.st_mtime_ns))
        with patch.object(payload, '_write', side_effect=mutate), self.assertRaises(payload.PayloadError):
            self.populate()
        self.assertTrue(changed)


if __name__ == '__main__':
    unittest.main()
