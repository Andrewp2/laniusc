// Validates the block-local definition relation without requiring block-entry
// reads to be resolved; those rows are the input to cross-CFG propagation.

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
StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_kinds;
StructuredBuffer<uint> opt_ir_access_order;
StructuredBuffer<uint> opt_ir_access_positions;
StructuredBuffer<uint> opt_ir_local_definition_by_access;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint access_id)
{
    {
        uint diagnostic_ignored;
        InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
            LOWERING_DIAGNOSTIC_NONE,
            LOWERING_DIAGNOSTIC_OPT_ACCESS_LOCAL_DEFINITIONS_VALIDATE,
            diagnostic_ignored);
    }
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, access_id);
}

bool is_definition(uint kind)
{
    return kind == OPT_IR_ACCESS_PARAMETER_DEFINITION ||
        kind == OPT_IR_ACCESS_DECLARATION_WRITE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint order_i = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_access_total[0u], gParams.access_capacity);
    if (order_i >= total) return;

    uint access_id = opt_ir_access_order[order_i];
    if (access_id >= total)
    {
        report_structure_failure(access_id);
        return;
    }

    uint kind = opt_ir_access_kinds[access_id];
    uint definition_id = opt_ir_local_definition_by_access[access_id];
    uint expected = INVALID;
    if (is_definition(kind))
        expected = access_id;
    else if (kind == OPT_IR_ACCESS_DECLARATION_READ && order_i > 0u)
    {
        uint previous_id = opt_ir_access_order[order_i - 1u];
        if (previous_id < total)
        {
            OptIrAccessCore access = opt_ir_accesses[access_id];
            OptIrAccessCore previous = opt_ir_accesses[previous_id];
            uint previous_kind = opt_ir_access_kinds[previous_id];
            if (opt_ir_access_domain(previous_kind) == 0u &&
                previous.subject == access.subject &&
                previous.block_id == access.block_id)
                expected = is_definition(previous_kind)
                    ? previous_id
                    : opt_ir_local_definition_by_access[previous_id];
        }
    }

    bool valid = definition_id == expected;
    if (valid && definition_id != INVALID)
    {
        valid = definition_id < total;
        if (valid)
        {
            OptIrAccessCore access = opt_ir_accesses[access_id];
            OptIrAccessCore definition = opt_ir_accesses[definition_id];
            uint definition_kind = opt_ir_access_kinds[definition_id];
            valid = is_definition(definition_kind) &&
                definition.subject == access.subject &&
                definition.block_id == access.block_id &&
                opt_ir_access_positions[definition_id] <=
                    opt_ir_access_positions[access_id];
        }
    }
    if (!valid) report_structure_failure(access_id);
}
