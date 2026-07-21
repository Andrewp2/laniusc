// Publish the target-independent expression forest over dense compact HIR.

import atomics;

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirCallArg { uint call; uint value; uint ordinal; uint file_id; };

ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<HirCore> hir_core;
StructuredBuffer<HirPayload> hir_payload;
StructuredBuffer<uint> call_arg_count;
StructuredBuffer<HirCallArg> call_args;
RWStructuredBuffer<uint> expr_parent_encoded;
RWStructuredBuffer<uint> expr_forest_status;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_EXPR = 14u;
static const uint HIR_STMT = 7u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_INDEX = 26u;
static const uint HIR_STMT_ASSIGN = 5u;
static const uint HIR_STMT_FOR = 7u;

uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_hir_count() { return min(canonical_count[0u], gCanonical.canonical_capacity); }
uint active_arg_count() { return min(call_arg_count[0u], gCanonical.canonical_capacity); }
bool valid_hir(uint hir) { return hir != INVALID && hir < active_hir_count(); }

bool fixed_arity_expression_kind(uint kind)
{
    return kind >= HIR_EXPR && kind <= HIR_LITERAL_EXPR &&
           kind != HIR_CALL_EXPR && kind != HIR_MEMBER_EXPR;
}

bool binary_form(uint form)
{
    return (form >= HIR_EXPR_EQ && form <= HIR_EXPR_GE) ||
           (form >= HIR_EXPR_ADD && form <= HIR_EXPR_SHR) ||
           form == HIR_EXPR_INDEX;
}

void publish_parent(uint child, uint owner)
{
    if (!valid_hir(child) || !valid_hir(owner) || child == owner)
    {
        atomic_u32_or(expr_forest_status, 0u, 1u);
        return;
    }

    uint encoded_owner = owner + 1u;
    uint previous = 0u;
    InterlockedCompareExchange(expr_parent_encoded[child], 0u, encoded_owner, previous);
    if (previous != 0u && previous != encoded_owner)
        atomic_u32_or(expr_forest_status, 0u, 2u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = tid(dtid);
    uint hir_count = active_hir_count();
    if (row < hir_count)
    {
        HirCore core = hir_core[row];
        HirPayload payload = hir_payload[row];
        if (fixed_arity_expression_kind(core.kind))
        {
            if (payload.a == HIR_EXPR_NOT || payload.a == HIR_EXPR_NEG)
                publish_parent(payload.b, row);
            else if (binary_form(payload.a))
            {
                publish_parent(payload.b, row);
                publish_parent(payload.c, row);
            }
        }

        if (core.kind == HIR_MEMBER_EXPR)
            publish_parent(payload.b, row);
        else if ((core.kind == HIR_STMT || core.kind == HIR_ASSIGN_EXPR) &&
                 payload.a == HIR_STMT_ASSIGN)
            // The destination path is assignment-owned lvalue syntax. It
            // contributes a declaration identity, not a value load.
            publish_parent(payload.b, row);
        else if (core.kind == HIR_FOR_STMT ||
                 (core.kind == HIR_STMT && payload.a == HIR_STMT_FOR))
            // The iterable/range wrapper is control syntax. Its bound
            // expressions remain independent value roots.
            publish_parent(payload.c, row);
        else if (core.kind == HIR_CALL_EXPR && valid_hir(payload.a))
            // The callee is owned syntax, not an independently evaluated
            // value. Keeping this edge for paths as well as member chains
            // lets lowering suppress the callee row without reverse-searching
            // every call.
            publish_parent(payload.a, row);
    }

    if (row < active_arg_count())
    {
        HirCallArg arg = call_args[row];
        publish_parent(arg.value, arg.call);
    }
}
