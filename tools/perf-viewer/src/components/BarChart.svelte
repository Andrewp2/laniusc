<script lang="ts">
  import { scaleLinear, scaleLog } from 'd3';

  export interface BarValue { name: string; value: number; color: string; contextOnly?: boolean }
  interface Props {
    values: BarValue[];
    unit: string;
    logarithmic?: boolean;
    valueFormatter: (value: number) => string;
    accessibleName?: string;
  }

  let {
    values,
    unit,
    logarithmic = false,
    valueFormatter,
    accessibleName = 'Bar chart',
  }: Props = $props();
  const BREAK_THRESHOLD = 10_000;
  const BREAK_ZONE = 56;
  let containerWidth = $state(500);
  const layout = $derived.by(() => {
    const width = Math.max(680, containerWidth || 680);
    const longestLabelWidth = Math.max(...values.map((value) => value.name.length * 6.2), 0);
    const left = Math.min(210, Math.max(140, longestLabelWidth + 18));
    const numeric = values.map(({ value }) => Number(value)).filter(Number.isFinite);
    const maximum = Math.max(...numeric, 1);
    // A broken bar's label also carries its multiple of the axis end.
    const right = !logarithmic && maximum > BREAK_THRESHOLD ? 170 : 90;
    const plotWidth = width - left - right;
    const minimum = Math.min(...numeric.filter((value) => value > 0), maximum);
    const domainMinimum = logarithmic ? Math.max(0.01, minimum / 2) : 0;
    // Linear mode: values past BREAK_THRESHOLD would flatten every other bar,
    // so the axis stops at the largest value below it and longer bars run
    // through a break into a zone past the axis end.
    const belowBreak = numeric.filter((value) => value <= BREAK_THRESHOLD);
    const broken = !logarithmic && maximum > BREAK_THRESHOLD && belowBreak.length > 0;
    const axisMaximum = broken ? Math.max(...belowBreak, 1) : maximum;
    const axisWidth = broken ? plotWidth - BREAK_ZONE : plotWidth;
    const scale = logarithmic
      ? scaleLog().domain([domainMinimum, maximum]).range([0, plotWidth]).clamp(true)
      : scaleLinear().domain([0, axisMaximum]).nice().range([0, axisWidth]);
    const axisEnd = scale.domain()[1];
    let ticks = scale.ticks(6).filter((value) => value >= domainMinimum && value <= axisEnd);
    if (logarithmic) {
      const useful = ticks.filter((value) => {
        const exponent = Math.floor(Math.log10(value));
        const mantissa = value / 10 ** exponent;
        return [1, 2, 5].some((candidate) => Math.abs(mantissa - candidate) < 0.001);
      });
      ticks = useful.length > 7
        ? useful.filter((value) => Math.abs(Math.log10(value) - Math.round(Math.log10(value))) < 0.001)
        : useful;
    }
    const barWidth = (value: number) => broken && value > axisEnd ? plotWidth : Math.max(2, scale(value));
    return { width, left, right, scale, ticks, broken, axisEnd, axisWidth, barWidth, height: 16 + values.length * 42 + 42 };
  });
</script>

<div class="chart" bind:clientWidth={containerWidth}>
  {#if values.length}
    <svg viewBox={`0 0 ${layout.width} ${layout.height}`} role="img" aria-label={accessibleName}>
      {#each layout.ticks as tick}
        {@const x = layout.left + layout.scale(tick)}
        <line class="grid-line" x1={x} y1="8" x2={x} y2={layout.height - 30} />
        <text class="tick" text-anchor="middle" x={x} y={layout.height - 8}>{valueFormatter(tick)}</text>
      {/each}
      {#each values as value, index}
        {@const y = 16 + index * 42}
        {@const barWidth = layout.barWidth(value.value)}
        {@const offScale = layout.broken && value.value > layout.axisEnd}
        <text class="bar-label" class:context-only={value.contextOnly} x="0" y={y + 22}>{value.name}</text>
        <rect x={layout.left} y={y + 6} width={barWidth} height="24" rx="3" fill={value.color} opacity=".9" class:off-scale={offScale}><title>{value.name}: {valueFormatter(value.value)}</title></rect>
        {#if offScale}
          {@const breakX = layout.left + layout.axisWidth + 14}
          <path class="bar-break" d={`M ${breakX} ${y + 2} l 8 32 M ${breakX + 9} ${y + 2} l 8 32`} />
        {/if}
        <text class="bar-label" class:off-scale-label={offScale} x={Math.min(layout.width - layout.right + 8, layout.left + barWidth + 8)} y={y + 23}>
          {valueFormatter(value.value)}{offScale ? ` · ${(value.value / layout.axisEnd).toFixed(1)}× axis` : ''}
        </text>
      {/each}
      <line class="axis" x1={layout.left} y1="8" x2={layout.left} y2={layout.height - 30} />
      {#if layout.broken}
        {@const breakX = layout.left + layout.axisWidth + 14}
        <path class="axis-break" d={`M ${breakX} ${layout.height - 34} l 6 10 M ${breakX + 9} ${layout.height - 34} l 6 10`} />
      {/if}
      <text class="axis-title" text-anchor="end" x={layout.width} y={layout.height - 8}>{logarithmic ? 'logarithmic' : 'linear'} · {unit}</text>
    </svg>
  {:else}
    <div class="empty">No data</div>
  {/if}
</div>
