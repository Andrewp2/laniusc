import primitive_types;
import hir_records;
import hir_expr_semantics;

// Contexts belong to expression roots. Forwarding HIR wrappers do not create
// another expression or another owner of its expected type.
public uint argument_context_root(uint node, uint count,
    StructuredBuffer<HirCore> core, StructuredBuffer<HirPayload> payload)
{
    for (uint step = 0u; step < count && node < count; step++)
    {
        uint kind = core[node].kind;
        if (!hir_is_forward_expression(kind, payload[node].a))
            return node;
        uint child = payload[node].b;
        if (child >= count || child == node) return 0xffffffffu;
        node = child;
    }
    return 0xffffffffu;
}

// Unsuffixed integer literals, including a single unary minus, can take a
// checked integer context. This does not convert an already typed value.
public bool integer_literal_magnitude(uint node, uint count,
    StructuredBuffer<HirCore> core, StructuredBuffer<HirPayload> payload,
    out uint literal, out bool negative)
{
    node = argument_context_root(node, count, core, payload);
    negative = false;
    if (node < count && core[node].kind == 17u && payload[node].a == 13u)
    {
        negative = true;
        node = argument_context_root(payload[node].b, count, core, payload);
    }
    literal = node;
    return node < count && core[node].kind == HIR_SEM_KIND_LITERAL_EXPR &&
        payload[node].a == HIR_SEM_EXPR_INT;
}

// A numeric expression with no independently typed value operand supplies a
// provisional claim. Named values, casts, calls and other-category leaves retain
// their own types. A shift count has an independent type and does not constrain
// its value operand. Literal children of mixed arithmetic receive their own
// context in the separate literal-context pass.
public bool numeric_literal_accepts_context(uint node, uint scalar, uint count,
    StructuredBuffer<HirCore> core, StructuredBuffer<HirPayload> payload,
    StructuredBuffer<uint> expression_parent)
{
    bool floating = scalar_is_float(scalar);
    if ((!floating && !scalar_is_integer(scalar)) || node >= count) return false;
    uint root = node;
    // The parser owns an acyclic expression forest and exact parent edges.
    // Walk children and those edges with constant private storage; the active
    // row count bounds work without imposing another expression-depth limit.
    for (uint visited = 0u; visited < count; visited++)
    {
        if (node >= count) return false;
        uint kind = core[node].kind;
        HirPayload value = payload[node];
        bool unary = kind == 17u && value.a == 13u;
        bool arithmetic = kind == 16u &&
            ((value.a >= 14u && value.a <= 16u) || value.a == 20u ||
             (!floating && value.a >= 19u && value.a <= 25u));
        if (hir_is_forward_expression(kind, value.a) || unary || arithmetic)
        {
            if (value.b >= count || value.b == node || expression_parent[value.b] != node)
                return false;
            if (arithmetic && (value.c >= count || value.c == node || value.b == value.c ||
                expression_parent[value.c] != node)) return false;
            node = value.b;
            continue;
        }
        if (kind != HIR_SEM_KIND_LITERAL_EXPR ||
            value.a != (floating ? HIR_SEM_EXPR_FLOAT : HIR_SEM_EXPR_INT))
            return false;
        bool next = false;
        for (uint ascended = 0u; ascended < count; ascended++)
        {
            if (node == root) return true;
            uint owner = expression_parent[node];
            if (owner >= count || owner == node) return false;
            HirCore owner_core = core[owner];
            HirPayload owner_value = payload[owner];
            bool binary = owner_core.kind == 16u &&
                ((owner_value.a >= 14u && owner_value.a <= 16u) || owner_value.a == 20u ||
                 (!floating && owner_value.a >= 19u && owner_value.a <= 25u));
            bool shift = owner_value.a == 24u || owner_value.a == 25u;
            if (binary && !shift && owner_value.b == node)
            {
                uint right = owner_value.c;
                if (right >= count || right == node || right == owner ||
                    expression_parent[right] != owner) return false;
                node = right;
                next = true;
                break;
            }
            bool forwards = hir_is_forward_expression(owner_core.kind, owner_value.a);
            bool negates = owner_core.kind == 17u && owner_value.a == 13u;
            if (!(((forwards || negates || (binary && shift)) && owner_value.b == node) ||
                  (binary && !shift && owner_value.c == node))) return false;
            node = owner;
        }
        if (!next) return false;
    }
    return false;
}
