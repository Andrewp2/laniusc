<script lang="ts">
  import { formatMs, SERIES } from '../lib/format';
  import type { Profile } from '../lib/types';

  let { profile }: { profile?: Profile } = $props();
  let containerWidth = $state(1100);
  let selectedEventIndex = $state(0);
  const layout = $derived.by(() => {
    const events = profile?.timeline ?? [];
    const lanes = [...new Set(events.map((event) => event.lane))];
    const width = Math.max(1100, containerWidth || 1100);
    const left = 190, right = 20, rowHeight = 36;
    const end = Math.max(...events.map((event) => event.start_ms + event.duration_ms), 0.001);
    return {
      events, lanes, width, left, right, rowHeight, end,
      height: 40 + lanes.length * rowHeight,
      laneIndex: new Map(lanes.map((lane, index) => [lane, index])),
      ticks: [0, .25, .5, .75, 1].map((fraction) => ({ fraction, value: end * fraction })),
      longest: events.map((event, index) => ({ event, index }))
        .sort((a, b) => b.event.duration_ms - a.event.duration_ms).slice(0, 6),
    };
  });
  const selectedEvent = $derived(layout.events[Math.min(selectedEventIndex, Math.max(0, layout.events.length - 1))]);
</script>

{#if layout.events.length}
  <div class="timeline-guide">
    <p>Each row is an execution lane. Horizontal position is time from job start; bar width is event duration. Select a bar or a longest-event entry to inspect it.</p>
    <div class="lane-legend">
      {#each layout.lanes as lane, index}<span><i style={`--lane:${SERIES[index % SERIES.length]}`}></i>{lane}</span>{/each}
    </div>
  </div>
  <div class="timeline" bind:clientWidth={containerWidth}>
    <svg viewBox={`0 0 ${layout.width} ${layout.height}`} style="min-width:1000px" role="img" aria-label="Compiler profile timeline">
      {#each layout.ticks as tick}
        {@const x = layout.left + tick.fraction * (layout.width - layout.left - layout.right)}
        <line class="grid-line" x1={x} y1="6" x2={x} y2={layout.height - 28} />
        <text class="tick" text-anchor={tick.fraction === 0 ? 'start' : tick.fraction === 1 ? 'end' : 'middle'} x={x} y={layout.height - 8}>{formatMs(tick.value)}</text>
      {/each}
      {#each layout.lanes as lane, index}
        <text class="lane-label" text-anchor="end" x={layout.left - 10} y={25 + index * layout.rowHeight}>{lane}</text>
      {/each}
      {#each layout.events as event, index}
        {@const x = layout.left + event.start_ms / layout.end * (layout.width - layout.left - layout.right)}
        {@const width = Math.max(1, event.duration_ms / layout.end * (layout.width - layout.left - layout.right))}
        {@const lane = layout.laneIndex.get(event.lane) ?? 0}
        {@const y = 8 + lane * layout.rowHeight}
        <rect
          class:selected-event={index === selectedEventIndex}
          {x} {y} {width} height="24" rx="2"
          fill={SERIES[lane % SERIES.length]}
          opacity={index === selectedEventIndex ? 1 : .72}
          role="button"
          tabindex="0"
          aria-label={`${event.name}, ${event.lane}, ${formatMs(event.duration_ms)}`}
          onclick={() => selectedEventIndex = index}
          onkeydown={(keyboardEvent) => {
            if (keyboardEvent.key === 'Enter' || keyboardEvent.key === ' ') {
              keyboardEvent.preventDefault();
              selectedEventIndex = index;
            }
          }}
        ><title>{event.lane} · {event.name} · {formatMs(event.duration_ms)}</title></rect>
      {/each}
    </svg>
  </div>
  <div class="timeline-details">
    <div class="event-inspector">
      <span class="detail-label">Selected event</span>
      <strong>{selectedEvent.name}</strong>
      <dl>
        <div><dt>Lane</dt><dd>{selectedEvent.lane}</dd></div>
        <div><dt>Category</dt><dd>{selectedEvent.category}</dd></div>
        <div><dt>Start</dt><dd>{formatMs(selectedEvent.start_ms)}</dd></div>
        <div><dt>Duration</dt><dd>{formatMs(selectedEvent.duration_ms)}</dd></div>
        <div><dt>Profile share</dt><dd>{(selectedEvent.duration_ms / Math.max(profile?.wall_ms ?? layout.end, .001) * 100).toFixed(1)}%</dd></div>
      </dl>
    </div>
    <div class="longest-events">
      <span class="detail-label">Longest events</span>
      {#each layout.longest as item, rank}
        <button class:active={item.index === selectedEventIndex} onclick={() => selectedEventIndex = item.index}>
          <span>{rank + 1}. {item.event.name}</span><strong>{formatMs(item.event.duration_ms)}</strong>
        </button>
      {/each}
    </div>
  </div>
{:else}
  <div class="empty">This analysis measurement does not include a captured profile.</div>
{/if}
