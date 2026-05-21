// x86_64 per-function incoming parameter register masks.
//
// Register allocation needs to avoid assigning temporaries to ABI parameter
// registers that are still live as incoming values. This pass scatters those
// masks from virtual PARAM rows in parallel so regalloc does not do a
// function-local row scan just to recover the same relation.

import atomics;
import bitset;
import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint4> x86_virtual_inst_args;
StructuredBuffer<uint> x86_virtual_inst_status;
StructuredBuffer<uint> x86_virtual_func_slot;

RWStructuredBuffer<uint> x86_func_param_reg_mask;
RWStructuredBuffer<uint> x86_func_param_reg_mask_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_FUNC_PARAM_REG_MASK_OK = 1u;
static const uint X86_ERR_FUNC_PARAM_REG_MASK = 20u;
static const uint X86_VINST_PARAM = 2u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint virtual_inst_count()
{
    return min(x86_virtual_inst_status[3u], gParams.inst_capacity);
}

bool upstream_ok()
{
    return x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
           x86_virtual_inst_status[1u] == 0u &&
           x86_virtual_inst_status[3u] <= gParams.inst_capacity;
}

void publish_status(bool ok, uint count)
{
    write_stage_status4_from_result(
        x86_func_param_reg_mask_status,
        ok,
        X86_FUNC_PARAM_REG_MASK_OK,
        INVALID,
        X86_ERR_FUNC_PARAM_REG_MASK,
        x86_virtual_inst_status[1u],
        count,
        x86_virtual_inst_status[2u],
        count);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    uint count = ok ? virtual_inst_count() : 0u;

    if (row == 0u)
        publish_status(ok, count);

    if (!ok || row >= count)
        return;

    if (x86_virtual_inst_record[row].z != X86_VINST_PARAM)
        return;

    uint fn_slot = x86_virtual_func_slot[row];
    if (fn_slot >= gParams.n_tokens)
        return;

    uint reg = x86_virtual_inst_args[row].z;
    if (!bitset32_valid_bit(reg))
    {
        publish_stage_error_min_detail4(
            x86_func_param_reg_mask_status,
            X86_ERR_FUNC_PARAM_REG_MASK,
            row);
        return;
    }

    atomic_u32_or(x86_func_param_reg_mask, fn_slot, bitset32_single(reg));
}
