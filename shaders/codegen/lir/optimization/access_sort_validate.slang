// Boundary validation for the stable OptIR access ordering.

import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint item_capacity;
    uint subject_bits;
    uint max_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_kinds;
StructuredBuffer<uint> opt_ir_access_order;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_order_failure(uint access_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, access_id);
}

bool key_before_or_equal(uint left_id, uint right_id)
{
    uint left_kind = opt_ir_access_kinds[left_id];
    uint right_kind = opt_ir_access_kinds[right_id];
    uint left_domain = opt_ir_access_domain(left_kind);
    uint right_domain = opt_ir_access_domain(right_kind);
    if (left_domain != right_domain)
        return left_domain < right_domain;
    uint left_subject = opt_ir_accesses[left_id].subject;
    uint right_subject = opt_ir_accesses[right_id].subject;
    if (left_subject != right_subject)
        return left_subject < right_subject;
    // Original access IDs encode metadata-before-schedule order. Strict order
    // inside equal keys proves stability and also rejects duplicate rows.
    return left_id < right_id;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint order_i = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_access_total[0u], gParams.item_capacity);
    if (order_i >= total) return;

    uint access_id = opt_ir_access_order[order_i];
    if (access_id >= total)
    {
        report_order_failure(access_id);
        return;
    }
    if (order_i == 0u) return;

    uint previous_id = opt_ir_access_order[order_i - 1u];
    if (previous_id >= total || !key_before_or_equal(previous_id, access_id))
        report_order_failure(access_id);
}
