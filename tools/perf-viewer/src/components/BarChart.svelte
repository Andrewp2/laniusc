<script lang="ts">
  import { scaleLinear, scaleLog } from 'd3';

  export interface BarValue { name: string; value: number; color: string }
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
  let containerWidth = $state(500);
  const layout = $derived.by(() => {
    const width = Math.max(500, containerWidth || 500);
    const left = Math.min(280, Math.max(190, width * 0.3));
    const right = 90;
    const plotWidth = width - left - right;
    const numeric = values.map(({ value }) => Number(value)).filter(Number.isFinite);
    const maximum = Math.max(...numeric, 1);
    const minimum = Math.min(...numeric.filter((value) => value > 0), maximum);
    const domainMinimum = logarithmic ? Math.max(0.01, minimum / 2) : 0;
    const scale = logarithmic
      ? scaleLog().domain([domainMinimum, maximum]).range([0, plotWidth]).clamp(true)
      : scaleLinear().domain([0, maximum]).range([0, plotWidth]);
    let ticks = scale.ticks(6).filter((value) => value >= domainMinimum && value <= maximum);
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
    return { width, left, right, scale, ticks, height: 16 + values.length * 42 + 42 };
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
        {@const barWidth = Math.max(2, layout.scale(value.value))}
        {@const shortName = value.name.length > 36 ? `${value.name.slice(0, 35)}…` : value.name}
        <text class="bar-label" x="0" y={y + 22}><title>{value.name}</title>{shortName}</text>
        <rect x={layout.left} y={y + 6} width={barWidth} height="24" rx="3" fill={value.color} opacity=".82" />
        <text class="bar-label" x={Math.min(layout.width - layout.right + 8, layout.left + barWidth + 8)} y={y + 23}>
          {valueFormatter(value.value)}
        </text>
      {/each}
      <line class="axis" x1={layout.left} y1="8" x2={layout.left} y2={layout.height - 30} />
      <text class="axis-title" text-anchor="end" x={layout.width} y={layout.height - 8}>{logarithmic ? 'logarithmic' : 'linear'} · {unit}</text>
    </svg>
  {:else}
    <div class="empty">No data</div>
  {/if}
</div>
