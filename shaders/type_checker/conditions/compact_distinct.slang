import primitive_types;
// Distinct types, step 2: reject a value whose brand differs from the brand
// its context expects. `type M = distinct T;` is an ordinary alias for type
// checking and lowering (M and T have the same checked type); this pass adds
// the one rule a distinct type has: a value of M mixes only with values of M
// and with numeric literals, and `as` converts between M and T.
//
// A brand is the declaration token of a distinct alias, BRAND_BASE for any
// other type, BRAND_LITERAL for an integer or float literal (it takes the
// brand of its context) and BRAND_UNKNOWN where this pass does not follow the
// value. Only two known, different brands are an error, so a value the pass
// cannot follow is never rejected.
//
// An expression's brand is found by a walk with no stack: a name goes to its
// declaration's annotation (or to the initializer of an unannotated `let`), a
// call to its callee's declared result, a field to the field's annotation, a
// cast to its target, and an arithmetic operator to its left operand. When
// the walk reaches a literal it climbs back to the nearest operator it
// entered from the left and continues with that operator's right operand.
//
// Checked here: `let` initializers against annotations, assignments, returns,
// call arguments against parameters, and both operands of arithmetic and
// comparison operators (not shift counts). Not followed (BRAND_UNKNOWN):
// generic parameters and results, stdlib (dependency) declarations, index,
// match, struct-literal and array values. Brands inside an aggregate type
// (`[M; 4]`, `&M`, `Vec<M>`) are not compared.

import hir_records;
import gpu_index;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
struct TokenIn { uint kind; uint start; uint len; };
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> compact_type_alias_target;
StructuredBuffer<uint> distinct_hir_node_by_token;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> fn_hir_by_decl_token;
StructuredBuffer<uint> member_result_field_node;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint BRAND_UNKNOWN = 0xffffffffu;
static const uint BRAND_LITERAL = 0xfffffffeu;
static const uint BRAND_BASE = 0xfffffffdu;
// walk_step: the brand is the brand of the type node it returns.
static const uint BRAND_OF_TYPE = 0xfffffffcu;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint TK_SELF_VALUE = 105u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_MUT = 203u;
static const uint TK_DISTINCT = 200u;
static const uint HIR_PARAM = 4u;
static const uint HIR_TYPE = 5u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_EXPR = 14u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_RETURN = 2u;
static const uint HIR_STMT_ASSIGN = 5u;
static const uint HIR_ASSIGN_OP_SHL = 8u;
static const uint HIR_ASSIGN_OP_SHR = 9u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_EXPR_CHAR = 29u;
static const uint HIR_EXPR_CAST = 36u;
static const uint HIR_TYPE_FORM_PATH = 1u;
static const uint DECL_KIND_TYPE_ALIAS = 8u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint ALIAS_CHAIN_LIMIT = 16u;
static const uint WALK_LIMIT = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[ForceInline]
uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }
bool known(uint brand) { return brand != BRAND_UNKNOWN && brand != BRAND_LITERAL; }

// The row the scatter pass mapped `token` to, when its kind and key agree.
uint mapped_node(uint token, uint kind)
{
    if (!valid_token(token)) return INVALID;
    uint node = distinct_hir_node_by_token[token];
    if (!valid_hir(node)) return INVALID;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (kind == HIR_TYPE)
        return core.kind == HIR_TYPE && core.token_start == token ? node : INVALID;
    if (kind == HIR_LET_STMT)
        return (core.kind == HIR_LET_STMT || core.kind == HIR_STMT) &&
            payload.a == HIR_STMT_LET && payload.b == token ? node : INVALID;
    return core.kind == HIR_PARAM && payload.c == token ? node : INVALID;
}

// The brand of a type annotation node. Aliases are followed to the first
// distinct one; a generic parameter has no brand of its own.
uint type_brand(uint node)
{
    for (uint step = 0u; step < ALIAS_CHAIN_LIMIT; step++)
    {
        if (!valid_hir(node) || compact_hir_core[node].kind != HIR_TYPE) return BRAND_UNKNOWN;
        uint first = compact_hir_core[node].token_start;
        if (valid_token(first) && type_expr_ref_tag[first] == TYPE_REF_GENERIC_PARAM)
            return BRAND_UNKNOWN;
        if (compact_hir_payload[node].a != HIR_TYPE_FORM_PATH) return BRAND_BASE;
        uint path = path_id_by_owner_hir[node];
        if (path >= min(path_count_out[0u], gParams.n_hir_nodes)) return BRAND_BASE;
        uint decl = resolved_type_decl[path];
        if (decl >= gParams.n_hir_nodes || decl_kind[decl] != DECL_KIND_TYPE_ALIAS) return BRAND_BASE;
        uint alias = decl_hir_node[decl];
        if (!valid_hir(alias)) return BRAND_UNKNOWN;
        uint target = compact_type_alias_target[alias];
        if (!valid_hir(target)) return BRAND_UNKNOWN;
        uint target_first = compact_hir_core[target].token_start;
        if (valid_token(target_first) && target_first > 0u &&
            token_words[target_first - 1u].kind == TK_DISTINCT)
            return valid_token(decl_name_token[decl]) ? decl_name_token[decl] : BRAND_UNKNOWN;
        node = target;
    }
    return BRAND_UNKNOWN;
}

bool expression_kind(uint kind)
{
    return kind == HIR_EXPR || kind == HIR_BINARY_EXPR || kind == HIR_UNARY_EXPR ||
        kind == HIR_LITERAL_EXPR;
}

// Arithmetic and bitwise forms whose result has the brand of their operands.
bool inherited_binary(uint form)
{
    return form >= HIR_EXPR_ADD && form <= HIR_EXPR_SHR && form != HIR_EXPR_AND &&
        form != HIR_EXPR_OR;
}

bool shift_form(uint form) { return form == HIR_EXPR_SHL || form == HIR_EXPR_SHR; }

bool compared_binary(uint form)
{
    return (inherited_binary(form) && !shift_form(form)) ||
        (form >= HIR_EXPR_EQ && form <= HIR_EXPR_GE);
}

// One step of the walk at `node`: its brand when the node decides it
// (`next` = INVALID; BRAND_OF_TYPE names a type node in `next` instead), else
// the node the walk continues at. A jump to a declaration's initializer sets
// `restart`, so the literal climb stops there. Each kernel inlines this and
// type_brand once.
uint walk_step(uint node, out uint next, out bool restart)
{
    next = INVALID; restart = false;
    if (!valid_hir(node)) return BRAND_UNKNOWN;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (core.kind == HIR_CALL_EXPR)
    {
        uint fn = callee_fn(node);
        next = valid_hir(fn) ? compact_fn_return_type[fn] : INVALID;
        return BRAND_OF_TYPE;
    }
    if (core.kind == HIR_MEMBER_EXPR)
    {
        uint field = valid_token(payload.c) ? member_result_field_node[payload.c] : INVALID;
        next = valid_token(field) && field + 2u < gParams.n_tokens
            ? mapped_node(field + 2u, HIR_TYPE) : INVALID;
        return BRAND_OF_TYPE;
    }
    bool name = core.kind == HIR_NAME_EXPR || core.kind == HIR_PATH_EXPR ||
        (expression_kind(core.kind) && payload.a == HIR_EXPR_NAME);
    if (name)
    {
        uint token = core.kind == HIR_PATH_EXPR ? core.token_start : payload.d;
        uint decl = valid_token(token) ? visible_decl[token] : INVALID;
        uint let_row = mapped_node(decl, HIR_LET_STMT);
        if (let_row != INVALID)
        {
            HirPayload binding = compact_hir_payload[let_row];
            if (valid_hir(binding.d)) { next = binding.d; return BRAND_OF_TYPE; }
            next = binding.c; restart = true;
            return BRAND_UNKNOWN;
        }
        uint param = mapped_node(decl, HIR_PARAM);
        next = param != INVALID ? compact_hir_payload[param].d : INVALID;
        return BRAND_OF_TYPE;
    }
    if (!expression_kind(core.kind)) return BRAND_UNKNOWN;
    uint form = payload.a;
    if (form == HIR_EXPR_INT || form == HIR_EXPR_FLOAT) return BRAND_LITERAL;
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE || form == HIR_EXPR_CHAR ||
        form == HIR_EXPR_STRING || form == HIR_EXPR_NOT || form == HIR_EXPR_AND ||
        form == HIR_EXPR_OR || (form >= HIR_EXPR_EQ && form <= HIR_EXPR_GE))
        return BRAND_BASE;
    if (form == HIR_EXPR_CAST) { next = payload.c; return BRAND_OF_TYPE; }
    if (form == HIR_EXPR_FORWARD || form == HIR_EXPR_NEG || inherited_binary(form))
        next = payload.b;
    return BRAND_UNKNOWN;
}

// The local function a call reaches, or INVALID (an intrinsic, a stdlib
// function, an unresolved callee).
uint callee_fn(uint call)
{
    uint callee = compact_hir_payload[call].a;
    if (!valid_hir(callee)) return INVALID;
    bool member = compact_hir_core[callee].kind == HIR_MEMBER_EXPR;
    uint token = member ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    if (!valid_token(token) || call_dependency_library_id[token] != INVALID) return INVALID;
    uint fn_token = call_fn_index[token];
    return valid_token(fn_token) ? fn_hir_by_decl_token[fn_token] : INVALID;
}

// The brand of `root`: a type annotation node when `typed`, else a value.
uint brand_of(uint root, bool typed)
{
    if (typed) return type_brand(root);
    uint node = root;
    uint start = root;
    for (uint step = 0u; step < WALK_LIMIT; step++)
    {
        uint next; bool restart;
        uint brand = walk_step(node, next, restart);
        if (brand == BRAND_OF_TYPE) return type_brand(next);
        if (valid_hir(next))
        {
            if (restart) start = next;
            node = next;
            continue;
        }
        if (brand != BRAND_LITERAL) return brand;
        // A literal: climb to the nearest operator entered from the left and
        // continue with its right operand.
        uint child = node;
        bool resumed = false;
        while (child != start && step < WALK_LIMIT)
        {
            step++;
            uint parent = compact_hir_core[child].parent;
            if (!valid_hir(parent)) return BRAND_LITERAL;
            HirPayload op_payload = compact_hir_payload[parent];
            if (expression_kind(compact_hir_core[parent].kind) && inherited_binary(op_payload.a) &&
                !shift_form(op_payload.a) && op_payload.b == child && valid_hir(op_payload.c))
            {
                node = op_payload.c;
                resumed = true;
                break;
            }
            child = parent;
        }
        if (!resumed) return BRAND_LITERAL;
    }
    return BRAND_UNKNOWN;
}

// A node checks pairs (expected, value). The expected side is a type
// annotation for `let`, return and call arguments, and a value for
// assignments and operators. A call has one pair per argument.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    uint pairs = 0u;
    uint expected_root = INVALID;
    bool expected_typed = true;
    uint value_root = INVALID;
    // Calls: parameters from params.start + skip, arguments from payload.b.
    HirRange params = { 0u, 0u };
    uint skip = 0u;
    bool call = core.kind == HIR_CALL_EXPR;
    if ((core.kind == HIR_LET_STMT || core.kind == HIR_STMT) && payload.a == HIR_STMT_LET)
    {
        pairs = 1u; expected_root = payload.d; value_root = payload.c;
    }
    else if ((core.kind == HIR_RETURN_STMT || core.kind == HIR_STMT) && payload.a == HIR_STMT_RETURN)
    {
        uint fn = compact_hir_nearest_fn[node];
        pairs = 1u; expected_root = valid_hir(fn) ? compact_fn_return_type[fn] : INVALID;
        value_root = payload.b;
    }
    else if ((core.kind == HIR_STMT || core.kind == HIR_ASSIGN_EXPR) && payload.a == HIR_STMT_ASSIGN)
    {
        if (payload.d == HIR_ASSIGN_OP_SHL || payload.d == HIR_ASSIGN_OP_SHR) return;
        pairs = 1u; expected_root = payload.b; expected_typed = false; value_root = payload.c;
    }
    else if (call)
    {
        uint fn = callee_fn(node);
        if (!valid_hir(fn)) return;
        params = compact_param_ranges[fn];
        uint param_total = min(compact_param_count[0u], gParams.n_hir_nodes);
        uint arg_total = min(compact_call_arg_count[0u], gParams.n_hir_nodes);
        if (params.start > param_total || params.count > param_total - params.start ||
            payload.b > arg_total || payload.c > arg_total - payload.b) return;
        // A method's receiver is the member's operand, not an argument.
        uint callee = payload.a;
        if (compact_hir_core[callee].kind == HIR_MEMBER_EXPR && params.count != 0u)
        {
            // `self`, or the `&` of `&self` and `&mut self`, names the receiver.
            uint first = compact_params[params.start].name_token;
            uint after = valid_token(first + 1u) && token_words[first + 1u].kind == TK_MUT ? first + 2u : first + 1u;
            bool receiver = valid_token(first) && (token_words[first].kind == TK_SELF_VALUE ||
                (token_words[first].kind == TK_AMPERSAND && valid_token(after) &&
                 token_words[after].kind == TK_SELF_VALUE));
            skip = receiver ? 1u : 0u;
        }
        pairs = min(payload.c, params.count - skip);
    }
    else if (expression_kind(core.kind) && compared_binary(payload.a))
    {
        pairs = 1u; expected_root = payload.b; expected_typed = false; value_root = payload.c;
    }

    for (uint pair = 0u; pair < pairs; pair++)
    {
        if (call)
        {
            HirCallArg argument = compact_call_args[payload.b + pair];
            if (argument.call != node) return;
            expected_root = compact_params[params.start + skip + pair].type_node;
            value_root = argument.value;
        }
        if (!valid_hir(expected_root) || !valid_hir(value_root)) continue;
        uint expected = BRAND_UNKNOWN;
        uint actual = BRAND_UNKNOWN;
        for (uint side = 0u; side < 2u; side++)
        {
            uint brand = brand_of(side == 0u ? expected_root : value_root, side == 0u && expected_typed);
            if (side == 0u) expected = brand; else actual = brand;
            if (!known(brand)) break;
        }
        uint token = compact_hir_core[value_root].token_start;
        if (known(expected) && known(actual) && expected != actual && valid_token(token))
            record_min_token_error(status, token, ERR_ASSIGN_MISMATCH, DISTINCT_TYPE_MISMATCH);
    }
}
