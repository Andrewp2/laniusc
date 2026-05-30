// x86_64 compact relocation records.
//
// Selection records still carry target instruction indices. This pass turns
// control-transfer instructions into dense relocation rows using the scanned
// relocation flags, giving jump linking a GPU record artifact instead of
// leaving target discovery local to byte encoding.

import gpu_index;
import prefix_scan;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;
ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> select_status;
StructuredBuffer<uint> size_status;
StructuredBuffer<uint> text_status;
StructuredBuffer<uint> x86_inst_kind;
StructuredBuffer<uint> x86_inst_arg0;
StructuredBuffer<uint> x86_inst_arg1;
StructuredBuffer<uint> x86_inst_arg2;
StructuredBuffer<uint> x86_reloc_scan_local_prefix;
StructuredBuffer<uint> x86_reloc_scan_block_prefix;

RWStructuredBuffer<uint> x86_reloc_count;
RWStructuredBuffer<uint> x86_reloc_kind;
RWStructuredBuffer<uint> x86_reloc_site_inst;
RWStructuredBuffer<uint> x86_reloc_target_inst;
RWStructuredBuffer<uint> reloc_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WG_SIZE = 256u;
static const uint INVALID = 0xffffffffu;
static const uint X86_SELECT_OK = 1u;
static const uint X86_SIZE_OK = 1u;
static const uint X86_TEXT_OK = 1u;
static const uint X86_RELOC_OK = 1u;
static const uint X86_ERR_RELOC = 8u;

static const uint X86_INST_V_BRANCH_ZERO = 56u;
static const uint X86_INST_V_JMP = 57u;
static const uint X86_INST_V_ENTRY_STACK_JMP = 64u;
static const uint X86_INST_V_FOR_ARRAY_BRANCH = 68u;
static const uint X86_INST_V_FOR_ARRAY_INC_JMP = 70u;
static const uint X86_INST_V_CALL_MIXED_DIRECT = 71u;
static const uint X86_INST_V_MATCH_TAG_BRANCH = 77u;
static const uint X86_INST_V_FOR_INTERVAL_BRANCH = 78u;

static const uint X86_RELOC_REL32 = 1u;
static const uint X86_RELOC_CALL_REL32 = 2u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint inst_kind_tag(uint inst_i)
{
    return x86_inst_kind[inst_i] & 0xffu;
}

bool upstream_ok()
{
    return select_status[0u] == X86_SELECT_OK &&
           select_status[1u] == 0u &&
           select_status[3u] <= gParams.inst_capacity &&
           select_status[3u] <= gScan.inst_capacity &&
           size_status[0u] == X86_SIZE_OK &&
           size_status[1u] == 0u &&
           size_status[3u] == select_status[3u] &&
           text_status[0u] == X86_TEXT_OK &&
           text_status[1u] == 0u &&
           text_status[3u] == select_status[3u];
}

uint selected_inst_count()
{
    return upstream_ok() ? min(select_status[3u], gParams.inst_capacity) : 0u;
}

bool inst_target_valid(uint target, uint inst_count)
{
    return target <= inst_count;
}

uint reloc_kind_for_inst(uint inst_i)
{
    uint kind = inst_kind_tag(inst_i);
    if (kind == X86_INST_V_CALL_MIXED_DIRECT)
        return X86_RELOC_CALL_REL32;
    if (kind == X86_INST_V_BRANCH_ZERO ||
        kind == X86_INST_V_JMP ||
        kind == X86_INST_V_ENTRY_STACK_JMP ||
        kind == X86_INST_V_FOR_ARRAY_BRANCH ||
        kind == X86_INST_V_FOR_ARRAY_INC_JMP ||
        kind == X86_INST_V_MATCH_TAG_BRANCH ||
        kind == X86_INST_V_FOR_INTERVAL_BRANCH)
        return X86_RELOC_REL32;
    return 0u;
}

uint reloc_target_for_inst(uint inst_i, uint inst_count)
{
    uint kind = inst_kind_tag(inst_i);
    uint target = INVALID;
    if (kind == X86_INST_V_BRANCH_ZERO)
        target = x86_inst_arg1[inst_i];
    if (kind == X86_INST_V_JMP ||
        kind == X86_INST_V_ENTRY_STACK_JMP ||
        kind == X86_INST_V_CALL_MIXED_DIRECT)
        target = x86_inst_arg0[inst_i];
    if (kind == X86_INST_V_FOR_ARRAY_BRANCH ||
        kind == X86_INST_V_FOR_INTERVAL_BRANCH ||
        kind == X86_INST_V_MATCH_TAG_BRANCH)
        target = x86_inst_arg2[inst_i];
    if (kind == X86_INST_V_FOR_ARRAY_INC_JMP)
        target = x86_inst_arg1[inst_i];
    return target;
}

uint reloc_flag_for_inst(uint inst_i, uint inst_count)
{
    uint reloc_kind = reloc_kind_for_inst(inst_i);
    uint target = reloc_target_for_inst(inst_i, inst_count);
    return reloc_kind != 0u && inst_target_valid(target, inst_count) ? 1u : 0u;
}

uint scanned_prefix_for_inst(uint inst_i)
{
    return global_exclusive_prefix(
        inst_i,
        WG_SIZE,
        x86_reloc_scan_local_prefix,
        x86_reloc_scan_block_prefix);
}

uint reloc_total(uint inst_count)
{
    if (inst_count == 0u)
        return 0u;
    uint last_inst = inst_count - 1u;
    return scanned_prefix_for_inst(last_inst) + reloc_flag_for_inst(last_inst, inst_count);
}

uint upstream_error_or_reloc()
{
    if (select_status[1u] != 0u)
        return select_status[1u];
    if (size_status[1u] != 0u)
        return size_status[1u];
    if (text_status[1u] != 0u)
        return text_status[1u];
    return X86_ERR_RELOC;
}

uint upstream_detail_or_zero()
{
    if (select_status[1u] != 0u)
        return select_status[2u];
    if (size_status[1u] != 0u)
        return size_status[2u];
    if (text_status[1u] != 0u)
        return text_status[2u];
    return 0u;
}

void publish_status(bool ok, uint total)
{
    reloc_status[0u] = ok ? X86_RELOC_OK : 0u;
    reloc_status[1u] = ok ? 0u : upstream_error_or_reloc();
    reloc_status[2u] = ok ? INVALID : upstream_detail_or_zero();
    reloc_status[3u] = ok ? total : 0u;
    x86_reloc_count[0u] = ok ? total : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint inst_i = linear_dispatch_id(tid);
    uint inst_count = selected_inst_count();
    uint total = upstream_ok() ? reloc_total(inst_count) : 0u;
    bool ok = upstream_ok() && total <= gParams.inst_capacity;

    if (inst_i == 0u)
        publish_status(ok, total);

    if (!ok || inst_i >= inst_count || reloc_flag_for_inst(inst_i, inst_count) == 0u)
        return;

    uint ordinal = scanned_prefix_for_inst(inst_i);
    if (ordinal >= gParams.inst_capacity)
    {
        publish_stage_error_min_detail4(reloc_status, X86_ERR_RELOC, inst_i);
        return;
    }

    x86_reloc_kind[ordinal] = reloc_kind_for_inst(inst_i);
    x86_reloc_site_inst[ordinal] = inst_i;
    x86_reloc_target_inst[ordinal] = reloc_target_for_inst(inst_i, inst_count);
}
