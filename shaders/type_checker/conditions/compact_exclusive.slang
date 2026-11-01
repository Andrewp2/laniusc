import primitive_types;
// Exclusive references: reject a call whose `&mut` argument shares its root
// with another reference argument of the same call, as in `swap(a, a)` with
// `fn swap(x: &mut T, y: &T)`. `&mut T` and `&mut self` check and lower as
// `&T` and `&self`; this pass is the one rule `mut` adds.
//
// A root is the local or parameter an argument reaches through field and
// index projections, parentheses and method-call receivers: `w` in `w`,
// `w.inner`, `w.items[i]`, `(w)` and `w.borrow()`. Arguments without a root
// (calls of free functions, literals) never conflict. Disjoint fields of one
// root are rejected too: the check compares roots, not paths.
//
// Checked: calls of functions in this unit, with the receiver of a method
// call as one more argument. Not checked: dependency (stdlib) callees, and
// aliases made through by-value copies of records that hold pointers.
//
// Liveness (docs/state-machines-design.md, M4): a local declared with a
// reference type and made by a method call, `let r: &T = e.view();` or
// `&mut T`, keeps e's root borrowed while r is used. A call that passes that
// root as a `&mut` argument while r is live is rejected (`m.step(event)` on
// a machine `m`). r is live at a call when it is used after the call, or
// anywhere in a loop around the call that does not declare r again, since
// the loop runs the call before such a use. Plain assignments to the root
// are not counted: `&T` does not yet mean read-only, and programs rely on
// seeing such a write through a live shared reference. Copies of r into
// other locals are not followed.

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
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> fn_hir_by_decl_token;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint TK_SELF_VALUE = 105u;
static const uint TK_MUT = 203u;
static const uint TK_AMPERSAND = 25u;
static const uint HIR_TYPE = 5u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_FOR_STMT = 30u;
static const uint STMT_LET = 1u;
static const uint HIR_EXPR = 14u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;
static const uint ARG_LIMIT = 64u;
static const uint WALK_LIMIT = 128u;
static const uint DISPATCH_X_STRIDE = 16776960u;

// Reference kinds of a parameter.
static const uint BY_VALUE = 0u;
static const uint SHARED = 1u;
static const uint EXCLUSIVE = 2u;

[ForceInline]
uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

// The local function a call reaches, or INVALID.
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

bool token_is(uint token, uint kind) { return valid_token(token) && token_words[token].kind == kind; }

// The `self` token of a receiver parameter, or INVALID. A parameter's name
// token is where its production starts: `self`, or the `&` of `&self` and
// `&mut self`.
uint self_token(uint name)
{
    if (token_is(name, TK_SELF_VALUE)) return name;
    if (!token_is(name, TK_AMPERSAND)) return INVALID;
    uint after = token_is(name + 1u, TK_MUT) ? name + 2u : name + 1u;
    return token_is(after, TK_SELF_VALUE) ? after : INVALID;
}

// Read from the raw tokens: `&` or `&mut` before `self`, and for a typed
// parameter the first tokens of its type.
uint param_mode(HirParam param)
{
    uint self_at = self_token(param.name_token);
    if (self_at != INVALID)
    {
        if (token_is(self_at - 1u, TK_MUT)) return EXCLUSIVE;
        return token_is(self_at - 1u, TK_AMPERSAND) ? SHARED : BY_VALUE;
    }
    uint type_node = param.type_node;
    if (!valid_hir(type_node) || compact_hir_core[type_node].kind != HIR_TYPE) return BY_VALUE;
    uint first = compact_hir_core[type_node].token_start;
    if (!token_is(first, TK_AMPERSAND)) return BY_VALUE;
    return token_is(first + 1u, TK_MUT) ? EXCLUSIVE : SHARED;
}

// The value at argument position `i`: the receiver, then the call's arguments.
uint argument_at(uint call, uint first_arg, uint receiver, uint skip, uint i)
{
    if (i < skip) return receiver;
    HirCallArg argument = compact_call_args[first_arg + i - skip];
    return argument.call == call ? argument.value : INVALID;
}

// The declaration token an argument's place starts from, or INVALID.
uint root_of(uint node)
{
    for (uint step = 0u; step < WALK_LIMIT; step++)
    {
        if (!valid_hir(node)) return INVALID;
        HirCore core = compact_hir_core[node];
        HirPayload payload = compact_hir_payload[node];
        bool forward = (core.kind == HIR_EXPR || core.kind == HIR_BINARY_EXPR ||
            core.kind == HIR_UNARY_EXPR) && payload.a == HIR_EXPR_FORWARD;
        if (forward || core.kind == HIR_MEMBER_EXPR || core.kind == HIR_INDEX_EXPR)
        { node = payload.b; continue; }
        if (core.kind == HIR_CALL_EXPR)
        {
            uint callee = payload.a;
            if (!valid_hir(callee) || compact_hir_core[callee].kind != HIR_MEMBER_EXPR) return INVALID;
            node = compact_hir_payload[callee].b;
            continue;
        }
        bool name = core.kind == HIR_NAME_EXPR || core.kind == HIR_PATH_EXPR ||
            (core.kind == HIR_EXPR && payload.a == HIR_EXPR_NAME);
        if (!name) return INVALID;
        uint token = core.kind == HIR_PATH_EXPR ? core.token_start : payload.d;
        return valid_token(token) ? visible_decl[token] : INVALID;
    }
    return INVALID;
}

// Whether `node` reads the local declared at token `decl`.
bool uses_decl(uint node, uint decl)
{
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    bool name = core.kind == HIR_NAME_EXPR || (core.kind == HIR_EXPR && payload.a == HIR_EXPR_NAME);
    uint token = core.kind == HIR_PATH_EXPR ? core.token_start : payload.d;
    return (name || core.kind == HIR_PATH_EXPR) && valid_token(token) && visible_decl[token] == decl;
}

// Whether a node of [first, end) reads the local declared at `decl`.
bool used_in(uint first, uint end, uint decl)
{
    for (uint node = first; node < end; node++)
        if (uses_decl(node, decl)) return true;
    return false;
}

// Whether `node` passes the value rooted at `root` as a `&mut` argument of
// a local function, the receiver included.
bool writes_root(uint node, uint root)
{
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (core.kind != HIR_CALL_EXPR) return false;
    uint fn = callee_fn(node);
    if (!valid_hir(fn)) return false;
    HirRange params = compact_param_ranges[fn];
    uint param_total = min(compact_param_count[0u], gParams.n_hir_nodes);
    uint arg_total = min(compact_call_arg_count[0u], gParams.n_hir_nodes);
    // A call without arguments may leave their start unset; its receiver
    // still counts.
    if (params.start > param_total || params.count > param_total - params.start ||
        (payload.c != 0u && (payload.b > arg_total || payload.c > arg_total - payload.b))) return false;
    uint receiver = INVALID;
    uint callee = payload.a;
    if (valid_hir(callee) && compact_hir_core[callee].kind == HIR_MEMBER_EXPR && params.count != 0u &&
        self_token(compact_params[params.start].name_token) != INVALID)
        receiver = compact_hir_payload[callee].b;
    uint skip = receiver != INVALID ? 1u : 0u;
    uint count = min(min(payload.c, params.count - skip) + skip, ARG_LIMIT);
    for (uint i = 0u; i < count; i++)
    {
        if (param_mode(compact_params[params.start + i]) == EXCLUSIVE &&
            root_of(argument_at(node, payload.b, receiver, skip, i)) == root)
            return true;
    }
    return false;
}

// The outermost loop around `node` that does not contain the declaration
// `let_node`, or INVALID.
uint loop_after_let(uint node, uint let_node)
{
    uint loop = INVALID;
    uint current = compact_hir_core[node].parent;
    for (uint step = 0u; step < WALK_LIMIT && valid_hir(current); step++)
    {
        if (current < let_node && let_node < compact_hir_links[current].subtree_end) break;
        uint kind = compact_hir_core[current].kind;
        if (kind == HIR_WHILE_STMT || kind == HIR_FOR_STMT) loop = current;
        current = compact_hir_core[current].parent;
    }
    return loop;
}

// A reference local: reject each `&mut` use of its root while it is live.
void check_reference_let(uint node)
{
    HirPayload let_stmt = compact_hir_payload[node];
    if (let_stmt.a != STMT_LET || !valid_token(let_stmt.b)) return;
    // `let name: &...`: the annotation starts after the name and `:`.
    uint decl = let_stmt.b;
    if (!valid_hir(let_stmt.d) || !token_is(decl + 2u, TK_AMPERSAND)) return;
    // Only a reference made by a method call (`m.log.view()`, a method that
    // returns `self`) borrows the receiver's root. Reading a reference that
    // a field holds (`self.source`) copies it: it points elsewhere.
    uint init = let_stmt.c;
    for (uint step = 0u; step < WALK_LIMIT && valid_hir(init); step++)
    {
        HirCore core = compact_hir_core[init];
        bool forward = (core.kind == HIR_EXPR || core.kind == HIR_UNARY_EXPR) &&
            compact_hir_payload[init].a == HIR_EXPR_FORWARD;
        if (!forward) break;
        init = compact_hir_payload[init].b;
    }
    if (!valid_hir(init) || compact_hir_core[init].kind != HIR_CALL_EXPR) return;
    uint callee = compact_hir_payload[init].a;
    if (!valid_hir(callee) || compact_hir_core[callee].kind != HIR_MEMBER_EXPR) return;
    uint root = root_of(init);
    if (!valid_token(root)) return;
    // Uses of the local come after it in its function; visible_decl tells
    // them from other locals of the same name.
    uint fn = compact_hir_nearest_fn[node];
    if (!valid_hir(fn)) return;
    uint first = compact_hir_links[node].subtree_end;
    uint end = min(compact_hir_links[fn].subtree_end, hir_count());
    uint last_use = INVALID;
    for (uint at = first; at < end; at++)
        if (uses_decl(at, decl)) last_use = compact_hir_core[at].token_start;
    if (last_use == INVALID) return;
    for (uint at = first; at < end; at++)
    {
        if (!writes_root(at, root)) continue;
        bool live = last_use >= compact_hir_core[at].token_end;
        if (!live)
        {
            uint loop = loop_after_let(at, node);
            live = valid_hir(loop) && used_in(loop, min(compact_hir_links[loop].subtree_end, end), decl);
        }
        uint token = compact_hir_core[at].token_start;
        if (live && valid_token(token))
            record_min_token_error(status, token, ERR_ASSIGN_MISMATCH, LIVE_REFERENCE_WRITTEN);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;
    uint kind = compact_hir_core[node].kind;
    if (kind == HIR_LET_STMT || kind == HIR_STMT)
    {
        check_reference_let(node);
        return;
    }
    if (kind != HIR_CALL_EXPR) return;
    HirPayload payload = compact_hir_payload[node];
    uint fn = callee_fn(node);
    if (!valid_hir(fn)) return;
    HirRange params = compact_param_ranges[fn];
    uint param_total = min(compact_param_count[0u], gParams.n_hir_nodes);
    uint arg_total = min(compact_call_arg_count[0u], gParams.n_hir_nodes);
    if (params.start > param_total || params.count > param_total - params.start ||
        payload.b > arg_total || payload.c > arg_total - payload.b) return;
    // Position 0 is the receiver of a method call with a `self` parameter;
    // the call's arguments follow it.
    uint receiver = INVALID;
    uint callee = payload.a;
    if (valid_hir(callee) && compact_hir_core[callee].kind == HIR_MEMBER_EXPR && params.count != 0u)
    {
        if (self_token(compact_params[params.start].name_token) != INVALID)
            receiver = compact_hir_payload[callee].b;
    }
    uint skip = receiver != INVALID ? 1u : 0u;
    uint count = min(min(payload.c, params.count - skip) + skip, ARG_LIMIT);
    for (uint i = 0u; i < count; i++)
    {
        if (param_mode(compact_params[params.start + i]) != EXCLUSIVE) continue;
        uint value_i = argument_at(node, payload.b, receiver, skip, i);
        uint root_i = root_of(value_i);
        if (!valid_token(root_i)) continue;
        for (uint j = 0u; j < count; j++)
        {
            if (j == i || param_mode(compact_params[params.start + j]) == BY_VALUE) continue;
            uint value_j = argument_at(node, payload.b, receiver, skip, j);
            if (root_of(value_j) != root_i) continue;
            uint token = valid_hir(value_j) ? compact_hir_core[value_j].token_start : INVALID;
            if (valid_token(token))
                record_min_token_error(status, token, ERR_ASSIGN_MISMATCH, EXCLUSIVE_REFERENCE_ALIAS);
        }
    }
}
