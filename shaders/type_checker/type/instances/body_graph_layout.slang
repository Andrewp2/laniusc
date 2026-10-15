// Capacities of the body specialization packet's shared seed graph (packet
// v3, CheckedBodySpecializationBatch). The host mirrors every value here
// (generic_body.rs), and constant_atoms.slang mirrors BODY_ATOM_RESERVE_ROWS.
#ifndef LANIUS_BODY_GRAPH_LAYOUT
#define LANIUS_BODY_GRAPH_LAYOUT

// Graph nodes. Each node owns one reserved type-instance row after the source
// token rows (with BODY_NODE_ARGUMENTS argument words) and one reserved
// constant atom row.
static const uint BODY_GRAPH_NODES = 1024u;
static const uint BODY_GRAPH_EDGES = 16384u;
static const uint BODY_NODE_ARGUMENTS = 32u;
// Type and constant parameter slots of one entry.
static const uint BODY_TYPE_SLOTS = 32u;
// Single-entry packet capacity: nodes 0..63 at rows 65 + 2i, edge words
// 0..2047 from row 193. Larger graphs continue in the extension rows.
static const uint BODY_GRAPH_V2_NODES = 64u;
static const uint BODY_GRAPH_V2_EDGES = 2048u;
// Rows 738.. of a packet whose graph exceeds the v2 capacity: node pairs for
// nodes 64.., then edge words 2048.. . The extra entries follow them.
static const uint BODY_GRAPH_EXT_START = 738u;
static const uint BODY_GRAPH_EXT_EDGE_START =
    BODY_GRAPH_EXT_START + (BODY_GRAPH_NODES - BODY_GRAPH_V2_NODES) * 2u;
static const uint BODY_GRAPH_EXT_ROWS =
    (BODY_GRAPH_NODES - BODY_GRAPH_V2_NODES) * 2u + (BODY_GRAPH_EDGES - BODY_GRAPH_V2_EDGES) / 4u;
// The checked constant atom table's tail: one row per graph node, then one
// per direct constant slot of entry 0.
static const uint BODY_CONSTANT_SLOTS = 32u;
static const uint BODY_ATOM_RESERVE_ROWS = BODY_GRAPH_NODES + BODY_CONSTANT_SLOTS;
static const uint BODY_MAX_ENTRIES = 4096u;

#endif
