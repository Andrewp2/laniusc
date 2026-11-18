// Decode published parents and seed one pointer-jump link per dense HIR row.

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> expr_parent_encoded;
RWStructuredBuffer<uint> expr_parent;
RWStructuredBuffer<uint> expr_root;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir = tid(dtid);
    uint count = min(canonical_count[0u], gCanonical.canonical_capacity);
    if (hir >= count) return;
    uint encoded = expr_parent_encoded[hir];
    uint parent = encoded == 0u ? INVALID : encoded - 1u;
    if (parent >= count) parent = INVALID;
    expr_parent[hir] = parent;
    expr_root[hir] = parent == INVALID ? hir : parent;
}
