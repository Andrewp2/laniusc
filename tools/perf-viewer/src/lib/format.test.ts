import assert from 'node:assert/strict';
import test from 'node:test';

import { formatComparisonMs, measurementLabel } from './format.ts';
import type { Measurement } from './types.ts';

test('comparison timings remain in milliseconds across the full range', () => {
  assert.equal(formatComparisonMs(0.125), '0.125 ms');
  assert.equal(formatComparisonMs(41.84), '41.84 ms');
  assert.equal(formatComparisonMs(1_146.351), '1,146.35 ms');
  assert.equal(formatComparisonMs(5_000), '5,000 ms');
});

test('the warm workspace label presents its useful distinguishing detail', () => {
  const measurement = {
    compiler: { name: 'lanius', version: 'test' },
    configuration: 'daemon_warm_workspace',
    target: 'x86_64',
    source: { files: 1 },
  } as Measurement;

  assert.equal(measurementLabel(measurement, false), 'Lanius · preallocated');
});
