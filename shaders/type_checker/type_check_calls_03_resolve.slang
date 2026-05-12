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
StructuredBuffer<uint> token_count;
ByteAddressBuffer source_bytes;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> function_lookup_key;
StructuredBuffer<uint> function_lookup_fn;
StructuredBuffer<uint> module_item_kind;
StructuredBuffer<uint> module_path_start;
StructuredBuffer<uint> module_path_end;

static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint MODULE_ITEM_NONE = 0u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_ARG_COMMA = 82u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_CONST = 92u;
static const uint TK_IMPORT = 96u;
static const uint TK_MODULE = 97u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PARAM_CACHE_STRIDE = 16u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint lookup_capacity()
{
    return max(gParams.n_tokens * 2u, 1u);
}

uint token_kind(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].kind : 0u;
}

uint token_start(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].start : 0u;
}

uint token_len(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].len : 0u;
}

uint source_at(uint start, uint delta)
{
    uint idx = start + delta;
    return idx < gParams.source_len ? load_byte_at(source_bytes, idx) : 0u;
}

bool span5(uint start, uint len, uint a, uint b, uint c, uint d, uint e)
{
    return len == 5u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c && source_at(start, 3u) == d &&
           source_at(start, 4u) == e;
}

bool span2(uint start, uint len, uint a, uint b)
{
    return len == 2u && source_at(start, 0u) == a && source_at(start, 1u) == b;
}

bool span3(uint start, uint len, uint a, uint b, uint c)
{
    return len == 3u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c;
}

bool span4(uint start, uint len, uint a, uint b, uint c, uint d)
{
    return len == 4u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c && source_at(start, 3u) == d;
}

bool token_text_eq5(uint i, uint a, uint b, uint c, uint d, uint e)
{
    return span5(token_start(i), token_len(i), a, b, c, d, e);
}

bool is_builtin_name(uint i)
{
    uint start = token_start(i);
    return token_text_eq5(i, 112u, 114u, 105u, 110u, 116u) ||
           (token_len(i) == 6u && source_at(start, 0u) == 97u &&
            source_at(start, 1u) == 115u && source_at(start, 2u) == 115u &&
            source_at(start, 3u) == 101u && source_at(start, 4u) == 114u &&
            source_at(start, 5u) == 116u);
}

bool same_text(uint a, uint b)
{
    uint len = token_len(a);
    if (len != token_len(b))
        return false;
    uint sa = token_start(a);
    uint sb = token_start(b);
    [loop]
    for (uint i = 0u; i < len; i += 1u)
    {
        if (source_at(sa, i) != source_at(sb, i))
            return false;
    }
    return true;
}

uint token_hash(uint i)
{
    uint h = 2166136261u;
    uint start = token_start(i);
    uint len = token_len(i);
    [loop]
    for (uint d = 0u; d < len; d += 1u)
    {
        h = (h ^ source_at(start, d)) * 16777619u;
    }
    return h ^ len;
}

bool is_path_segment_token(uint i)
{
    uint kind = token_kind(i);
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT ||
           kind == TK_LET_IDENT;
}

uint leading_module_decl_end()
{
    if (token_kind(0u) != TK_MODULE)
        return INVALID;

    uint n_active = active_token_count();
    [loop]
    for (uint j = 1u; j < n_active; j += 1u)
    {
        if (token_kind(j) == TK_SEMICOLON)
            return j;
    }
    return INVALID;
}

bool token_in_leading_module_decl(uint i)
{
    uint end = leading_module_decl_end();
    return end != INVALID && i <= end;
}

uint import_decl_end(uint import_i)
{
    if (token_kind(import_i) != TK_IMPORT)
        return INVALID;

    uint n_active = active_token_count();
    [loop]
    for (uint j = import_i + 1u; j < n_active; j += 1u)
    {
        if (token_kind(j) == TK_SEMICOLON)
            return j;
    }
    return INVALID;
}

uint first_token_after_optional_module()
{
    uint module_end = leading_module_decl_end();
    return module_end == INVALID ? 0u : module_end + 1u;
}

bool token_in_leading_import_decl(uint i)
{
    uint n_active = active_token_count();
    uint j = first_token_after_optional_module();
    [loop]
    for (uint guard = 0u; guard < 256u && j < n_active; guard += 1u)
    {
        if (token_kind(j) != TK_IMPORT)
            return false;
        uint end = import_decl_end(j);
        if (end == INVALID)
            return false;
        if (i >= j && i <= end)
            return true;
        if (i < j)
            return false;
        j = end + 1u;
    }
    return false;
}

// The parser/HIR item pass owns module/import header spans. Resolution only
// asks whether this token belongs to one of those AST-derived metadata spans.
bool token_belongs_to_module_metadata_ast_span(uint i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = 0u; j < n_active; j += 1u)
    {
        if (module_item_kind[j] == MODULE_ITEM_NONE)
            continue;
        if (i == j)
            return true;
        uint start = module_path_start[j];
        uint end = module_path_end[j];
        if (start != INVALID && end != INVALID && i >= start && i <= end)
            return true;
    }
    return false;
}

uint qualified_path_start_for_segment(uint segment_i)
{
    uint start = segment_i;
    [loop]
    for (uint guard = 0u; guard < 32u && start >= 3u; guard += 1u)
    {
        if (token_kind(start - 1u) != TK_COLON || token_kind(start - 2u) != TK_COLON ||
            !is_path_segment_token(start - 3u))
            break;
        start -= 3u;
    }
    return start;
}

uint qualified_path_end(uint start)
{
    uint n_active = active_token_count();
    uint end = start;
    [loop]
    for (uint guard = 0u; guard < 32u && end + 3u < n_active; guard += 1u)
    {
        if (token_kind(end + 1u) != TK_COLON || token_kind(end + 2u) != TK_COLON ||
            !is_path_segment_token(end + 3u))
            break;
        end += 3u;
    }
    return end;
}

bool segment_in_qualified_path(uint segment_i)
{
    if (!is_path_segment_token(segment_i))
        return false;
    uint start = qualified_path_start_for_segment(segment_i);
    uint end = qualified_path_end(start);
    return end > start && segment_i >= start && segment_i <= end;
}

bool is_qualified_type_context(uint prev)
{
    return prev == TK_COLON || prev == TK_ARROW || prev == TK_LT || prev == TK_COMMA ||
           prev == TK_PARAM_COMMA;
}

uint same_source_qualified_value_leaf(uint start)
{
    uint module_end = leading_module_decl_end();
    if (module_end == INVALID || start >= active_token_count())
        return INVALID;

    uint module_seg = 1u;
    uint path_seg = start;
    [loop]
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (module_seg >= module_end || !is_path_segment_token(module_seg) ||
            !is_path_segment_token(path_seg) || !same_text(module_seg, path_seg))
            return INVALID;

        bool module_has_next =
            module_seg + 3u < module_end && token_kind(module_seg + 1u) == TK_COLON &&
            token_kind(module_seg + 2u) == TK_COLON && is_path_segment_token(module_seg + 3u);
        if (module_has_next)
        {
            if (path_seg + 3u >= active_token_count() ||
                token_kind(path_seg + 1u) != TK_COLON ||
                token_kind(path_seg + 2u) != TK_COLON ||
                !is_path_segment_token(path_seg + 3u))
                return INVALID;
            module_seg += 3u;
            path_seg += 3u;
            continue;
        }

        uint leaf = path_seg + 3u;
        if (leaf >= active_token_count() || token_kind(path_seg + 1u) != TK_COLON ||
            token_kind(path_seg + 2u) != TK_COLON || !is_path_segment_token(leaf))
            return INVALID;
        if (leaf + 2u < active_token_count() && token_kind(leaf + 1u) == TK_COLON &&
            token_kind(leaf + 2u) == TK_COLON)
            return INVALID;
        uint next = token_kind(leaf + 1u);
        return (next == TK_CALL_LPAREN || next == TK_LPAREN) ? leaf : INVALID;
    }
    return INVALID;
}

void record_error(uint token_i, uint code, uint detail)
{
    uint old;
    InterlockedMin(status[1], token_i, old);
    if (token_i <= old)
    {
        status[0] = 0u;
        status[2] = code;
        status[3] = detail;
    }
}

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
}

uint primitive_type_code(uint type_i)
{
    uint start = token_start(type_i);
    uint len = token_len(type_i);
    if (span2(start, len, 105u, 56u) || span3(start, len, 105u, 49u, 54u) ||
        span3(start, len, 105u, 51u, 50u) || span3(start, len, 105u, 54u, 52u) ||
        span5(start, len, 105u, 115u, 105u, 122u, 101u))
        return TY_INT;

    if (span2(start, len, 117u, 56u) || span3(start, len, 117u, 49u, 54u) ||
        span3(start, len, 117u, 51u, 50u) || span3(start, len, 117u, 54u, 52u) ||
        span5(start, len, 117u, 115u, 105u, 122u, 101u))
        return TY_UINT;

    if (span3(start, len, 102u, 51u, 50u) || span3(start, len, 102u, 54u, 52u))
        return TY_FLOAT;
    if (span4(start, len, 98u, 111u, 111u, 108u))
        return TY_BOOL;
    if (span4(start, len, 99u, 104u, 97u, 114u))
        return TY_CHAR;
    if (span3(start, len, 115u, 116u, 114u))
        return TY_STRING;

    return TY_UNKNOWN;
}

uint generic_param_list_open(uint item_i)
{
    uint n_active = active_token_count();
    [loop]
    for (uint j = item_i + 1u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            return j;
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_LPAREN ||
            kind == TK_PARAM_LPAREN || kind == TK_SEMICOLON)
            return INVALID;
    }
    return INVALID;
}

uint generic_param_list_close(uint open_i)
{
    uint n_active = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < n_active; j += 1u)
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
        else if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_SEMICOLON)
        {
            return INVALID;
        }
    }
    return INVALID;
}

bool is_type_generic_param_token(uint param_i, uint open_i, uint close_i)
{
    uint kind = token_kind(param_i);
    if (param_i <= open_i || param_i >= close_i ||
        (kind != TK_IDENT && kind != TK_TYPE_IDENT && kind != TK_PARAM_IDENT))
        return false;
    if (param_i > open_i + 1u && token_kind(param_i - 1u) == TK_CONST)
        return false;
    if (param_i + 1u < close_i && token_kind(param_i + 1u) == TK_COLON)
        return false;
    return true;
}

uint enclosing_function_start(uint target_i)
{
    uint j = min(target_i, active_token_count());
    [loop]
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        if (token_kind(j) == TK_FN)
            return j;
    }
    return INVALID;
}

uint generic_type_code_for_name(uint name_i)
{
    uint fn_i = enclosing_function_start(name_i);
    if (fn_i == INVALID)
        return TY_UNKNOWN;

    uint open_i = generic_param_list_open(fn_i);
    if (open_i == INVALID)
        return TY_UNKNOWN;
    uint close_i = generic_param_list_close(open_i);
    if (close_i == INVALID)
        return TY_UNKNOWN;

    [loop]
    for (uint p = open_i + 1u; p < close_i; p += 1u)
    {
        if (is_type_generic_param_token(p, open_i, close_i) && same_text(p, name_i))
            return TY_GENERIC_BASE + p;
    }
    return TY_UNKNOWN;
}

uint type_code_for_type_expr(uint type_i)
{
    uint kind = token_kind(type_i);
    if (kind != TK_TYPE_IDENT && kind != TK_IDENT)
        return TY_UNKNOWN;

    uint elem = primitive_type_code(type_i);
    if (elem == TY_UNKNOWN)
        elem = generic_type_code_for_name(type_i);
    return elem;
}

bool is_group_open_kind(uint kind)
{
    return kind == TK_GROUP_LPAREN || kind == TK_LPAREN || kind == TK_CALL_LPAREN ||
           kind == TK_PARAM_LPAREN;
}

bool is_group_close_kind(uint kind)
{
    return kind == TK_GROUP_RPAREN || kind == TK_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_PARAM_RPAREN;
}

uint find_call_close(uint call_lparen_i)
{
    uint n_active = active_token_count();
    uint depth = 0u;
    [loop]
    for (uint j = call_lparen_i; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_CALL_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_LPAREN)
            depth += 1u;
        else if (kind == TK_CALL_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_RPAREN)
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

uint call_arg_count(uint call_lparen_i, uint close_i)
{
    if (close_i == INVALID || call_lparen_i + 1u >= close_i)
        return 0u;
    uint group_depth = 0u;
    uint count = 1u;
    [loop]
    for (uint j = call_lparen_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if ((kind == TK_ARG_COMMA || kind == TK_COMMA) && group_depth == 0u)
            count += 1u;
    }
    return count;
}

uint call_arg_start(uint call_lparen_i, uint close_i, uint arg_index)
{
    uint current = 0u;
    uint start = call_lparen_i + 1u;
    uint group_depth = 0u;
    [loop]
    for (uint j = call_lparen_i + 1u; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if ((kind == TK_ARG_COMMA || kind == TK_COMMA) && group_depth == 0u)
        {
            if (current == arg_index)
                return start < j ? start : INVALID;
            current += 1u;
            start = j + 1u;
        }
    }
    if (current == arg_index)
        return start < close_i ? start : INVALID;
    return INVALID;
}

uint call_arg_end(uint arg_start_i, uint close_i)
{
    uint group_depth = 0u;
    [loop]
    for (uint j = arg_start_i; j < close_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if ((kind == TK_ARG_COMMA || kind == TK_COMMA) && group_depth == 0u)
            return j;
    }
    return close_i;
}

uint function_value_params_start(uint fn_i)
{
    uint n_active = active_token_count();
    uint j = fn_i + 2u;
    if (j < n_active && token_kind(j) == TK_LT)
    {
        uint close_i = generic_param_list_close(j);
        if (close_i == INVALID)
            return INVALID;
        j = close_i + 1u;
    }

    [loop]
    for (; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_PARAM_LPAREN || kind == TK_LPAREN)
            return j + 1u;
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE || kind == TK_SEMICOLON)
            return INVALID;
    }
    return INVALID;
}

bool is_param_decl(uint i)
{
    uint n_active = active_token_count();
    uint kind = token_kind(i);
    return kind == TK_PARAM_IDENT ||
           (kind == TK_IDENT && i + 1u < n_active && token_kind(i + 1u) == TK_COLON);
}

uint local_identifier_type(uint name_i)
{
    uint fn_i = enclosing_function_start(name_i);
    if (fn_i == INVALID)
        return TY_UNKNOWN;

    uint start_i = function_value_params_start(fn_i);
    if (start_i == INVALID)
        return TY_UNKNOWN;

    [loop]
    for (uint j = start_i; j < name_i; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_PARAM_RPAREN || kind == TK_RPAREN || kind == TK_LBRACE ||
            kind == TK_IF_LBRACE)
            break;
        if (is_param_decl(j) && same_text(j, name_i))
            return type_code_for_type_expr(j + 2u);
    }

    [loop]
    for (uint j = fn_i + 1u; j + 3u < name_i; j += 1u)
    {
        if (token_kind(j) != TK_LET)
            continue;
        uint ident_i = j + 1u;
        if ((token_kind(ident_i) == TK_LET_IDENT || token_kind(ident_i) == TK_IDENT) &&
            same_text(ident_i, name_i) && token_kind(ident_i + 1u) == TK_COLON)
            return type_code_for_type_expr(ident_i + 2u);
    }

    return TY_UNKNOWN;
}

uint find_function_decl_by_name(uint name_i)
{
    if (name_i >= active_token_count() || token_kind(name_i) != TK_IDENT)
        return INVALID;

    uint cap = lookup_capacity();
    uint key = token_hash(name_i);
    uint start_slot = key % cap;
    [loop]
    for (uint probe = 0u; probe < cap; probe += 1u)
    {
        uint slot = (start_slot + probe) % cap;
        uint fn_i = function_lookup_fn[slot];
        if (fn_i == INVALID)
            return INVALID;
        if (function_lookup_key[slot] == key && same_text(fn_i + 1u, name_i))
            return fn_i;
    }
    return INVALID;
}

uint leading_arg_token(uint arg_start_i, uint arg_end_i)
{
    uint cur = arg_start_i;
    [loop]
    for (uint guard = 0u; guard < 16u && cur < arg_end_i && cur < active_token_count();
         guard += 1u)
    {
        uint kind = token_kind(cur);
        if (kind == TK_GROUP_LPAREN || kind == TK_LPAREN)
        {
            cur += 1u;
            continue;
        }
        break;
    }
    return cur;
}

uint literal_or_identifier_arg_type_direct(uint arg_start_i, uint arg_end_i)
{
    uint cur = leading_arg_token(arg_start_i, arg_end_i);
    uint kind = token_kind(cur);
    if (kind == TK_INT)
        return TY_INT;
    if (kind == TK_TRUE || kind == TK_FALSE)
        return TY_BOOL;
    if (kind == TK_FLOAT)
        return TY_FLOAT;
    if (kind == TK_STRING)
        return TY_STRING;
    if (kind == TK_CHAR)
        return TY_CHAR;
    if (kind == TK_IDENT)
        return local_identifier_type(cur);
    return TY_UNKNOWN;
}

uint inferred_generic_return_type_direct(uint callee_i, uint fn_i, uint ret_ty)
{
    uint open_i = callee_i + 1u;
    uint close_i = find_call_close(open_i);
    if (close_i == INVALID)
        return TY_UNKNOWN;

    uint param_count = fn_i < active_token_count() ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count(open_i, close_i);
    if (arg_count != param_count)
        return TY_UNKNOWN;

    uint inferred = TY_UNKNOWN;
    [loop]
    for (uint arg_i = 0u; arg_i < arg_count && arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        uint param_ty = call_param_type[fn_i * PARAM_CACHE_STRIDE + arg_i];
        if (param_ty != ret_ty)
            continue;

        uint arg_start_i = call_arg_start(open_i, close_i, arg_i);
        if (arg_start_i == INVALID)
            return TY_UNKNOWN;
        uint arg_ty =
            literal_or_identifier_arg_type_direct(arg_start_i, call_arg_end(arg_start_i, close_i));
        if (arg_ty == TY_UNKNOWN)
            return TY_UNKNOWN;
        if (inferred == TY_UNKNOWN)
            inferred = arg_ty;
        else if (inferred != arg_ty)
            return TY_UNKNOWN;
    }

    return inferred;
}

uint direct_call_return_type_direct(uint callee_i)
{
    uint fn_i = find_function_decl_by_name(callee_i);
    if (fn_i == INVALID)
        return TY_UNKNOWN;

    uint ret_ty = call_return_type[fn_i];
    if (!is_generic_type(ret_ty))
        return ret_ty;
    return inferred_generic_return_type_direct(callee_i, fn_i, ret_ty);
}

uint literal_or_identifier_arg_type(uint arg_start_i, uint arg_end_i)
{
    uint cur = leading_arg_token(arg_start_i, arg_end_i);
    uint qualified_leaf = same_source_qualified_value_leaf(cur);
    if (qualified_leaf != INVALID && qualified_leaf + 1u < arg_end_i)
    {
        return direct_call_return_type_direct(qualified_leaf);
    }
    if (cur + 1u < arg_end_i && token_kind(cur) == TK_IDENT &&
        (token_kind(cur + 1u) == TK_CALL_LPAREN || token_kind(cur + 1u) == TK_LPAREN))
    {
        return direct_call_return_type_direct(cur);
    }
    return literal_or_identifier_arg_type_direct(arg_start_i, arg_end_i);
}

uint inferred_generic_return_type(uint callee_i, uint fn_i, uint ret_ty)
{
    uint open_i = callee_i + 1u;
    uint close_i = find_call_close(open_i);
    if (close_i == INVALID)
        return TY_UNKNOWN;

    uint param_count = fn_i < active_token_count() ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count(open_i, close_i);
    if (arg_count != param_count)
        return TY_UNKNOWN;

    uint inferred = TY_UNKNOWN;
    [loop]
    for (uint arg_i = 0u; arg_i < arg_count && arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        uint param_ty = call_param_type[fn_i * PARAM_CACHE_STRIDE + arg_i];
        if (param_ty != ret_ty)
            continue;

        uint arg_start_i = call_arg_start(open_i, close_i, arg_i);
        if (arg_start_i == INVALID)
            return TY_UNKNOWN;
        uint arg_ty = literal_or_identifier_arg_type(arg_start_i, call_arg_end(arg_start_i, close_i));
        if (arg_ty == TY_UNKNOWN)
            return TY_UNKNOWN;
        if (inferred == TY_UNKNOWN)
            inferred = arg_ty;
        else if (inferred != arg_ty)
            return TY_UNKNOWN;
    }

    return inferred;
}

bool check_generic_argument_consistency(uint callee_i, uint fn_i)
{
    uint open_i = callee_i + 1u;
    uint close_i = find_call_close(open_i);
    if (close_i == INVALID)
        return true;

    uint param_count = fn_i < active_token_count() ? call_param_count[fn_i] : 0u;
    uint arg_count = call_arg_count(open_i, close_i);
    if (arg_count != param_count)
        return true;

    [loop]
    for (uint arg_i = 0u; arg_i < arg_count && arg_i < PARAM_CACHE_STRIDE; arg_i += 1u)
    {
        uint param_ty = call_param_type[fn_i * PARAM_CACHE_STRIDE + arg_i];
        if (!is_generic_type(param_ty))
            continue;

        uint arg_start_i = call_arg_start(open_i, close_i, arg_i);
        if (arg_start_i == INVALID)
            continue;
        uint arg_ty = literal_or_identifier_arg_type(arg_start_i, call_arg_end(arg_start_i, close_i));
        if (arg_ty == TY_UNKNOWN)
            continue;

        [loop]
        for (uint prev_i = 0u; prev_i < arg_i && prev_i < PARAM_CACHE_STRIDE; prev_i += 1u)
        {
            uint prev_param_ty = call_param_type[fn_i * PARAM_CACHE_STRIDE + prev_i];
            if (prev_param_ty != param_ty)
                continue;

            uint prev_start_i = call_arg_start(open_i, close_i, prev_i);
            if (prev_start_i == INVALID)
                continue;
            uint prev_ty =
                literal_or_identifier_arg_type(prev_start_i, call_arg_end(prev_start_i, close_i));
            if (prev_ty != TY_UNKNOWN && prev_ty != arg_ty)
            {
                record_error(arg_start_i, ERR_ASSIGN_MISMATCH, param_ty * 256u + arg_ty);
                return false;
            }
        }
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n_active = active_token_count();
    if (i >= n_active || token_kind(i) != TK_IDENT)
        return;
    if (token_belongs_to_module_metadata_ast_span(i) || token_in_leading_module_decl(i) ||
        token_in_leading_import_decl(i))
        return;

    bool qualified_leaf_token = false;
    uint qualified_start_token = INVALID;
    if (segment_in_qualified_path(i))
    {
        uint qualified_start = qualified_path_start_for_segment(i);
        qualified_start_token = qualified_start;
        uint prev = qualified_start > 0u ? token_kind(qualified_start - 1u) : 0u;
        if (is_qualified_type_context(prev))
            return;
        uint qualified_leaf = same_source_qualified_value_leaf(qualified_start);
        if (qualified_leaf == INVALID)
        {
            call_return_type[i] = TY_UNKNOWN;
            if (i == qualified_start)
                record_error(i, ERR_UNRESOLVED_IDENT, TK_COLON);
            return;
        }
        if (qualified_leaf != i)
            return;
        qualified_leaf_token = true;
    }

    bool is_call = i + 1u < n_active &&
                   (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN);

    if (is_builtin_name(i))
    {
        if (is_call)
        {
            call_return_type[i] = TY_VOID;
            call_return_type_token[i] = INVALID;
        }
        return;
    }

    uint cap = lookup_capacity();
    uint key = token_hash(i);
    uint start_slot = key % cap;
    [loop]
    for (uint probe = 0u; probe < cap; probe += 1u)
    {
        uint slot = (start_slot + probe) % cap;
        uint fn_i = function_lookup_fn[slot];
        if (fn_i == INVALID)
        {
            if (qualified_leaf_token)
                record_error(i, ERR_UNRESOLVED_IDENT, 0u);
            return;
        }
        if (function_lookup_key[slot] == key && same_text(fn_i + 1u, i))
        {
            call_fn_index[i] = fn_i;
            if (is_call)
            {
                uint ret_ty = call_return_type[fn_i];
                if (!check_generic_argument_consistency(i, fn_i))
                    return;
                if (is_generic_type(ret_ty))
                {
                    uint inferred = inferred_generic_return_type(i, fn_i, ret_ty);
                    if (inferred != TY_UNKNOWN)
                        ret_ty = inferred;
                }
                call_return_type[i] = ret_ty;
                call_return_type_token[i] = call_return_type_token[fn_i];
                if (qualified_leaf_token && qualified_start_token != INVALID)
                {
                    call_fn_index[qualified_start_token] = fn_i;
                    call_return_type[qualified_start_token] = ret_ty;
                    call_return_type_token[qualified_start_token] = call_return_type_token[fn_i];
                    visible_type[qualified_start_token] = ret_ty;
                }
            }
            return;
        }
    }

    call_return_type[i] = TY_UNKNOWN;
    if (qualified_leaf_token)
        record_error(i, ERR_UNRESOLVED_IDENT, 0u);
}
