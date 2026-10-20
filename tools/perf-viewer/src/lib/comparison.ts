import type { CatalogEntry, Measurement, PerformanceRun } from './types';

// Shown for context but never picked as the external best: TCC does not
// optimize, and TypeScript emits JavaScript rather than native code.
const CONTEXT_ONLY_COMPILERS = new Set(['tcc', 'tsc', 'tsrs']);

export function isComparisonCandidate(measurement: Measurement): boolean {
  return !CONTEXT_ONLY_COMPILERS.has(measurement.compiler.name.toLowerCase());
}

export function selectableResults(entries: CatalogEntry[]): CatalogEntry[] {
  return entries.filter((entry) => !entry.document.workload.baseline_only);
}

// Timings from different machines are never mixed: two results are
// comparable only when their GPU model and logical CPU count match.
export function machineIdentity(machine: PerformanceRun['machine']): string {
  const gpu = (machine.gpu ?? '').split(',')[0].trim();
  return [gpu || machine.platform, machine.logical_cpus ?? ''].join('\u0000');
}

export function composeMeasurements(
  selected: CatalogEntry | undefined,
  entriesNewestFirst: CatalogEntry[],
): Measurement[] {
  if (!selected) return [];
  const measurements = [...selected.document.measurements];
  const comparisonGroup = selected.document.workload.comparison_group;
  if (!comparisonGroup) return measurements;

  const machine = machineIdentity(selected.document.machine);
  const occupied = new Set(measurements.map(measurementIdentity));
  for (const entry of entriesNewestFirst) {
    if (
      !entry.document.workload.baseline_only
      || entry.document.workload.comparison_group !== comparisonGroup
      || machineIdentity(entry.document.machine) !== machine
    ) continue;
    for (const measurement of entry.document.measurements) {
      if (measurement.compiler.name.toLowerCase() === 'lanius') continue;
      const identity = measurementIdentity(measurement);
      if (occupied.has(identity)) continue;
      occupied.add(identity);
      measurements.push({
        ...measurement,
        comparison_origin: {
          kind: 'frozen_baseline',
          result_path: entry.path,
          run_id: entry.document.run.id,
          recorded_at: entry.document.run.recorded_at,
          machine: entry.document.machine,
        },
      });
    }
  }
  return measurements;
}

function measurementIdentity(measurement: Measurement): string {
  return [
    measurement.compiler.name.toLowerCase(),
    measurement.configuration,
    measurement.target,
  ].join('\u0000');
}
