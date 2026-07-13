// GPU match-pattern binder for resolved enum variant paths.
//
// This pass consumes parser-owned HIR match-arm records plus resolver rows and
// publishes arm-local declaration links. Payload type substitution is handled by
// the following payload pass so each shader stays within WebGPU's storage-buffer
// limits.
// It uses the compact path table's HIR-owner order as a sorted index; if the
// lower-bound row is not the expected HIR path expression inside the pattern
// subtree, binding fails closed instead of scanning the subtree.

import range_query;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_match_arm_pattern_node;
StructuredBuffer<uint> hir_match_arm_payload_start;
StructuredBuffer<uint> hir_match_arm_payload_count;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_owner_hir;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> hir_variant_payload_count;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> visible_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LANGUAGE_SYMBOL_WILDCARD = 18u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint VARIANT_PAYLOAD_SLOT_STRIDE = 4u;

static const uint HIR_PATH_EXPR = 33u;

static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_ENUM_BASE = 6144u;

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
    return gParams.n_hir_nodes;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

bool token_is_wildcard(uint i)
{
    return valid_token(i) && name_id_by_token[i] != INVALID &&
           name_id_by_token[i] == language_name_id[LANGUAGE_SYMBOL_WILDCARD];
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

int compare_u32(uint left, uint right)
{
    if (left < right)
        return -1;
    if (left > right)
        return 1;
    return 0;
}

public struct PathOwnerCompare : IRowQueryCompare<uint>
{
    public static int compare(uint row, uint owner_hir)
    {
        return compare_u32(path_owner_hir[row], owner_hir);
    }
}

uint first_pattern_path_node(uint pattern_node)
{
    if (!valid_node(pattern_node))
        return INVALID;

    uint end = min(subtree_end[pattern_node], active_hir_node_count());
    if (end <= pattern_node)
        return INVALID;

    uint row = lower_bound_query<uint, PathOwnerCompare>(active_path_count(), pattern_node);
    if (row >= active_path_count())
        return INVALID;

    uint node = path_owner_hir[row];
    if (node >= end || !valid_node(node))
        return INVALID;
    if (hir_kind[node] != HIR_PATH_EXPR)
        return INVALID;
    if (path_id_by_owner_hir[node] != row)
        return INVALID;
    return node;
}

bool enum_variant_decl(
    uint decl_i,
    out uint variant_token,
    out uint enum_token,
    out uint variant_node)
{
    variant_token = INVALID;
    enum_token = INVALID;
    variant_node = INVALID;
    if (decl_i >= gParams.n_hir_nodes || decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;

    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= gParams.n_hir_nodes || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;

    variant_token = decl_name_token[decl_i];
    enum_token = decl_name_token[enum_decl_i];
    variant_node = decl_hir_node[decl_i];
    return variant_token != INVALID && enum_token != INVALID &&
           variant_token < active_token_count() && enum_token < active_token_count() &&
           valid_node(variant_node);
}

bool match_payload_shape_supported(uint arm_node, uint variant_node)
{
    if (!valid_node(arm_node) || !valid_node(variant_node))
        return false;

    uint actual_count = hir_match_arm_payload_count[arm_node];
    uint expected_count = hir_variant_payload_count[variant_node];
    return actual_count == expected_count &&
           actual_count <= VARIANT_PAYLOAD_SLOT_STRIDE &&
           expected_count <= VARIANT_PAYLOAD_SLOT_STRIDE;
}

uint first_payload_binding(uint arm_node)
{
    if (!valid_node(arm_node) || hir_match_arm_payload_count[arm_node] == 0u)
        return INVALID;
    uint payload_node = hir_match_arm_payload_start[arm_node];
    if (!valid_node(payload_node))
        return INVALID;
    uint token_i = hir_token_pos[payload_node];
    return valid_token(token_i) ? token_i : INVALID;
}

void bind_decl(uint use_i, uint decl_i)
{
    if (use_i >= active_token_count())
        return;
    visible_decl[use_i] = decl_i;
    module_value_path_status[use_i] = INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint arm_node = linear_thread_id(dtid);
    if (!valid_node(arm_node) || !valid_node(hir_match_arm_pattern_node[arm_node]))
        return;

    uint pattern_node = hir_match_arm_pattern_node[arm_node];

    uint pattern_token = hir_token_pos[pattern_node];
    if (!valid_token(pattern_token))
        return;
    if (token_is_wildcard(pattern_token))
    {
        bind_decl(pattern_token, pattern_token);
        visible_type[pattern_token] = TY_UNKNOWN;
        return;
    }

    uint path_node = first_pattern_path_node(pattern_node);
    if (!valid_node(path_node))
        return;

    uint path_i = path_id_by_owner_hir[path_node];
    if (path_i == INVALID || path_i >= gParams.n_hir_nodes)
        return;

    uint owner_token = path_owner_token[path_i];
    if (!valid_token(owner_token))
        return;

    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return;

    uint variant_token;
    uint enum_token;
    uint variant_node;
    if (!enum_variant_decl(resolved_value_decl[path_i], variant_token, enum_token, variant_node))
        return;

    if (!match_payload_shape_supported(arm_node, variant_node))
    {
        record_error(owner_token, ERR_ASSIGN_MISMATCH, 0u);
        return;
    }

    bind_decl(owner_token, variant_token);
    visible_type[owner_token] = TY_ENUM_BASE + enum_token;

    uint binder_i = first_payload_binding(arm_node);
    if (binder_i == INVALID)
        return;

    bind_decl(binder_i, binder_i);
    visible_type[binder_i] = TY_UNKNOWN;
}
