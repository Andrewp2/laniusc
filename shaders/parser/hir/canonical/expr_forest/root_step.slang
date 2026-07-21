// Resolve final compact expression roots with parallel pointer jumping.

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> expr_root_in;
RWStructuredBuffer<uint> expr_root_out;

static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir = tid(dtid);
    uint count = min(canonical_count[0u], gCanonical.canonical_capacity);
    if (hir >= count) return;
    uint link = expr_root_in[hir];
    expr_root_out[hir] = link < count ? expr_root_in[link] : hir;
}
