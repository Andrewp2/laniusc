import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint call_arg_capacity;
    uint aggregate_capacity;
    uint function_capacity;
    uint token_capacity;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
RWStructuredBuffer<uint> x86_position_by_semantic;
RWStructuredBuffer<uint> x86_last_use_by_semantic;
RWStructuredBuffer<uint> x86_function_start;
RWStructuredBuffer<uint> x86_function_end;
RWStructuredBuffer<X86FunctionRegisterAnalysis>
    x86_register_analysis_by_function;
RWStructuredBuffer<X86DeclarationAnalysis> x86_decl_analysis_by_token;
RWStructuredBuffer<uint> x86_direct_call_count_by_function;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (position >= total) return;
    uint row = semantic_schedule_order[position];
    if (row >= total) return;

    OptIrNodeCore core = opt_ir_core[row];
    OptIrNodeOperands operands = opt_ir_operands[row];
    uint op = opt_ir_op(core);
    if (op == SEMANTIC_LIR_OP_CALL && operands.a < gParams.function_capacity)
    {
        uint ignored;
        InterlockedAdd(x86_direct_call_count_by_function[operands.a], 1u, ignored);
    }
    if (op == SEMANTIC_LIR_OP_VALUE_GET)
    {
        uint declaration = operands.a;
        if (declaration < gParams.token_capacity)
        {
            uint ignored;
            InterlockedMax(
                x86_decl_analysis_by_token[declaration].last_read,
                position + 1u, ignored);
            InterlockedMax(
                x86_decl_analysis_by_token[declaration].last_access,
                position + 1u, ignored);
            InterlockedAdd(
                x86_decl_analysis_by_token[declaration].read_count,
                1u, ignored);
        }
    }
    else if (op == SEMANTIC_LIR_OP_VALUE_SET ||
             (op == SEMANTIC_LIR_OP_STORE &&
              (core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                             SEMANTIC_LIR_FLAG_FIELD)) == 0u))
    {
        uint declaration = operands.a;
        if (declaration < gParams.token_capacity)
        {
            uint ignored;
            InterlockedMax(
                x86_decl_analysis_by_token[declaration].last_access,
                position + 1u, ignored);
            uint prior;
            InterlockedCompareExchange(
                x86_decl_analysis_by_token[declaration].definition,
                INVALID, row, prior);
            if (prior != INVALID && prior != row)
                InterlockedExchange(
                    x86_decl_analysis_by_token[declaration].definition,
                    X86_DECLARATION_MULTIPLE_DEFINITIONS);
        }
    }

    x86_position_by_semantic[row] = position;
    x86_last_use_by_semantic[row] = position;
    uint owner = opt_ir_source_hir[row];
    if (owner >= gParams.function_capacity) return;
    uint function_id = semantic_function_id_by_hir[owner];
    if (function_id >= gParams.function_capacity) return;
    uint ignored;
    InterlockedMin(x86_function_start[function_id], position, ignored);
    InterlockedMax(x86_function_end[function_id], position + 1u, ignored);
    if (semantic_lir_is_call(op))
        InterlockedMin(
            x86_register_analysis_by_function[function_id].first_call,
            position + 1u, ignored);
}
