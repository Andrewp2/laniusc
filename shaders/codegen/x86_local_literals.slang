// x86_64 local literal projection over HIR statement/expression records.
//
// This pass projects supported top-level literal/constant let bindings by
// declaration token. It repeatedly scans HIR records on the GPU so local chains
// resolve through visible_decl and the already-projected declaration table,
// without relying on HIR node numbering as a source-order proxy. Later x86
// consumers resolve a name through visible_decl and read this table directly
// instead of scanning all HIR statements to rediscover locals.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint4> x86_const_value_record;
StructuredBuffer<uint> x86_const_value_status;

RWStructuredBuffer<uint4> x86_local_literal_record;
RWStructuredBuffer<uint> x86_local_literal_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_FN = 3u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint X86_LOCAL_LITERALS_OK = 1u;
static const uint X86_LOCAL_LITERAL_TOP_LEVEL = 1u;
static const uint X86_CONST_VALUES_OK = 1u;
static const uint X86_CONST_VALUE_LITERAL = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
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

uint stmt_record_slot(uint node, uint slot)
{
    return hir_stmt_record[node * STMT_RECORD_STRIDE + slot];
}

uint expr_record_slot(uint node, uint slot)
{
    return hir_expr_record[node * EXPR_RECORD_STRIDE + slot];
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_FORM) : 0u;
}

uint expr_left(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

uint expr_right(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_RIGHT) : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (!valid_node(node))
            return INVALID;
        if (expr_form(node) != HIR_EXPR_FORWARD)
            return node;
        node = expr_left(node);
    }
    return INVALID;
}

uint owning_function_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    if (hir_kind[node] == HIR_FN)
        return node;

    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return INVALID;
        if (hir_kind[p] == HIR_FN)
            return p;
        cur = p;
    }
    return INVALID;
}

bool node_has_hir_ancestor(uint node, uint ancestor_kind, uint stop_node)
{
    if (!valid_node(node))
        return false;
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = parent[cur];
        if (!valid_node(p) || p == cur || p == stop_node)
            return false;
        if (hir_kind[p] == ancestor_kind)
            return true;
        cur = p;
    }
    return false;
}

bool const_values_ok()
{
    return x86_const_value_status[0u] == X86_CONST_VALUES_OK &&
           x86_const_value_status[1u] == 0u;
}

bool literal_leaf_value(uint value_node, out uint value)
{
    value = 0u;
    value_node = resolve_expr(value_node);
    if (!valid_node(value_node))
        return false;

    uint form = expr_form(value_node);
    if (form == HIR_EXPR_INT)
    {
        value = hir_expr_int_value[value_node];
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        value = form == HIR_EXPR_TRUE ? 1u : 0u;
        return true;
    }
    return false;
}

bool const_atom_value(uint token_i, out uint value)
{
    value = 0u;
    if (!const_values_ok() || !valid_token(token_i))
        return false;

    uint decl_i = visible_decl[token_i];
    if (!valid_token(decl_i))
        return false;

    uint4 record = x86_const_value_record[decl_i];
    if (record.x != X86_CONST_VALUE_LITERAL)
        return false;

    value = record.y;
    return true;
}

bool local_atom_value(
    uint token_i,
    uint fn_node,
    out uint value)
{
    value = 0u;
    if (!valid_token(token_i) || !valid_node(fn_node))
        return false;

    uint decl_i = visible_decl[token_i];
    if (!valid_token(decl_i))
        return false;

    uint4 record = x86_local_literal_record[decl_i];
    if (record.x != fn_node || record.y == INVALID)
        return false;
    if (record.w != X86_LOCAL_LITERAL_TOP_LEVEL)
        return false;

    value = record.z;
    return true;
}

bool expr_leaf_value(
    uint value_node,
    uint fn_node,
    uint before_node,
    out uint value)
{
    value = 0u;
    value_node = resolve_expr(value_node);
    if (literal_leaf_value(value_node, value))
        return true;
    if (!valid_node(value_node))
        return false;

    if (expr_form(value_node) == HIR_EXPR_NAME)
    {
        uint token_i = expr_value_token(value_node);
        if (const_atom_value(token_i, value))
            return true;
        return local_atom_value(token_i, fn_node, value);
    }
    return false;
}

bool binary_const_value(uint form, uint left, uint right, out uint value)
{
    value = 0u;
    if (form == HIR_EXPR_ADD)
    {
        value = left + right;
        return true;
    }
    if (form == HIR_EXPR_SUB)
    {
        value = left - right;
        return true;
    }
    if (form == HIR_EXPR_MUL)
    {
        value = left * right;
        return true;
    }
    if (form == HIR_EXPR_EQ)
    {
        value = left == right ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_NE)
    {
        value = left != right ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_LT)
    {
        value = int(left) < int(right) ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_GT)
    {
        value = int(left) > int(right) ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_LE)
    {
        value = int(left) <= int(right) ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_GE)
    {
        value = int(left) >= int(right) ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_AND)
    {
        value = (left != 0u && right != 0u) ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_OR)
    {
        value = (left != 0u || right != 0u) ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_BIT_AND)
    {
        value = left & right;
        return true;
    }
    if (form == HIR_EXPR_BIT_OR)
    {
        value = left | right;
        return true;
    }
    if (form == HIR_EXPR_BIT_XOR)
    {
        value = left ^ right;
        return true;
    }
    if (form == HIR_EXPR_SHL)
    {
        value = left << (right & 31u);
        return true;
    }
    if (form == HIR_EXPR_SHR)
    {
        value = uint(int(left) >> int(right & 31u));
        return true;
    }
    if (form == HIR_EXPR_MOD)
    {
        if (right == 0u)
            return false;
        value = left % right;
        return true;
    }
    if (form == HIR_EXPR_DIV)
    {
        if (right == 0u)
            return false;
        value = uint(int(left) / int(right));
        return true;
    }
    return false;
}

bool const_expr_value(uint root, uint fn_node, uint before_node, out uint value)
{
    value = 0u;
    root = resolve_expr(root);
    if (!valid_node(root))
        return false;

    uint node_stack[32];
    uint state_stack[32];
    uint left_stack[32];
    uint sp = 1u;
    uint last_value = 0u;
    node_stack[0u] = root;
    state_stack[0u] = 0u;
    left_stack[0u] = 0u;

    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (sp == 0u)
        {
            value = last_value;
            return true;
        }

        uint frame = sp - 1u;
        uint node = resolve_expr(node_stack[frame]);
        if (!valid_node(node))
            return false;

        uint state = state_stack[frame];
        uint form = expr_form(node);
        if (state == 0u)
        {
            if (expr_leaf_value(node, fn_node, before_node, last_value))
            {
                sp -= 1u;
                continue;
            }
            if (form == HIR_EXPR_NEG || form == HIR_EXPR_NOT)
            {
                if (sp >= 32u)
                    return false;
                state_stack[frame] = 1u;
                node_stack[sp] = expr_left(node);
                state_stack[sp] = 0u;
                left_stack[sp] = 0u;
                sp += 1u;
                continue;
            }
            if (form == HIR_EXPR_ADD ||
                form == HIR_EXPR_SUB ||
                form == HIR_EXPR_MUL ||
                form == HIR_EXPR_EQ ||
                form == HIR_EXPR_NE ||
                form == HIR_EXPR_LT ||
                form == HIR_EXPR_GT ||
                form == HIR_EXPR_LE ||
                form == HIR_EXPR_GE ||
                form == HIR_EXPR_AND ||
                form == HIR_EXPR_OR ||
                form == HIR_EXPR_MOD ||
                form == HIR_EXPR_DIV ||
                form == HIR_EXPR_BIT_OR ||
                form == HIR_EXPR_BIT_XOR ||
                form == HIR_EXPR_BIT_AND ||
                form == HIR_EXPR_SHL ||
                form == HIR_EXPR_SHR)
            {
                if (sp >= 32u)
                    return false;
                state_stack[frame] = 2u;
                node_stack[sp] = expr_left(node);
                state_stack[sp] = 0u;
                left_stack[sp] = 0u;
                sp += 1u;
                continue;
            }
            return false;
        }
        if (state == 1u)
        {
            last_value = form == HIR_EXPR_NEG ? 0u - last_value :
                                                (last_value == 0u ? 1u : 0u);
            sp -= 1u;
            continue;
        }
        if (state == 2u)
        {
            left_stack[frame] = last_value;
            state_stack[frame] = 3u;
            if (sp >= 32u)
                return false;
            node_stack[sp] = expr_right(node);
            state_stack[sp] = 0u;
            left_stack[sp] = 0u;
            sp += 1u;
            continue;
        }
        if (state == 3u)
        {
            uint result = 0u;
            if (!binary_const_value(form, left_stack[frame], last_value, result))
                return false;
            last_value = result;
            sp -= 1u;
            continue;
        }
        return false;
    }
    return false;
}

void scatter_local_literal(uint let_node)
{
    if (stmt_record_slot(let_node, 0u) != STMT_RECORD_KIND_LET)
        return;

    uint fn_node = owning_function_node(let_node);
    if (!valid_node(fn_node))
        return;
    if (node_has_hir_ancestor(let_node, HIR_IF_STMT, fn_node))
        return;

    uint decl_i = stmt_record_slot(let_node, 1u);
    if (!valid_token(decl_i))
        return;

    uint value = 0u;
    uint expr_node = stmt_record_slot(let_node, 2u);
    if (!const_expr_value(expr_node, fn_node, let_node, value))
        return;

    uint4 previous = x86_local_literal_record[decl_i];
    bool fresh_record = previous.x != fn_node ||
                        previous.y != let_node ||
                        previous.w != X86_LOCAL_LITERAL_TOP_LEVEL;
    x86_local_literal_record[decl_i] =
        uint4(fn_node, let_node, value, X86_LOCAL_LITERAL_TOP_LEVEL);
    if (fresh_record)
    {
        uint old_count = 0u;
        InterlockedAdd(x86_local_literal_status[3u], 1u, old_count);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i != 0u)
        return;

    uint n = active_hir_node_count();
    [loop]
    for (uint iteration = 0u; iteration < gParams.n_hir_nodes; iteration += 1u)
    {
        if (iteration >= n)
            break;

        [loop]
        for (uint scan = 0u; scan < gParams.n_hir_nodes; scan += 1u)
        {
            if (scan >= n)
                break;
            scatter_local_literal(scan);
        }
    }
}
