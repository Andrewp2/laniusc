import atomics;
import gpu_index;
import hir_records;
import type_checker.methods.lookup;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<uint> method_decl_method_row;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_name_id;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_hash;
RWStructuredBuffer<uint> method_lookup_head;
RWStructuredBuffer<uint> method_lookup_next;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_token_count()
{
    return min(token_count[0u], gParams.n_tokens);
}

uint active_method_count()
{
    return min(compact_method_count[0u], gParams.n_hir_nodes);
}

uint decl_token_from_type_code(uint ty)
{
    if (ty >= TY_STRUCT_BASE && ty < TY_ENUM_BASE)
        return ty - TY_STRUCT_BASE;
    if (ty >= TY_ENUM_BASE && ty < TY_GENERIC_BASE)
        return ty - TY_ENUM_BASE;
    return INVALID;
}

uint receiver_payload_key(uint tag, uint payload)
{
    if (tag == TYPE_REF_GENERIC_PARAM)
        return INVALID;
    if (tag == TYPE_REF_INSTANCE && payload < active_token_count())
    {
        uint declaration = type_instance_decl_token[payload];
        if (declaration != INVALID)
            return declaration;
        declaration = decl_token_from_type_code(module_type_path_type[payload]);
        if (declaration != INVALID)
            return declaration;
    }
    return payload;
}

uint receiver_arg_count(uint tag, uint payload)
{
    return tag == TYPE_REF_INSTANCE && payload < active_token_count()
        ? type_instance_arg_count[payload]
        : 0u;
}

uint receiver_arg_hash(uint tag, uint payload)
{
    return tag == TYPE_REF_INSTANCE && payload < active_token_count()
        ? type_instance_arg_hash[payload]
        : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    uint count = active_method_count();
    if (row >= count)
        return;

    method_lookup_next[row] = 0u;
    uint fn_token = compact_method_cores[row].name_token;
    if (fn_token >= active_token_count() || method_decl_method_row[fn_token] == INVALID)
        return;

    uint tag = method_decl_receiver_ref_tag[fn_token];
    uint payload = method_decl_receiver_ref_payload[fn_token];
    uint name_id = method_decl_name_id[fn_token];
    if (tag == TYPE_REF_INVALID || payload == INVALID || name_id == INVALID)
        return;

    uint bucket = method_lookup_bucket(
        tag,
        receiver_payload_key(tag, payload),
        receiver_arg_count(tag, payload),
        receiver_arg_hash(tag, payload),
        name_id,
        count);
    uint prior = method_lookup_head[bucket];
    for (;;)
    {
        method_lookup_next[row] = prior;
        uint observed = atomic_u32_compare_exchange(
            method_lookup_head, bucket, prior, row + 1u);
        if (observed == prior)
            break;
        prior = observed;
    }
}
