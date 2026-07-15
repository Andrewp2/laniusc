// Publish the target-independent expression forest from parser-owned HIR records.
//
// Each semantic HIR row handles its own fixed-arity operand edges. Call
// arguments independently publish the edge to their owning call, so wide calls
// remain fully parallel. Forwarding wrappers are resolved through the parser's
// pointer-jumped result-root table before an edge is written.

import atomics;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirExprForest;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint> hir_member_receiver_node;

RWStructuredBuffer<uint> hir_expr_parent_node;
RWStructuredBuffer<uint> hir_expr_forest_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SHR = 25u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirExprForest.uses_status_count != 0u ?
        min(gHirExprForest.n, tree_count_status[5u]) :
        gHirExprForest.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

uint semantic_row_node(uint row)
{
    if (row >= active_semantic_count())
        return INVALID;
    uint node = hir_semantic_dense_node[row];
    return valid_node(node) ? node : INVALID;
}

uint expr_record_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint resolved_expr_node(uint node)
{
    // Raw parser argument rows occupy the full HIR-capacity domain even when
    // they are not members of the compact semantic-node projection.
    if (node == INVALID || node >= gHirExprForest.n)
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    if (valid_node(root))
        return root;
    uint form = expr_record_slot(node, EXPR_RECORD_FORM);
    return valid_node(node) && form != HIR_EXPR_FORWARD ? node : INVALID;
}

bool binary_form(uint form)
{
    return (form >= HIR_EXPR_EQ && form <= HIR_EXPR_GE) ||
           (form >= HIR_EXPR_ADD && form <= HIR_EXPR_SHR);
}

void publish_parent_node(uint child, uint owner)
{
    if (!valid_node(child) || !valid_node(owner) || child == owner)
    {
        atomic_u32_or(hir_expr_forest_status, 0u, 1u);
        return;
    }

    uint previous = INVALID;
    InterlockedCompareExchange(hir_expr_parent_node[child], INVALID, owner, previous);
    if (previous != INVALID && previous != owner)
        atomic_u32_or(hir_expr_forest_status, 0u, 2u);
}

void publish_parent(uint raw_child, uint owner)
{
    publish_parent_node(resolved_expr_node(raw_child), owner);
}

void publish_member_receiver_parent(uint member)
{
    uint raw_receiver = hir_member_receiver_node[member];
    uint receiver = valid_node(raw_receiver) && hir_kind[raw_receiver] == HIR_MEMBER_EXPR
                        ? raw_receiver
                        : resolved_expr_node(raw_receiver);
    publish_parent_node(receiver, member);
}

uint method_member_node(uint call)
{
    if (!valid_node(call) || hir_kind[call] != HIR_CALL_EXPR)
        return INVALID;

    uint member = hir_call_callee_node[call];
    if (!valid_node(member) || hir_kind[member] != HIR_MEMBER_EXPR)
    {
        member = resolved_expr_node(member);
        if (!valid_node(member) || hir_kind[member] != HIR_MEMBER_EXPR)
            return INVALID;
    }
    return member;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint node = semantic_row_node(row);
    if (node != INVALID)
    {
        uint form = expr_record_slot(node, EXPR_RECORD_FORM);
        if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
        {
            publish_parent(expr_record_slot(node, EXPR_RECORD_LEFT), node);
        }
        else if (binary_form(form))
        {
            publish_parent(expr_record_slot(node, EXPR_RECORD_LEFT), node);
            publish_parent(expr_record_slot(node, EXPR_RECORD_RIGHT), node);
        }

        // Member-address chains are expression trees too. Publishing one edge
        // per receiver lets each member contribute only its own load, so an
        // arbitrarily deep chain is reduced by the same parallel subtree scan
        // as scalar operators instead of a bounded per-lane walk.
        // Method receivers are implicit ABI arguments rather than entries in
        // the raw call-argument rows. Attach the callee member node; its own
        // receiver edge above then preserves the complete expression chain.
        if (hir_kind[node] == HIR_CALL_EXPR)
        {
            uint member = method_member_node(node);
            if (valid_node(member))
                publish_parent_node(member, node);
        }
    }

    // Call-argument metadata is indexed by raw argument rows, not by the
    // semantic dense-node projection used for fixed-arity expression records.
    // Publish this independent edge even when the raw wrapper is not itself a
    // semantic row; publish_parent resolves that wrapper to its semantic root.
    uint raw_arg = row < gHirExprForest.n ? row : INVALID;
    // Nested member receivers can live outside the compact semantic-node
    // projection, just like raw call-argument wrappers. Publish these edges
    // over the full active HIR domain so no member depth is silently skipped.
    if (valid_node(raw_arg) && hir_kind[raw_arg] == HIR_MEMBER_EXPR)
        publish_member_receiver_parent(raw_arg);

    uint call = raw_arg != INVALID ? hir_call_arg_parent_call[raw_arg] : INVALID;
    if (valid_node(call) && hir_kind[call] == HIR_CALL_EXPR)
        publish_parent(raw_arg, call);
}
