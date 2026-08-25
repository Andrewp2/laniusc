// Resolves the nearest preceding definition for declaration reads within one
// basic block. Each workgroup owns one declaration; its lanes own contiguous
// slices so the carry between slices is a small associative scan rather than a
// serial function walk. Reads unresolved at a block entry remain INVALID for
// the cross-CFG propagation stage.

import codegen.optimization_ir;
import gpu_index;
import prefix_scan;

StructuredBuffer<uint> opt_ir_access_group_total;
StructuredBuffer<OptIrAccessGroup> opt_ir_access_groups;
StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_kinds;
StructuredBuffer<uint> opt_ir_access_order;
RWStructuredBuffer<uint> opt_ir_local_definition_by_access;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

public struct DefinitionSummary
{
    uint first_block;
    uint last_block;
    uint last_definition;
    uint valid;
};

public struct DefinitionSummaryScan : IPrefixScanOp<DefinitionSummary>
{
    public static DefinitionSummary identity()
    {
        DefinitionSummary result;
        result.first_block = INVALID;
        result.last_block = INVALID;
        result.last_definition = INVALID;
        result.valid = 0u;
        return result;
    }

    public static DefinitionSummary combine(
        DefinitionSummary left,
        DefinitionSummary right)
    {
        if (left.valid == 0u) return right;
        if (right.valid == 0u) return left;

        DefinitionSummary result;
        result.first_block = left.first_block;
        result.last_block = right.last_block;
        result.last_definition = right.last_definition;
        if (result.last_definition == INVALID &&
            right.first_block == right.last_block &&
            left.last_block == right.first_block)
            result.last_definition = left.last_definition;
        result.valid = 1u;
        return result;
    }
};

groupshared DefinitionSummary lane_summaries[256];

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

bool is_definition(uint kind)
{
    return kind == OPT_IR_ACCESS_PARAMETER_DEFINITION ||
        kind == OPT_IR_ACCESS_DECLARATION_WRITE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group_id = linear_group_id(gid);
    uint group_total = opt_ir_access_group_total[0u];
    if (group_id >= group_total) return;

    OptIrAccessGroup group = opt_ir_access_groups[group_id];
    uint access_total = opt_ir_access_total[0u];
    uint rows_per_lane = group.count / WG_SIZE;
    if (group.count % WG_SIZE != 0u) rows_per_lane += 1u;
    uint begin = min(group.start + ltid.x * rows_per_lane,
        group.start + group.count);
    uint end = min(begin + rows_per_lane, group.start + group.count);

    DefinitionSummary summary = DefinitionSummaryScan.identity();
    uint block = INVALID;
    uint definition = INVALID;
    for (uint order_i = begin; order_i < end; ++order_i)
    {
        uint access_id = opt_ir_access_order[order_i];
        if (access_id >= access_total) continue;
        OptIrAccessCore access = opt_ir_accesses[access_id];
        uint kind = opt_ir_access_kinds[access_id];
        if (summary.valid == 0u)
        {
            summary.first_block = access.block_id;
            summary.valid = 1u;
        }
        if (access.block_id != block)
        {
            block = access.block_id;
            definition = INVALID;
        }
        if (is_definition(kind)) definition = access_id;
        opt_ir_local_definition_by_access[access_id] =
            kind == OPT_IR_ACCESS_DECLARATION_READ ? definition :
            is_definition(kind) ? access_id : INVALID;
        summary.last_block = block;
        summary.last_definition = definition;
    }

    DefinitionSummary inclusive = prefix_scan_inclusive<
        DefinitionSummary, DefinitionSummaryScan, 256>(
            ltid.x, summary, lane_summaries);
    DefinitionSummary prior = ltid.x == 0u
        ? DefinitionSummaryScan.identity()
        : lane_summaries[ltid.x - 1u];
    uint carry = prior.valid != 0u && summary.valid != 0u &&
        prior.last_block == summary.first_block
        ? prior.last_definition : INVALID;
    uint first_block = summary.first_block;
    for (uint order_i = begin; order_i < end && carry != INVALID; ++order_i)
    {
        uint access_id = opt_ir_access_order[order_i];
        if (access_id >= access_total) continue;
        OptIrAccessCore access = opt_ir_accesses[access_id];
        if (access.block_id != first_block) break;
        uint kind = opt_ir_access_kinds[access_id];
        if (is_definition(kind)) break;
        if (kind == OPT_IR_ACCESS_DECLARATION_READ)
            opt_ir_local_definition_by_access[access_id] = carry;
    }
}
