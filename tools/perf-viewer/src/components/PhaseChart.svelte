<script lang="ts">
  import { formatMs, median, SERIES } from '../lib/format';
  import type { Measurement } from '../lib/types';

  let { measurement }: { measurement: Measurement } = $props();
  let containerWidth = $state(430);
  const phases = $derived.by(() => {
    const samples = measurement.samples.filter((sample) => sample.request_phases_ms);
    if (!samples.length) return [];
    return ['load', 'compile', 'write'].map((name) => ({
      name,
      value: median(samples.map((sample) => Number(sample.request_phases_ms?.[name as 'load' | 'compile' | 'write'] ?? 0))),
    }));
  });
  const total = $derived(phases.reduce((sum, phase) => sum + phase.value, 0) || 1);
  const chartWidth = $derived(Math.max(430, containerWidth || 430));
  const barWidth = $derived(chartWidth - 40);
</script>

<div class="chart" bind:clientWidth={containerWidth}>
  {#if phases.length}
    <div class="legend">
      {#each phases as phase, index}<span class="legend-item"><span class="swatch" style={`--series:${SERIES[index]}`}></span>{phase.name} {formatMs(phase.value)}</span>{/each}
    </div>
    <svg viewBox={`0 0 ${chartWidth} 180`}>
      {#each phases as phase, index}
        {@const offset = phases.slice(0, index).reduce((sum, current) => sum + current.value, 0) / total * barWidth}
        <rect x={20 + offset} y="58" width={phase.value / total * barWidth} height="42" fill={SERIES[index]}><title>{phase.name}: {formatMs(phase.value)}</title></rect>
      {/each}
      <text class="tick" x="20" y="124">Median structured daemon phases · total {formatMs(total)}</text>
    </svg>
  {:else}
    <div class="empty">Structured request phases are unavailable for this configuration.</div>
  {/if}
</div>
