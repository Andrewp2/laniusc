<script lang="ts">
  import { onMount } from 'svelte';
  import { select, zoom, zoomIdentity } from 'd3';
  import type { D3ZoomEvent, ZoomBehavior, ZoomTransform } from 'd3';
  import { formatBytes, formatMs } from '../lib/format';
  import type { GpuMemoryTimeline, Profile } from '../lib/types';

  let { memory, profile }: { memory?: GpuMemoryTimeline; profile?: Profile } = $props();
  let containerWidth = $state(1100);
  let svgElement = $state<SVGSVGElement>();
  let zoomBehavior: ZoomBehavior<SVGSVGElement, unknown> | undefined;
  let zoomTransform = $state<ZoomTransform>(zoomIdentity);

  const layout = $derived.by(() => {
    const points = [...(memory?.physical_residency.points ?? [])]
      .filter((point) => Number.isFinite(point.start_ms) && Number.isFinite(point.bytes))
      .sort((left, right) => left.start_ms - right.start_ms);
    const intervals = [...(memory?.graph_managed_working_set.intervals ?? [])]
      .filter((interval) => Number.isFinite(interval.start_ms) && Number.isFinite(interval.bytes))
      .sort((left, right) => left.start_ms - right.start_ms);
    const width = Math.max(1100, containerWidth || 1100);
    const left = 180, right = 24, top = 24, rowHeight = 90, plotHeight = 62;
    const timelineEnd = Math.max(
      ...(profile?.timeline ?? []).map((event) => event.start_ms + event.duration_ms),
      ...points.map((point) => point.start_ms),
      ...intervals.map((interval) => interval.start_ms + interval.duration_ms),
      0.001,
    );
    const maximumBytes = Math.max(
      ...points.map((point) => point.bytes),
      ...intervals.map((interval) => interval.bytes),
      1,
    );
    return {
      points, intervals, width, left, right, top, rowHeight, plotHeight,
      height: 2 * rowHeight + 48,
      timelineEnd,
      maximumBytes,
      rowPeaks: [
        Math.max(...points.map((point) => point.bytes), 0),
        Math.max(...intervals.map((interval) => interval.bytes), 0),
      ],
      ticks: [0, .25, .5, .75, 1].map((fraction) => ({ fraction, value: timelineEnd * fraction })),
    };
  });

  const viewportTicks = $derived(layout.ticks.map((tick) => {
    const x = layout.left + tick.fraction * plotWidth();
    const sourceX = zoomTransform.invertX(x);
    const fraction = Math.max(0, Math.min(1, (sourceX - layout.left) / plotWidth()));
    return { x, value: layout.timelineEnd * fraction };
  }));

  onMount(() => {
    if (!svgElement) return;
    zoomBehavior = zoom<SVGSVGElement, unknown>()
      .scaleExtent([1, 64])
      .constrain((transform) => constrainTransform(transform))
      .on('zoom', (event: D3ZoomEvent<SVGSVGElement, unknown>) => {
        zoomTransform = event.transform;
      });
    const selection = select(svgElement);
    selection.call(zoomBehavior).on('dblclick.zoom', null);
    return () => { selection.on('.zoom', null); };
  });

  function plotWidth(): number {
    return Math.max(1, layout.width - layout.left - layout.right);
  }

  function constrainTransform(transform: ZoomTransform): ZoomTransform {
    const right = layout.width - layout.right;
    return zoomIdentity
      .translate(
        Math.max(right * (1 - transform.k), Math.min(layout.left * (1 - transform.k), transform.x)),
        0,
      )
      .scale(transform.k);
  }

  function timeX(timeMs: number): number {
    return zoomTransform.applyX(layout.left + timeMs / layout.timelineEnd * plotWidth());
  }

  function valueY(bytes: number, row: number): number {
    const bottom = layout.top + row * layout.rowHeight + layout.plotHeight;
    return bottom - bytes / layout.maximumBytes * layout.plotHeight;
  }

  function physicalPath(): string {
    if (!layout.points.length) return '';
    const bottom = layout.top + layout.plotHeight;
    const first = layout.points[0];
    let path = `M ${timeX(0)} ${bottom} L ${timeX(first.start_ms)} ${bottom} L ${timeX(first.start_ms)} ${valueY(first.bytes, 0)}`;
    for (let index = 1; index < layout.points.length; index += 1) {
      const previous = layout.points[index - 1];
      const point = layout.points[index];
      path += ` L ${timeX(point.start_ms)} ${valueY(previous.bytes, 0)} L ${timeX(point.start_ms)} ${valueY(point.bytes, 0)}`;
    }
    const last = layout.points[layout.points.length - 1];
    return `${path} L ${timeX(layout.timelineEnd)} ${valueY(last.bytes, 0)}`;
  }

  function physicalAreaPath(): string {
    const line = physicalPath();
    if (!line) return '';
    const bottom = layout.top + layout.plotHeight;
    return `${line} L ${timeX(layout.timelineEnd)} ${bottom} L ${timeX(0)} ${bottom} Z`;
  }

  function zoomBy(factor: number): void {
    if (svgElement && zoomBehavior) select(svgElement).call(zoomBehavior.scaleBy, factor);
  }

  function resetView(): void {
    if (svgElement && zoomBehavior) select(svgElement).call(zoomBehavior.transform, zoomIdentity);
  }
</script>

{#if layout.points.length || layout.intervals.length}
  <div class="memory-guide">
    <p>Physical residency is allocated VRAM retained by Lanius. Graph working set is the deduplicated range needed by each recorded GPU submission.</p>
    <div class="memory-legend" aria-label="GPU memory series">
      <span><i class="resident"></i>Physical residency</span>
      <span><i class="working"></i>Graph working set</span>
    </div>
  </div>
  <div class="graph-toolbar" aria-label="GPU memory timeline zoom controls">
    <button type="button" aria-label="Zoom out" title="Zoom out" onclick={() => zoomBy(1 / 1.35)}>
      <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8h10" /></svg>
    </button>
    <span>{Math.round(zoomTransform.k * 100)}%</span>
    <button type="button" aria-label="Zoom in" title="Zoom in" onclick={() => zoomBy(1.35)}>
      <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8h10M8 3v10" /></svg>
    </button>
    <button type="button" onclick={resetView}>Reset</button>
    <small>Drag to pan · wheel or pinch to zoom</small>
  </div>
  <div class="memory-timeline" bind:clientWidth={containerWidth}>
    <svg bind:this={svgElement} viewBox={`0 0 ${layout.width} ${layout.height}`} role="img" aria-label="GPU memory over the compiler job clock">
      <defs>
        <clipPath id="gpu-memory-plot-clip">
          <rect x={layout.left} y="0" width={plotWidth()} height={layout.height - 30} />
        </clipPath>
      </defs>
      {#each viewportTicks as tick}
        <line class="grid" x1={tick.x} y1={layout.top - 8} x2={tick.x} y2={layout.height - 32} />
        <text class="tick" x={tick.x} y={layout.height - 9} text-anchor={tick.x === layout.left ? 'start' : tick.x === layout.width - layout.right ? 'end' : 'middle'}>{formatMs(tick.value)}</text>
      {/each}
      {#each ['Physical residency', 'Graph working set'] as label, row}
        {@const bottom = layout.top + row * layout.rowHeight + layout.plotHeight}
        <line class="baseline" x1={layout.left} y1={bottom} x2={layout.width - layout.right} y2={bottom} />
        <text class="row-label" x={layout.left - 14} y={layout.top + row * layout.rowHeight + 27} text-anchor="end">{label}</text>
        <text class="row-maximum" x={layout.left - 14} y={layout.top + row * layout.rowHeight + 45} text-anchor="end">peak {formatBytes(layout.rowPeaks[row])}</text>
      {/each}
      <g clip-path="url(#gpu-memory-plot-clip)">
        {#if layout.points.length}
          <path class="resident-area" d={physicalAreaPath()} />
          <path class="resident-line" d={physicalPath()} />
          {#each layout.points as point}
            <circle class="resident-point" cx={timeX(point.start_ms)} cy={valueY(point.bytes, 0)} r="2.5">
              <title>{formatMs(point.start_ms)} · {formatBytes(point.bytes)} · {point.allocations} allocations{point.label ? ` · ${point.event} ${point.label}` : ''}</title>
            </circle>
          {/each}
        {/if}
        {#each layout.intervals as interval}
          {@const x = timeX(interval.start_ms)}
          {@const width = Math.max(1, timeX(interval.start_ms + interval.duration_ms) - x)}
          {@const y = valueY(interval.bytes, 1)}
          {@const bottom = layout.top + layout.rowHeight + layout.plotHeight}
          <rect class="working-set" {x} {y} {width} height={Math.max(1, bottom - y)} rx="1">
            <title>{interval.label} · {formatBytes(interval.bytes)} · {formatMs(interval.duration_ms)} · {interval.operation_count} operations</title>
          </rect>
        {/each}
      </g>
    </svg>
  </div>
  {#if layout.points.length === 1}
    <p class="memory-note">Physical residency is flat because this capture reused a preallocated workspace. The lower row still shows which graph-managed ranges were active.</p>
  {/if}
{:else}
  <div class="empty">This profile predates GPU memory timeline capture.</div>
{/if}

<style>
  .memory-guide { display: flex; justify-content: space-between; align-items: start; gap: 24px; margin-bottom: 13px; }
  .memory-guide p { max-width: 720px; margin: 0; }
  .memory-legend { display: flex; flex-wrap: wrap; justify-content: end; gap: 14px; color: var(--muted); font-size: 11px; }
  .memory-legend span { display: inline-flex; align-items: center; gap: 7px; white-space: nowrap; }
  .memory-legend i { width: 9px; height: 9px; border-radius: 2px; }
  .memory-legend .resident { background: var(--cyan); }
  .memory-legend .working { background: var(--orange); }
  .memory-timeline { overflow: hidden; border: 1px solid var(--line); border-radius: 9px; background: #090d13; }
  .memory-timeline svg { display: block; cursor: grab; touch-action: none; user-select: none; }
  .memory-timeline svg:active { cursor: grabbing; }
  .grid { stroke: var(--line); stroke-dasharray: 2 4; }
  .baseline { stroke: var(--line); }
  .tick, .row-label, .row-maximum { fill: var(--muted); font-size: 10px; }
  .row-label { fill: var(--text); font-size: 11px; }
  .row-maximum { font-size: 9px; }
  .resident-area { fill: color-mix(in srgb, var(--cyan) 18%, transparent); }
  .resident-line { fill: none; stroke: var(--cyan); stroke-width: 1.5; }
  .resident-point { fill: var(--cyan); stroke: #090d13; stroke-width: 1; }
  .working-set { fill: var(--orange); opacity: .72; }
  .working-set:hover { opacity: 1; }
  .memory-note { margin: 10px 0 0; color: var(--muted); font-size: 11px; }
  @media (max-width: 760px) {
    .memory-guide { flex-direction: column; }
    .memory-legend { justify-content: start; }
  }
</style>
