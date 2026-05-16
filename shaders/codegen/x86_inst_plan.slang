// Direct x86_64 select planning over backend layout records.
//
// x86_entry_inst_plan and x86_func_return_inst_plan materialize instruction
// rows. x86_reloc_plan materializes relocation rows. This pass publishes the
// compact select plan from the layout/status records those producers emit.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_return_vreg;
StructuredBuffer<uint> x86_vreg_value;
StructuredBuffer<uint4> x86_call_abi_record;
StructuredBuffer<uint4> x86_terminal_if_record;
StructuredBuffer<uint4> x86_func_layout_record;
StructuredBuffer<uint> x86_func_layout_status;
StructuredBuffer<uint> x86_func_return_inst_status;
StructuredBuffer<uint> x86_entry_inst_status;

RWStructuredBuffer<uint> x86_select_plan;
RWStructuredBuffer<uint> plan_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_FUNC_LAYOUT_OK = 1u;
static const uint X86_FUNC_RETURN_INST_OK = 1u;
static const uint X86_ENTRY_INST_OK = 1u;
static const uint X86_PLAN_OK = 1u;
static const uint X86_ERR_UNSUPPORTED_RETURN = 3u;

static const uint X86_SELECT_SHAPE_LITERAL = 1u;
static const uint X86_SELECT_SHAPE_BINARY = 2u;
static const uint X86_SELECT_SHAPE_COMPARE = 3u;
static const uint X86_SELECT_SHAPE_BRANCH = 4u;
static const uint X86_SELECT_SHAPE_CALL = 5u;
static const uint X86_FUNC_LAYOUT_CALLEE = 2u;

static const uint X86_LAYOUT_STATUS_TOTAL_INSTS = 3u;
static const uint X86_LAYOUT_STATUS_SHAPE = 6u;
static const uint X86_LAYOUT_STATUS_NESTED_CALL_NODE = 5u;
static const uint X86_ENTRY_STATUS_INST_COUNT = 3u;
static const uint X86_ENTRY_STATUS_RELOC_COUNT = 5u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint call_abi_base_row(uint call_node)
{
    return call_node * 2u;
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool terminal_if_record_at(
    uint key_node,
    out uint then_expr,
    out uint else_expr)
{
    then_expr = INVALID;
    else_expr = INVALID;
    if (!valid_node(key_node))
        return false;

    uint4 terminal_if = x86_terminal_if_record[key_node];
    if (!valid_node(terminal_if.x) ||
        !valid_node(terminal_if.y) ||
        !valid_node(terminal_if.z) ||
        !valid_node(terminal_if.w))
        return false;

    then_expr = terminal_if.z;
    else_expr = terminal_if.w;
    return true;
}

bool call_target_fn(uint call_node, out uint target_fn)
{
    target_fn = INVALID;
    if (!valid_node(call_node))
        return false;

    uint4 call_abi = x86_call_abi_record[call_abi_base_row(call_node)];
    target_fn = call_abi.y;
    return valid_node(call_abi.x) && valid_node(target_fn);
}

uint direct_call_reloc_count(uint node)
{
    uint target_fn = INVALID;
    if (!call_target_fn(node, target_fn))
        return 0u;
    return 1u;
}

uint flat_terminal_if_reloc_count(uint key_node)
{
    uint then_expr = INVALID;
    uint else_expr = INVALID;
    if (!terminal_if_record_at(key_node, then_expr, else_expr))
        return 0u;

    return 2u;
}

uint call_value_reloc_count(uint node)
{
    uint target_fn = INVALID;
    if (!call_target_fn(node, target_fn))
        return 0u;

    uint target_then = INVALID;
    uint target_else = INVALID;
    if (!terminal_if_record_at(target_fn, target_then, target_else))
        return 1u;

    return 1u + flat_terminal_if_reloc_count(target_fn);
}

uint terminal_if_reloc_count(uint key_node)
{
    uint then_expr = INVALID;
    uint else_expr = INVALID;
    if (!terminal_if_record_at(key_node, then_expr, else_expr))
        return 0u;

    uint reloc_count = 2u + call_value_reloc_count(then_expr);
    uint nested_then = INVALID;
    uint nested_else = INVALID;
    if (terminal_if_record_at(else_expr, nested_then, nested_else))
        reloc_count += flat_terminal_if_reloc_count(else_expr);
    else
        reloc_count += call_value_reloc_count(else_expr);
    return reloc_count;
}

uint callee_terminal_if_reloc_count(uint return_vreg)
{
    if (return_vreg == INVALID)
        return 0u;

    uint call_node = x86_vreg_value[return_vreg];
    if (!valid_node(call_node))
        return 0u;

    uint4 call_abi = x86_call_abi_record[call_abi_base_row(call_node)];
    uint target_fn = call_abi.y;
    if (!valid_node(target_fn))
        return 0u;

    uint4 layout = x86_func_layout_record[target_fn];
    if (layout.z != X86_FUNC_LAYOUT_CALLEE)
        return 0u;

    return terminal_if_reloc_count(target_fn);
}

void write_plan(
    uint shape,
    uint inst_count,
    uint reloc_count,
    uint return_vreg,
    uint nested_call_node)
{
    x86_select_plan[0u] = shape;
    x86_select_plan[1u] = inst_count;
    x86_select_plan[2u] = reloc_count;
    x86_select_plan[3u] = return_vreg;
    x86_select_plan[4u] = nested_call_node;
}

bool upstream_ok()
{
    return x86_func_layout_status[0u] == X86_FUNC_LAYOUT_OK &&
           x86_func_layout_status[1u] == 0u &&
           x86_func_return_inst_status[0u] == X86_FUNC_RETURN_INST_OK &&
           x86_func_return_inst_status[1u] == 0u &&
           x86_entry_inst_status[0u] == X86_ENTRY_INST_OK &&
           x86_entry_inst_status[1u] == 0u;
}

uint upstream_error()
{
    if (x86_func_layout_status[1u] != 0u)
        return x86_func_layout_status[1u];
    if (x86_func_return_inst_status[1u] != 0u)
        return x86_func_return_inst_status[1u];
    if (x86_entry_inst_status[1u] != 0u)
        return x86_entry_inst_status[1u];
    return X86_ERR_UNSUPPORTED_RETURN;
}

uint upstream_detail()
{
    if (x86_func_layout_status[1u] != 0u)
        return x86_func_layout_status[2u];
    if (x86_func_return_inst_status[1u] != 0u)
        return x86_func_return_inst_status[2u];
    if (x86_entry_inst_status[1u] != 0u)
        return x86_entry_inst_status[2u];
    return x86_func_layout_status[2u];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (linear_dispatch_id(tid) != 0u)
        return;

    uint shape = x86_func_layout_status[X86_LAYOUT_STATUS_SHAPE];
    uint inst_count = x86_func_layout_status[X86_LAYOUT_STATUS_TOTAL_INSTS];
    uint entry_inst_count = x86_entry_inst_status[X86_ENTRY_STATUS_INST_COUNT];
    uint return_vreg = x86_return_vreg[0u];
    bool branch_ok = shape == X86_SELECT_SHAPE_BRANCH;
    bool call_ok = shape == X86_SELECT_SHAPE_CALL;
    bool shape_ok = shape == X86_SELECT_SHAPE_LITERAL ||
                    shape == X86_SELECT_SHAPE_BINARY ||
                    shape == X86_SELECT_SHAPE_COMPARE ||
                    branch_ok ||
                    call_ok;
    bool ok = upstream_ok() &&
              shape_ok &&
              inst_count != 0u &&
              inst_count == entry_inst_count;
    uint nested_call_node = call_ok ?
                            x86_func_layout_status[X86_LAYOUT_STATUS_NESTED_CALL_NODE] :
                            INVALID;
    uint nested_call_relocs = valid_node(nested_call_node) ?
                              call_value_reloc_count(nested_call_node) :
                              0u;
    uint callee_relocs = call_ok ?
                         callee_terminal_if_reloc_count(return_vreg) +
                         nested_call_relocs :
                         0u;
    uint entry_relocs = x86_entry_inst_status[X86_ENTRY_STATUS_RELOC_COUNT];
    uint reloc_count = entry_relocs +
                       (branch_ok ? 2u :
                        (call_ok ? 1u + callee_relocs : 0u));

    write_plan(
        ok ? shape : 0u,
        ok ? inst_count : 0u,
        ok ? reloc_count : 0u,
        ok ? return_vreg : INVALID,
        ok ? nested_call_node : INVALID);
    plan_status[0u] = ok ? X86_PLAN_OK : 0u;
    plan_status[1u] = ok ? 0u : upstream_error();
    plan_status[2u] = ok ? INVALID : upstream_detail();
    plan_status[3u] = ok ? inst_count : 0u;
}
