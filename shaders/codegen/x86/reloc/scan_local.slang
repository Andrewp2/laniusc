// x86_64 relocation-record local scan.
//
// This pass flags selected control-transfer instructions that require a
// PC-relative displacement. The following scan/scatter stage materializes the
// compact relocation records consumed by the jump-link/patch pass.

import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint inst_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> select_status;
StructuredBuffer<uint> size_status;
StructuredBuffer<uint> text_status;
StructuredBuffer<uint> x86_inst_kind;
StructuredBuffer<uint> x86_inst_arg0;
StructuredBuffer<uint> x86_inst_arg1;
StructuredBuffer<uint> x86_inst_arg2;

RWStructuredBuffer<uint> x86_reloc_scan_local_prefix;
RWStructuredBuffer<uint> x86_reloc_scan_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint X86_SELECT_OK = 1u;
static const uint X86_SIZE_OK = 1u;
static const uint X86_TEXT_OK = 1u;
static const uint INVALID = 0xffffffffu;

static const uint X86_INST_V_BRANCH_ZERO = 56u;
static const uint X86_INST_V_JMP = 57u;
static const uint X86_INST_V_ENTRY_STACK_JMP = 64u;
static const uint X86_INST_V_FOR_ARRAY_BRANCH = 68u;
static const uint X86_INST_V_FOR_ARRAY_INC_JMP = 70u;
static const uint X86_INST_V_CALL_MIXED_DIRECT = 71u;
static const uint X86_INST_V_CALL_MIXED_EXTERNAL = 124u;
static const uint X86_INST_V_MATCH_TAG_BRANCH = 77u;
static const uint X86_INST_V_FOR_INTERVAL_BRANCH = 78u;
static const uint X86_INST_MOV_ESI_TEXT_ROW_ADDR = 49u;
static const uint X86_INST_V_STORE_LOCAL_RODATA_PTR = 83u;
static const uint X86_INST_V_HOST_TEXT_WRITE = 84u;
static const uint X86_INST_V_HOST_OPEN_WRITE_PATH = 85u;
static const uint X86_INST_V_HOST_OPEN_READ_PATH = 89u;

static const uint X86_AGG_SOURCE_LOCAL = 1u;
static const uint X86_AGG_SOURCE_PARAM = 2u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint inst_kind_tag(uint inst_i)
{
    return x86_inst_kind[inst_i] & 0xffu;
}

bool upstream_ok()
{
    return select_status[0u] == X86_SELECT_OK &&
           select_status[1u] == 0u &&
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
    return upstream_ok() ? min(select_status[3u], gScan.inst_capacity) : 0u;
}

bool inst_target_valid(uint target, uint inst_count)
{
    return target <= inst_count;
}

uint reloc_target_for_inst(uint inst_i, uint inst_count)
{
    uint kind = inst_kind_tag(inst_i);
    uint target = 0xffffffffu;
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
    uint kind = inst_kind_tag(inst_i);
    if (kind == X86_INST_V_CALL_MIXED_EXTERNAL)
        return 1u;
    if (kind == X86_INST_MOV_ESI_TEXT_ROW_ADDR ||
        kind == X86_INST_V_STORE_LOCAL_RODATA_PTR)
        return 1u;
    if (kind == X86_INST_V_HOST_TEXT_WRITE)
        return x86_inst_arg2[inst_i] != INVALID ? 1u : 0u;
    if (kind == X86_INST_V_HOST_OPEN_WRITE_PATH ||
        kind == X86_INST_V_HOST_OPEN_READ_PATH)
    {
        uint source_kind = x86_inst_arg2[inst_i];
        return source_kind != X86_AGG_SOURCE_LOCAL &&
               source_kind != X86_AGG_SOURCE_PARAM ? 1u : 0u;
    }
    uint target = reloc_target_for_inst(inst_i, inst_count);
    return inst_target_valid(target, inst_count) ? 1u : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint count = selected_inst_count();
    uint active_blocks = max(1u, (count + WG_SIZE - 1u) / WG_SIZE);
    uint block_i = linear_group_id(gid);
    if (block_i >= active_blocks)
        return;

    uint lane = ltid.x;
    uint inst_i = block_i * WG_SIZE + lane;
    uint value = inst_i < count ? reloc_flag_for_inst(inst_i, count) : 0u;
    uint inclusive = prefix_scan_u32_256(lane, value);

    if (inst_i < count)
        x86_reloc_scan_local_prefix[inst_i] = inclusive - value;

    if (lane == WG_SIZE - 1u)
        x86_reloc_scan_block_sum[block_i] = inclusive;
}
