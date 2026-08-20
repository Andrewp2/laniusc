import { compilerPhaseName } from './format.ts';
import type { Measurement } from './types.ts';

export interface AnalysisHighlights {
  busiestGpuPhase: { name: string; durationMs: number } | null;
  peakTrackedBytes: number | null;
  peakGraphBytes: number | null;
  peakAllocations: number | null;
}

export function analysisHighlights(measurement: Measurement | undefined): AnalysisHighlights {
  if (!measurement) return emptyHighlights();

  const gpuTimeByPhase = new Map<string, number>();
  for (const event of measurement.profile?.timeline ?? []) {
    if (event.execution_domain !== 'gpu_execution' || !Number.isFinite(event.duration_ms)) continue;
    const phase = event.phase === 'orchestration' ? 'unattributed_gpu' : event.phase;
    gpuTimeByPhase.set(phase, (gpuTimeByPhase.get(phase) ?? 0) + event.duration_ms);
  }
  const busiest = [...gpuTimeByPhase.entries()].sort((left, right) => right[1] - left[1])[0];

  const physicalPoints = measurement.profile?.gpu_memory_timeline?.physical_residency.points ?? [];
  const workingSet = measurement.profile?.gpu_memory_timeline?.graph_managed_working_set.intervals ?? [];
  const trackedBytes = [
    ...measurement.samples.map((sample) => sample.gpu_memory?.peak_bytes),
    ...physicalPoints.map((point) => point.bytes),
  ];
  const allocations = [
    ...measurement.samples.map((sample) => sample.gpu_memory?.peak_allocations),
    ...physicalPoints.map((point) => point.allocations),
  ];

  return {
    busiestGpuPhase: busiest ? { name: compilerPhaseName(busiest[0]), durationMs: busiest[1] } : null,
    peakTrackedBytes: maximum(trackedBytes),
    peakGraphBytes: maximum(workingSet.map((interval) => interval.bytes)),
    peakAllocations: maximum(allocations),
  };
}

function maximum(values: Array<number | null | undefined>): number | null {
  const finite = values.filter((value): value is number => typeof value === 'number' && Number.isFinite(value));
  return finite.length ? Math.max(...finite) : null;
}

function emptyHighlights(): AnalysisHighlights {
  return {
    busiestGpuPhase: null,
    peakTrackedBytes: null,
    peakGraphBytes: null,
    peakAllocations: null,
  };
}
