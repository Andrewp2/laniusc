import type { Measurement, PerformanceRun } from './types';

export const SERIES = ['var(--cyan)', 'var(--violet)', 'var(--green)', 'var(--orange)', 'var(--red)'];

const COMPILER_NAMES: Record<string, string> = {
  c: 'C',
  cpp: 'C++',
  lanius: 'Lanius',
  pareas: 'Pareas',
  rust: 'Rust',
  tcc: 'TCC',
  zig: 'Zig',
};

const CONFIGURATION_NAMES: Record<string, string> = {
  process_cold: 'pure cold',
  daemon_cold_workspace: 'daemon, cold workspace',
  daemon_warm_workspace: 'daemon, preallocated workspace',
  o0: '-O0',
  cuda: 'CUDA',
  'preallocated (legacy variable-project run)': 'preallocated (legacy)',
};

export function formatMs(value: number): string {
  if (!Number.isFinite(value)) return '—';
  if (value === 0) return '0 ms';
  if (value < 1) return `${value.toFixed(3)} ms`;
  if (value < 1000) return `${value.toFixed(2)} ms`;
  return `${(value / 1000).toFixed(2)} s`;
}

export function formatRate(value: number, unit: string): string {
  if (!Number.isFinite(value)) return '—';
  return `${new Intl.NumberFormat('en', { notation: 'compact', maximumFractionDigits: 2 }).format(value)} ${unit}/s`;
}

export function formatBytes(value: number): string {
  if (!Number.isFinite(value)) return '—';
  if (value >= 1e9) return `${(value / 1e9).toFixed(2)} GB`;
  if (value >= 1e6) return `${(value / 1e6).toFixed(2)} MB`;
  if (value >= 1e3) return `${(value / 1e3).toFixed(2)} KB`;
  return `${value} B`;
}

export function measurementLabel(measurement: Measurement, mixedFileCounts: boolean): string {
  const compiler = COMPILER_NAMES[measurement.compiler.name] ?? measurement.compiler.name;
  const rawConfiguration = measurement.configuration_display ?? measurement.configuration ?? measurement.target;
  const configuration = CONFIGURATION_NAMES[rawConfiguration] ?? rawConfiguration;
  const files = mixedFileCounts ? ` · ${measurement.source.files.toLocaleString()} files` : '';
  return `${compiler} · ${configuration}${files}`;
}

export function measurementColor(measurement: Measurement): string {
  const compiler = measurement.compiler.name.toLowerCase();
  if (compiler === 'lanius') {
    if (measurement.configuration === 'process_cold') return 'var(--blue)';
    if (measurement.configuration === 'daemon_cold_workspace') return 'var(--violet)';
    if (measurement.configuration === 'daemon_warm_workspace') return 'var(--green)';
    return 'var(--cyan)';
  }
  return ({
    c: 'var(--orange)',
    cpp: 'var(--green)',
    pareas: 'var(--violet)',
    rust: 'var(--red)',
    tcc: 'var(--yellow)',
    zig: 'var(--blue)',
  } as Record<string, string>)[compiler] ?? 'var(--muted)';
}

export function resultLabel(run: PerformanceRun): string {
  const source = run.measurements[0]?.source;
  const kind = run.workload.kind === 'single_file' ? 'Single file' : 'Typical project';
  if (!source) return kind;
  const files = source.files === 1 ? '1 file' : `${source.files.toLocaleString()} files`;
  return `${kind} · ${files} · ${formatBytes(source.bytes)} · ${source.sloc.toLocaleString()} SLOC`;
}

export function formatRecordedAt(value: string): string {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return value;
  return new Intl.DateTimeFormat('en', {
    year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  }).format(date);
}

export function hasPhaseData(measurement: Measurement | undefined): boolean {
  return Boolean(measurement?.samples.some((sample) =>
    Object.values(sample.request_phases_ms ?? {}).some((value) => typeof value === 'number' && Number.isFinite(value))));
}

export function hasMemoryData(measurement: Measurement | undefined): boolean {
  return Boolean(measurement?.samples.some((sample) => Number.isFinite(Number(sample.gpu_memory?.peak_bytes))));
}

export function analysisCapabilities(measurement: Measurement | undefined): string[] {
  if (!measurement) return [];
  return [
    hasPhaseData(measurement) ? 'phases' : null,
    hasMemoryData(measurement) ? 'memory' : null,
    measurement.profile ? 'profile' : null,
  ].filter((value): value is string => value !== null);
}

export function median(values: number[]): number {
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

export function commandLines(commands: Record<string, unknown>): string {
  return Object.entries(commands).map(([name, command]) => {
    const value = command && typeof command === 'object' && 'display' in command
      ? String((command as { display: unknown }).display)
      : JSON.stringify(command);
    return `${name}: ${value}`;
  }).join('\n');
}
