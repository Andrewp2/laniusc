import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint edge_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> semantic_function_total;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
RWStructuredBuffer<OptIrFunction> opt_ir_functions;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint node)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.hir_capacity, semantic_function_total[0u]);
    if (function_id >= total) return;

    OptIrFunction function = opt_ir_functions[function_id];
    if (function.block_start == INVALID)
    {
        if (function.node_start != INVALID || function.node_count != 0u ||
            function.block_count != 0u || function.entry_block != INVALID ||
            function.region_count != 0u)
            report_structure_failure(0u);
        function.node_start = 0u;
        function.node_count = 0u;
        function.block_start = 0u;
        function.block_count = 0u;
        function.entry_block = INVALID;
    }
    else
    {
        uint node_total = min(gParams.semantic_capacity, opt_ir_total[0u]);
        uint block_total = min(gParams.block_capacity, opt_ir_block_total[0u]);
        uint node_end = function.node_count;
        uint block_end = function.block_count;
        uint first_node = function.node_start < node_total
            ? semantic_schedule_order[function.node_start] : INVALID;
        bool valid = function.node_start < node_end && node_end <= node_total &&
            function.block_start < block_end && block_end <= block_total &&
            function.entry_block == function.block_start &&
            function.region_count == block_end - function.block_start;
        if (valid)
        {
            OptIrBlock first = opt_ir_blocks[function.block_start];
            OptIrBlock last = opt_ir_blocks[block_end - 1u];
            valid = first.function_id == function_id &&
                last.function_id == function_id &&
                first.position_start == function.node_start;
        }
        if (!valid)
            report_structure_failure(first_node);
        function.node_count = valid ? node_end - function.node_start : 0u;
        function.block_count = valid ? block_end - function.block_start : 0u;
    }
    function.region_count = 0u;
    opt_ir_functions[function_id] = function;
}
