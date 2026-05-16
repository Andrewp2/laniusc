// Direct x86_64 instruction selection from allocated virtual instructions.
//
// The selected instruction records are derived from node-generated virtual
// instruction rows after GPU liveness and register allocation. This pass does
// not inspect source text, token spelling, helper names, or function-body
// shapes.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_select_plan;
StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint4> x86_virtual_inst_args;
StructuredBuffer<uint> x86_virtual_inst_status;
StructuredBuffer<uint> x86_virtual_phys_reg;
StructuredBuffer<uint> x86_virtual_regalloc_status;
StructuredBuffer<uint> x86_func_meta;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> x86_planned_inst_kind;
StructuredBuffer<uint> x86_planned_inst_arg0;
StructuredBuffer<uint> x86_planned_reloc_kind;
StructuredBuffer<uint> x86_planned_reloc_site_inst;
StructuredBuffer<uint> x86_planned_reloc_target_inst;
StructuredBuffer<uint> plan_status;

RWStructuredBuffer<uint> x86_inst_kind;
RWStructuredBuffer<uint> x86_inst_arg0;
RWStructuredBuffer<uint> x86_inst_arg1;
RWStructuredBuffer<uint> x86_inst_arg2;
RWStructuredBuffer<uint> x86_reloc_count;
RWStructuredBuffer<uint> x86_reloc_kind;
RWStructuredBuffer<uint> x86_reloc_site_inst;
RWStructuredBuffer<uint> x86_reloc_target_inst;
RWStructuredBuffer<uint> select_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_INSTS = 256u;
static const uint MAX_X86_RELOCS = 8u;

static const uint X86_SELECT_OK = 1u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_VIRTUAL_REGALLOC_OK = 1u;
static const uint X86_ERR_SELECT = 17u;

static const uint X86_VINST_IMM_I32 = 1u;
static const uint X86_VINST_PARAM = 2u;
static const uint X86_VINST_UNARY = 3u;
static const uint X86_VINST_BINARY = 4u;
static const uint X86_VINST_COMPARE = 5u;
static const uint X86_VINST_CALL = 6u;
static const uint X86_VINST_INTRINSIC = 7u;
static const uint X86_VINST_ALIAS = 8u;
static const uint X86_VINST_RETURN = 9u;
static const uint X86_VINST_BRANCH = 10u;
static const uint X86_VINST_LOOP = 11u;
static const uint X86_VINST_TRANSFER = 12u;

static const uint X86_INST_V_MOV_R32_IMM32 = 50u;
static const uint X86_INST_V_MOV_R32_R32 = 51u;
static const uint X86_INST_V_UNARY_R32 = 52u;
static const uint X86_INST_V_BINARY_R32_R32 = 53u;
static const uint X86_INST_V_COMPARE_R32_R32 = 54u;
static const uint X86_INST_V_RETURN_R32 = 55u;
static const uint X86_INST_V_BRANCH_ZERO = 56u;
static const uint X86_INST_V_JMP = 57u;
static const uint X86_INST_V_PARAM_R32 = 58u;
static const uint X86_INST_V_CALL_DIRECT = 59u;
static const uint X86_INST_V_RETURN_FUNC_R32 = 60u;
static const uint X86_INST_V_PRINT_I32 = 61u;
static const uint X86_INTRINSIC_TEXT_WRITE = 1u;

static const uint FUNC_META_MAIN_NODE = 4u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint virtual_inst_count()
{
    return min(x86_virtual_inst_status[3u], MAX_X86_INSTS);
}

uint selected_inst_count()
{
    return min(virtual_inst_count() + 1u, MAX_X86_INSTS);
}

bool upstream_ok()
{
    uint inst_count = virtual_inst_count();
    return x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
           x86_virtual_inst_status[1u] == 0u &&
           x86_virtual_inst_status[3u] < MAX_X86_INSTS &&
           x86_virtual_regalloc_status[0u] == X86_VIRTUAL_REGALLOC_OK &&
           x86_virtual_regalloc_status[1u] == 0u &&
           x86_virtual_regalloc_status[3u] == inst_count;
}

void publish_error(uint detail)
{
    select_status[0u] = 0u;
    uint old_error = 0u;
    InterlockedCompareExchange(select_status[1u], 0u, X86_ERR_SELECT, old_error);
    uint old_detail = INVALID;
    InterlockedMin(select_status[2u], detail, old_detail);
}

bool has_value_def(uint row, uint inst_count)
{
    if (row >= inst_count)
        return false;
    uint4 inst = x86_virtual_inst_record[row];
    return inst.x != INVALID && inst.z != 0u && inst.w == row;
}

bool phys_reg_for_value(uint row, uint inst_count, out uint reg)
{
    reg = INVALID;
    if (!has_value_def(row, inst_count))
        return false;
    reg = x86_virtual_phys_reg[row];
    return reg != INVALID;
}

bool target_valid(uint target, uint inst_count)
{
    return target != INVALID && target <= inst_count;
}

uint selected_target(uint virtual_target, uint inst_count)
{
    return virtual_target == inst_count ? inst_count + 1u : virtual_target + 1u;
}

bool first_row_for_function(uint fn_node, uint inst_count, out uint row)
{
    row = INVALID;
    if (fn_node == INVALID)
        return false;

    [loop]
    for (uint candidate = 0u; candidate < MAX_X86_INSTS; candidate += 1u)
    {
        if (candidate >= inst_count)
            break;
        uint node = x86_virtual_inst_record[candidate].x;
        if (node != INVALID && x86_node_func[node] == fn_node)
        {
            row = candidate;
            return true;
        }
    }
    return false;
}

bool main_entry_target(uint inst_count, out uint target)
{
    target = INVALID;
    uint main_node = x86_func_meta[FUNC_META_MAIN_NODE];
    uint main_row = INVALID;
    if (!first_row_for_function(main_node, inst_count, main_row))
        return false;
    target = selected_target(main_row, inst_count);
    return true;
}

uint pack_regs(uint a, uint b)
{
    return (a & 0xffu) | ((b & 0xffu) << 8u);
}

bool select_virtual_inst(uint row, uint inst_count)
{
    uint4 inst = x86_virtual_inst_record[row];
    uint4 args = x86_virtual_inst_args[row];
    uint op = inst.z;
    uint out_row = row + 1u;

    if (inst.x == INVALID || op == 0u)
        return false;

    if (op == X86_VINST_IMM_I32)
    {
        uint dst = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_MOV_R32_IMM32;
        x86_inst_arg0[out_row] = dst;
        x86_inst_arg1[out_row] = args.x;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_PARAM)
    {
        uint dst = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_PARAM_R32;
        x86_inst_arg0[out_row] = dst;
        x86_inst_arg1[out_row] = args.z;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_UNARY)
    {
        uint dst = INVALID;
        uint src = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst) ||
            !phys_reg_for_value(args.y, inst_count, src))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_UNARY_R32;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = dst;
        x86_inst_arg2[out_row] = src;
        return true;
    }

    if (op == X86_VINST_BINARY)
    {
        uint dst = INVALID;
        uint left = INVALID;
        uint right = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst) ||
            !phys_reg_for_value(args.y, inst_count, left) ||
            !phys_reg_for_value(args.z, inst_count, right))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_BINARY_R32_R32;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = dst;
        x86_inst_arg2[out_row] = pack_regs(left, right);
        return true;
    }

    if (op == X86_VINST_COMPARE)
    {
        uint dst = INVALID;
        uint left = INVALID;
        uint right = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst) ||
            !phys_reg_for_value(args.y, inst_count, left) ||
            !phys_reg_for_value(args.z, inst_count, right))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_COMPARE_R32_R32;
        x86_inst_arg0[out_row] = args.x;
        x86_inst_arg1[out_row] = dst;
        x86_inst_arg2[out_row] = pack_regs(left, right);
        return true;
    }

    if (op == X86_VINST_CALL)
    {
        uint dst = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst) ||
            !target_valid(args.x, inst_count) ||
            args.y > 2u)
            return false;

        uint arg0 = INVALID;
        uint arg1 = INVALID;
        if (args.y >= 1u &&
            !phys_reg_for_value(args.z & 0xffffu, inst_count, arg0))
            return false;
        if (args.y >= 2u &&
            !phys_reg_for_value((args.z >> 16u) & 0xffffu, inst_count, arg1))
            return false;

        x86_inst_kind[out_row] = X86_INST_V_CALL_DIRECT;
        x86_inst_arg0[out_row] = selected_target(args.x, inst_count);
        x86_inst_arg1[out_row] = dst;
        x86_inst_arg2[out_row] = (args.y & 0xffu) |
                                 ((arg0 & 0xffu) << 8u) |
                                 ((arg1 & 0xffu) << 16u);
        return true;
    }

    if (op == X86_VINST_INTRINSIC)
    {
        if (args.x != X86_INTRINSIC_TEXT_WRITE)
            return false;
        uint src = INVALID;
        if (!phys_reg_for_value(args.y, inst_count, src))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_PRINT_I32;
        x86_inst_arg0[out_row] = src;
        x86_inst_arg1[out_row] = 0u;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_ALIAS)
    {
        uint dst = INVALID;
        uint src = INVALID;
        if (!phys_reg_for_value(row, inst_count, dst) ||
            !phys_reg_for_value(args.x, inst_count, src))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_MOV_R32_R32;
        x86_inst_arg0[out_row] = dst;
        x86_inst_arg1[out_row] = src;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_RETURN)
    {
        uint src = INVALID;
        if (!phys_reg_for_value(args.x, inst_count, src))
            return false;
        uint owner_fn = inst.x == INVALID ? INVALID : x86_node_func[inst.x];
        uint main_node = x86_func_meta[FUNC_META_MAIN_NODE];
        x86_inst_kind[out_row] = owner_fn == main_node ?
                                 X86_INST_V_RETURN_R32 :
                                 X86_INST_V_RETURN_FUNC_R32;
        x86_inst_arg0[out_row] = src;
        x86_inst_arg1[out_row] = 0u;
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    if (op == X86_VINST_BRANCH)
    {
        if (!target_valid(args.y, inst_count))
            return false;
        if (args.x == INVALID)
        {
            x86_inst_kind[out_row] = X86_INST_V_JMP;
            x86_inst_arg0[out_row] = selected_target(args.y, inst_count);
            x86_inst_arg1[out_row] = 0u;
            x86_inst_arg2[out_row] = 0u;
            return true;
        }

        uint cond = INVALID;
        if (!phys_reg_for_value(args.x, inst_count, cond))
            return false;
        x86_inst_kind[out_row] = X86_INST_V_BRANCH_ZERO;
        x86_inst_arg0[out_row] = cond;
        x86_inst_arg1[out_row] = selected_target(args.y, inst_count);
        x86_inst_arg2[out_row] = 0u;
        return true;
    }

    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    uint inst_count = ok ? virtual_inst_count() : 0u;
    uint selected_count = ok ? selected_inst_count() : 0u;

    if (row == 0u)
    {
        uint entry_target = INVALID;
        bool entry_ok = ok && main_entry_target(inst_count, entry_target);
        select_status[0u] = entry_ok ? X86_SELECT_OK : 0u;
        select_status[1u] = entry_ok ? 0u :
                             (x86_virtual_regalloc_status[1u] == 0u ?
                              X86_ERR_SELECT :
                              x86_virtual_regalloc_status[1u]);
        select_status[2u] = entry_ok ? INVALID :
                             (x86_virtual_regalloc_status[1u] == 0u ?
                              x86_virtual_inst_status[2u] :
                              x86_virtual_regalloc_status[2u]);
        select_status[3u] = entry_ok ? selected_count : 0u;
        x86_reloc_count[0u] = 0u;
        if (entry_ok)
        {
            x86_inst_kind[0u] = X86_INST_V_JMP;
            x86_inst_arg0[0u] = entry_target;
            x86_inst_arg1[0u] = 0u;
            x86_inst_arg2[0u] = 0u;
        }
    }

    if (!ok || selected_count == 0u)
        return;

    if (row < MAX_X86_RELOCS)
    {
        x86_reloc_kind[row] = 0u;
        x86_reloc_site_inst[row] = INVALID;
        x86_reloc_target_inst[row] = INVALID;
    }

    if (row >= inst_count)
        return;

    if (!select_virtual_inst(row, inst_count))
        publish_error(row);
}
