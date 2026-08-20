import assert from 'node:assert/strict';
import test from 'node:test';

import { analysisHighlights } from './analysis.ts';
import type { Measurement } from './types.ts';

test('analysis highlights retain the most actionable profile and memory peaks', () => {
  const measurement = {
    samples: [
      { gpu_memory: { peak_bytes: 800, peak_allocations: 8 } },
      { gpu_memory: { peak_bytes: 900, peak_allocations: 9 } },
    ],
    profile: {
      timeline: [
        { phase: 'parsing', execution_domain: 'gpu_execution', duration_ms: 4 },
        { phase: 'parsing', execution_domain: 'gpu_execution', duration_ms: 3 },
        { phase: 'type_checking', execution_domain: 'gpu_execution', duration_ms: 6 },
        { phase: 'parsing', execution_domain: 'host_orchestration', duration_ms: 50 },
      ],
      gpu_memory_timeline: {
        physical_residency: { points: [{ bytes: 1000, allocations: 10 }] },
        graph_managed_working_set: { intervals: [{ bytes: 650 }, { bytes: 700 }] },
      },
    },
  } as Measurement;

  assert.deepEqual(analysisHighlights(measurement), {
    busiestGpuPhase: { name: 'Parsing', durationMs: 7 },
    peakTrackedBytes: 1000,
    peakGraphBytes: 700,
    peakAllocations: 10,
  });
});

test('analysis highlights remain explicit when telemetry was not captured', () => {
  assert.deepEqual(analysisHighlights({ samples: [] } as unknown as Measurement), {
    busiestGpuPhase: null,
    peakTrackedBytes: null,
    peakGraphBytes: null,
    peakAllocations: null,
  });
});
