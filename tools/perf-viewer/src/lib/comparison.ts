import type { CatalogEntry, Measurement } from './types';

const CONTEXT_ONLY_COMPILERS = new Set(['tcc']);

export function isComparisonCandidate(measurement: Measurement): boolean {
  return !CONTEXT_ONLY_COMPILERS.has(measurement.compiler.name.toLowerCase());
}

export function selectableResults(entries: CatalogEntry[]): CatalogEntry[] {
  return entries.filter((entry) => !entry.document.workload.baseline_only);
}

export function composeMeasurements(
  selected: CatalogEntry | undefined,
  entriesNewestFirst: CatalogEntry[],
): Measurement[] {
  if (!selected) return [];
  const measurements = [...selected.document.measurements];
  const comparisonGroup = selected.document.workload.comparison_group;
  if (!comparisonGroup) return measurements;

  const occupied = new Set(measurements.map(measurementIdentity));
  for (const entry of entriesNewestFirst) {
    if (
      !entry.document.workload.baseline_only
      || entry.document.workload.comparison_group !== comparisonGroup
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
