// Publish complete normal forms before signatures and accepted expression
// facts are captured. Mapping reads are immutable, so annotations and source
// graph edges can be updated in parallel without following changing pointers.
struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint2> type_alias_normalized_ref;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_instance_elem_ref_tag;
RWStructuredBuffer<uint> type_instance_elem_ref_payload;
RWStructuredBuffer<uint> type_instance_arg_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_ref_payload;
RWStructuredBuffer<uint> type_instance_arg_row_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_row_ref_payload;
RWStructuredBuffer<uint> module_type_path_type;
RWStructuredBuffer<uint> module_type_path_status;
static const uint INVALID = 0xffffffffu;

uint2 normalized(uint tag, uint payload)
{
    if (tag == 3u && payload < gParams.n_tokens)
    {
        uint2 value = type_alias_normalized_ref[payload];
        if (value.x != 0u && value.y != INVALID) return value;
    }
    return uint2(tag, payload);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = dtid.x + dtid.y * 16776960u;
    if (token >= gParams.n_tokens) return;
    uint2 value = normalized(type_expr_ref_tag[token], type_expr_ref_payload[token]);
    type_expr_ref_tag[token] = value.x;
    type_expr_ref_payload[token] = value.y;
    if (value.x != 0u && value.x != 4u && value.y != INVALID)
    {
        if (value.x == 1u) module_type_path_type[token] = value.y;
        module_type_path_status[token] = 0u;
    }
    uint kind = type_instance_kind[token];
    if (kind >= 2u && kind <= 4u)
    {
        value = normalized(type_instance_elem_ref_tag[token], type_instance_elem_ref_payload[token]);
        type_instance_elem_ref_tag[token] = value.x;
        type_instance_elem_ref_payload[token] = value.y;
    }
    if (kind != 1u) return;
    uint count = type_instance_arg_count[token];
    if (count > 32u) return;
    uint start = type_instance_arg_row_start[token];
    uint total = type_instance_arg_row_count_out[0u];
    for (uint i = 0u; i < count; i++)
    {
        if (start < total && i < total - start)
        {
            uint row = start + i;
            value = normalized(type_instance_arg_row_ref_tag[row], type_instance_arg_row_ref_payload[row]);
            type_instance_arg_row_ref_tag[row] = value.x;
            type_instance_arg_row_ref_payload[row] = value.y;
        }
        if (i < 4u)
        {
            uint row = token * 4u + i;
            value = normalized(type_instance_arg_ref_tag[row], type_instance_arg_ref_payload[row]);
            type_instance_arg_ref_tag[row] = value.x;
            type_instance_arg_ref_payload[row] = value.y;
        }
    }
}
