import assert from 'node:assert/strict';
import test from 'node:test';

import { composeMeasurements } from './comparison.ts';
import type { CatalogEntry, Measurement } from './types.ts';

const GROUP = 'typical-project/v1/seed-20260808/files-100';
const WORKLOAD_GROUPS = [
  'compiler-stress/comparative-single-file/pareas-common-subset/1000000/seeds-reference',
  'compiler-stress/comparative-single-file/pareas-common-subset/10000000/seeds-reference',
  'compiler-stress/comparative-single-file/pareas-common-subset/100000000/seeds-reference',
  'compiler-stress/comparative-single-file/pareas-common-subset/1000000000/seeds-reference',
  'typical-project/v1/seed-20260808/files-10',
  'typical-project/v1/seed-20260808/files-100',
  'typical-project/v1/seed-20260808/files-1000',
  'typical-project/v1/seed-20260808/files-10000',
];

function measurement(compiler: string, configuration: string): Measurement {
  return {
    id: `${compiler}-${configuration}`,
    compiler: { name: compiler, version: 'test' },
    target: 'x86_64',
    configuration,
    source: { files: 100, bytes: 1, sloc: 1 } as Measurement['source'],
    commands: {},
    samples: [{ index: 0, wall_ms: 1 }],
    summary: {
      wall_ms: {
        samples: 1, median: 1, mean: 1, mad: 0, minimum: 1, maximum: 1, p95: 1,
        histogram: { unit: 'ms', edges: [1, 1], counts: [1] },
      },
      compiler_ms: null,
      median_bytes_per_second: 1,
      median_sloc_per_second: 1,
    },
  } as Measurement;
}

function entry(
  path: string,
  measurements: Measurement[],
  baselineOnly = false,
  comparisonGroup = GROUP,
): CatalogEntry {
  return {
    result_id: path,
    path,
    document: {
      schema: 'lanius.performance-run.v1',
      run: { id: path, recorded_at: '2026-08-18T00:00:00Z', git_commit: 'test', git_dirty: false },
      machine: { platform: 'test' },
      workload: {
        id: 'typical-100', kind: 'typical_project', classification: 'test', generator: 'test',
        comparison_group: comparisonGroup, baseline_only: baselineOnly,
      },
      measurements,
    },
  };
}

test('every workload shape receives all available frozen measurements in its group', () => {
  for (const comparisonGroup of WORKLOAD_GROUPS) {
    const selected = entry('lanius.json', [
      measurement('lanius', 'daemon_warm_workspace'),
    ], false, comparisonGroup);
    const external = entry('external.json', [
      measurement('c', 'o0'), measurement('c', 'optimized'),
      measurement('cpp', 'o0'), measurement('cpp', 'optimized'),
      measurement('rust', 'o0'), measurement('rust', 'optimized'),
      measurement('zig', 'o0'), measurement('zig', 'optimized'),
    ], true, comparisonGroup);
    const tcc = entry('tcc.json', [
      measurement('tcc', 'default'), measurement('tcc', 'parallel-32'),
    ], true, comparisonGroup);
    const unrelated = entry(
      'unrelated.json', [measurement('pareas', 'cuda')], true, `${comparisonGroup}/other`,
    );

    const composed = composeMeasurements(selected, [selected, tcc, external, unrelated]);
    const identities = composed.map((value) => `${value.compiler.name}:${value.configuration}`);

    assert.deepEqual(identities, [
      'lanius:daemon_warm_workspace',
      'tcc:default',
      'tcc:parallel-32',
      'c:o0',
      'c:optimized',
      'cpp:o0',
      'cpp:optimized',
      'rust:o0',
      'rust:optimized',
      'zig:o0',
      'zig:optimized',
    ], comparisonGroup);
    assert.equal(composed.filter((value) => value.comparison_origin).length, 10);
  }
});

test('a selected measurement wins over a frozen duplicate', () => {
  const selected = entry('selected.json', [measurement('lanius', 'daemon_warm_workspace')]);
  const frozen = entry('frozen.json', [
    measurement('lanius', 'daemon_warm_workspace'),
    measurement('c', 'o0'),
  ], true);

  const composed = composeMeasurements(selected, [selected, frozen]);

  assert.deepEqual(composed.map((value) => `${value.compiler.name}:${value.configuration}`), [
    'lanius:daemon_warm_workspace',
    'c:o0',
  ]);
});
