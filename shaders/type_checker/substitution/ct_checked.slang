// Canonical IDs of checked operands produced during inference. Rows, atoms
// and projections written after the early canonical stage are not interned
// until the late stage; a reader that needs their IDs interns them here, on
// demand, without a stack: it descends to the first child that is not
// interned, interns that candidate from its children (through a lane-owned
// spare record, never the candidate's fixed record), publishes its reference
// and starts again from the root. Published references only go from pending
// (or empty) to the candidate's ID, which every interning lane agrees on.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_candidates;
import type_checker.canonical.canonical_constants;
import type_checker.checked_type_graph;
import type_checker.constant_atoms;
import type_checker.substitution.ct_rows;

static const uint INVALID = 0xffffffffu;

bool needs_intern(uint ref)
{
    return ref == CT_PENDING || ref == CT_NONE;
}

// The candidate of a checked operand, or INVALID when it is not a row, atom
// or projection.
uint operand_candidate(uint tag, uint payload)
{
    uint rows = ct_row_capacity();
    if ((tag & CT_CONSTANT_TAG_BIT) != 0u)
    {
        uint kind = tag & ~CT_CONSTANT_TAG_BIT;
        if (kind == 1u && payload < ct_atom_capacity()) return rows + payload;
        if (kind == 3u && payload < ct_projection_capacity()) return rows + ct_atom_capacity() + payload;
        return INVALID;
    }
    // Legacy scalar-coded nominal values name their zero-argument row.
    if (tag == 1u && payload >= 4096u && payload < 8192u) payload -= payload < 6144u ? 4096u : 6144u;
    else if (tag != 3u) return INVALID;
    return payload < rows ? payload : INVALID;
}

// The first child of `candidate` that is not interned, as a candidate.
uint pending_child(uint candidate)
{
    uint rows = ct_row_capacity();
    if (candidate >= rows)
    {
        uint projection = candidate - rows - ct_atom_capacity();
        uint target; uint2 child;
        if (candidate - rows < ct_atom_capacity() || !checked_constant_projection(projection, target, child))
            return INVALID;
        uint tag = CT_CONSTANT_TAG_BIT | child.x;
        return needs_intern(ct_ref(tag, child.y)) ? operand_candidate(tag, child.y) : INVALID;
    }
    uint kind = type_instance_kind[candidate];
    uint arity = kind == 1u ? type_instance_arg_count[candidate] : kind == 2u ? 2u : kind <= 4u ? 1u : 0u;
    for (uint index = 0u; index < min(arity, 32u); index++)
    {
        uint tag = type_instance_elem_ref_tag[candidate];
        uint payload = type_instance_elem_ref_payload[candidate];
        if (kind == 1u && !ScopedCheckedTypeGraph.argument(candidate, index, tag, payload)) continue;
        if (kind == 2u && index == 1u)
        {
            tag = CT_CONSTANT_TAG_BIT | type_instance_len_kind[candidate];
            payload = type_instance_len_payload[candidate];
        }
        if (!needs_intern(ct_ref(tag, payload))) continue;
        uint child = operand_candidate(tag, payload);
        if (child != INVALID) return child;
    }
    return INVALID;
}

// Offer a candidate interned here as the row of its ID.
void seed_row(uint candidate, uint id)
{
    uint rows = ct_row_capacity();
    uint atoms = ct_atom_capacity();
    if (candidate < rows)
    {
        uint tokens; uint stride;
        type_generic_param_slot_by_token.GetDimensions(tokens, stride);
        ct_seed_type_row(candidate, type_instance_kind[candidate], type_instance_decl_token[candidate], id, tokens);
    }
    else if (candidate - rows < atoms) ct_seed_constant_row(1u, candidate - rows, id);
    else ct_seed_constant_row(3u, candidate - rows - atoms, id);
}

// The canonical reference of checked operand (tag, payload), interning the
// candidates it needs. CT_NONE for an empty candidate, CT_UNKNOWN for an
// unsupported one. `spare` is the lane's unpublished record (CT_NONE when it
// has none).
public uint ct_intern_checked(uint tag, uint payload, inout uint spare)
{
    uint ref = ct_ref(tag, payload);
    if (!needs_intern(ref)) return ref;
    uint root = operand_candidate(tag, payload);
    if (root == INVALID) return ref == CT_NONE ? CT_NONE : CT_UNKNOWN;
    for (uint work = 0u; work < 1024u; work++)
    {
        uint node = root;
        for (uint depth = 0u; depth < 64u; depth++)
        {
            uint child = pending_child(node);
            if (child == INVALID) break;
            node = child;
        }
        CtKey key;
        uint id = canonical_build_candidate_key(node, false, key);
        if (id == CT_KEY_BUILT) id = ct_intern_spare(key, key.extra, spare);
        if (!ct_is_resolved(id)) return id == CT_NONE ? CT_NONE : CT_UNKNOWN;
        // ct_publish_candidate fences (release) before the store.
        if (needs_intern(ct_candidate_state(node)))
        {
            ct_publish_candidate(node, id);
            seed_row(node, id);
        }
        if (node == root) return id;
    }
    return CT_UNKNOWN;
}
