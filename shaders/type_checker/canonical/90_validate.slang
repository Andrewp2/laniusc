// Debug validation: canonical IDs against the previous graph equality.
// [0] false merges (one ID, unequal rows), [1] missed merges (equal rows in
// one closed-application lookup bucket, different IDs), [2] unknown rows, [3] resolved rows,
// [4..] up to 30 (row, other) witness pairs, false merges first.
import type_checker.canonical.canonical_types;
import type_checker.checked_type_graph;
import type_checker.constant_atoms;
import constant_value;
import primitive_types;
import type_checker.checked_scoped_types;
import type_checker.scoped_type_equality;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> canonical_validation;

void witness(uint row, uint other)
{
    uint slot; InterlockedAdd(canonical_validation[34u], 1u, slot);
    if (slot < 15u)
    {
        canonical_validation[4u + slot * 2u] = row;
        canonical_validation[5u + slot * 2u] = other;
    }
}

bool old_equal(uint left, uint right)
{
    return scoped_type_refs_equal<ScopedCheckedTypeGraph>(3u, left, 0xffffffffu,
        3u, right, 0xffffffffu, checked_type_capacity(), gParams.n_tokens);
}

void validate_row(uint row)
{
    uint id = canonical_row[row];
    uint ignored;
    if (id == CANON_UNKNOWN || id == CANON_PENDING)
    { InterlockedAdd(canonical_validation[2u], 1u, ignored); return; }
    if (id == CANON_NONE) return;
    InterlockedAdd(canonical_validation[3u], 1u, ignored);
    if (id < CANON_FIRST_DYNAMIC || id >= canonical_record_capacity()) return;
    uint representative = canonical_ct_rep[id];
    if (representative != row && representative < canonical_row_capacity() &&
        !old_equal(row, representative))
    {
        InterlockedAdd(canonical_validation[0u], 1u, ignored);
        witness(row, representative);
    }
}

// Rows in one bucket of the previous closed-application index that the
// previous equality accepts must share one canonical ID. Walking buckets
// rather than rehashing rows keeps the hash walker out of this kernel.
void validate_bucket(uint bucket)
{
    uint ignored;
    uint link = type_instance_lookup_head[bucket];
    for (uint steps = 0u; steps < 256u && link != 0u; steps++)
    {
        uint row = link - 1u;
        if (row >= canonical_row_capacity()) return;
        uint id = canonical_row[row];
        uint other_link = type_instance_lookup_next[row];
        for (uint inner = 0u; inner < 256u && other_link != 0u; inner++)
        {
            uint other = other_link - 1u;
            if (other >= canonical_row_capacity()) break;
            uint other_id = canonical_row[other];
            if (canonical_is_resolved(id) && canonical_is_resolved(other_id) && other_id != id &&
                old_equal(row, other))
            {
                InterlockedAdd(canonical_validation[1u], 1u, ignored);
                witness(row, other);
            }
            other_link = type_instance_lookup_next[other];
        }
        link = type_instance_lookup_next[row];
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    if (i < canonical_row_capacity()) validate_row(i);
    uint buckets; uint stride;
    type_instance_lookup_head.GetDimensions(buckets, stride);
    if (i < buckets) validate_bucket(i);
}
