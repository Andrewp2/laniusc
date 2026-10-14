// Propose every candidate whose children are all canonical. A candidate whose
// children are still pending stays idle and is retried next round.
import type_checker.canonical.canonical_types;
import type_checker.checked_type_graph;
import type_checker.constant_atoms;
import constant_value;
import primitive_types;

static const uint INVALID = 0xffffffffu;

uint canonical_child(uint tag, uint payload, inout bool pending, inout bool unknown)
{
    uint id = canonical_ref(tag, payload);
    // Parameter references are tagged tokens below every sentinel value.
    if (id == CANON_PENDING) pending = true;
    else if (id == CANON_UNKNOWN || id == CANON_NONE) unknown = true;
    return id;
}

bool write_key(uint candidate, uint4 a, uint aux2, uint arity)
{
    uint base = 0u;
    if (arity != 0u)
    {
        uint capacity; uint stride;
        canonical_cand_args.GetDimensions(capacity, stride);
        InterlockedAdd(canonical_counts[2u], arity, base);
        if (base > capacity || arity > capacity - base)
        {
            InterlockedOr(canonical_counts[3u], 4u);
            return false;
        }
    }
    canonical_cand_key_a[candidate] = a;
    canonical_cand_key_b[candidate] = uint4(aux2, arity, base, canonical_key_hash(a, aux2, arity));
    return true;
}

void propose_atom(uint candidate, uint atom)
{
    if (canonical_atom[atom] != CANON_PENDING) return;
    uint3 value;
    if (!checked_constant_atom_value(atom, value)) { canonical_atom[atom] = CANON_NONE; return; }
    if (!write_key(candidate, uint4(CT_CONST, value.x, value.y, value.z), 0u, 0u))
    { canonical_atom[atom] = CANON_UNKNOWN; return; }
    canonical_cand_state[candidate] = CAND_PROPOSED;
}

void propose_row(uint row)
{
    if (canonical_row[row] != CANON_PENDING) return;
    uint kind = ScopedCheckedTypeGraph.metadata(row, 0u);
    if (kind == 0u) { canonical_row[row] = CANON_NONE; return; }
    bool pending = false; bool unknown = false;
    uint4 a = uint4(0u, 0u, 0u, 0u); uint aux2 = 0u; uint arity = 0u;
    if (kind == 1u)
    {
        uint declaration = ScopedCheckedTypeGraph.metadata(row, 1u);
        arity = ScopedCheckedTypeGraph.metadata(row, 2u);
        if (arity > CANON_MAX_ARITY) unknown = true;
        a = uint4(CT_NAMED, declaration, INVALID, INVALID);
        if (declaration == INVALID)
        {
            a.z = ScopedCheckedTypeGraph.metadata(row, 7u);
            a.w = ScopedCheckedTypeGraph.metadata(row, 8u);
            aux2 = ScopedCheckedTypeGraph.metadata(row, 9u);
            if (a.z == INVALID || a.w == INVALID || aux2 == INVALID) unknown = true;
        }
        for (uint slot = 0u; slot < arity && !pending && !unknown; slot++)
        {
            uint tag; uint payload;
            if (!ScopedCheckedTypeGraph.argument(row, slot, tag, payload)) unknown = true;
            else canonical_child(tag, payload, pending, unknown);
        }
    }
    else if (kind >= 2u && kind <= 4u)
    {
        uint element = canonical_child(ScopedCheckedTypeGraph.metadata(row, 3u),
            ScopedCheckedTypeGraph.metadata(row, 4u), pending, unknown);
        a = uint4(kind == 2u ? CT_ARRAY : kind == 3u ? CT_SLICE : CT_REF, element, 0u, 0u);
        if (kind == 2u)
        {
            uint length_kind = ScopedCheckedTypeGraph.metadata(row, 5u);
            uint length = ScopedCheckedTypeGraph.metadata(row, 6u);
            uint3 value; uint count;
            if (length_kind == 1u && checked_constant_atom_value(length, value) &&
                constant_value_to_count(value, count))
                a.zw = uint2(count, CT_LENGTH_COUNT);
            else if (length_kind == 2u && length < CANON_PARAM_BIT)
                a.zw = uint2(length, CT_LENGTH_PARAM);
            else unknown = true;
        }
    }
    else unknown = true;
    if (unknown) { canonical_row[row] = CANON_UNKNOWN; return; }
    if (pending) return;
    if (!write_key(row, a, aux2, arity)) { canonical_row[row] = CANON_UNKNOWN; return; }
    uint base = canonical_cand_key_b[row].z;
    for (uint slot = 0u; slot < arity; slot++)
    {
        uint tag; uint payload;
        ScopedCheckedTypeGraph.argument(row, slot, tag, payload);
        canonical_cand_args[base + slot] = canonical_ref(tag, payload);
    }
    // Argument identities participate in the hash; probing compares them.
    uint hash = canonical_cand_key_b[row].w;
    for (uint slot = 0u; slot < arity; slot++)
        hash = canonical_hash_mix(hash, canonical_cand_args[base + slot]);
    canonical_cand_key_b[row].w = hash;
    canonical_cand_state[row] = CAND_PROPOSED;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint candidate = dtid.x + dtid.y * 16776960u;
    if (candidate >= canonical_candidate_capacity() ||
        canonical_cand_state[candidate] != CAND_IDLE) return;
    uint rows = canonical_row_capacity();
    if (candidate < rows) propose_row(candidate);
    else propose_atom(candidate, candidate - rows);
}
