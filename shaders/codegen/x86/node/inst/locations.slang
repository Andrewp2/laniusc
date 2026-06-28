// x86_64 per-node virtual instruction locations.
//
// Prefix scanning assigns each executable HIR node a compact instruction range.
// This pass records the first few default local locations and the corrected
// branch/loop locations that intentionally reuse padding slots in child ranges.
// Wider nodes still use their prefix range directly during instruction
// generation.

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

struct FeatureParams
{
    uint mask;
    uint enum_count;
    uint match_count;
    uint aggregate_count;
};

ConstantBuffer<FeatureParams> gX86Features;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> x86_expr_semantic_type;
StructuredBuffer<uint4> x86_match_record;
StructuredBuffer<uint> x86_for_iterable_node;
StructuredBuffer<uint> x86_decl_layout_record;
StructuredBuffer<uint> x86_node_inst_range_start;
StructuredBuffer<uint> x86_node_inst_range_info;
StructuredBuffer<uint> x86_node_inst_same_end_rank;
StructuredBuffer<uint> x86_node_inst_same_end_bucket_count;
StructuredBuffer<uint> x86_node_inst_range_status;

RWStructuredBuffer<uint4> x86_node_inst_location_record;
RWStructuredBuffer<uint> x86_node_inst_location_status;
RWStructuredBuffer<uint> x86_node_inst_gen_flag;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_INST_RANGE_OK = 1u;
static const uint X86_NODE_INST_LOCATIONS_OK = 1u;
static const uint X86_ERR_NODE_INST_LOCATIONS = 16u;
static const uint X86_FEATURE_MATCH = 1u << 1u;
static const uint HIR_PARAM = 4u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_PARAM_RECORD_NAME_TOKEN = 2u;
static const uint HIR_PARAM_RECORD_NODE = 3u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_WHILE = 6u;
static const uint STMT_RECORD_KIND_FOR = 7u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_NEG = 13u;
static const uint X86_NODE_INST_BRANCH = 4u;
static const uint X86_NODE_INST_LOOP = 5u;
static const uint X86_NODE_INST_EXPR_VALUE = 1u;
static const uint X86_NODE_INST_PADDING = 7u;
static const uint X86_NODE_INST_RANGE_KIND_SHIFT = 28u;
static const uint X86_NODE_INST_RANGE_COUNT_MASK = 0x0fffffffu;
static const uint X86_LOCATION_META_KIND_MASK = 0xf0000000u;
static const uint X86_LOCATION_META_EXPR_SEMANTIC_TYPE = 0xe0000000u;
static const uint X86_LOCATION_META_PARAM_DECL = 0xd0000000u;
static const uint X86_LOCATION_META_PAYLOAD_MASK = 0x0fffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint TY_UINT = 4u;
static const uint EXPR_SEMANTIC_UINT_FLAG = 0x40000000u;
static const uint X86_NODE_INST_LOCATION_ERR_BRANCH = 1u;
static const uint X86_NODE_INST_LOCATION_ERR_MATCH = 2u;
static const uint X86_NODE_INST_LOCATION_ERR_LOOP = 3u;
static const uint X86_NODE_INST_LOCATION_ERR_FOR = 4u;
static const uint X86_NODE_INST_LOCATION_ERR_RANGE = 5u;
static const uint X86_NODE_INST_LOCATION_ERR_RANGE_START = 52u;
static const uint X86_NODE_INST_LOCATION_ERR_RANGE_CAPACITY = 53u;
static const uint X86_DECL_LAYOUT_STRIDE = 4u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool has_match_feature()
{
    return (gX86Features.mask & X86_FEATURE_MATCH) != 0u;
}

bool upstream_ok()
{
    return x86_node_inst_range_status[0u] == X86_NODE_INST_RANGE_OK &&
           x86_node_inst_range_status[1u] == 0u &&
           x86_node_inst_range_status[3u] <= gParams.inst_capacity;
}

uint stmt_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint decl_layout_word(uint row, uint slot)
{
    return row_major_load<uint>(
        x86_decl_layout_record,
        row,
        X86_DECL_LAYOUT_STRIDE,
        slot,
        INVALID);
}

uint decl_layout_width(uint row)
{
    return decl_layout_word(row, 1u);
}

uint for_element_width(uint for_node)
{
    if (!valid_node(for_node) ||
        hir_kind[for_node] != HIR_FOR_STMT ||
        stmt_slot(for_node, 0u) != STMT_RECORD_KIND_FOR)
        return 1u;
    uint decl_token = stmt_slot(for_node, 1u);
    uint width = decl_layout_width(decl_token);
    return width == INVALID || width == 0u ? 1u : width;
}

uint expr_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_FORM) : 0u;
}

uint expr_left(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

uint range_count(uint2 range)
{
    return range.y & X86_NODE_INST_RANGE_COUNT_MASK;
}

uint range_kind(uint2 range)
{
    return range.y == INVALID ? INVALID : range.y >> X86_NODE_INST_RANGE_KIND_SHIFT;
}

uint2 node_inst_range_record(uint node)
{
    return uint2(x86_node_inst_range_start[node], x86_node_inst_range_info[node]);
}

void publish_error(uint detail, uint extra)
{
    publish_stage_error_min_detail_extra4(
        x86_node_inst_location_status,
        X86_ERR_NODE_INST_LOCATIONS,
        detail,
        extra);
}

uint4 default_locations(uint start, uint count)
{
    uint4 locations = uint4_fill(INVALID);
    if (count > 0u) locations.x = start;
    if (count > 1u) locations.y = start + 1u;
    if (count > 2u) locations.z = start + 2u;
    if (count > 3u) locations.w = start + 3u;
    return locations;
}

bool range_generates(uint2 range)
{
    uint count = range_count(range);
    return range.x != INVALID &&
           range.y != INVALID &&
           range.x + count <= gParams.inst_capacity;
}

bool locations_generate(uint4 locations)
{
    return (locations.x != INVALID && locations.x < gParams.inst_capacity) ||
           (locations.y != INVALID && locations.y < gParams.inst_capacity) ||
           (locations.z != INVALID && locations.z < gParams.inst_capacity) ||
           ((locations.w & X86_LOCATION_META_KIND_MASK) != X86_LOCATION_META_EXPR_SEMANTIC_TYPE &&
            (locations.w & X86_LOCATION_META_KIND_MASK) != X86_LOCATION_META_PARAM_DECL &&
            locations.w != INVALID &&
            locations.w < gParams.inst_capacity);
}

void store_locations_and_gen_flag(uint node, uint4 locations, uint2 range)
{
    x86_node_inst_location_record[node] = locations;
    x86_node_inst_gen_flag[node] =
        range_generates(range) || locations_generate(locations) ? 1u : 0u;
}

bool padding_location_for_node(uint node, out uint location)
{
    location = INVALID;
    if (!valid_node(node))
        return false;

    uint2 range = node_inst_range_record(node);
    uint count = range_count(range);
    if (range.x == INVALID || range.y == INVALID || count == 0u ||
        range.x + count > gParams.inst_capacity)
        return false;

    location = range.x + count - 1u;
    return location < gParams.inst_capacity;
}

bool trailing_padding_start_for_node(uint node, uint padding_count, out uint location)
{
    location = INVALID;
    if (!valid_node(node) || padding_count == 0u)
        return false;

    uint2 range = node_inst_range_record(node);
    uint count = range_count(range);
    if (range.x == INVALID || range.y == INVALID || count < padding_count ||
        range.x + count > gParams.inst_capacity)
        return false;

    location = range.x + count - padding_count;
    return location < gParams.inst_capacity;
}

uint nth_match_arm_node(uint match_node, uint ordinal)
{
    if (!has_match_feature() || !valid_node(match_node))
        return INVALID;
    uint4 record = x86_match_record[match_node];
    if (ordinal == 0u)
        return record.y;
    if (ordinal == 1u)
        return record.w;
    return INVALID;
}

bool corrected_branch_locations(uint node, out uint4 locations)
{
    locations = uint4_fill(INVALID);
    if (!valid_node(node) ||
        hir_kind[node] != HIR_IF_STMT ||
        stmt_slot(node, 0u) != STMT_RECORD_KIND_IF)
        return false;

    uint cond_node = stmt_slot(node, 1u);
    uint then_node = stmt_slot(node, 2u);
    uint else_node = stmt_slot(node, 3u);
    uint cond_location = INVALID;
    uint then_location = INVALID;
    if (!padding_location_for_node(cond_node, cond_location))
        return false;
    if (valid_node(else_node) && !padding_location_for_node(then_node, then_location))
        return false;

    locations = uint4(cond_location, then_location, INVALID, INVALID);
    return true;
}

bool corrected_loop_locations(uint node, out uint4 locations)
{
    locations = uint4_fill(INVALID);
    if (!valid_node(node) ||
        hir_kind[node] != HIR_WHILE_STMT ||
        stmt_slot(node, 0u) != STMT_RECORD_KIND_WHILE)
        return false;

    uint cond_node = stmt_slot(node, 1u);
    uint body_node = stmt_slot(node, 2u);
    uint cond_location = INVALID;
    uint body_location = INVALID;
    if (!padding_location_for_node(cond_node, cond_location) ||
        !padding_location_for_node(body_node, body_location))
        return false;

    locations = uint4(cond_location, body_location, INVALID, INVALID);
    return true;
}

bool corrected_for_locations(uint node, out uint4 locations)
{
    locations = uint4_fill(INVALID);
    if (!valid_node(node) ||
        hir_kind[node] != HIR_FOR_STMT ||
        stmt_slot(node, 0u) != STMT_RECORD_KIND_FOR)
        return false;

    uint iterable_node = valid_node(node) ? x86_for_iterable_node[node] : INVALID;
    uint body_node = stmt_slot(node, 3u);
    uint load_count = for_element_width(node);
    uint iterable_padding_count = 2u + load_count;
    uint iterable_padding = INVALID;
    uint body_location = INVALID;
    if (!trailing_padding_start_for_node(iterable_node, iterable_padding_count, iterable_padding) ||
        iterable_padding + 1u + load_count >= gParams.inst_capacity ||
        !padding_location_for_node(body_node, body_location))
        return false;

    locations = uint4(iterable_padding, iterable_padding + 1u, iterable_padding + 2u, body_location);
    return true;
}

bool corrected_match_return_locations(uint node, out uint4 locations)
{
    locations = uint4_fill(INVALID);
    if (!has_match_feature() || !valid_node(node) || hir_kind[node] != HIR_MATCH_EXPR)
        return false;

    uint4 match_record = x86_match_record[node];
    if (!valid_node(match_record.x) || match_record.z != 2u)
        return false;

    uint arm0 = nth_match_arm_node(node, 0u);
    uint arm1 = nth_match_arm_node(node, 1u);
    if (!valid_node(arm0) || !valid_node(arm1))
        return false;

    uint result0 = resolve_expr(x86_match_record[arm0].w);
    uint result1 = resolve_expr(x86_match_record[arm1].w);
    uint branch_location = INVALID;
    uint return0_location = INVALID;
    uint return1_location = INVALID;
    if (!padding_location_for_node(match_record.x, branch_location) ||
        !padding_location_for_node(result0, return0_location) ||
        !padding_location_for_node(result1, return1_location))
        return false;

    locations = uint4(branch_location, return0_location, return1_location, INVALID);
    return true;
}

bool binary_expr_form(uint form)
{
    return form >= HIR_EXPR_EQ && form <= HIR_EXPR_SHR && form != HIR_EXPR_NEG;
}

bool compare_expr_form(uint form)
{
    return form == HIR_EXPR_LT ||
           form == HIR_EXPR_GT ||
           form == HIR_EXPR_LE ||
           form == HIR_EXPR_GE;
}

bool semantic_metadata_expr_form(uint form)
{
    return compare_expr_form(form) ||
           form == HIR_EXPR_MOD ||
           form == HIR_EXPR_DIV;
}

uint pack_expr_semantic_type_metadata(uint ty)
{
    return X86_LOCATION_META_EXPR_SEMANTIC_TYPE |
           (ty & X86_LOCATION_META_PAYLOAD_MASK);
}

uint pack_param_decl_metadata(uint decl_token)
{
    return X86_LOCATION_META_PARAM_DECL |
           (decl_token & X86_LOCATION_META_PAYLOAD_MASK);
}

uint param_node_decl_token(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_PARAM)
        return INVALID;
    uint4 record = hir_param_record[node];
    if (record[HIR_PARAM_RECORD_NODE] != node)
        return INVALID;
    uint decl_token = record[HIR_PARAM_RECORD_NAME_TOKEN];
    return valid_token(decl_token) ? decl_token : INVALID;
}

uint4 attach_param_decl_metadata(uint node, uint4 locations)
{
    if (!valid_node(node) || hir_kind[node] != HIR_PARAM || locations.w != INVALID)
        return locations;

    uint decl_token = param_node_decl_token(node);
    if (!valid_token(decl_token) || decl_token > X86_LOCATION_META_PAYLOAD_MASK)
        return locations;

    locations.w = pack_param_decl_metadata(decl_token);
    return locations;
}

uint expr_semantic_compare_type(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;
    uint record = x86_expr_semantic_type[node];
    return (record & EXPR_SEMANTIC_UINT_FLAG) != 0u ? TY_UINT : TY_UNKNOWN;
}

uint4 attach_expr_semantic_type_metadata(uint node, uint4 locations)
{
    if (!valid_node(node) || locations.w != INVALID)
        return locations;

    bool can_attach =
        (hir_kind[node] == HIR_BINARY_EXPR && semantic_metadata_expr_form(expr_form(node))) ||
        hir_kind[node] == HIR_INDEX_EXPR ||
        hir_kind[node] == HIR_MEMBER_EXPR;
    if (!can_attach)
        return locations;

    uint ty = expr_semantic_compare_type(node);
    if (ty == INVALID)
        return locations;

    locations.w = pack_expr_semantic_type_metadata(ty);
    return locations;
}

bool corrected_binary_expr_location(uint node, out uint4 locations)
{
    locations = uint4_fill(INVALID);
    uint form = expr_form(node);
    if (!valid_node(node) ||
        hir_kind[node] != HIR_BINARY_EXPR ||
        !binary_expr_form(form))
        return false;

    uint2 range = node_inst_range_record(node);
    if (range_kind(range) != X86_NODE_INST_EXPR_VALUE ||
        range_count(range) != 1u ||
        range.x == INVALID)
        return false;

    uint bucket_count = x86_node_inst_same_end_bucket_count[node];
    uint rank = x86_node_inst_same_end_rank[node];
    if (bucket_count <= 1u || rank >= bucket_count)
        return false;

    uint old_offset = bucket_count - 1u - rank;
    if (range.x < old_offset)
        return false;
    uint base = range.x - old_offset;
    uint location = base + rank;
    if (location >= gParams.inst_capacity)
        return false;

    locations = uint4(location, INVALID, INVALID, INVALID);
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    if (node == 0u)
    {
        x86_node_inst_gen_flag[active_hir_node_count()] = 0u;
        x86_node_inst_location_status[0u] = ok ? X86_NODE_INST_LOCATIONS_OK : 0u;
        x86_node_inst_location_status[1u] = ok ? 0u :
                                          (x86_node_inst_range_status[1u] == 0u ?
                                           X86_ERR_NODE_INST_LOCATIONS :
                                           x86_node_inst_range_status[1u]);
        x86_node_inst_location_status[2u] = ok ? INVALID :
                                          (x86_node_inst_range_status[1u] == 0u ?
                                           x86_node_inst_range_status[3u] :
                                           x86_node_inst_range_status[2u]);
        x86_node_inst_location_status[3u] = ok ? x86_node_inst_range_status[3u] : 0u;
    }

    if (node < gParams.n_hir_nodes)
        x86_node_inst_gen_flag[node] = 0u;

    if (!ok || !valid_node(node))
        return;

    uint2 range = node_inst_range_record(node);
    if (range.y == INVALID)
    {
        store_locations_and_gen_flag(node, uint4_fill(INVALID), range);
        return;
    }
    uint count = range_count(range);
    uint kind = range_kind(range);

    if (hir_kind[node] == HIR_IF_STMT && kind == X86_NODE_INST_BRANCH)
    {
        uint4 branch_locations = uint4_fill(INVALID);
        if (corrected_branch_locations(node, branch_locations))
        {
            store_locations_and_gen_flag(node, branch_locations, range);
            return;
        }
        publish_error(node, X86_NODE_INST_LOCATION_ERR_BRANCH);
        return;
    }

    if (has_match_feature() && hir_kind[node] == HIR_MATCH_EXPR && kind == X86_NODE_INST_BRANCH)
    {
        uint4 match_locations = uint4_fill(INVALID);
        if (corrected_match_return_locations(node, match_locations))
        {
            store_locations_and_gen_flag(node, match_locations, range);
            return;
        }
        publish_error(node, X86_NODE_INST_LOCATION_ERR_MATCH);
        return;
    }

    if (hir_kind[node] == HIR_WHILE_STMT && kind == X86_NODE_INST_LOOP)
    {
        uint4 loop_locations = uint4_fill(INVALID);
        if (corrected_loop_locations(node, loop_locations))
        {
            store_locations_and_gen_flag(node, loop_locations, range);
            return;
        }
        publish_error(node, X86_NODE_INST_LOCATION_ERR_LOOP);
        return;
    }

    if (hir_kind[node] == HIR_FOR_STMT && kind == X86_NODE_INST_LOOP)
    {
        uint4 for_locations = uint4_fill(INVALID);
        if (corrected_for_locations(node, for_locations))
        {
            store_locations_and_gen_flag(node, for_locations, range);
            return;
        }
        publish_error(node, X86_NODE_INST_LOCATION_ERR_FOR);
        return;
    }

    if (count == 0u)
    {
        store_locations_and_gen_flag(
            node,
            attach_param_decl_metadata(node, uint4_fill(INVALID)),
            range);
        return;
    }

    if (range.x == INVALID || range.y == INVALID || range.x + count > gParams.inst_capacity)
    {
        store_locations_and_gen_flag(node, uint4_fill(INVALID), range);
        uint reason = range.x == INVALID || range.y == INVALID
                          ? X86_NODE_INST_LOCATION_ERR_RANGE_START +
                                min(x86_node_inst_same_end_bucket_count[node], 99u) * 100u +
                                min(x86_node_inst_same_end_rank[node], 99u) * 10000u
                          : X86_NODE_INST_LOCATION_ERR_RANGE_CAPACITY;
        publish_error(node, reason);
        return;
    }

    uint4 binary_locations = uint4_fill(INVALID);
    if (corrected_binary_expr_location(node, binary_locations))
    {
        store_locations_and_gen_flag(
            node,
            attach_expr_semantic_type_metadata(node, binary_locations),
            range);
        return;
    }

    uint4 locations = default_locations(range.x, count);
    locations = attach_expr_semantic_type_metadata(node, locations);
    locations = attach_param_decl_metadata(node, locations);
    store_locations_and_gen_flag(node, locations, range);
}
