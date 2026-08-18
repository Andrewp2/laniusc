<script lang="ts">
  import { formatSourceBytes } from '../lib/format';
  import type { SourceFacts } from '../lib/types';

  let { source }: { source: SourceFacts } = $props();
</script>

<section class="panel facts">
  <div class="fact"><span>Source files</span><strong>{source.files.toLocaleString()}</strong></div>
  <div class="fact"><span>Source data</span><strong>{formatSourceBytes(source.bytes)}</strong></div>
  <div class="fact"><span>SLOC</span><strong>{source.sloc.toLocaleString()}</strong></div>
  <div class="fact"><span>Largest file</span><strong>{formatSourceBytes(source.largest_file_bytes)}</strong></div>
</section>
