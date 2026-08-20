<script lang="ts">
  import { analysisHighlights } from '../lib/analysis';
  import { formatBytes, formatMs } from '../lib/format';
  import type { Measurement } from '../lib/types';

  let { measurement }: { measurement?: Measurement } = $props();
  const highlights = $derived(analysisHighlights(measurement));
</script>

<section class="analysis-summary span-12" aria-label="Compiler analysis highlights">
  <div>
    <span>Most GPU time</span>
    <strong>{highlights.busiestGpuPhase?.name ?? '—'}</strong>
    <small>{highlights.busiestGpuPhase ? formatMs(highlights.busiestGpuPhase.durationMs) : 'Not captured'}</small>
  </div>
  <div>
    <span>Peak tracked VRAM</span>
    <strong>{highlights.peakTrackedBytes === null ? '—' : formatBytes(highlights.peakTrackedBytes)}</strong>
    <small>Physical residency</small>
  </div>
  <div>
    <span>Graph working set</span>
    <strong>{highlights.peakGraphBytes === null ? '—' : formatBytes(highlights.peakGraphBytes)}</strong>
    <small>Largest submission</small>
  </div>
  <div>
    <span>Tracked allocations</span>
    <strong>{highlights.peakAllocations?.toLocaleString() ?? '—'}</strong>
    <small>Peak live count</small>
  </div>
</section>
