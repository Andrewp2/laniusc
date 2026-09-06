"""Focused acceptance/rejection tests for the fresh single-process checker."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
PREFIX = 'Lanius.Extraction.VerifiedFrontend.'


class BatchCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lean = subprocess.check_output(
            ['lake', 'env', 'which', 'lean'], cwd=ROOT, text=True).strip()
        cls.lean_path = subprocess.check_output(
            ['lake', 'env', 'printenv', 'LEAN_PATH'], cwd=ROOT, text=True).strip()

    def run_case(self, sources, final='batchResult', shared=None, duplicate=False,
                 prebuild=False):
        with tempfile.TemporaryDirectory(prefix='lanius-batch-test-') as temporary:
            root = Path(temporary)
            modules = []
            for name, source in sources.items():
                module = PREFIX + name
                path = root / (module.replace('.', '/') + '.lean')
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('import Lean\n' + source)
                modules.append(module)
            env = dict(os.environ, LEAN_PATH=self.lean_path)
            imports = shared or ['Lean']
            if prebuild:
                module = modules[0]
                library = root / 'lib'
                output = library / (module.replace('.', '/') + '.olean')
                output.parent.mkdir(parents=True, exist_ok=True)
                compiled = subprocess.run([
                    self.lean, '--root=' + str(root), '-o', str(output),
                    str(root / (module.replace('.', '/') + '.lean')),
                ], cwd=root, env=env, capture_output=True, text=True)
                self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
                env['LEAN_PATH'] = str(library) + ':' + self.lean_path
                imports = ['Lean', module]
                modules = []
            if duplicate:
                modules += modules[:1]
            manifest = root / 'manifest.json'
            manifest.write_text(json.dumps({
                'root': str(root), 'shared': imports, 'modules': modules,
                'finalName': final, 'output': str(root / 'objects'),
            }))
            return subprocess.run([
                self.lean, '-M', '12000', '--run',
                str(ROOT / 'Lanius/Tools/SurfaceBatch.lean'), str(manifest),
            ], cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)

    def assert_rejected(self, result, reason):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(reason, result.stdout + result.stderr)
        self.assertNotIn('"complete":true', result.stdout)

    def test_valid_and_private_file_boundaries(self):
        result = self.run_case({
            'First': 'private def value := 1\ntheorem first : value = 1 := by rfl\n',
            'Second': 'private def value := 2\ntheorem batchResult : value = 2 := by rfl\n',
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        final = json.loads(result.stdout.splitlines()[-1])
        self.assertTrue(final['complete'])
        self.assertEqual(final['modules'], 2)
        self.assertEqual(final['axioms'], [])

    def test_false_proof(self):
        self.assert_rejected(self.run_case({
            'False': 'theorem batchResult : (1 : Nat) = 2 := by rfl\n',
        }), 'rfl')

    def test_fresh_dependency_diamond(self):
        result = self.run_case({
            'Base': 'def seed : Nat := 3\n',
            'Left': f'import {PREFIX}Base\ndef left := seed + 1\n',
            'Right': f'import {PREFIX}Base\ndef right := seed + 2\n',
            'Join': f'import {PREFIX}Left\nimport {PREFIX}Right\n'
                    'theorem batchResult : left + right = 9 := by rfl\n',
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(json.loads(result.stdout.splitlines()[-1])['complete'])

    def test_unimported_program_declaration_is_unavailable(self):
        self.assert_rejected(self.run_case({
            'Hidden': 'def hiddenValue : Nat := 3\n',
            'Consumer': 'set_option autoImplicit false\n'
                        'theorem batchResult : hiddenValue = 3 := by rfl\n',
        }), 'Unknown identifier')

    def test_admitted_proof(self):
        self.assert_rejected(self.run_case({
            'Admitted': 'theorem batchResult : False := by sorry\n',
        }), 'unexpected axiom: sorryAx')

    def test_unprocessed_source(self):
        self.assert_rejected(self.run_case({
            'Truncated': 'theorem batchResult : True := trivial\n#exit\nthis is invalid\n',
        }), 'source was not fully processed')

    def test_missing_final_theorem(self):
        self.assert_rejected(self.run_case({
            'Missing': 'theorem another : True := trivial\n',
        }), 'final theorem was not checked')

    def test_duplicate_module(self):
        self.assert_rejected(self.run_case({
            'Repeated': 'theorem batchResult : True := trivial\n',
        }, duplicate=True), 'duplicate or imported program module')

    def test_prebuilt_program_import(self):
        self.assert_rejected(self.run_case({
            'Prebuilt': 'theorem batchResult : True := trivial\n',
        }, prebuild=True), 'program-specific import forbidden')


if __name__ == '__main__':
    unittest.main()
