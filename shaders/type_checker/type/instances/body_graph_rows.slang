// Shared seed graph rows of a body specialization packet. Requires
// body_specialization_inputs. Row 0 = (argument count, target, node count,
// edge count) of entry 0 and of the shared graph.
#ifndef LANIUS_BODY_GRAPH_ROWS
#define LANIUS_BODY_GRAPH_ROWS
#include "body_graph_layout.slang"

uint body_graph_node_count()
{
    return min(body_specialization_inputs[0u].z, BODY_GRAPH_NODES);
}

// Rows a packet spends on graph extension before its extra entries.
uint body_graph_extension_rows()
{
    uint4 header = body_specialization_inputs[0u];
    return header.z > BODY_GRAPH_V2_NODES || header.w > BODY_GRAPH_V2_EDGES ? BODY_GRAPH_EXT_ROWS : 0u;
}

// The (kind, a, b, width) row of node `ordinal`; the identity row follows it.
uint body_graph_node_row(uint ordinal)
{
    return ordinal < BODY_GRAPH_V2_NODES ? 65u + ordinal * 2u
        : BODY_GRAPH_EXT_START + (ordinal - BODY_GRAPH_V2_NODES) * 2u;
}

uint4 body_graph_node(uint ordinal)
{
    return body_specialization_inputs[body_graph_node_row(ordinal)];
}

uint4 body_graph_identity(uint ordinal)
{
    return body_specialization_inputs[body_graph_node_row(ordinal) + 1u];
}

// Edge word `edge` (a child ordinal of an application node).
uint body_graph_edge(uint edge)
{
    uint row = edge < BODY_GRAPH_V2_EDGES ? 193u + edge / 4u
        : BODY_GRAPH_EXT_EDGE_START + (edge - BODY_GRAPH_V2_EDGES) / 4u;
    return body_specialization_inputs[row][edge % 4u];
}

#endif
