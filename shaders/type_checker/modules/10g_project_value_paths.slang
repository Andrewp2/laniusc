// GPU value-path fail-closed status projection from resolver arrays.
//
// Scheduling contract:
// - Dispatch after type path projection and value call-head marking, so
//   successfully resolved type expressions are not also treated as value
//   expressions and value status is propagated for downstream value consumers.
// - This pass consumes value resolution produced by the sorted GPU module/import
//   resolver. Call/value consumers are not allowed to accept qualified values
//   through token-level shortcuts, so qualified value paths write a
//   token-indexed status at the path head even when the resolver found a
//   declaration. HIR value/call consumers must read the value declaration arrays
//   directly and clear the status only for cases they really consume.
//   One-segment imported or top-level value paths also publish resolver status
//   when the sorted tables found a declaration or import ambiguity; unresolved
//   one-segment paths with no module owner or no import hit stay available to
//   normal lexical local/parameter lookup.
// - It does not inspect source bytes, hash token text, scan for "::", patch
//   call outputs, or perform any CPU lookup.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> hir_bound_path_owner_by_leaf;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_owner_hir;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> module_type_path_status;
StructuredBuffer<uint> module_value_path_call_head;
StructuredBuffer<uint> module_value_path_expr_head;
StructuredBuffer<uint> module_value_path_associated_method_token;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> predicate_syntax_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED = 2u;
static const uint PATH_RESOLVE_STATUS_INVALID_OWNER = 3u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_DECL = 6u;
static const uint TK_LPAREN = 4u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_PATH_COLON = 114u;
static const uint TK_TYPE_ARG_LT = 131u;
static const uint TK_TYPE_ARG_GT = 132u;
static const uint TK_PATH_TYPE_ARG_LT = 184u;
static const uint TK_PATH_TYPE_ARG_GT = 185u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
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

uint token_kind(uint token)
{
    return valid_token(token) ? token_words[token].kind : 0u;
}

bool path_colon(uint kind)
{
    return kind == TK_COLON || kind == TK_PATH_COLON;
}

bool call_open(uint kind)
{
    return kind == TK_LPAREN || kind == TK_CALL_LPAREN || kind == TK_GROUP_LPAREN;
}

bool type_arg_open(uint kind)
{
    return kind == TK_LT || kind == TK_TYPE_ARG_LT || kind == TK_PATH_TYPE_ARG_LT;
}

bool type_arg_close(uint kind)
{
    return kind == TK_GT || kind == TK_TYPE_ARG_GT || kind == TK_PATH_TYPE_ARG_GT;
}

bool generic_associated_receiver_path_owner(uint owner_token)
{
    if (!valid_token(owner_token))
        return false;

    uint depth = 0u;
    [unroll]
    for (uint step = 0u; step < 64u; step += 1u)
    {
        uint cursor = owner_token + step;
        if (!valid_token(cursor))
            return false;

        uint kind = token_kind(cursor);
        if (type_arg_open(kind))
        {
            depth += 1u;
        }
        else if (type_arg_close(kind))
        {
            if (depth > 0u)
                depth -= 1u;
            if (depth == 0u)
            {
                return valid_token(cursor + 4u) &&
                       path_colon(token_kind(cursor + 1u)) &&
                       path_colon(token_kind(cursor + 2u)) &&
                       call_open(token_kind(cursor + 4u));
            }
        }

        if (kind == TK_SEMICOLON || call_open(kind))
            return false;
    }
    return false;
}

bool predicate_bound_type_path(uint path_i)
{
    uint owner = path_owner_hir[path_i];
    if (!valid_node(owner))
        return false;

    uint leaf = hir_type_path_leaf_node[owner];
    if (!valid_node(leaf))
        return false;

    return valid_node(hir_bound_path_owner_by_leaf[leaf]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;
    if (path_kind[path_i] != PATH_RECORD_KIND_HIR_PATH_EXPR)
        return;
    uint segment_count = path_segment_count[path_i];
    if (segment_count == 0u)
        return;

    uint owner_token = path_owner_token[path_i];
    if (owner_token >= gParams.n_tokens)
        return;
    if (predicate_bound_type_path(path_i))
    {
        predicate_syntax_token[owner_token] = 1u;
        return;
    }
    if (resolved_type_decl[path_i] != INVALID)
        return;
    if (module_type_path_status[owner_token] == PATH_RESOLVE_STATUS_OK)
        return;
    if (module_value_path_expr_head[owner_token] == 0u)
        return;
    if (module_value_path_associated_method_token[owner_token] != INVALID)
        return;
    if (generic_associated_receiver_path_owner(owner_token))
        return;
    if (segment_count == 1u &&
        (resolved_value_status[path_i] == PATH_RESOLVE_STATUS_UNRESOLVED ||
         resolved_value_status[path_i] == PATH_RESOLVE_STATUS_INVALID_OWNER ||
         resolved_value_status[path_i] == PATH_RESOLVE_STATUS_UNRESOLVED_DECL))
        return;
    module_value_path_status[owner_token] = resolved_value_status[path_i];
}
