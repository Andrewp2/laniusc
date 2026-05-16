// GPU match payload type substitution.
//
// The previous pattern pass establishes arm-local declaration links from the
// module resolver. This pass walks HIR match spans and fills visible_type for
// tuple payload binders and their uses with the substituted enum payload type.

import utils;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> visible_type;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_TYPE_SCAN = 64u;

static const uint HIR_MATCH_EXPR = 34u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TK_IDENT = 1u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_FN = 67u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_ENUM = 93u;
static const uint TK_MATCH = 95u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint token_kind(uint i)
{
    return i < active_token_count() ? token_words[i].kind : 0u;
}

bool is_name_kind(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT;
}

bool is_group_open_kind(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN;
}

bool is_group_close_kind(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN;
}

bool is_bracket_open_kind(uint kind)
{
    return kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET;
}

bool is_bracket_close_kind(uint kind)
{
    return kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET;
}

bool same_name(uint a, uint b)
{
    if (a >= active_token_count() || b >= active_token_count())
        return false;
    uint left = name_id_by_token[a];
    uint right = name_id_by_token[b];
    return left != INVALID && left == right;
}

uint find_group_close(uint open_i, uint limit_i)
{
    uint n = min(active_token_count(), limit_i);
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            depth += 1u;
        else if (is_group_close_kind(kind))
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return j;
        }
    }
    return INVALID;
}

uint find_match_brace_close(uint open_i, uint limit_i)
{
    uint n = min(active_token_count(), limit_i);
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
            depth += 1u;
        else if (kind == TK_RBRACE)
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return j;
        }
    }
    return INVALID;
}

uint find_arm_arrow(uint pattern_i, uint limit_i)
{
    uint group_depth = 0u;
    uint bracket_depth = 0u;
    uint n = min(active_token_count(), limit_i);
    [loop]
    for (uint j = pattern_i; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (is_bracket_open_kind(kind))
            bracket_depth += 1u;
        else if (is_bracket_close_kind(kind) && bracket_depth > 0u)
            bracket_depth -= 1u;
        else if (group_depth == 0u && bracket_depth == 0u && kind == TK_ARROW)
            return j;
        else if (group_depth == 0u && bracket_depth == 0u &&
                 (kind == TK_COMMA || kind == TK_RBRACE))
            return INVALID;
    }
    return INVALID;
}

uint arm_result_end(uint result_i, uint limit_i)
{
    uint group_depth = 0u;
    uint bracket_depth = 0u;
    uint brace_depth = 0u;
    uint n = min(active_token_count(), limit_i);
    [loop]
    for (uint j = result_i; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (is_bracket_open_kind(kind))
            bracket_depth += 1u;
        else if (is_bracket_close_kind(kind) && bracket_depth > 0u)
            bracket_depth -= 1u;
        else if (kind == TK_LBRACE)
            brace_depth += 1u;
        else if (kind == TK_RBRACE)
        {
            if (brace_depth == 0u && group_depth == 0u && bracket_depth == 0u)
                return j;
            if (brace_depth > 0u)
                brace_depth -= 1u;
        }
        else if (kind == TK_COMMA && group_depth == 0u && bracket_depth == 0u &&
                 brace_depth == 0u)
            return j;
    }
    return n;
}

uint generic_param_list_open(uint item_i)
{
    uint n = active_token_count();
    uint limit = min(n, item_i + MAX_TYPE_SCAN);
    [loop]
    for (uint j = item_i + 1u; j < limit; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            return j;
        if (kind == TK_LBRACE || kind == TK_LPAREN || kind == TK_SEMICOLON)
            return INVALID;
    }
    return INVALID;
}

uint generic_param_list_close(uint open_i)
{
    if (open_i == INVALID)
        return INVALID;

    uint n = active_token_count();
    uint limit = min(n, open_i + MAX_TYPE_SCAN);
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < limit; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            depth += 1u;
        else if (kind == TK_GT)
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return j;
        }
        else if (kind == TK_LBRACE || kind == TK_SEMICOLON)
            return INVALID;
    }
    return INVALID;
}

bool is_type_generic_param_token(uint param_i, uint open_i, uint close_i)
{
    return param_i > open_i && param_i < close_i && is_name_kind(token_kind(param_i));
}

uint generic_param_slot(uint decl_i, uint param_i)
{
    uint open_i = generic_param_list_open(decl_i);
    uint close_i = generic_param_list_close(open_i);
    if (open_i == INVALID || close_i == INVALID)
        return INVALID;

    uint slot = 0u;
    [loop]
    for (uint p = open_i + 1u; p < close_i; p += 1u)
    {
        if (!is_type_generic_param_token(p, open_i, close_i))
            continue;
        if (same_name(p, param_i))
            return slot;
        slot += 1u;
    }
    return INVALID;
}

uint generic_param_decl_for_use(uint name_i)
{
    uint j = name_i;
    [loop]
    for (uint guard = 0u; guard < 256u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind != TK_FN && kind != TK_ENUM)
            continue;

        uint open_i = generic_param_list_open(j);
        if (open_i == INVALID)
            continue;
        uint close_i = generic_param_list_close(open_i);
        if (close_i == INVALID)
            continue;
        [loop]
        for (uint p = open_i + 1u; p < close_i; p += 1u)
        {
            if (is_type_generic_param_token(p, open_i, close_i) && same_name(p, name_i))
                return p;
        }
    }
    return INVALID;
}

uint find_matching_gt(uint lt_i)
{
    uint depth = 0u;
    [loop]
    for (uint j = lt_i; j < active_token_count(); j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            depth += 1u;
        else if (kind == TK_GT)
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return j;
        }
        else if (kind == TK_LBRACE || kind == TK_SEMICOLON)
            return INVALID;
    }
    return INVALID;
}

uint top_level_type_arg_head(uint lt_i, uint gt_i, uint slot)
{
    uint current_slot = 0u;
    uint nested_angle = 0u;
    uint nested_array = 0u;
    uint candidate = lt_i + 1u;
    [loop]
    for (uint j = lt_i + 1u; j < gt_i; j += 1u)
    {
        if (current_slot == slot)
            return candidate;
        uint kind = token_kind(j);
        if (kind == TK_LT)
            nested_angle += 1u;
        else if (kind == TK_GT && nested_angle > 0u)
            nested_angle -= 1u;
        else if (is_bracket_open_kind(kind))
            nested_array += 1u;
        else if (is_bracket_close_kind(kind) && nested_array > 0u)
            nested_array -= 1u;
        else if (kind == TK_COMMA && nested_angle == 0u && nested_array == 0u)
        {
            current_slot += 1u;
            candidate = j + 1u;
        }
    }
    return current_slot == slot ? candidate : INVALID;
}

uint type_ref_to_type_code(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint decl_i = generic_param_decl_for_use(payload);
        return decl_i == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + decl_i;
    }
    return TY_UNKNOWN;
}

void substituted_ref(uint instance_i, uint enum_token, uint type_head, out uint tag, out uint payload)
{
    tag = type_expr_ref_tag[type_head];
    payload = type_expr_ref_payload[type_head];
    if (tag != TYPE_REF_GENERIC_PARAM)
        return;

    uint decl_i = type_instance_decl_token[instance_i];
    if (decl_i == INVALID || decl_i >= active_token_count())
        decl_i = enum_token;
    uint slot = generic_param_slot(decl_i, payload);
    if (slot == INVALID || slot >= type_instance_arg_count[instance_i])
        return;

    uint arg_i = type_instance_arg_start[instance_i] + slot;
    tag = type_instance_arg_ref_tag[arg_i];
    payload = type_instance_arg_ref_payload[arg_i];
    if (tag != TYPE_REF_INVALID)
        return;

    uint lt_i = instance_i + 1u;
    uint gt_i = token_kind(lt_i) == TK_LT ? find_matching_gt(lt_i) : INVALID;
    uint arg_head = gt_i == INVALID ? INVALID : top_level_type_arg_head(lt_i, gt_i, slot);
    if (arg_head != INVALID)
    {
        tag = type_expr_ref_tag[arg_head];
        payload = type_expr_ref_payload[arg_head];
    }
}

uint scrutinee_instance_for_match(uint match_i)
{
    if (match_i + 1u >= active_token_count() || !is_group_open_kind(token_kind(match_i + 1u)))
        return INVALID;
    uint open_i = match_i + 1u;
    uint close_i = find_group_close(open_i, active_token_count());
    if (close_i == INVALID || open_i + 1u >= close_i)
        return INVALID;

    uint expr_i = open_i + 1u;
    uint decl_i = visible_decl[expr_i];
    if (decl_i == INVALID || decl_i + 2u >= active_token_count())
        return INVALID;
    if (token_kind(decl_i + 1u) != TK_COLON)
        return INVALID;

    uint type_head = decl_i + 2u;
    if (type_expr_ref_tag[type_head] != TYPE_REF_INSTANCE)
        return INVALID;
    return type_expr_ref_payload[type_head];
}

uint enum_variant_payload_type_head(uint variant_token)
{
    if (variant_token + 1u >= active_token_count() ||
        !is_group_open_kind(token_kind(variant_token + 1u)))
        return INVALID;
    return variant_token + 2u;
}

uint enum_body_open(uint enum_token)
{
    uint limit = min(active_token_count(), enum_token + MAX_TYPE_SCAN);
    [loop]
    for (uint j = enum_token + 1u; j < limit; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
            return j;
        if (kind == TK_SEMICOLON || kind == TK_FN)
            return INVALID;
    }
    return INVALID;
}

uint enum_body_close(uint open_i)
{
    if (open_i == INVALID)
        return INVALID;
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < active_token_count(); j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
            depth += 1u;
        else if (kind == TK_RBRACE)
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return j;
        }
    }
    return INVALID;
}

uint find_enum_variant_by_name(uint enum_token, uint pattern_leaf)
{
    uint open_i = enum_body_open(enum_token);
    uint close_i = enum_body_close(open_i);
    if (open_i == INVALID || close_i == INVALID)
        return INVALID;

    uint group_depth = 0u;
    [loop]
    for (uint j = open_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (group_depth == 0u && is_name_kind(kind) && same_name(j, pattern_leaf))
            return j;
    }
    return INVALID;
}

uint find_enum_decl_by_name(uint name_i)
{
    [loop]
    for (uint j = 1u; j + 1u < active_token_count(); j += 1u)
    {
        if (token_kind(j) == TK_ENUM && same_name(j + 1u, name_i))
            return j + 1u;
    }
    return INVALID;
}

uint pattern_payload_type(uint match_i, uint enum_token, uint variant_token)
{
    uint instance_i = scrutinee_instance_for_match(match_i);
    if (instance_i == INVALID)
        return TY_UNKNOWN;
    uint instance_enum = type_instance_decl_token[instance_i];
    if (instance_enum == INVALID || instance_enum >= active_token_count())
        instance_enum = find_enum_decl_by_name(instance_i);
    if (instance_enum != enum_token)
        return TY_UNKNOWN;

    uint payload_type_head = enum_variant_payload_type_head(variant_token);
    if (payload_type_head == INVALID)
        return TY_UNKNOWN;

    uint tag = TYPE_REF_INVALID;
    uint payload = INVALID;
    substituted_ref(instance_i, enum_token, payload_type_head, tag, payload);
    return type_ref_to_type_code(tag, payload);
}

uint leaf_token_for_pattern(uint pattern_i, uint arrow_i)
{
    uint leaf = pattern_i;
    [loop]
    for (uint j = pattern_i; j < arrow_i && j < active_token_count(); j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            return leaf;
        if (is_name_kind(kind))
            leaf = j;
    }
    return leaf;
}

uint first_payload_binding(uint leaf_token)
{
    if (leaf_token + 1u >= active_token_count() || !is_group_open_kind(token_kind(leaf_token + 1u)))
        return INVALID;
    uint close_i = find_group_close(leaf_token + 1u, active_token_count());
    if (close_i == INVALID)
        return INVALID;
    [loop]
    for (uint j = leaf_token + 2u; j < close_i; j += 1u)
    {
        if (is_name_kind(token_kind(j)))
            return j;
    }
    return INVALID;
}

void bind_payload_uses(uint result_start, uint result_end, uint binder_i, uint payload_ty)
{
    visible_decl[binder_i] = binder_i;
    visible_type[binder_i] = payload_ty;
    [loop]
    for (uint j = result_start; j < result_end && j < active_token_count(); j += 1u)
    {
        if (is_name_kind(token_kind(j)) && same_name(j, binder_i))
        {
            visible_decl[j] = binder_i;
            visible_type[j] = payload_ty;
        }
    }
}

void type_payloads(uint match_i, uint end_i)
{
    uint group_close = find_group_close(match_i + 1u, end_i);
    if (group_close == INVALID || group_close + 1u >= end_i)
        return;
    uint brace_open = group_close + 1u;
    if (token_kind(brace_open) != TK_LBRACE)
        return;
    uint brace_close = find_match_brace_close(brace_open, end_i);
    if (brace_close == INVALID)
        return;

    uint arm_i = brace_open + 1u;
    [loop]
    for (uint guard = 0u; guard < 64u && arm_i < brace_close; guard += 1u)
    {
        if (token_kind(arm_i) == TK_COMMA)
        {
            arm_i += 1u;
            continue;
        }

        uint arrow_i = find_arm_arrow(arm_i, brace_close);
        if (arrow_i == INVALID)
            return;

        uint pattern_ty = visible_type[arm_i];
        uint variant_token = visible_decl[arm_i];
        uint leaf_token = leaf_token_for_pattern(arm_i, arrow_i);
        if (pattern_ty < TY_ENUM_BASE)
        {
            uint instance_i = scrutinee_instance_for_match(match_i);
            if (instance_i != INVALID)
            {
                uint enum_token = type_instance_decl_token[instance_i];
                if (enum_token == INVALID || enum_token >= active_token_count())
                    enum_token = find_enum_decl_by_name(instance_i);
                uint found_variant = find_enum_variant_by_name(enum_token, leaf_token);
                if (found_variant != INVALID)
                {
                    pattern_ty = TY_ENUM_BASE + enum_token;
                    variant_token = found_variant;
                    visible_type[arm_i] = pattern_ty;
                    visible_decl[arm_i] = variant_token;
                }
            }
        }
        if (pattern_ty >= TY_ENUM_BASE && variant_token != INVALID)
        {
            uint binder_i = first_payload_binding(leaf_token);
            if (binder_i != INVALID)
            {
                uint payload_ty = pattern_payload_type(match_i, pattern_ty - TY_ENUM_BASE, variant_token);
                bind_payload_uses(arrow_i + 1u, arm_result_end(arrow_i + 1u, brace_close), binder_i, payload_ty);
            }
        }

        uint result_end = arm_result_end(arrow_i + 1u, brace_close);
        arm_i = result_end;
        if (arm_i < brace_close && token_kind(arm_i) == TK_COMMA)
            arm_i += 1u;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count() || hir_kind[i] != HIR_MATCH_EXPR)
        return;

    uint match_i = hir_token_pos[i];
    uint end_i = hir_token_end[i];
    if (match_i == INVALID || end_i == INVALID || match_i >= active_token_count() ||
        end_i > active_token_count() || token_kind(match_i) != TK_MATCH)
        return;

    type_payloads(match_i, end_i);
}
