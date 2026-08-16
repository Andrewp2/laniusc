<script lang="ts">
  import { formatMs, formatRate, measurementLabel } from '../lib/format';
  import type { Measurement } from '../lib/types';

  interface Props { measurements: Measurement[]; selectedIndex: number; mixedFileCounts: boolean }
  let { measurements, selectedIndex, mixedFileCounts }: Props = $props();
  const selected = $derived(measurements[selectedIndex]);
  const fastest = $derived([...measurements].sort((a, b) => a.summary.wall_ms.median - b.summary.wall_ms.median)[0]);
  const throughput = $derived([...measurements].sort((a, b) => b.summary.median_bytes_per_second - a.summary.median_bytes_per_second)[0]);
  const laniusBest = $derived([...measurements]
    .filter((measurement) => measurement.compiler.name.toLowerCase() === 'lanius')
    .sort((a, b) => a.summary.wall_ms.median - b.summary.wall_ms.median)[0]);
  const externalBest = $derived([...measurements]
    .filter((measurement) => measurement.compiler.name.toLowerCase() !== 'lanius')
    .sort((a, b) => a.summary.wall_ms.median - b.summary.wall_ms.median)[0]);
  const cold = $derived(measurements.find((measurement) => measurement.configuration === 'process_cold'));
  const warm = $derived(measurements.find((measurement) => measurement.configuration === 'daemon_warm_workspace'));
  const comparison = $derived.by(() => {
    if (laniusBest && externalBest) {
      const ratio = externalBest.summary.wall_ms.median / laniusBest.summary.wall_ms.median;
      return {
        value: ratio >= 1 ? `${ratio.toFixed(2)}× faster` : `${(1 / ratio).toFixed(2)}× slower`,
        caption: `Best Lanius vs ${measurementLabel(externalBest, false)}`,
      };
    }
    if (cold && warm) return {
      value: `${(cold.summary.wall_ms.median / warm.summary.wall_ms.median).toFixed(1)}× faster`,
      caption: 'Preallocated daemon vs pure cold',
    };
    return { value: '—', caption: 'No comparable Lanius lane' };
  });
  const variability = $derived(selected.summary.wall_ms.median > 0
    ? selected.summary.wall_ms.mad / selected.summary.wall_ms.median * 100
    : 0);
</script>

<section class="summary-grid" aria-label="Benchmark highlights">
  <div class="summary-card accent">
    <span>Fastest result</span>
    <strong>{formatMs(fastest.summary.wall_ms.median)}</strong>
    <small>{measurementLabel(fastest, mixedFileCounts)}</small>
  </div>
  <div class="summary-card">
    <span>Lanius comparison</span>
    <strong>{comparison.value}</strong>
    <small>{comparison.caption}</small>
  </div>
  <div class="summary-card">
    <span>Best throughput</span>
    <strong>{formatRate(throughput.summary.median_bytes_per_second, 'B')}</strong>
    <small>{measurementLabel(throughput, mixedFileCounts)}</small>
  </div>
  <div class="summary-card">
    <span>Selected row variability</span>
    <strong>{variability.toFixed(2)}%</strong>
    <small>{measurementLabel(selected, mixedFileCounts)} · MAD / median</small>
  </div>
</section>
