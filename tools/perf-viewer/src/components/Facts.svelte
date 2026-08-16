<script lang="ts">
  import { formatBytes } from '../lib/format';
  import type { SourceFacts } from '../lib/types';

  let { source }: { source: SourceFacts } = $props();
</script>

<section class="panel facts">
  <div class="fact"><span>Source files</span><strong>{source.files.toLocaleString()}</strong></div>
  <div class="fact"><span>Source data</span><strong>{formatBytes(source.bytes)} <small>({source.bytes.toLocaleString()} B)</small></strong></div>
  <div class="fact"><span>SLOC</span><strong>{source.sloc.toLocaleString()}</strong></div>
  <div class="fact"><span>Largest file</span><strong>{formatBytes(source.largest_file_bytes)}</strong></div>
</section>
