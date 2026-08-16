<script lang="ts">
  import BarChart from './components/BarChart.svelte';
  import BenchmarkSummary from './components/BenchmarkSummary.svelte';
  import ExecutionGraph from './components/ExecutionGraph.svelte';
  import Facts from './components/Facts.svelte';
  import Histogram from './components/Histogram.svelte';
  import MeasurementTable from './components/MeasurementTable.svelte';
  import MemoryChart from './components/MemoryChart.svelte';
  import PhaseChart from './components/PhaseChart.svelte';
  import Timeline from './components/Timeline.svelte';
  import { loadCatalog } from './lib/catalog';
  import {
    analysisCapabilities, formatMs, formatRecordedAt, hasMemoryData, hasPhaseData,
    measurementColor, measurementLabel, resultLabel,
  } from './lib/format';
  import type { PerformanceRun } from './lib/types';

  type WorkloadFilter = 'all' | PerformanceRun['workload']['kind'];
  const catalog = loadCatalog();
  let workloadFilter = $state<WorkloadFilter>('all');
  let selectedPath = $state(catalog.results[0]?.path ?? '');
  let selectedIndex = $state(0);
  let analysisSelectedIndex = $state(firstAnalysisIndex(catalog.results[0]?.document));
  let logarithmic = $state(true);
  let graphOpen = $state(false);
  const filteredEntries = $derived(catalog.results.filter((candidate) =>
    workloadFilter === 'all' || candidate.document.workload.kind === workloadFilter));
  const entry = $derived(catalog.results.find((candidate) => candidate.path === selectedPath) ?? filteredEntries[0]);
  const document = $derived(entry?.document);
  const measurements = $derived(document?.measurements ?? []);
  const selected = $derived(measurements[Math.min(selectedIndex, Math.max(0, measurements.length - 1))]);
  const analysisSelected = $derived(measurements[Math.max(0, analysisSelectedIndex)] ?? selected);
  const mixedFileCounts = $derived(measurements.some((measurement) => measurement.source.files !== measurements[0]?.source.files));
  const latencyValues = $derived(measurements.map((measurement) => ({
    name: measurementLabel(measurement, mixedFileCounts),
    value: measurement.summary.wall_ms.median,
    color: measurementColor(measurement),
  })));
  const phaseAvailable = $derived(measurements.some(hasPhaseData));
  const memoryAvailable = $derived(measurements.some(hasMemoryData));
  const profileAvailable = $derived(measurements.some((measurement) => Boolean(measurement.profile)));
  const analysisAvailable = $derived(phaseAvailable || memoryAvailable || profileAvailable);
  const runCapabilities = $derived([...new Set(measurements.flatMap(analysisCapabilities))]);
  const machineLabel = $derived((document?.machine.gpu || document?.machine.platform || 'Unknown machine').split(',')[0]);

  function selectRun(path: string): void {
    selectedPath = path;
    selectedIndex = 0;
    analysisSelectedIndex = firstAnalysisIndex(catalog.results.find((candidate) => candidate.path === path)?.document);
  }

  function setWorkloadFilter(filter: WorkloadFilter): void {
    workloadFilter = filter;
    const candidates = catalog.results.filter((candidate) => filter === 'all' || candidate.document.workload.kind === filter);
    if (!candidates.some((candidate) => candidate.path === selectedPath)) selectRun(candidates[0]?.path ?? '');
  }

  function selectMeasurement(index: number): void {
    selectedIndex = index;
    if (analysisCapabilities(measurements[index]).length) analysisSelectedIndex = index;
  }

  function firstAnalysisIndex(run: PerformanceRun | undefined): number {
    let bestIndex = 0;
    let bestCount = 0;
    run?.measurements.forEach((measurement, index) => {
      const count = analysisCapabilities(measurement).length;
      if (count > bestCount) {
        bestIndex = index;
        bestCount = count;
      }
    });
    return bestIndex;
  }
</script>

<svelte:head><title>Lanius Performance Explorer</title></svelte:head>

<main>
  {#if document && measurements.length}
    <header class="hero">
      <div>
        <h1>Lanius Performance Explorer</h1>
        <p>Reproducible latency, throughput, memory, and GPU execution data.</p>
      </div>
    </header>

    <section class="toolbar" aria-label="Benchmark controls">
      <div class="toolbar-group">
        <span class="control-label">Workload</span>
        <div class="segmented">
          <button class:active={workloadFilter === 'all'} aria-pressed={workloadFilter === 'all'} onclick={() => setWorkloadFilter('all')}>All</button>
          <button class:active={workloadFilter === 'single_file'} aria-pressed={workloadFilter === 'single_file'} onclick={() => setWorkloadFilter('single_file')}>Single file</button>
          <button class:active={workloadFilter === 'typical_project'} aria-pressed={workloadFilter === 'typical_project'} onclick={() => setWorkloadFilter('typical_project')}>Typical project</button>
        </div>
      </div>
      <div class="control result-control">
        <label for="run-select">Benchmark result</label>
        <select id="run-select" value={entry.path} onchange={(event) => selectRun(event.currentTarget.value)}>
          {#each filteredEntries as result}
            <option value={result.path}>{resultLabel(result.document)}</option>
          {/each}
        </select>
      </div>
      <div class="toolbar-group scale-control">
        <span class="control-label">Latency scale</span>
        <div class="segmented">
          <button class:active={logarithmic} aria-pressed={logarithmic} onclick={() => logarithmic = true}>Log</button>
          <button class:active={!logarithmic} aria-pressed={!logarithmic} onclick={() => logarithmic = false}>Linear</button>
        </div>
      </div>
    </section>

    <section class="result-intro panel">
      <div class="result-title"><h2>{resultLabel(document)}</h2><p>{document.workload.classification}</p></div>
      <div class="result-meta" aria-label="Selected result metadata">
        <div><span>Recorded</span><strong>{formatRecordedAt(document.run.recorded_at)}</strong></div>
        <div><span>Machine</span><strong title={document.machine.gpu || document.machine.platform}>{machineLabel}</strong></div>
        <div><span>Target</span><strong>{measurements[0].target}</strong></div>
        <div><span>Git revision</span><strong>{document.run.git_commit.slice(0, 8)}{document.run.git_dirty ? ' · dirty' : ''}</strong></div>
        <div class="result-capabilities"><span>Analysis data</span><strong>
          {#if runCapabilities.length}
            {#each runCapabilities as capability}<span class="capability-tag available">{capability}</span>{/each}
          {:else}<span class="capability-none">timings only</span>{/if}
        </strong></div>
      </div>
    </section>

    <Facts source={measurements[0].source} />
    <BenchmarkSummary {measurements} {selectedIndex} {mixedFileCounts} />

    <div class="grid overview-grid">
      <section class="panel span-12">
        <div class="section-heading">
          <div><h2>Compile latency</h2><p>Median wall time across every recorded compiler configuration.</p></div>
          <span class="section-count">{measurements.length} configurations</span>
        </div>
        <BarChart values={latencyValues} unit="ms" {logarithmic} valueFormatter={formatMs} accessibleName="Compile latency comparison" />
      </section>
      <section class="panel span-12">
        <div class="section-heading table-heading">
          <div><h2>Compiler results</h2></div>
          <p>Select a row to update the distribution; available analysis data is shown at right.</p>
        </div>
        <MeasurementTable {measurements} {selectedIndex} {mixedFileCounts} onselect={selectMeasurement} />
      </section>
      <section class="panel span-12 distribution-panel">
        <div class="section-heading">
          <div><h2>Latency distribution</h2><p>{measurementLabel(selected, mixedFileCounts)}</p></div>
          <span class="section-count">{selected.summary.wall_ms.samples} samples</span>
        </div>
        <Histogram measurement={selected} />
      </section>

      {#if analysisAvailable}
        <div class="section-break span-12">
          <div><h2>Compiler analysis</h2><p>Request phases, GPU residency, and the captured execution trace.</p></div>
          <div class="control analysis-control">
            <label for="analysis-select">Analysis measurement</label>
            <select id="analysis-select" value={analysisSelectedIndex} onchange={(event) => analysisSelectedIndex = Number(event.currentTarget.value)}>
              {#each measurements as measurement, index}
                {#if analysisCapabilities(measurement).length}
                  <option value={index}>{measurementLabel(measurement, mixedFileCounts)} · {analysisCapabilities(measurement).join(', ')}</option>
                {/if}
              {/each}
            </select>
          </div>
        </div>
        {#if phaseAvailable}
          <section class="panel" class:span-6={memoryAvailable} class:span-12={!memoryAvailable}>
            <div class="section-heading"><div><h2>Time breakdown</h2></div></div>
            <PhaseChart measurement={analysisSelected} />
          </section>
        {/if}
        {#if memoryAvailable}
          <section class="panel" class:span-6={phaseAvailable} class:span-12={!phaseAvailable}>
            <div class="section-heading"><div><h2>Tracked GPU memory</h2></div></div>
            <MemoryChart {measurements} {mixedFileCounts} />
          </section>
        {/if}
        {#if profileAvailable}
          <section class="panel span-12">
            <div class="section-heading">
              <div><h2>Execution timeline</h2><p>Select a bar or ranked event to inspect the captured work.</p></div>
              <span class="section-count">excluded from latency statistics</span>
            </div>
            <Timeline profile={analysisSelected.profile} />
          </section>
          <details class="panel span-12 analysis-detail" bind:open={graphOpen}>
            <summary>
              <strong>Executed compiler graph</strong>
              <small>{analysisSelected.profile?.execution_graph.nodes.length ?? 0} operations · {graphOpen ? 'collapse' : 'expand'} to inspect</small>
            </summary>
            <p class="profile-note">Consecutive traced operations are connected within each execution lane; repeated operations are collapsed.</p>
            <ExecutionGraph profile={analysisSelected.profile} />
          </details>
        {/if}
      {/if}
    </div>
  {:else}
    <div class="empty page-empty">
      No canonical results yet.<br />Run <code>python3 tools/lanius_perf.py run-lanius …</code>.
      {#if catalog.invalid_results.length}<small>{catalog.invalid_results.length} result file(s) could not be loaded.</small>{/if}
    </div>
  {/if}
</main>
