<script lang="ts">
  import {
    forceCollide, forceLink, forceManyBody, forceSimulation, forceX, forceY,
  } from 'd3';
  import type { SimulationLinkDatum, SimulationNodeDatum } from 'd3';
  import { formatMs, SERIES } from '../lib/format';
  import type { GraphNode, Profile } from '../lib/types';

  interface LayoutNode extends GraphNode, SimulationNodeDatum {}
  interface LayoutLink extends SimulationLinkDatum<LayoutNode> { transitions: number }

  let { profile }: { profile?: Profile } = $props();
  let containerWidth = $state(1100);
  let selectedNodeId = $state('');
  const layout = $derived.by(() => {
    const graph = profile?.execution_graph;
    const sourceNodes = graph?.nodes ?? [];
    const lanes = [...new Set(sourceNodes.map((node) => node.lane))];
    const laneIndex = new Map(lanes.map((lane, index) => [lane, index]));
    const width = Math.max(960, containerWidth || 960);
    const height = Math.max(580, 130 + lanes.length * 105);
    const nodes: LayoutNode[] = sourceNodes.map((node, index) => ({
      ...node,
      x: width * (.18 + .64 * ((index % 17) / 16)),
      y: 75 + (laneIndex.get(node.lane) ?? 0) * 105 + (index % 5) * 5,
    }));
    const links: LayoutLink[] = (graph?.edges ?? []).map((edge) => ({ ...edge }));
    const simulation = forceSimulation(nodes)
      .force('link', forceLink<LayoutNode, LayoutLink>(links).id((node) => node.id).distance(72).strength(.38))
      .force('charge', forceManyBody().strength(-105).distanceMax(260))
      .force('collide', forceCollide<LayoutNode>().radius((node) => nodeRadius(node) + 4).iterations(2))
      .force('x', forceX<LayoutNode>(width / 2).strength(.025))
      .force('y', forceY<LayoutNode>((node) => 75 + (laneIndex.get(node.lane) ?? 0) * 105).strength(.72))
      .stop();
    for (let iteration = 0; iteration < 240; iteration += 1) simulation.tick();
    const ranked = [...nodes].sort((a, b) => b.total_duration_ms - a.total_duration_ms);
    return {
      nodes, links, lanes, laneIndex, width, height,
      nodeMap: new Map(nodes.map((node) => [node.id, node])),
      labeled: new Set(ranked.slice(0, 12).map((node) => node.id)),
      ranked: ranked.slice(0, 8),
    };
  });
  const selectedNode = $derived(layout.nodeMap.get(selectedNodeId) ?? layout.nodes[0]);

  function nodeRadius(node: GraphNode): number {
    return Math.min(13, 5 + Math.log2(Math.max(1, node.total_duration_ms + 1)));
  }

  function endpointNode(endpoint: string | number | LayoutNode): LayoutNode | undefined {
    return typeof endpoint === 'object' ? endpoint : layout.nodeMap.get(String(endpoint));
  }
</script>

{#if layout.nodes.length}
  <div class="graph-guide">
    <p>This is the directed transition graph captured from the profiled compile. Arrows show observed operation-to-operation transitions; node size represents total recorded duration. Select a node to inspect it.</p>
    <div class="lane-legend">
      {#each layout.lanes as lane, index}<span><i style={`--lane:${SERIES[index % SERIES.length]}`}></i>{lane}</span>{/each}
    </div>
  </div>
  <div class="graph-wrap" bind:clientWidth={containerWidth}>
    <svg viewBox={`0 0 ${layout.width} ${layout.height}`} style="min-width:900px" role="img" aria-label="Directed compiler operation transition graph">
      <defs>
        <marker id="transition-arrow" viewBox="0 0 10 10" refX="15" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill="var(--line-strong)" />
        </marker>
      </defs>
      {#each layout.lanes as lane, index}
        {@const y = 75 + index * 105}
        <line class="lane-line" x1="10" y1={y} x2={layout.width - 10} y2={y} />
        <text class="lane-watermark" x="18" y={y - 36}>{lane}</text>
      {/each}
      {#each layout.links as edge}
        {@const source = endpointNode(edge.source)}
        {@const target = endpointNode(edge.target)}
        {#if source && target}
          <line
            class="graph-edge"
            x1={source.x ?? 0} y1={source.y ?? 0}
            x2={target.x ?? 0} y2={target.y ?? 0}
            stroke-width={Math.min(4, .7 + Math.log2(edge.transitions + 1))}
            marker-end="url(#transition-arrow)"
          ><title>{edge.transitions} transitions · {source.name} → {target.name}</title></line>
        {/if}
      {/each}
      {#each layout.nodes as node, index}
        {@const active = node.id === selectedNode?.id}
        <circle
          class="graph-node"
          class:active
          cx={node.x ?? 0} cy={node.y ?? 0} r={nodeRadius(node)}
          fill={SERIES[(layout.laneIndex.get(node.lane) ?? index) % SERIES.length]}
          role="button" tabindex="0"
          aria-label={`${node.name}, ${node.lane}, ${formatMs(node.total_duration_ms)}`}
          onclick={() => selectedNodeId = node.id}
          onkeydown={(keyboardEvent) => {
            if (keyboardEvent.key === 'Enter' || keyboardEvent.key === ' ') {
              keyboardEvent.preventDefault();
              selectedNodeId = node.id;
            }
          }}
        ><title>{node.name} · {node.invocations}× · {formatMs(node.total_duration_ms)}</title></circle>
        {#if active || layout.labeled.has(node.id)}
          <text class="graph-node-label" x={(node.x ?? 0) + nodeRadius(node) + 4} y={(node.y ?? 0) + 4}>
            {node.name.length > 32 ? `${node.name.slice(0, 31)}…` : node.name}
          </text>
        {/if}
      {/each}
    </svg>
  </div>
  <div class="graph-details">
    <div class="event-inspector">
      <span class="detail-label">Selected operation</span>
      <strong>{selectedNode.name}</strong>
      <dl>
        <div><dt>Lane</dt><dd>{selectedNode.lane}</dd></div>
        <div><dt>Invocations</dt><dd>{selectedNode.invocations.toLocaleString()}</dd></div>
        <div><dt>Total duration</dt><dd>{formatMs(selectedNode.total_duration_ms)}</dd></div>
      </dl>
    </div>
    <div class="longest-events">
      <span class="detail-label">Longest operations</span>
      {#each layout.ranked as node, rank}
        <button class:active={node.id === selectedNode.id} onclick={() => selectedNodeId = node.id}>
          <span>{rank + 1}. {node.name}</span><strong>{formatMs(node.total_duration_ms)}</strong>
        </button>
      {/each}
    </div>
  </div>
{:else}
  <div class="empty">This analysis measurement does not include an execution graph.</div>
{/if}
