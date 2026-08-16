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

export interface NsightMetrics {
  sm_throughput_pct?: number | null;
  alu_throughput_pct?: number | null;
  fma_throughput_pct?: number | null;
  dram_throughput_pct?: number | null;
  dram_read_throughput_pct?: number | null;
  dram_write_throughput_pct?: number | null;
  l1_hit_rate_pct?: number | null;
  l2_hit_rate_pct?: number | null;
  compute_warps_active_pct?: number | null;
  average_compute_warp_latency?: number | null;
  long_scoreboard_l1tex_stall_pct?: number | null;
  wait_stall_pct?: number | null;
  barrier_stall_pct?: number | null;
  lg_throttle_stall_pct?: number | null;
  not_selected_stall_pct?: number | null;
  math_pipe_throttle_stall_pct?: number | null;
  register_allocation_stall_pct?: number | null;
  instructions_executed?: number | null;
  compute_warps_launched?: number | null;
}

export interface NsightEvent {
  event_index: number;
  pass_name: string;
  occurrence: number;
  time_ms: number;
  gpu_start_ms: number;
  phase: string;
  stage: string;
}

export interface NsightPass extends NsightMetrics {
  pass_name: string;
  count: number;
  total_time_ms: number;
  phase: string;
  stage: string;
}

export interface NsightSummaryRow {
  phase?: string;
  stage?: string;
  event_count: number;
  total_time_ms: number;
  percent_of_labeled_time: number;
  first_event_index: number;
  last_event_index: number;
}

export interface NsightProfile {
  schema: 'lanius.nsight-gpu-profile.v1';
  tool: string;
  capture: Record<string, string>;
  event_count: number;
  unique_pass_count: number;
  labeled_gpu_time_ms: number;
  time_axis: 'cumulative_labeled_gpu_time';
  timeline_semantics: string;
  frame_metrics: NsightMetrics;
  events: NsightEvent[];
  passes: NsightPass[];
  phases: NsightSummaryRow[];
  stages: NsightSummaryRow[];
}

export interface GraphNode {
  id: string;
  kind: 'declared_operation' | 'recorded_pass_endpoint' | 'empty_submission' | 'stage_boundary';
  graph: string;
  name: string;
  phase: string;
  dispatch_domain: string;
  declaration_index: number;
  execution_count: number;
  submissions: number[];
  submission_label?: string;
  from_graph?: string;
  to_graph?: string;
}

export interface GraphEdge {
  source: string;
  target: string;
  kind: 'resource_dependency' | 'stage_order' | 'submit_span' | 'submit_order';
  dependencies: Array<{ resource: string; hazard: string }>;
  submission_index?: number;
  submission_boundaries?: Array<{
    from_index: number;
    from_label: string;
    to_index: number;
    to_label: string;
  }>;
}

export interface ComputeSubmission {
  index: number;
  label: string;
  recorded_passes: number;
  matched_passes: number;
  first_node: string | null;
  last_node: string | null;
}

export interface ExecutionGraph {
  nodes: GraphNode[];
  edges: GraphEdge[];
  submissions: ComputeSubmission[];
  coverage: {
    declared_operations: number;
    executed_labels: number;
    matched_labels: number;
    unregistered_executed_labels: number;
    recorded_passes: number;
    matched_recorded_passes: number;
  };
  semantics: string;
}

export interface Profile {
  excluded_from_timing_statistics: boolean;
  reason: string;
  wall_ms: number;
  timeline: TimelineEvent[];
  execution_graph: ExecutionGraph;
  nsight?: NsightProfile;
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
  comparison_origin?: {
    kind: 'frozen_baseline';
    result_path: string;
    run_id: string;
    recorded_at: string;
    machine: PerformanceRun['machine'];
  };
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
    comparison_group?: string;
    baseline_only?: boolean;
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
