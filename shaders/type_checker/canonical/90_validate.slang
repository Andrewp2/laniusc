// Debug validation, step 3 of 3: cross-check against the previous graph
// equality (scoped_type_refs_equal). Only this kernel imports the old
// walker, and it calls it at one site: checked rows on the left, the
// canonical bridge graph (rows, or IDs at CT_ROW_BASE) on the right.
// - bridge mismatch: the old walker rejects a row against its own canonical
//   ID read through the bridge (canonical_bridge.slang).
// - false merge: a row and its representative (the smallest row with the
//   same canonical ID, 89_crosscheck_buckets), while the old walker says the
//   two rows differ. A pair whose top-level nominal spelling differs
//   (declaration token against an imported triple) is the intended
//   unification of local and imported references and is counted as a
//   normalized merge instead.
// - missed merge: two rows of one coarse bucket that the old walker accepts
//   but that have different canonical IDs.
// A row whose ID has no representative (a preseeded scalar ID) is confirmed
// against the next row of its bucket chain with the same ID instead, which
// chains every such row of the bucket.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_bridge;
import type_checker.canonical.canonical_crosscheck;
import type_checker.checked_type_graph;
import type_checker.scoped_type_equality;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> canonical_validation;

static const uint INVALID = 0xffffffffu;
static const uint V_FALSE_MERGES = 0u;
static const uint V_MISSED_MERGES = 1u;
static const uint V_WITNESSES = 14u;
static const uint V_NORMALIZED = 15u;
static const uint V_WITNESS_BASE = 16u;
static const uint V_WITNESS_PAIRS = 10u;
static const uint BUCKET_WALK_LIMIT = 4096u;
static const uint V_BRIDGE_MISMATCHES = 38u;

void witness(uint row, uint other)
{
    uint slot;
    InterlockedAdd(canonical_validation[V_WITNESSES], 1u, slot);
    if (slot < V_WITNESS_PAIRS)
    {
        canonical_validation[V_WITNESS_BASE + slot * 2u] = row;
        canonical_validation[V_WITNESS_BASE + slot * 2u + 1u] = other;
    }
}

// `other` is a row, or the bridged row of `id`.
bool spelling_differs(uint row, uint other, uint id)
{
    uint token = other >= CT_ROW_BASE ? ct_named_decl_token(id) : type_instance_decl_token[other];
    return type_instance_kind[row] == 1u && (type_instance_decl_token[row] == INVALID) != (token == INVALID);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint rows = crosscheck_rows();
    uint buckets = crosscheck_buckets();
    if (row >= rows || buckets == 0u || !crosscheck_row(row)) return;
    uint id = canonical_row[row];
    uint representative = crosscheck_owner(id);
    uint link = canonical_crosscheck_links[buckets + row];
    bool anchored = representative < rows;
    // Step 0 compares the row with its own ID through the bridge; step 1
    // with its representative (a merge to confirm); later steps with its
    // bucket successors (merges to find).
    for (uint step = 0u; step <= BUCKET_WALK_LIMIT + 1u; step++)
    {
        uint other;
        bool merged = step <= 1u;
        if (step == 0u) other = CT_ROW_BASE + id;
        else if (merged)
        {
            if (representative >= rows || representative == row) continue;
            other = representative;
        }
        else
        {
            if (link == 0u || link - 1u >= rows) break;
            other = link - 1u;
            link = canonical_crosscheck_links[buckets + other];
            merged = !anchored && canonical_row[other] == id;
            anchored = anchored || merged;
            if (!merged && (canonical_row[other] == id || !coarse_equal(row, other))) continue;
        }
        bool equal = scoped_type_refs_equal_graphs<ScopedCheckedTypeGraph, CanonicalBridgeTypeGraph>(
            3u, row, INVALID, 3u, other, INVALID, checked_type_capacity(), CT_BRIDGE_TYPE_CAPACITY,
            gParams.n_tokens);
        if (merged == equal) continue;
        if (merged && spelling_differs(row, other, id))
        {
            InterlockedAdd(canonical_validation[V_NORMALIZED], 1u);
            continue;
        }
        uint counter = step == 0u ? V_BRIDGE_MISMATCHES : merged ? V_FALSE_MERGES : V_MISSED_MERGES;
        InterlockedAdd(canonical_validation[counter], 1u);
        witness(row, other);
    }
}
