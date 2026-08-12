import type_checker.type.instances.struct_field_lookup;
import hir_records;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> name_id_by_token;
RWStructuredBuffer<uint> struct_field_lookup_state;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    uint count = min(compact_field_count[0u], gParams.n_tokens);
    struct_field_lookup_insert(
        row, count, gParams.n_tokens,
        compact_fields, name_id_by_token,
        struct_field_lookup_state);
}
