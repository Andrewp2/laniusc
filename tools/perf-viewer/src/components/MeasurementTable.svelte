<script lang="ts">
  import {
    analysisCapabilities, commandLines, formatMs, formatRate, formatRecordedAt,
    measurementColor, measurementLabel,
  } from '../lib/format';
  import type { Measurement } from '../lib/types';

  type SortKey = 'compiler' | 'samples' | 'median' | 'mean' | 'mad' | 'sloc' | 'bytes';
  type SortDirection = 'ascending' | 'descending';
  interface Props {
    measurements: Measurement[];
    selectedIndex: number;
    mixedFileCounts: boolean;
    onselect: (index: number) => void;
  }
  let { measurements, selectedIndex, mixedFileCounts, onselect }: Props = $props();
  let sortKey = $state<SortKey>('compiler');
  let sortDirection = $state<SortDirection>('ascending');
  const rows = $derived.by(() => measurements
    .map((measurement, index) => ({ measurement, index }))
    .sort((left, right) => {
      const a = sortValue(left.measurement, sortKey);
      const b = sortValue(right.measurement, sortKey);
      const order = typeof a === 'string' && typeof b === 'string' ? a.localeCompare(b) : Number(a) - Number(b);
      return sortDirection === 'ascending' ? order : -order;
    }));

  function sortValue(measurement: Measurement, key: SortKey): string | number {
    const summary = measurement.summary;
    return ({
      compiler: measurementLabel(measurement, mixedFileCounts),
      samples: summary.wall_ms.samples,
      median: summary.wall_ms.median,
      mean: summary.wall_ms.mean,
      mad: summary.wall_ms.mad,
      sloc: summary.median_sloc_per_second,
      bytes: summary.median_bytes_per_second,
    } as Record<SortKey, string | number>)[key];
  }

  function sortBy(key: SortKey): void {
    if (sortKey === key) sortDirection = sortDirection === 'ascending' ? 'descending' : 'ascending';
    else {
      sortKey = key;
      sortDirection = key === 'sloc' || key === 'bytes' ? 'descending' : 'ascending';
    }
  }

  function sortState(key: SortKey): SortDirection | undefined {
    return sortKey === key ? sortDirection : undefined;
  }
</script>

<div class="table-scroll">
  <table>
    <thead><tr>
      <th aria-sort={sortState('compiler')}><button class="sort-button" data-sort={sortState('compiler')} onclick={() => sortBy('compiler')}>Compiler / configuration <span class="sort-indicator" aria-hidden="true"></span></button></th>
      <th aria-sort={sortState('samples')}><button class="sort-button" data-sort={sortState('samples')} onclick={() => sortBy('samples')}>Samples <span class="sort-indicator" aria-hidden="true"></span></button></th>
      <th aria-sort={sortState('median')}><button class="sort-button" data-sort={sortState('median')} onclick={() => sortBy('median')}>Median <span class="sort-indicator" aria-hidden="true"></span></button></th>
      <th aria-sort={sortState('mean')}><button class="sort-button" data-sort={sortState('mean')} onclick={() => sortBy('mean')}>Mean <span class="sort-indicator" aria-hidden="true"></span></button></th>
      <th aria-sort={sortState('mad')}><button class="sort-button" data-sort={sortState('mad')} onclick={() => sortBy('mad')}>MAD <span class="sort-indicator" aria-hidden="true"></span></button></th>
      <th aria-sort={sortState('sloc')}><button class="sort-button" data-sort={sortState('sloc')} onclick={() => sortBy('sloc')}>Median SLOC/s <span class="sort-indicator" aria-hidden="true"></span></button></th>
      <th aria-sort={sortState('bytes')}><button class="sort-button" data-sort={sortState('bytes')} onclick={() => sortBy('bytes')}>Median byte/s <span class="sort-indicator" aria-hidden="true"></span></button></th>
      <th>Analysis</th>
    </tr></thead>
    <tbody>
      {#each rows as row}
        {@const measurement = row.measurement}
        {@const capabilities = analysisCapabilities(measurement)}
        <tr
          class:selected={row.index === selectedIndex}
          onclick={() => onselect(row.index)}
          onkeydown={(event) => {
            if (event.key === 'Enter' || event.key === ' ') {
              event.preventDefault();
              onselect(row.index);
            }
          }}
          tabindex="0"
          aria-current={row.index === selectedIndex ? 'true' : undefined}
          style={`--series:${measurementColor(measurement)}`}
        >
          <td>
            <span class="measurement-name">
              <span class="language"><span class="swatch"></span>{measurementLabel(measurement, mixedFileCounts)}</span>
              {#if measurement.comparison_origin}
                <small title={`${measurement.comparison_origin.result_path} · ${measurement.comparison_origin.machine.gpu || measurement.comparison_origin.machine.platform}`}>Frozen · {formatRecordedAt(measurement.comparison_origin.recorded_at)}</small>
              {/if}
            </span>
          </td>
          <td>{measurement.summary.wall_ms.samples}</td>
          <td>{formatMs(measurement.summary.wall_ms.median)}</td>
          <td>{formatMs(measurement.summary.wall_ms.mean)}</td>
          <td>{formatMs(measurement.summary.wall_ms.mad)}</td>
          <td>{formatRate(measurement.summary.median_sloc_per_second, 'LOC')}</td>
          <td>{formatRate(measurement.summary.median_bytes_per_second, 'B')}</td>
          <td class="capability-cell">
            {#if capabilities.length}
              {#each capabilities as capability}<span class="capability-tag">{capability}</span>{/each}
            {:else}<span class="capability-none">—</span>{/if}
          </td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>
<details class="command-details">
  <summary>Reproduction commands <span>{measurementLabel(measurements[selectedIndex], mixedFileCounts)}</span></summary>
  <pre class="command">{commandLines(measurements[selectedIndex].commands)}</pre>
</details>
