// Resolve dense compact-HIR scalar result types with pointer jumping.

import gpu_index;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_expr_scalar_type_in;
RWStructuredBuffer<uint> compact_expr_scalar_type_out;

static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint SCALAR_TYPE_SHIFT = 28u;
static const uint SCALAR_TYPE_LINK_MASK = 0x0fffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
uint record_type(uint record) { return record >> SCALAR_TYPE_SHIFT; }
uint record_link(uint record)
{
    uint link = record & SCALAR_TYPE_LINK_MASK;
    return link == SCALAR_TYPE_LINK_MASK ? INVALID : link;
}
uint pack_scalar_type(uint ty, uint link)
{
    uint packed_link = valid_hir(link) && link < SCALAR_TYPE_LINK_MASK
                           ? link
                           : SCALAR_TYPE_LINK_MASK;
    return (ty << SCALAR_TYPE_SHIFT) | packed_link;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;
    uint record = compact_expr_scalar_type_in[node];
    uint ty = record_type(record);
    uint link = record_link(record);
    if (ty != TY_UNKNOWN || !valid_hir(link) || link == node)
    {
        compact_expr_scalar_type_out[node] = pack_scalar_type(ty, INVALID);
        return;
    }
    uint linked = compact_expr_scalar_type_in[link];
    uint linked_ty = record_type(linked);
    uint next = record_link(linked);
    compact_expr_scalar_type_out[node] = pack_scalar_type(
        linked_ty,
        linked_ty == TY_UNKNOWN && valid_hir(next) ? next : INVALID);
}
