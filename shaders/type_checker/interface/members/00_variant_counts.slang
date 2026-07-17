// Derive aggregate member counts from compact field and variant family rows.
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };
struct HirVariant { uint owner; uint name_token; uint ordinal; uint file_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
RWStructuredBuffer<uint> interface_field_count_by_hir;
RWStructuredBuffer<uint> interface_variant_count_by_hir;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 d) { return d.x + d.y * MAX_GROUPS_X * WG_SIZE; }
[shader("compute")][numthreads(256,1,1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row < min(compact_field_count[0u], gParams.hir_capacity))
    {
        HirField field = compact_fields[row];
        if (field.owner < gParams.hir_capacity && field.ordinal < gParams.hir_capacity)
            atomic_u32_max(interface_field_count_by_hir, field.owner, field.ordinal + 1u);
    }
    if (row < min(compact_variant_count[0u], gParams.hir_capacity))
    {
        HirVariant variant = compact_variants[row];
        if (variant.owner < gParams.hir_capacity && variant.ordinal < gParams.hir_capacity)
            atomic_u32_max(interface_variant_count_by_hir, variant.owner, variant.ordinal + 1u);
    }
}
