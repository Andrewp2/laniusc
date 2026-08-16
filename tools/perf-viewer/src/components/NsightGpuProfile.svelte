<script lang="ts">
  import { formatMs, SERIES } from '../lib/format';
  import type { NsightEvent, NsightMetrics, NsightProfile } from '../lib/types';

  let { profile }: { profile: NsightProfile } = $props();
  let containerWidth = $state(1100);
  let selectedEventIndex = $state(0);

  const layout = $derived.by(() => {
    const events = profile.events ?? [];
    const phases = [...new Set(events.map((event) => event.phase))];
    const width = Math.max(1100, containerWidth || 1100);
    const left = 190, right = 20, rowHeight = 34;
    const end = Math.max(profile.labeled_gpu_time_ms, .001);
    return {
      events, phases, width, left, right, rowHeight, end,
      height: 40 + phases.length * rowHeight,
      phaseIndex: new Map(phases.map((phase, index) => [phase, index])),
      ticks: [0, .25, .5, .75, 1].map((fraction) => ({ fraction, value: end * fraction })),
      longest: (profile.passes ?? []).slice(0, 8),
    };
  });
  const selectedEvent = $derived(layout.events[Math.min(selectedEventIndex, Math.max(0, layout.events.length - 1))]);
  const selectedPass = $derived(profile.passes.find((pass) => pass.pass_name === selectedEvent?.pass_name));

  const headlineMetrics: Array<{ key: keyof NsightMetrics; label: string }> = [
    { key: 'sm_throughput_pct', label: 'SM throughput' },
    { key: 'dram_throughput_pct', label: 'DRAM throughput' },
    { key: 'compute_warps_active_pct', label: 'Compute warps active' },
  ];
  const eventMetrics: Array<{ key: keyof NsightMetrics; label: string; kind?: 'count' | 'latency' }> = [
    { key: 'sm_throughput_pct', label: 'SM throughput' },
    { key: 'alu_throughput_pct', label: 'ALU throughput' },
    { key: 'fma_throughput_pct', label: 'FMA throughput' },
    { key: 'dram_throughput_pct', label: 'DRAM throughput' },
    { key: 'dram_read_throughput_pct', label: 'DRAM read' },
    { key: 'dram_write_throughput_pct', label: 'DRAM write' },
    { key: 'l1_hit_rate_pct', label: 'L1 hit rate' },
    { key: 'l2_hit_rate_pct', label: 'L2 hit rate' },
    { key: 'compute_warps_active_pct', label: 'Compute warps active' },
    { key: 'long_scoreboard_l1tex_stall_pct', label: 'Long scoreboard stall' },
    { key: 'wait_stall_pct', label: 'Wait stall' },
    { key: 'barrier_stall_pct', label: 'Barrier stall' },
    { key: 'register_allocation_stall_pct', label: 'Register allocation stall' },
    { key: 'average_compute_warp_latency', label: 'Average warp latency', kind: 'latency' },
    { key: 'instructions_executed', label: 'Instructions executed', kind: 'count' },
    { key: 'compute_warps_launched', label: 'Compute warps launched', kind: 'count' },
  ];

  function formatMetric(value: number | null | undefined, kind?: 'count' | 'latency'): string {
    if (value === null || value === undefined || !Number.isFinite(value)) return '—';
    if (kind === 'count') return new Intl.NumberFormat('en', { notation: 'compact', maximumFractionDigits: 2 }).format(value);
    if (kind === 'latency') return value.toLocaleString(undefined, { maximumFractionDigits: 1 });
    return `${value.toFixed(1)}%`;
  }

  function selectPass(passName: string): void {
    const index = layout.events.findIndex((event) => event.pass_name === passName);
    if (index >= 0) selectedEventIndex = index;
  }
</script>

{#if selectedEvent}
  <div class="nsight-overview">
    <div><span>Labeled GPU time</span><strong>{formatMs(profile.labeled_gpu_time_ms)}</strong></div>
    <div><span>GPU actions</span><strong>{profile.event_count.toLocaleString()}</strong></div>
    <div><span>Unique pass labels</span><strong>{profile.unique_pass_count.toLocaleString()}</strong></div>
    {#each headlineMetrics as metric}
      <div><span>{metric.label}</span><strong>{formatMetric(profile.frame_metrics[metric.key])}</strong></div>
    {/each}
  </div>

  <div class="nsight-provenance">
    <p>{profile.timeline_semantics}.</p>
    <dl>
      <div><dt>GPU</dt><dd>{profile.capture.device_name ?? '—'}</dd></div>
      <div><dt>Driver</dt><dd>{profile.capture.driver_version ?? '—'}</dd></div>
      <div><dt>Nsight</dt><dd>{profile.capture.nsight_version ?? '—'}</dd></div>
      <div><dt>Capture</dt><dd>{profile.capture.limited_to ?? profile.capture.max_duration ?? '—'}</dd></div>
    </dl>
  </div>

  <div class="lane-legend nsight-legend">
    {#each layout.phases as phase, index}<span><i style={`--lane:${SERIES[index % SERIES.length]}`}></i>{phase}</span>{/each}
  </div>
  <div class="timeline nsight-timeline" bind:clientWidth={containerWidth}>
    <svg viewBox={`0 0 ${layout.width} ${layout.height}`} style="min-width:1000px" role="img" aria-label="Nsight GPU action timeline">
      {#each layout.ticks as tick}
        {@const x = layout.left + tick.fraction * (layout.width - layout.left - layout.right)}
        <line class="grid-line" x1={x} y1="6" x2={x} y2={layout.height - 28} />
        <text class="tick" text-anchor={tick.fraction === 0 ? 'start' : tick.fraction === 1 ? 'end' : 'middle'} x={x} y={layout.height - 8}>{formatMs(tick.value)}</text>
      {/each}
      {#each layout.phases as phase, index}
        <text class="lane-label" text-anchor="end" x={layout.left - 10} y={24 + index * layout.rowHeight}>{phase}</text>
      {/each}
      {#each layout.events as event, index}
        {@const x = layout.left + event.gpu_start_ms / layout.end * (layout.width - layout.left - layout.right)}
        {@const width = Math.max(1, event.time_ms / layout.end * (layout.width - layout.left - layout.right))}
        {@const phase = layout.phaseIndex.get(event.phase) ?? 0}
        {@const y = 7 + phase * layout.rowHeight}
        <rect
          class:selected-event={index === selectedEventIndex}
          {x} {y} {width} height="23" rx="1"
          fill={SERIES[phase % SERIES.length]}
          opacity={index === selectedEventIndex ? 1 : .75}
          role="button" tabindex="0"
          aria-label={`${event.pass_name}, ${event.phase}, ${formatMs(event.time_ms)}`}
          onclick={() => selectedEventIndex = index}
          onkeydown={(keyboardEvent) => {
            if (keyboardEvent.key === 'Enter' || keyboardEvent.key === ' ') {
              keyboardEvent.preventDefault();
              selectedEventIndex = index;
            }
          }}
        ><title>{event.pass_name} · {formatMs(event.time_ms)}</title></rect>
      {/each}
    </svg>
  </div>

  <div class="timeline-details nsight-details">
    <div class="event-inspector nsight-inspector">
      <span class="detail-label">Selected GPU action</span>
      <strong>{selectedEvent.pass_name}</strong>
      <dl class="event-identity">
        <div><dt>Phase</dt><dd>{selectedEvent.phase}</dd></div>
        <div><dt>Stage</dt><dd title={selectedEvent.stage}>{selectedEvent.stage}</dd></div>
        <div><dt>Duration</dt><dd>{formatMs(selectedEvent.time_ms)}</dd></div>
        <div><dt>GPU share</dt><dd>{(selectedEvent.time_ms / profile.labeled_gpu_time_ms * 100).toFixed(2)}%</dd></div>
      </dl>
      <p class="metric-semantics">Hardware counters are duration-weighted across all invocations carrying this pass label in the capture.</p>
      <div class="hardware-metrics">
        {#each eventMetrics as metric}
          <div><span>{metric.label}</span><strong>{formatMetric(selectedPass?.[metric.key], metric.kind)}</strong></div>
        {/each}
      </div>
    </div>
    <div class="longest-events">
      <span class="detail-label">Most GPU time by pass</span>
      {#each layout.longest as pass, rank}
        <button class:active={pass.pass_name === selectedEvent.pass_name} onclick={() => selectPass(pass.pass_name)}>
          <span>{rank + 1}. {pass.pass_name}<small>{pass.count.toLocaleString()} invocation{pass.count === 1 ? '' : 's'}</small></span>
          <strong>{formatMs(pass.total_time_ms)}</strong>
        </button>
      {/each}
    </div>
  </div>
{:else}
  <div class="empty">This Nsight capture contains no labeled GPU actions.</div>
{/if}
