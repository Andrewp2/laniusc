export interface Distribution {
  samples: number;
  median: number;
  mean: number;
  mad: number;
  minimum: number;
  maximum: number;
  p95: number;
  histogram: { unit: string; edges: number[]; counts: number[] };
}

export interface SourceFacts {
  files: number;
  bytes: number;
  kilobytes: number;
  megabytes: number;
  physical_lines: number;
  sloc: number;
  sloc_policy: string;
  largest_file_bytes: number;
}

export interface TimingSample {
  index: number;
  wall_ms: number;
  compiler_ms?: number | null;
  request_phases_ms?: { load?: number | null; compile?: number | null; write?: number | null } | null;
  gpu_memory?: { peak_bytes?: number; peak_allocations?: number; phase_snapshots?: MemorySnapshot[] } | null;
}

export interface MemorySnapshot {
  phase: string;
  bytes: number;
  allocations: number;
}

export interface TimelineEvent {
  name: string;
  category: string;
  lane: string;
  start_ms: number;
  duration_ms: number;
}

export interface GraphNode {
  id: string;
  lane: string;
  name: string;
  invocations: number;
  total_duration_ms: number;
}

export interface GraphEdge {
  source: string;
  target: string;
  transitions: number;
}

export interface Profile {
  excluded_from_timing_statistics: boolean;
  reason: string;
  wall_ms: number;
  timeline: TimelineEvent[];
  execution_graph: { nodes: GraphNode[]; edges: GraphEdge[]; semantics: string };
}

export interface Measurement {
  id: string;
  compiler: { name: string; version: string };
  target: string;
  configuration: string;
  configuration_display?: string;
  source: SourceFacts;
  commands: Record<string, unknown>;
  samples: TimingSample[];
  summary: {
    wall_ms: Distribution;
    compiler_ms: Distribution | null;
    median_bytes_per_second: number;
    median_sloc_per_second: number;
  };
  profile?: Profile;
}

export interface PerformanceRun {
  schema: 'lanius.performance-run.v1';
  run: { id: string; recorded_at: string; git_commit: string; git_dirty: boolean };
  machine: { platform: string; cpu?: string; logical_cpus?: number; gpu?: string | null };
  workload: {
    id: string;
    kind: 'single_file' | 'typical_project';
    classification: string;
    generator: string;
  };
  measurements: Measurement[];
}

export interface CatalogEntry { path: string; document: PerformanceRun }
export interface PerformanceCatalog {
  schema: 'lanius.performance-catalog.v1';
  generated_at_unix_seconds: number;
  results: CatalogEntry[];
  invalid_results: Array<{ path: string; error: string }>;
}

declare global {
  interface Window { LANIUS_PERFORMANCE_CATALOG?: PerformanceCatalog }
}
