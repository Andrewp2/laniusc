<script lang="ts">
  import { onMount } from 'svelte';
  import { select, zoom, zoomIdentity } from 'd3';
  import type { D3ZoomEvent, ZoomBehavior, ZoomTransform } from 'd3';
  import { COMPILER_PHASES, compilerPhaseName, formatMs } from '../lib/format';
  import type { Profile } from '../lib/types';

  let { profile, target }: { profile?: Profile; target?: string } = $props();
  let containerWidth = $state(1100);
  let selectedEventIndex = $state(0);
  let svgElement = $state<SVGSVGElement>();
  let zoomBehavior: ZoomBehavior<SVGSVGElement, unknown> | undefined;
  let zoomTransform = $state<ZoomTransform>(zoomIdentity);

  const DOMAINS = [
    ['host_orchestration', 'Host timing span', 'var(--cyan)'],
    ['queue_submission', 'Queue submission', 'var(--violet)'],
    ['gpu_execution', 'GPU execution', 'var(--red)'],
    ['submission_gap', 'Between GPU submissions', 'var(--muted)'],
    ['host_readback_wait', 'Host waiting for readback', 'var(--orange)'],
  ] as const;
  const phaseLabels = new Map<string, string>(COMPILER_PHASES);
  const domainLabels = new Map<string, string>(DOMAINS.map(([id, label]) => [id, label]));
  const domainColors = new Map<string, string>(DOMAINS.map(([id, , color]) => [id, color]));

  function displayPhase(event: Profile['timeline'][number]): string {
    if (event.phase === 'orchestration' && event.execution_domain === 'gpu_execution') {
      return 'unattributed_gpu';
    }
    return event.phase;
  }

  function eventPhaseLabel(event: Profile['timeline'][number]): string {
    const phase = displayPhase(event);
    return compilerPhaseName(phase);
  }

  function belongsToSelectedTarget(event: Profile['timeline'][number]): boolean {
    if (target === 'x86_64' && event.phase === 'wasm_emission') return false;
    if (target === 'wasm' && event.phase === 'x86_emission') return false;
    return true;
  }

  const layout = $derived.by(() => {
    const events = (profile?.timeline ?? []).filter(belongsToSelectedTarget);
    const presentPhases = new Set(events.map(displayPhase));
    const phases: Array<readonly [string, string]> = COMPILER_PHASES.filter(([id]) => presentPhases.has(id));
    phases.push(...[...presentPhases]
      .filter((phase) => !phaseLabels.has(phase))
      .sort()
      .map((phase) => [phase, phase] as const));
    const presentDomains = DOMAINS.filter(([id]) => events.some((event) => event.execution_domain === id));
    const width = Math.max(1100, containerWidth || 1100);
    const left = 160, right = 20, barHeight = 8, plotTop = 26;
    const rowHeight = Math.max(43, presentDomains.length * 9 + 7);
    const end = Math.max(...events.map((event) => event.start_ms + event.duration_ms), 0.001);
    const unitStarts = events.filter((event) => event.name === 'compile.source-pack.record_more');
    const unitFinishes = events.filter((event) => event.name === 'compile.source-pack.finish');
    const units = unitStarts.map((start, index) => {
      const nextStart = unitStarts[index + 1]?.start_ms ?? Number.POSITIVE_INFINITY;
      const finish = unitFinishes.find((candidate) =>
        candidate.start_ms >= start.start_ms && candidate.start_ms < nextStart
      );
      return {
        start: start.start_ms,
        end: finish ? finish.start_ms + finish.duration_ms : nextStart,
        index: index + 1,
      };
    }).filter((unit) => Number.isFinite(unit.end));
    return {
      events, phases, presentDomains, units, width, left, right, rowHeight, barHeight, plotTop, end,
      height: 58 + phases.length * rowHeight,
      phaseIndex: new Map(phases.map(([phase], index) => [phase, index])),
      domainIndex: new Map<string, number>(presentDomains.map(([domain], index) => [domain, index])),
      ticks: [0, .25, .5, .75, 1].map((fraction) => ({ fraction, value: end * fraction })),
      longest: events.map((event, index) => ({ event, index }))
        .filter(({ event }) => event.execution_domain === 'gpu_execution')
        .sort((a, b) => b.event.duration_ms - a.event.duration_ms).slice(0, 6),
    };
  });
  const viewportTicks = $derived(layout.ticks.map((tick) => {
    const x = layout.left + tick.fraction * plotWidth();
    const sourceX = zoomTransform.invertX(x);
    const fraction = Math.max(0, Math.min(1, (sourceX - layout.left) / plotWidth()));
    return { x, value: layout.end * fraction };
  }));
  const selectedEvent = $derived(layout.events[Math.min(selectedEventIndex, Math.max(0, layout.events.length - 1))]);

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
    const left = layout.left;
    const right = layout.width - layout.right;
    const minimumX = right * (1 - transform.k);
    const maximumX = left * (1 - transform.k);
    return zoomIdentity
      .translate(Math.max(minimumX, Math.min(maximumX, transform.x)), 0)
      .scale(transform.k);
  }

  function eventX(timeMs: number): number {
    return zoomTransform.applyX(layout.left + timeMs / layout.end * plotWidth());
  }

  function zoomBy(factor: number): void {
    if (svgElement && zoomBehavior) select(svgElement).call(zoomBehavior.scaleBy, factor);
  }

  function resetView(): void {
    if (svgElement && zoomBehavior) select(svgElement).call(zoomBehavior.transform, zoomIdentity);
  }
</script>

{#if layout.events.length}
  <div class="timeline-guide">
    <p>Rows are compiler phases. Filled bars are direct GPU or synchronization measurements; outlined host spans provide job-clock context.</p>
    <div class="lane-legend" aria-label="Execution domains">
      {#each layout.presentDomains as [, label, color]}<span><i style={`--lane:${color}`}></i>{label}</span>{/each}
    </div>
  </div>
  <div class="graph-toolbar" aria-label="Timeline zoom controls">
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
  <div class="timeline" bind:clientWidth={containerWidth}>
    <svg bind:this={svgElement} class="timeline-canvas" viewBox={`0 0 ${layout.width} ${layout.height}`} role="img" aria-label="Zoomable compiler profile timeline">
      <defs>
        <clipPath id="timeline-plot-clip">
          <rect x={layout.left} y="0" width={plotWidth()} height={layout.height - 26} />
        </clipPath>
      </defs>
      {#each viewportTicks as tick}
        {@const x = tick.x}
        <line class="grid-line" x1={x} y1={layout.plotTop - 4} x2={x} y2={layout.height - 28} />
        <text class="tick" text-anchor={x === layout.left ? 'start' : x === layout.width - layout.right ? 'end' : 'middle'} x={x} y={layout.height - 8}>{formatMs(tick.value)}</text>
      {/each}
      {#if layout.units.length > 1}
        <g clip-path="url(#timeline-plot-clip)">
          {#each layout.units as unit}
            {@const unitStart = eventX(unit.start)}
            {@const unitEnd = eventX(unit.end)}
            <line class="unit-boundary" x1={unitStart} y1={layout.plotTop - 4} x2={unitStart} y2={layout.height - 28} />
            <text class="unit-label" x={unitStart + 6} y={14}>Unit {unit.index}</text>
            <line class="unit-span" x1={unitStart + 5} y1={18} x2={Math.max(unitStart + 5, unitEnd - 5)} y2={18} />
          {/each}
        </g>
      {/if}
      {#each layout.phases as [, label], index}
        <line class="phase-line" x1={layout.left} y1={layout.plotTop + (index + 1) * layout.rowHeight - 4} x2={layout.width - layout.right} y2={layout.plotTop + (index + 1) * layout.rowHeight - 4} />
        <text class="lane-label" text-anchor="end" x={layout.left - 12} y={layout.plotTop + 21 + index * layout.rowHeight}>{label}</text>
      {/each}
      <g clip-path="url(#timeline-plot-clip)">
        {#each layout.events as event, index}
          {@const x = eventX(event.start_ms)}
          {@const width = Math.max(1, eventX(event.start_ms + event.duration_ms) - x)}
          {@const phase = layout.phaseIndex.get(displayPhase(event)) ?? 0}
          {@const domain = layout.domainIndex.get(event.execution_domain) ?? 0}
          {@const y = layout.plotTop + phase * layout.rowHeight + domain * 9}
          {@const visible = x + width >= layout.left && x <= layout.width - layout.right}
          {@const isHostSpan = event.execution_domain === 'host_orchestration'}
          <rect
            class="timeline-event"
            class:host-span={isHostSpan}
            class:selected-event={index === selectedEventIndex}
            {x} {y} {width} height={layout.barHeight} rx="1.5"
            fill={isHostSpan ? 'transparent' : domainColors.get(event.execution_domain) ?? 'var(--muted)'}
            stroke={isHostSpan ? domainColors.get(event.execution_domain) : undefined}
            opacity={index === selectedEventIndex ? 1 : isHostSpan ? .58 : .72}
            role="button"
            tabindex={visible ? 0 : -1}
            aria-label={`${event.name}, ${eventPhaseLabel(event)}, ${domainLabels.get(event.execution_domain) ?? event.execution_domain}, ${formatMs(event.duration_ms)}`}
            onclick={() => selectedEventIndex = index}
            onkeydown={(keyboardEvent) => {
              if (keyboardEvent.key === 'Enter' || keyboardEvent.key === ' ') {
                keyboardEvent.preventDefault();
                selectedEventIndex = index;
              }
            }}
          ><title>{eventPhaseLabel(event)} · {domainLabels.get(event.execution_domain) ?? event.execution_domain} · {event.name} · {formatMs(event.duration_ms)}</title></rect>
        {/each}
      </g>
    </svg>
  </div>
  <div class="timeline-details">
    <div class="event-inspector">
      <span class="detail-label">Selected event</span>
      <strong>{selectedEvent.name}</strong>
      <dl>
        <div><dt>Compiler phase</dt><dd>{eventPhaseLabel(selectedEvent)}</dd></div>
        <div><dt>Execution</dt><dd>{domainLabels.get(selectedEvent.execution_domain) ?? selectedEvent.execution_domain}</dd></div>
        <div><dt>Start</dt><dd>{formatMs(selectedEvent.start_ms)}</dd></div>
        <div><dt>Duration</dt><dd>{formatMs(selectedEvent.duration_ms)}</dd></div>
        <div><dt>Profile share</dt><dd>{(selectedEvent.duration_ms / Math.max(profile?.wall_ms ?? layout.end, .001) * 100).toFixed(1)}%</dd></div>
        <div><dt>Trace source</dt><dd title={selectedEvent.lane}>{selectedEvent.lane}</dd></div>
      </dl>
    </div>
    <div class="longest-events">
      <span class="detail-label">Longest GPU events</span>
      {#each layout.longest as item, rank}
        <button class:active={item.index === selectedEventIndex} onclick={() => selectedEventIndex = item.index}>
          <span>{rank + 1}. {item.event.name}<small>{eventPhaseLabel(item.event)} · {domainLabels.get(item.event.execution_domain) ?? item.event.execution_domain}</small></span><strong>{formatMs(item.event.duration_ms)}</strong>
        </button>
      {/each}
    </div>
  </div>
{:else}
  <div class="empty">This analysis measurement does not include a captured profile.</div>
{/if}
