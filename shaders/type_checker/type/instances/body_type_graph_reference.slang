// Reserved source atoms share the physical table allocation. The tail contains
// 64 graph-node rows followed by 32 direct constant-binding rows. Only 00e writes
// these rows, before any replay reference is published.
uint body_constant_atom_base()
{
    uint capacity; uint stride;
    checked_constant_atoms.GetDimensions(capacity, stride);
    return capacity >= 96u ? capacity - 96u : 0xffffffffu;
}

// Decode an owned checked graph node. Local monomorphic nominal leaves retain
// their checked scalar identity; applications always use fresh structural rows.
void body_type_graph_reference(uint ordinal, uint source_capacity,
    out uint tag, out uint payload)
{
    uint4 node = body_specialization_inputs[65u + ordinal * 2u];
    uint local_identity = body_specialization_inputs[66u + ordinal * 2u].w;
    bool local_scalar = node.x == 9u &&
        (local_identity & 0xe0000000u) == 0x40000000u;
    tag = node.x == 10u ? 0x80000001u : node.x == 1u || local_scalar ? 1u : 3u;
    payload = node.x == 10u ? body_constant_atom_base() + ordinal :
        node.x == 1u ? node.y : local_scalar
        ? local_identity & 0x1fffffffu : source_capacity + ordinal;
}
