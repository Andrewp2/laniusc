// Debug validation, step 3 of 3: cross-check against the previous graph
// equality (scoped_type_refs_equal). Only this kernel imports the old
// walker, and it calls it at one site.
// - false merge: a row whose canonical ID is another row's record, while the
//   old walker says the two rows differ. A pair whose top-level nominal
//   spelling differs (declaration token against an imported triple) is the
//   intended unification of local and imported references and is counted
//   as a normalized merge instead.
// - missed merge: two rows of one coarse bucket that the old walker accepts
//   but that have different canonical IDs.
import type_checker.canonical.canonical_api;
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

bool spelling_differs(uint left, uint right)
{
    return type_instance_kind[left] == 1u &&
        (type_instance_decl_token[left] == INVALID) != (type_instance_decl_token[right] == INVALID);
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
    uint representative = id >= CT_FIRST_RECORD ? id - CT_FIRST_RECORD : INVALID;
    uint link = canonical_crosscheck_links[buckets + row];
    // Step 0 compares the row with its representative (a merge to confirm);
    // later steps compare it with its bucket successors (merges to find).
    for (uint step = 0u; step <= BUCKET_WALK_LIMIT; step++)
    {
        uint other;
        bool merged = step == 0u;
        if (merged)
        {
            if (representative >= rows || representative == row) continue;
            other = representative;
        }
        else
        {
            if (link == 0u || link - 1u >= rows) break;
            other = link - 1u;
            link = canonical_crosscheck_links[buckets + other];
            if (canonical_row[other] == id || !coarse_equal(row, other)) continue;
        }
        bool equal = scoped_type_refs_equal<ScopedCheckedTypeGraph>(3u, row, INVALID,
            3u, other, INVALID, checked_type_capacity(), gParams.n_tokens);
        if (merged == equal) continue;
        if (merged && spelling_differs(row, other))
        {
            InterlockedAdd(canonical_validation[V_NORMALIZED], 1u);
            continue;
        }
        InterlockedAdd(canonical_validation[merged ? V_FALSE_MERGES : V_MISSED_MERGES], 1u);
        witness(row, other);
    }
}
