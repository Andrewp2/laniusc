<script lang="ts">
  import BarChart, { type BarValue } from './BarChart.svelte';
  import { formatBytes, measurementColor, measurementLabel, median } from '../lib/format';
  import type { Measurement } from '../lib/types';

  interface Props { measurements: Measurement[]; mixedFileCounts: boolean }
  let { measurements, mixedFileCounts }: Props = $props();
  const values = $derived.by(() => measurements.flatMap((measurement): BarValue[] => {
    const peaks = measurement.samples.map((sample) => Number(sample.gpu_memory?.peak_bytes)).filter(Number.isFinite);
    return peaks.length ? [{
      name: measurementLabel(measurement, mixedFileCounts),
      value: median(peaks),
      color: measurementColor(measurement),
    }] : [];
  }));
</script>

{#if values.length}
  <BarChart {values} unit="bytes" valueFormatter={formatBytes} accessibleName="Tracked peak GPU memory" />
{:else}
  <div class="empty">Tracked GPU memory is unavailable for these measurements.</div>
{/if}
