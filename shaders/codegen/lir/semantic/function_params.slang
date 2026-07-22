import codegen.lir.semantic.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };
struct HirParam { uint owner; uint name_token; uint type_node; uint ordinal; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> semantic_function_flag;
StructuredBuffer<uint> semantic_function_prefix;
StructuredBuffer<uint> semantic_param_type_by_row;
RWStructuredBuffer<uint> semantic_lir_param_total;
RWStructuredBuffer<SemanticLirParam> semantic_lir_params;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint source_count = compact_param_count[0u];
    uint count = min(source_count, gParams.param_capacity);
    if (row == 0u)
    {
        semantic_lir_param_total[0u] = count;
        if (source_count > gParams.param_capacity)
        {
            InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_SEMANTIC_CAPACITY);
            InterlockedMax(lowering_status[0u].required_capacity, source_count);
            InterlockedMin(lowering_status[0u].available_capacity, gParams.param_capacity);
        }
    }
    if (row >= count) return;

    HirParam source = compact_params[row];
    SemanticLirParam result;
    result.function_id = source.owner < gParams.n_hir_nodes && semantic_function_flag[source.owner] != 0u
        ? semantic_function_prefix[source.owner] : LIR_INVALID;
    result.declaration_id = source.name_token;
    result.ordinal = source.ordinal;
    result.type_id = semantic_param_type_by_row[row];
    semantic_lir_params[row] = result;
}
