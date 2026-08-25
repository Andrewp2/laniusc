import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint access_capacity;
    uint declaration_capacity;
    uint parameter_capacity;
    uint local_capacity;
    uint reserved;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<OptIrNodeControl> opt_ir_control;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_access_flag;
StructuredBuffer<uint> opt_ir_access_prefix;
StructuredBuffer<uint> opt_ir_instruction_access_total;
StructuredBuffer<uint> opt_ir_metadata_access_total;
RWStructuredBuffer<OptIrAccessCore> opt_ir_accesses;
RWStructuredBuffer<uint> opt_ir_access_source_rows;
RWStructuredBuffer<uint> opt_ir_access_positions;
RWStructuredBuffer<uint> opt_ir_access_kinds;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (position == 0u &&
        opt_ir_instruction_access_total[0u] > gParams.access_capacity)
    {
        InterlockedOr(lowering_status[0u].flags,
            LOWERING_STATUS_OPTIMIZATION_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity,
            opt_ir_instruction_access_total[0u]);
        lowering_status[0u].available_capacity = gParams.access_capacity;
    }
    if (position >= total || opt_ir_access_flag[position] == 0u) return;

    uint node = semantic_schedule_order[position];
    uint metadata_total = min(
        opt_ir_metadata_access_total[0u], gParams.access_capacity);
    uint access_id = metadata_total + opt_ir_access_prefix[position];
    if (node >= total || access_id >= gParams.access_capacity) return;

    OptIrAccessCore access;
    access.subject = opt_ir_operands[node].a;
    access.block_id = opt_ir_control[node].block_id;
    opt_ir_accesses[access_id] = access;
    opt_ir_access_source_rows[access_id] = node;
    opt_ir_access_positions[access_id] = position;
    opt_ir_access_kinds[access_id] = opt_ir_access_kind(opt_ir_core[node]);
}
