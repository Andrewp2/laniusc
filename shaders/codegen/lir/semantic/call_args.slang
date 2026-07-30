import hir_records;
import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_call_args; uint n_hir_nodes; uint lir_capacity; uint reserved; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> semantic_call_receiver;
StructuredBuffer<uint> semantic_call_arg_count_by_hir;
StructuredBuffer<uint> semantic_call_arg_prefix_by_hir;
StructuredBuffer<uint> semantic_expr_type;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> semantic_lir_count;
StructuredBuffer<uint> semantic_lir_offset;
RWStructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint lir_for_hir(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes &&
           semantic_lir_count[node] != 0u
        ? semantic_lir_offset[node]
        : INVALID;
}

uint value_metadata_for_hir(uint node)
{
    return node < gParams.n_hir_nodes
        ? semantic_lir_value_metadata(
            semantic_lir_type(semantic_expr_type[node]),
            semantic_expr_ref_tag[node],
            semantic_expr_ref_payload[node])
        : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint explicit_count = min(gParams.n_call_args, compact_call_arg_count[0u]);
    if (row < explicit_count)
    {
        HirCallArg source = compact_call_args[row];
        uint receiver_shift = source.call < gParams.n_hir_nodes &&
            semantic_call_receiver[source.call] != INVALID ? 1u : 0u;
        uint destination = source.call < gParams.n_hir_nodes
            ? semantic_call_arg_prefix_by_hir[source.call] + receiver_shift + source.ordinal
            : INVALID;
        SemanticLirCallArg result;
        result.call_instruction = lir_for_hir(source.call);
        result.value_instruction = lir_for_hir(source.value);
        result.ordinal = source.ordinal + receiver_shift;
        result.value_metadata = value_metadata_for_hir(source.value);
        if (destination < gParams.n_call_args)
            semantic_lir_call_args[destination] = result;
    }

    if (row < gParams.n_hir_nodes &&
        semantic_call_receiver[row] != INVALID &&
        semantic_call_arg_count_by_hir[row] != 0u)
    {
        uint destination = semantic_call_arg_prefix_by_hir[row];
        SemanticLirCallArg receiver;
        receiver.call_instruction = lir_for_hir(row);
        receiver.value_instruction = lir_for_hir(semantic_call_receiver[row]);
        receiver.ordinal = 0u;
        receiver.value_metadata =
            value_metadata_for_hir(semantic_call_receiver[row]);
        if (destination < gParams.n_call_args)
            semantic_lir_call_args[destination] = receiver;
    }
}
