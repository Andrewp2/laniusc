import atomics;
import gpu_index;
import hir_records;
import type_checker.methods.lookup;
import type_checker.instance_arguments;
import type_checker.constant_parameter_slots;

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
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> method_lookup_head;
RWStructuredBuffer<uint> method_lookup_next;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[ForceInline]
uint active_token_count()
{
    return min(token_count[0u], gParams.n_tokens);
}

uint active_method_count()
{
    return min(compact_method_count[0u], gParams.n_hir_nodes);
}

#include "receiver_graph.slang"

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

    MethodReceiverHead head;
    if (!method_receiver_head<MethodReceiverGraph>(tag, payload,
        method_receiver_type_capacity(), active_token_count(), head)) return;
    uint bucket = method_lookup_bucket(head, name_id, count);
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
