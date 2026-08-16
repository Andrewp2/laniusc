// Project every raw semantic wrapper to the winning canonical HIR row. The
// early identity mark records each raw row's source anchor before later HIR
// enrichment reuses the token-end column.

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> canonical_anchor_owner;
StructuredBuffer<uint> canonical_raw_to_dense;
RWStructuredBuffer<uint> raw_to_hir;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;

uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }
bool valid(uint node) { return node != INVALID && node < active_count(); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint raw = tid(dtid);
    if (raw >= gCanonical.raw_capacity) return;
    if (!valid(raw)) { raw_to_hir[raw] = INVALID; return; }

    uint direct = canonical_raw_to_dense[raw];
    if (direct < gCanonical.canonical_capacity)
    {
        raw_to_hir[raw] = direct;
        return;
    }

    // This output owns the raw-row storage. Before this pass, the same rows
    // contain the source anchors recorded by canonical mark. Each invocation
    // consumes its own anchor before replacing it with the durable dense ID.
    uint anchor = raw_to_hir[raw];
    if (anchor >= gCanonical.canonical_capacity)
    {
        raw_to_hir[raw] = INVALID;
        return;
    }
    uint winner_plus_one = canonical_anchor_owner[anchor] & 0x0fffffffu;
    uint winner = winner_plus_one == 0u ? INVALID : winner_plus_one - 1u;
    uint dense = valid(winner) ? canonical_raw_to_dense[winner] : INVALID;
    raw_to_hir[raw] = dense < gCanonical.canonical_capacity ? dense : INVALID;
}
