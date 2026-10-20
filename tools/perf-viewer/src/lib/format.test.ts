import assert from 'node:assert/strict';
import test from 'node:test';

import { formatComparisonMs, measurementColor, measurementLabel } from './format.ts';
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

test('the added cross-language compilers have display names and distinct colors', () => {
  const cases: [string, string, string][] = [
    ['d', 'optimized', 'D (dmd) · optimized'],
    ['ldc', 'o0', 'D (LDC) · -O0'],
    ['go', 'optimized', 'Go · optimized'],
    ['v', 'o0', 'V · -O0'],
    ['vx', 'optimized', 'Vx · optimized'],
    ['tsc', 'check_emit', 'TypeScript (tsc) · type check + JS emit (no native code)'],
    ['tsrs', 'check_emit', 'TypeScript (tsrs) · type check + JS emit (no native code)'],
  ];
  const colors = new Set<string>();
  for (const [name, configuration, label] of cases) {
    const measurement = {
      compiler: { name, version: 'test' },
      configuration,
      target: 'x86_64',
      source: { files: 1 },
    } as Measurement;
    assert.equal(measurementLabel(measurement, false), label);
    const color = measurementColor(measurement);
    assert.notEqual(color, 'var(--muted)', name);
    colors.add(color);
  }
  assert.equal(colors.size, cases.length);
  const original = ['c', 'cpp', 'rust', 'zig', 'tcc', 'pareas'].map((name) =>
    measurementColor({ compiler: { name, version: 'test' }, configuration: 'o0' } as Measurement));
  for (const color of original) assert.ok(!colors.has(color), color);
  const fastest = {
    compiler: { name: 'vx', version: 'test' },
    configuration: 'fastest',
    target: 'x86_64',
    source: { files: 1 },
  } as Measurement;
  assert.equal(measurementLabel(fastest, false), 'Vx · fastest config, 5 seeds');
});
