// Persist the compact public declaration order before module-path scratch is
// reused by later type-instance passes.

struct Params
{
    uint capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> decl_type_key_count_out;
StructuredBuffer<uint> decl_value_key_count_out;
StructuredBuffer<uint> decl_type_key_to_decl_id;
StructuredBuffer<uint> decl_value_key_to_decl_id;
StructuredBuffer<uint> decl_type_public_flag;
StructuredBuffer<uint> decl_value_public_flag;
StructuredBuffer<uint> decl_type_public_prefix;
StructuredBuffer<uint> decl_value_public_prefix;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_kind;
RWStructuredBuffer<uint> interface_public_decl_count;
RWStructuredBuffer<uint> interface_public_decl_local_id;
RWStructuredBuffer<uint> interface_public_decl_index_by_local;
RWStructuredBuffer<uint> interface_public_decl_index_by_hir;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint compact_count(
    StructuredBuffer<uint> count_out,
    StructuredBuffer<uint> flag,
    StructuredBuffer<uint> prefix)
{
    uint count = min(count_out[0u], gParams.capacity);
    return count == 0u ? 0u : prefix[count - 1u] + flag[count - 1u];
}

void publish(uint local_decl, uint persisted_decl)
{
    if (local_decl >= gParams.capacity || persisted_decl >= gParams.capacity)
        return;
    interface_public_decl_local_id[persisted_decl] = local_decl;
    interface_public_decl_index_by_local[local_decl] = persisted_decl;
    uint hir = decl_hir_node[local_decl];
    if (decl_kind[local_decl] != HIR_ITEM_KIND_ENUM_VARIANT && hir < gParams.capacity)
        interface_public_decl_index_by_hir[hir] = persisted_decl;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= gParams.capacity)
        return;

    uint type_count = min(decl_type_key_count_out[0u], gParams.capacity);
    uint value_count = min(decl_value_key_count_out[0u], gParams.capacity);
    uint type_public_count = compact_count(
        decl_type_key_count_out,
        decl_type_public_flag,
        decl_type_public_prefix);
    uint value_public_count = compact_count(
        decl_value_key_count_out,
        decl_value_public_flag,
        decl_value_public_prefix);

    if (row == 0u)
        interface_public_decl_count[0u] = min(
            type_public_count + value_public_count,
            gParams.capacity);

    if (row < type_count && decl_type_public_flag[row] != 0u)
        publish(
            decl_type_key_to_decl_id[row],
            decl_type_public_prefix[row]);
    if (row < value_count && decl_value_public_flag[row] != 0u)
        publish(
            decl_value_key_to_decl_id[row],
            type_public_count + decl_value_public_prefix[row]);
}
