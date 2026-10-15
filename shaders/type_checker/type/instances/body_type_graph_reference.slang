// Reserved source atoms share the physical table allocation. The tail contains
// BODY_GRAPH_NODES graph-node rows followed by BODY_CONSTANT_SLOTS direct
// constant-binding rows. Only 00e writes these rows, before any replay
// reference is published.
#ifndef LANIUS_BODY_TYPE_GRAPH_REFERENCE
#define LANIUS_BODY_TYPE_GRAPH_REFERENCE
#include "body_graph_rows.slang"

uint body_constant_atom_base()
{
    uint capacity; uint stride;
    checked_constant_atoms.GetDimensions(capacity, stride);
    return capacity >= BODY_ATOM_RESERVE_ROWS ? capacity - BODY_ATOM_RESERVE_ROWS : 0xffffffffu;
}

// Decode an owned checked graph node. Local monomorphic nominal leaves retain
// their checked scalar identity; applications always use fresh structural rows.
void body_type_graph_reference(uint ordinal, uint source_capacity,
    out uint tag, out uint payload)
{
    uint4 node = body_graph_node(ordinal);
    uint local_identity = body_graph_identity(ordinal).w;
    bool local_scalar = node.x == 9u &&
        (local_identity & 0xe0000000u) == 0x40000000u;
    tag = node.x == 10u ? 0x80000001u : node.x == 1u || local_scalar ? 1u : 3u;
    payload = node.x == 10u ? body_constant_atom_base() + ordinal :
        node.x == 1u ? node.y : local_scalar
        ? local_identity & 0x1fffffffu : source_capacity + ordinal;
}

#endif
