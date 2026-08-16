<script lang="ts">
  import { onMount } from 'svelte';
  import { select, zoom, zoomIdentity } from 'd3';
  import type { D3ZoomEvent, ZoomBehavior, ZoomTransform } from 'd3';
  import { SERIES } from '../lib/format';
  import type { GraphEdge, GraphNode, Profile } from '../lib/types';

  interface LayoutNode extends GraphNode { x: number; y: number; rank: number }
  interface LayoutLink extends GraphEdge { sourceNode: LayoutNode; targetNode: LayoutNode }

  const viewportHeight = 580;
  const nodeWidth = 260;
  const nodeHeight = 44;
  const horizontalStep = 300;
  const verticalStep = 58;
  let { profile }: { profile?: Profile } = $props();
  let containerWidth = $state(1100);
  let selectedNodeId = $state('');
  let svgElement = $state<SVGSVGElement>();
  let zoomBehavior: ZoomBehavior<SVGSVGElement, unknown> | undefined;
  let zoomTransform = $state<ZoomTransform>(zoomIdentity);

  const layout = $derived.by(() => dependencyLayout(
    profile?.execution_graph.nodes ?? [],
    profile?.execution_graph.edges ?? [],
    containerWidth,
  ));
  const selectedNode = $derived(layout.nodeMap.get(selectedNodeId) ?? layout.nodes[0]);
  const selectedLinks = $derived(layout.links.filter((edge) =>
    edge.source === selectedNode?.id || edge.target === selectedNode?.id
  ));

  onMount(() => {
    if (!svgElement) return;
    zoomBehavior = zoom<SVGSVGElement, unknown>()
      .scaleExtent([0.01, 4])
      .on('zoom', (event: D3ZoomEvent<SVGSVGElement, unknown>) => {
        zoomTransform = event.transform;
      });
    const selection = select(svgElement);
    selection.call(zoomBehavior).on('dblclick.zoom', null);
    resetView();
    return () => { selection.on('.zoom', null); };
  });

  function dependencyLayout(nodes: GraphNode[], edges: GraphEdge[], availableWidth: number) {
    const ordered = topologicalOrder(nodes, edges);
    const outgoing = new Map(nodes.map((node) => [node.id, [] as string[]]));
    for (const edge of edges) outgoing.get(edge.source)?.push(edge.target);

    const rank = new Map(nodes.map((node) => [node.id, 0]));
    for (const node of ordered) {
      for (const target of outgoing.get(node.id) ?? []) {
        rank.set(target, Math.max(rank.get(target) ?? 0, (rank.get(node.id) ?? 0) + 1));
      }
    }
    const layers = new Map<number, GraphNode[]>();
    for (const node of nodes) {
      const nodeRank = rank.get(node.id) ?? 0;
      const layer = layers.get(nodeRank) ?? [];
      layer.push(node);
      layers.set(nodeRank, layer);
    }
    for (const layer of layers.values()) {
      layer.sort((left, right) =>
        left.graph.localeCompare(right.graph)
        || left.phase.localeCompare(right.phase)
        || left.declaration_index - right.declaration_index
      );
    }

    const maxRank = Math.max(0, ...layers.keys());
    const tallestLayer = Math.max(1, ...[...layers.values()].map((layer) => layer.length));
    const width = Math.max(960, availableWidth || 960, 300 + maxRank * horizontalStep);
    const height = Math.max(520, 110 + tallestLayer * verticalStep);
    const positioned: LayoutNode[] = [];
    for (const [nodeRank, layer] of [...layers.entries()].sort(([left], [right]) => left - right)) {
      layer.forEach((node, index) => positioned.push({
        ...node,
        rank: nodeRank,
        x: 145 + nodeRank * horizontalStep,
        y: 65 + index * verticalStep,
      }));
    }
    const nodeMap = new Map(positioned.map((node) => [node.id, node]));
    const links: LayoutLink[] = edges.flatMap((edge) => {
      const sourceNode = nodeMap.get(edge.source);
      const targetNode = nodeMap.get(edge.target);
      return sourceNode && targetNode ? [{ ...edge, sourceNode, targetNode }] : [];
    });
    const phases = [...new Set(
      positioned.filter((node) => node.kind === 'declared_operation').map((node) => node.phase),
    )];
    const phaseIndex = new Map(phases.map((phase, index) => [phase, index]));
    const ranked = positioned
      .filter((node) => node.kind === 'declared_operation')
      .sort((left, right) => right.execution_count - left.execution_count)
      .slice(0, 8);
    return { nodes: positioned, links, nodeMap, phases, phaseIndex, ranked, width, height, maxRank };
  }

  function topologicalOrder(nodes: GraphNode[], edges: GraphEdge[]): GraphNode[] {
    const byId = new Map(nodes.map((node) => [node.id, node]));
    const outgoing = new Map(nodes.map((node) => [node.id, [] as string[]]));
    const indegree = new Map(nodes.map((node) => [node.id, 0]));
    for (const edge of edges) {
      if (!byId.has(edge.source) || !byId.has(edge.target)) {
        throw new Error('compiler dependency edge references a missing node');
      }
      outgoing.get(edge.source)?.push(edge.target);
      indegree.set(edge.target, (indegree.get(edge.target) ?? 0) + 1);
    }
    const ready = nodes.filter((node) => indegree.get(node.id) === 0);
    const ordered: GraphNode[] = [];
    while (ready.length) {
      ready.sort((left, right) =>
        right.graph.localeCompare(left.graph)
        || right.declaration_index - left.declaration_index
      );
      const node = ready.pop();
      if (!node) break;
      ordered.push(node);
      for (const target of outgoing.get(node.id) ?? []) {
        const remaining = (indegree.get(target) ?? 0) - 1;
        indegree.set(target, remaining);
        if (remaining === 0) ready.push(byId.get(target)!);
      }
    }
    if (ordered.length !== nodes.length) throw new Error('compiler dependency graph must be acyclic');
    return ordered;
  }

  function phaseColor(phase: string): string {
    return SERIES[(layout.phaseIndex.get(phase) ?? 0) % SERIES.length];
  }

  function nodeHalfWidth(node: GraphNode): number {
    return node.kind === 'stage_boundary' ? 9 : nodeWidth / 2;
  }

  function edgePath(edge: LayoutLink): string {
    if (edge.source === edge.target) {
      const x = edge.sourceNode.x + nodeWidth / 2;
      const y = edge.sourceNode.y;
      return `M ${x} ${y - 6} C ${x + 78} ${y - 58}, ${x + 78} ${y + 58}, ${x} ${y + 6}`;
    }
    if (edge.kind !== 'resource_dependency' && edge.targetNode.x <= edge.sourceNode.x) {
      const startY = edge.sourceNode.y - nodeHeight / 2;
      const endY = edge.targetNode.y - nodeHeight / 2;
      const controlY = Math.min(startY, endY) - 58;
      return `M ${edge.sourceNode.x} ${startY} C ${edge.sourceNode.x} ${controlY}, ${edge.targetNode.x} ${controlY}, ${edge.targetNode.x} ${endY}`;
    }
    const startX = edge.sourceNode.x + nodeHalfWidth(edge.sourceNode);
    const endX = edge.targetNode.x - nodeHalfWidth(edge.targetNode);
    const control = Math.max(24, (endX - startX) * .48);
    return `M ${startX} ${edge.sourceNode.y} C ${startX + control} ${edge.sourceNode.y}, ${endX - control} ${edge.targetNode.y}, ${endX} ${edge.targetNode.y}`;
  }

  function edgeLabel(edge: GraphEdge): string {
    if (edge.kind === 'submit_order') {
      return (edge.submission_boundaries ?? [])
        .map((boundary) => `submit ${boundary.from_index}: ${boundary.from_label} → submit ${boundary.to_index}: ${boundary.to_label}`)
        .join(', ');
    }
    if (edge.kind === 'stage_order') return `compiler stage boundary · submit ${edge.submission_index}`;
    if (edge.kind === 'submit_span') return `submission completion · submit ${edge.submission_index}`;
    return edge.dependencies
      .map((dependency) => `${dependency.resource} (${dependency.hazard.replaceAll('_', ' ')})`)
      .join(', ');
  }

  function nodeLabelLines(name: string): string[] {
    const lines: string[] = [];
    let remaining = name;
    while (remaining.length > 34) {
      let split = 34;
      for (let index = 34; index >= 18; index -= 1) {
        if (remaining[index] === '.' || remaining[index] === '_') {
          split = index + 1;
          break;
        }
      }
      lines.push(remaining.slice(0, split));
      remaining = remaining.slice(split);
    }
    lines.push(remaining);
    return lines;
  }

  function zoomBy(factor: number): void {
    if (svgElement && zoomBehavior) select(svgElement).call(zoomBehavior.scaleBy, factor);
  }

  function resetView(): void {
    if (!svgElement || !zoomBehavior) return;
    select(svgElement).call(zoomBehavior.transform, zoomIdentity.translate(20, 20).scale(.8));
  }

  function fitGraph(): void {
    if (!svgElement || !zoomBehavior) return;
    const viewportWidth = Math.max(320, containerWidth);
    const scale = Math.max(.01, Math.min(
      (viewportWidth - 48) / layout.width,
      (viewportHeight - 48) / layout.height,
      1,
    ));
    const x = (viewportWidth - layout.width * scale) / 2;
    const y = (viewportHeight - layout.height * scale) / 2;
    select(svgElement).call(zoomBehavior.transform, zoomIdentity.translate(x, y).scale(scale));
  }
</script>

{#if layout.nodes.length}
  <div class="graph-legends">
    <div class="lane-legend">
      {#each layout.phases as phase}<span><i style={`--lane:${phaseColor(phase)}`}></i>{phase.replaceAll('_', ' ')}</span>{/each}
    </div>
    <div class="edge-legend"><span><i></i>resource dependency</span><span><i class="boundary"></i>stage boundary</span><span><i class="submit"></i>execution order</span></div>
  </div>
  <div class="graph-toolbar" aria-label="Graph zoom controls">
    <button type="button" aria-label="Zoom out" title="Zoom out" onclick={() => zoomBy(1 / 1.35)}>
      <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8h10" /></svg>
    </button>
    <span>{Math.round(zoomTransform.k * 100)}%</span>
    <button type="button" aria-label="Zoom in" title="Zoom in" onclick={() => zoomBy(1.35)}>
      <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8h10M8 3v10" /></svg>
    </button>
    <button type="button" onclick={resetView}>Reset</button>
    <button type="button" onclick={fitGraph}>Fit all</button>
    <small>{profile?.execution_graph.submissions.length.toLocaleString()} submits captured</small>
  </div>
  <div class="graph-wrap" bind:clientWidth={containerWidth}>
    <svg
      bind:this={svgElement}
      class="graph-canvas"
      viewBox={`0 0 ${Math.max(320, containerWidth)} ${viewportHeight}`}
      role="img"
      aria-label="Zoomable compiler resource dependency graph arranged by topological depth"
    >
      <defs>
        <marker id="dependency-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill="var(--line-strong)" />
        </marker>
        <marker id="submit-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill="var(--cyan)" />
        </marker>
      </defs>
      <g transform={zoomTransform.toString()}>
        {#each Array(layout.maxRank + 1) as _, rank}
          {@const x = 145 + rank * horizontalStep}
          <line class="depth-line" x1={x} y1="24" x2={x} y2={layout.height - 20} vector-effect="non-scaling-stroke" />
          <text class="depth-label" x={x} y="17">depth {rank}</text>
        {/each}
        {#each layout.links.filter((edge) => edge.kind === 'resource_dependency') as edge}
          <path class="graph-edge" d={edgePath(edge)} marker-end="url(#dependency-arrow)" vector-effect="non-scaling-stroke">
            <title>{edgeLabel(edge)}</title>
          </path>
        {/each}
        {#each layout.links.filter((edge) => edge.kind !== 'resource_dependency') as edge}
          <path class="graph-edge execution-order" d={edgePath(edge)} marker-end="url(#submit-arrow)" vector-effect="non-scaling-stroke">
            <title>{edgeLabel(edge)}</title>
          </path>
        {/each}
        {#each layout.nodes as node}
          {@const active = node.id === selectedNode?.id}
          {@const labelLines = nodeLabelLines(node.name)}
          <g
            class="graph-operation"
            class:active
            class:scheduling={node.kind === 'recorded_pass_endpoint' || node.kind === 'empty_submission'}
            class:boundary={node.kind === 'stage_boundary'}
            role="button" tabindex="0"
            aria-label={node.kind === 'stage_boundary'
              ? `Stage boundary from ${node.from_graph} to ${node.to_graph}`
              : `${node.name}, ${node.phase}, ran ${node.execution_count} times`}
            onclick={() => selectedNodeId = node.id}
            onkeydown={(keyboardEvent) => {
              if (keyboardEvent.key === 'Enter' || keyboardEvent.key === ' ') {
                keyboardEvent.preventDefault();
                selectedNodeId = node.id;
              }
            }}
          >
            {#if node.kind === 'stage_boundary'}
              <rect x={node.x - 7} y={node.y - 7} width="14" height="14" rx="2" transform={`rotate(45 ${node.x} ${node.y})`} />
              <title>{node.from_graph} → {node.to_graph} · structural stage boundary · submit {node.submissions[0]}</title>
            {:else}
              <rect x={node.x - nodeWidth / 2} y={node.y - nodeHeight / 2} width={nodeWidth} height={nodeHeight} rx="6" fill={phaseColor(node.phase)} />
              <text x={node.x - nodeWidth / 2 + 9} y={node.y - (labelLines.length - 1) * 6 + 4}>
                {#each labelLines as line, lineIndex}<tspan x={node.x - nodeWidth / 2 + 9} dy={lineIndex === 0 ? 0 : 12}>{line}</tspan>{/each}
              </text>
              <title>{node.name} · {node.kind.replaceAll('_', ' ')} · {node.execution_count.toLocaleString()} executions · submits {node.submissions.join(', ') || 'not captured'}</title>
            {/if}
          </g>
        {/each}
      </g>
    </svg>
  </div>
  <div class="graph-details">
    <div class="event-inspector">
      <span class="detail-label">Selected operation</span>
      <strong>{selectedNode.name}</strong>
      <dl>
        <div><dt>{selectedNode.kind === 'stage_boundary' ? 'Boundary' : 'Graph'}</dt><dd>{selectedNode.kind === 'stage_boundary' ? `${selectedNode.from_graph} → ${selectedNode.to_graph}` : selectedNode.graph}</dd></div>
        <div><dt>Node type</dt><dd>{selectedNode.kind.replaceAll('_', ' ')}</dd></div>
        <div><dt>Phase</dt><dd>{selectedNode.phase.replaceAll('_', ' ')}</dd></div>
        <div><dt>Domain</dt><dd>{selectedNode.dispatch_domain.replaceAll('_', ' ')}</dd></div>
        <div><dt>Dependency depth</dt><dd>{selectedNode.rank}</dd></div>
        <div><dt>Executions</dt><dd>{selectedNode.kind === 'stage_boundary' ? '—' : selectedNode.execution_count.toLocaleString()}</dd></div>
        <div><dt>Submits</dt><dd>{selectedNode.submissions.join(', ') || 'not captured'}</dd></div>
        <div><dt>Direct relations</dt><dd>{selectedLinks.length.toLocaleString()}</dd></div>
      </dl>
      {#if selectedLinks.length}
        <div class="dependency-list">
          {#each selectedLinks.slice(0, 6) as edge}
            <span class:submit={edge.kind === 'submit_order'}>{edge.target === selectedNode.id ? 'from' : 'to'} <strong>{edge.target === selectedNode.id ? edge.sourceNode.name : edge.targetNode.name}</strong><small>{edgeLabel(edge)}</small></span>
          {/each}
        </div>
      {/if}
    </div>
    <div class="longest-events">
      <span class="detail-label">Most frequently executed</span>
      {#each layout.ranked as node, rank}
        <button class:active={node.id === selectedNode.id} onclick={() => selectedNodeId = node.id}>
          <span>{rank + 1}. {node.name}<small>{node.phase.replaceAll('_', ' ')} · depth {node.rank}</small></span><strong>{node.execution_count.toLocaleString()}×</strong>
        </button>
      {/each}
    </div>
  </div>
{:else}
  <div class="empty">This profile does not contain an executed declarative compiler graph.</div>
{/if}
