<script lang="ts">
  import { formatMs, measurementColor } from '../lib/format';
  import type { Measurement } from '../lib/types';

  let { measurement }: { measurement: Measurement } = $props();
  let containerWidth = $state(320);
  const layout = $derived.by(() => {
    const width = Math.max(320, containerWidth || 320);
    const { counts, edges } = measurement.summary.wall_ms.histogram;
    const left = 0, right = 12, top = 10, bottom = 36, height = 205;
    return {
      width, height, left, right, top, bottom, counts, edges,
      maximum: Math.max(1, ...counts),
      barWidth: (width - left - right) / counts.length,
      medianX: left + (measurement.summary.wall_ms.median - edges[0]) /
        Math.max(0.001, (edges.at(-1) ?? edges[0]) - edges[0]) * (width - left - right),
    };
  });
  const distribution = $derived(measurement.summary.wall_ms);
</script>

<div class="histogram">
  <div class="histogram-plot" bind:clientWidth={containerWidth}>
    <svg viewBox={`0 0 ${layout.width} ${layout.height}`} role="img" aria-label="Latency histogram">
    {#each layout.counts as count, index}
      {@const height = count / layout.maximum * (layout.height - layout.top - layout.bottom)}
      <rect
        x={layout.left + index * layout.barWidth + 1}
        y={layout.height - layout.bottom - height}
        width={Math.max(1, layout.barWidth - 2)}
        {height}
        fill={measurementColor(measurement)}
        opacity=".75"
      >
        <title>{count} samples, {formatMs(layout.edges[index])}–{formatMs(layout.edges[index + 1])}</title>
      </rect>
    {/each}
    <line class="median-line" x1={layout.medianX} y1={layout.top} x2={layout.medianX} y2={layout.height - layout.bottom} />
    <text class="median-label" text-anchor="middle" x={layout.medianX} y={layout.top + 10}>median</text>
    <line class="axis" x1={layout.left} y1={layout.height - layout.bottom} x2={layout.width - layout.right} y2={layout.height - layout.bottom} />
    <text class="tick" x={layout.left} y={layout.height - 12}>{formatMs(layout.edges[0])}</text>
    <text class="tick" text-anchor="end" x={layout.width - layout.right} y={layout.height - 12}>{formatMs(layout.edges.at(-1) ?? 0)}</text>
    </svg>
  </div>
  <div class="distribution-stats">
    <div><span>Median</span><strong>{formatMs(distribution.median)}</strong></div>
    <div><span>Mean</span><strong>{formatMs(distribution.mean)}</strong></div>
    <div><span>MAD</span><strong>{formatMs(distribution.mad)}</strong></div>
    <div><span>P95</span><strong>{formatMs(distribution.p95)}</strong></div>
  </div>
</div>
