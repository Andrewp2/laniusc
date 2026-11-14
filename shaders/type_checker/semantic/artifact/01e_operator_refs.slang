// The checked type reference of an operator row whose operand type is a
// type parameter. One lane per dense HIR row.
//
// Expression typing (expression_types/00_init) gives an arithmetic, bitwise
// or negation row its operand's scalar type, and 01_expression_refs projects
// that scalar. Under `T` there is no scalar, so the row would stay untyped.
// The instance table then reads such a row as having the template's type in
// every instance, and a copy at `f64` lowers `a + b` as an integer add.
//
// This pass gives the row its operand's symbolic reference: the exact
// parameter reference of the operand's declaration, not a slot or a name.
// The instance table substitutes it under each environment. A forwarding
// wrapper (parentheses) takes its child's reference the same way.
// Comparisons and logical operators already have a bool result reference;
// their operand constraints are checked per instance (closure/06c).
//
// An unsuffixed literal whose context is a type parameter
// (literal_symbolic_context.slang) has no template scalar either. Its row
// takes that parameter's reference, so `a + 1` at `u8` has a `u8` literal
// and `2 * a` at `f64` is rejected at the `2`, per instance.
//
// The result type of an inherited row is its first operand's (00_init
// follows the same edge), so a row walks its left operand chain to the
// first row that is not operator-shaped. A literal leaf with a symbolic
// context gives that context; any other leaf gives its reference when it is
// a parameter reference. The walk is the chain 00_init walks, no wider.
//
// A lane writes only its own row, when it is still untyped. Operator lanes
// read the references of leaves that are not literals, which no lane
// writes, and a literal leaf's context, which this pass does not write.
import hir_records;
import hir_expr_semantics;
import gpu_index;
import type_checker.literal_symbolic_context;
import type_checker.inherited_expression_type;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> literal_context_type_by_hir;
RWStructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
RWStructuredBuffer<uint> semantic_expr_ref_payload_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint HIR_EXPR = 14u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint DISPATCH_X_STRIDE = 16776960u;
[ForceInline]
uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }

// The symbolic context of an unsuffixed numeric literal row, or 0.
uint symbolic_literal_context(uint node)
{
    if (!valid_hir(node) || compact_hir_core[node].kind != HIR_LITERAL_EXPR) return 0u;
    uint form = compact_hir_payload[node].a;
    if (form != HIR_EXPR_INT && form != HIR_EXPR_FLOAT) return 0u;
    uint context = literal_context_type_by_hir[node];
    return literal_context_is_symbolic(context) ? context : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node) || semantic_expr_ref_tag_by_hir[node] != TYPE_REF_INVALID) return;
    uint context = symbolic_literal_context(node);
    if (context != 0u)
    {
        semantic_expr_ref_tag_by_hir[node] = TYPE_REF_GENERIC_PARAM;
        semantic_expr_ref_payload_by_hir[node] = literal_context_parameter(context);
        return;
    }
    if (!expression_inherits_operand_type(compact_hir_core[node].kind, compact_hir_payload[node].a)) return;
    uint current = inherited_expression_type_leaf(node, active_hir_count(), compact_hir_core, compact_hir_payload);
    if (!valid_hir(current)) return;
    context = symbolic_literal_context(current);
    if (context != 0u)
    {
        semantic_expr_ref_tag_by_hir[node] = TYPE_REF_GENERIC_PARAM;
        semantic_expr_ref_payload_by_hir[node] = literal_context_parameter(context);
        return;
    }
    // Only a parameter reference is taken. A concrete operand already typed
    // the row through its scalar cache; any other reference here is not an
    // arithmetic operand type, and 06c/compact_expr check the operand.
    if (semantic_expr_ref_tag_by_hir[current] == TYPE_REF_GENERIC_PARAM)
    {
        semantic_expr_ref_tag_by_hir[node] = TYPE_REF_GENERIC_PARAM;
        semantic_expr_ref_payload_by_hir[node] = semantic_expr_ref_payload_by_hir[current];
    }
}
