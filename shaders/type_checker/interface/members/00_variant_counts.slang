// Derive enum member counts from parser-produced parent and ordinal records.
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_variant_parent_enum;
StructuredBuffer<uint> hir_variant_ordinal;
RWStructuredBuffer<uint> interface_variant_count_by_hir;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint variant = linear_thread_id(dtid);
    if (variant >= min(hir_status[5u], gParams.hir_capacity)) return;
    uint owner = hir_variant_parent_enum[variant];
    uint ordinal = hir_variant_ordinal[variant];
    if (owner < gParams.hir_capacity && ordinal < gParams.hir_capacity)
        atomic_u32_max(interface_variant_count_by_hir, owner, ordinal + 1u);
}
