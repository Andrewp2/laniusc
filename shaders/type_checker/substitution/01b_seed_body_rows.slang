// Seed the row of each ID from a replay's body graph rows
// (type/instances/00e), after the body canonical stage and 01_seed_rows. A
// source row of the same ID is smaller and stays its row.
//
// Without this, a type argument's ID had no row, and realizing one wrote a
// private row from its record. A foreign nominal's record holds only its
// declaration triple, so that row had no layout: [P; N] under a dependency's
// Vec<P, N> got a P without the width the seed node carries.
//
// Only active nodes are offered: the reserved rows of a larger graph from an
// earlier job keep stale contents.
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_rows;
import type_checker.checked_type_graph;

StructuredBuffer<uint4> body_specialization_inputs;
#include "../type/instances/body_graph_rows.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint ordinal = dtid.x;
    if (dtid.y != 0u || dtid.z != 0u || ordinal >= body_graph_node_count()) return;
    uint tokens; uint stride;
    type_generic_param_slot_by_token.GetDimensions(tokens, stride);
    uint row = tokens + ordinal;
    if (row >= checked_type_capacity() || row >= ct_row_capacity()) return;
    ct_offer_type_row(row, type_instance_kind[row], type_instance_decl_token[row], canonical_row[row]);
}
