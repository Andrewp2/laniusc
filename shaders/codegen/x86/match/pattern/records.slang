// x86_64 match-pattern candidate projection.
//
// This pass augments parser-owned match arm records without scanning each arm's
// pattern subtree from the arm thread. It runs one thread per HIR node, consumes
// precomputed nearest pattern-owner records, and publishes first-use,
// first-variant, and first-payload candidate nodes for a later arm-local
// finalizer.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
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

struct HirVariant { uint owner; uint name_token; uint ordinal; uint file_id; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> x86_match_pattern_dense_owner;
StructuredBuffer<uint> x86_match_pattern_root_owner;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint4> x86_match_arm_record;

RWStructuredBuffer<uint> x86_match_pattern_node_variant;
RWStructuredBuffer<uint> x86_match_pattern_node_payload_decl;
RWStructuredBuffer<uint> x86_match_pattern_node_owner;
RWStructuredBuffer<uint> x86_match_pattern_first_use_node;
RWStructuredBuffer<uint> x86_match_pattern_first_variant_node;
RWStructuredBuffer<uint> x86_match_pattern_first_payload_node;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_FEATURE_MATCH = 1u << 1u;
static const uint MATCH_ARM_VARIANT_UNKNOWN = 0xffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;

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

uint active_arm_count()
{
    return min(compact_match_arm_count[0u], gParams.n_hir_nodes);
}

bool valid_arm(uint arm)
{
    return arm != INVALID && arm < active_arm_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool has_match_feature()
{
    return (gX86Features.mask & X86_FEATURE_MATCH) != 0u;
}

uint active_decl_count()
{
    return min(decl_count_out[0u], gParams.n_hir_nodes);
}

uint active_path_count()
{
    return min(path_count_out[0u], gParams.n_hir_nodes);
}

uint active_variant_count()
{
    return min(compact_variant_count[0u], gParams.n_hir_nodes);
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

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint node_token(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint token = hir_token_pos[node];
    return valid_token(token) ? token : INVALID;
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

uint callee_token_for_call(uint call_node)
{
    uint callee_node = resolve_expr(hir_call_callee_node[call_node]);
    return valid_node(callee_node) ? expr_value_token(callee_node) : INVALID;
}

uint path_node_for_pattern_node(uint node)
{
    if (hir_kind[node] == HIR_PATH_EXPR)
        return node;
    if (hir_kind[node] == HIR_CALL_EXPR)
    {
        uint callee_node = resolve_expr(hir_call_callee_node[node]);
        if (valid_node(callee_node) && hir_kind[callee_node] == HIR_PATH_EXPR)
            return callee_node;
    }
    return INVALID;
}

uint semantic_use_token_for_pattern_node(uint node)
{
    if (hir_kind[node] == HIR_NAME_EXPR)
    {
        uint token = expr_value_token(node);
        return valid_token(token) ? token : node_token(node);
    }
    if (hir_kind[node] == HIR_PATH_EXPR)
        return node_token(node);
    if (hir_kind[node] == HIR_CALL_EXPR)
    {
        uint token = callee_token_for_call(node);
        if (valid_token(token))
            return token;
        uint callee_node = resolve_expr(hir_call_callee_node[node]);
        return node_token(callee_node);
    }
    return INVALID;
}

bool variant_ordinal_from_decl(uint decl_i, out uint ordinal)
{
    ordinal = INVALID;
    uint decl_count = active_decl_count();
    if (decl_i >= decl_count || decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;

    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= decl_count || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;

    uint variant_node = decl_hir_node[decl_i];
    if (variant_node >= active_variant_count())
        return false;

    ordinal = compact_variants[variant_node].ordinal;
    return ordinal < MATCH_ARM_VARIANT_UNKNOWN;
}

bool variant_ordinal_from_decl_token(uint decl_token, out uint ordinal)
{
    ordinal = INVALID;
    if (!valid_token(decl_token))
        return false;

    return variant_ordinal_from_decl(decl_id_by_name_token[decl_token], ordinal);
}

bool variant_ordinal_for_use_token(uint use_token, out uint ordinal)
{
    ordinal = INVALID;
    if (!valid_token(use_token))
        return false;
    return variant_ordinal_from_decl_token(visible_decl[use_token], ordinal);
}

bool variant_ordinal_for_path_node(uint path_node, out uint ordinal)
{
    ordinal = INVALID;
    if (!valid_node(path_node))
        return false;

    uint dense = raw_to_compact_hir[path_node];
    uint path_i = dense < gParams.n_hir_nodes
                      ? path_id_by_owner_hir[dense]
                      : INVALID;
    if (path_i >= active_path_count() ||
        resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return false;
    return variant_ordinal_from_decl(resolved_value_decl[path_i], ordinal);
}

bool pattern_node_variant_ordinal(uint node, out uint ordinal, out bool found_use_token)
{
    ordinal = INVALID;
    found_use_token = false;

    uint path_node = path_node_for_pattern_node(node);
    if (valid_node(path_node))
    {
        found_use_token = true;
        if (variant_ordinal_for_path_node(path_node, ordinal))
            return true;
        uint use_token = semantic_use_token_for_pattern_node(path_node);
        return variant_ordinal_for_use_token(use_token, ordinal);
    }

    uint use_token = semantic_use_token_for_pattern_node(node);
    if (!valid_token(use_token))
        return false;

    found_use_token = true;
    return variant_ordinal_for_use_token(use_token, ordinal);
}

uint pattern_node_payload_decl(uint node)
{
    uint use_token = semantic_use_token_for_pattern_node(node);
    if (!valid_token(use_token) || visible_decl[use_token] != use_token)
        return INVALID;

    uint ordinal = INVALID;
    if (variant_ordinal_for_use_token(use_token, ordinal))
        return INVALID;

    return use_token;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;
    if (!has_match_feature())
        return;

    x86_match_pattern_node_variant[node] = MATCH_ARM_VARIANT_UNKNOWN;
    x86_match_pattern_node_payload_decl[node] = INVALID;

    uint dense = raw_to_compact_hir[node];
    uint arm = dense != INVALID && dense < gParams.n_hir_nodes
        ? x86_match_pattern_dense_owner[dense]
        : INVALID;
    if (valid_arm(arm) && x86_match_pattern_root_owner[dense] != arm)
    {
        uint pattern = x86_match_arm_record[arm].x;
        if (pattern == INVALID || pattern >= gParams.n_hir_nodes)
            arm = INVALID;
        else
        {
            uint end = compact_hir_links[pattern].subtree_end;
            HirCore pattern_core = compact_hir_core[pattern];
            HirCore node_core = compact_hir_core[dense];
            if (dense < pattern || end == INVALID || dense >= end ||
                node_core.token_start < pattern_core.token_start ||
                node_core.token_end > pattern_core.token_end)
                arm = INVALID;
        }
    }
    x86_match_pattern_node_owner[node] = arm;
    if (!valid_arm(arm))
        return;

    uint ordinal = INVALID;
    bool found_use_token = false;
    if (pattern_node_variant_ordinal(node, ordinal, found_use_token))
    {
        x86_match_pattern_node_variant[node] = ordinal;
        atomic_u32_min(x86_match_pattern_first_variant_node, arm, node);
    }
    if (found_use_token)
        atomic_u32_min(x86_match_pattern_first_use_node, arm, node);

    uint payload_decl = pattern_node_payload_decl(node);
    if (valid_token(payload_decl))
    {
        x86_match_pattern_node_payload_decl[node] = payload_decl;
        atomic_u32_min(x86_match_pattern_first_payload_node, arm, node);
    }
}
