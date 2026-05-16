// SysV x86_64 call ABI projection over backend call and argument-value records.
//
// x86_call_records owns the parser/resolver/type boundary,
// x86_call_arg_values owns argument value/eval projection, and
// x86_call_arg_lookup owns the per-call/per-ordinal argument lookup table.
// This pass assigns SysV argument registers and records argument identity
// without looking at source text, token layout, or HIR expression forms.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> x86_func_lookup_key;
StructuredBuffer<uint> x86_func_lookup_node;
StructuredBuffer<uint4> x86_call_record;
StructuredBuffer<uint4> x86_call_type_record;
StructuredBuffer<uint> call_record_status;
StructuredBuffer<uint4> x86_call_arg_value_record;
StructuredBuffer<uint4> x86_call_arg_lookup_record;
StructuredBuffer<uint> call_arg_lookup_status;
StructuredBuffer<uint> call_intrinsic_tag;

RWStructuredBuffer<uint4> x86_call_abi_record;
RWStructuredBuffer<uint4> x86_call_arg_abi_record;
RWStructuredBuffer<uint> x86_call_abi_flags;
RWStructuredBuffer<uint> call_abi_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_CALL_ARG_LOOKUP_OK = 1u;
static const uint X86_CALL_ABI_OK = 1u;
static const uint X86_ERR_CALL_ABI = 9u;

static const uint X86_CALL_ABI_PRESENT = 1u;
static const uint X86_CALL_ABI_DIRECT_TARGET = 2u;
static const uint X86_CALL_ABI_ARG_WINDOW = 4u;
static const uint X86_CALL_ABI_TYPED_RETURN = 8u;
static const uint X86_CALL_ABI_VALUE_ARG_WINDOW = 16u;
static const uint INTRINSIC_NONE = 0u;
static const uint X86_CALL_ARG_VALUE_SCALAR = 1u;
static const uint X86_CALL_ARG_VALUE_BINARY_IMM = 2u;
static const uint X86_CALL_ARG_VALUE_PARAM = 3u;

static const uint X86_SYSV_MAX_INTEGER_ARGS = 6u;
static const uint X86_REG_EDI = 7u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_EDX = 2u;
static const uint X86_REG_ECX = 1u;
static const uint X86_REG_R8D = 8u;
static const uint X86_REG_R9D = 9u;

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

uint lookup_capacity()
{
    return max(gParams.n_tokens * 2u, 1u);
}

bool call_records_ok()
{
    return call_record_status[0u] == X86_CALL_RECORDS_OK && call_record_status[1u] == 0u;
}

bool call_arg_lookup_ok()
{
    return call_arg_lookup_status[0u] == X86_CALL_ARG_LOOKUP_OK &&
           call_arg_lookup_status[1u] == 0u;
}

bool has_call_record(uint call_node)
{
    if (!valid_node(call_node))
        return false;

    uint4 record = x86_call_record[call_node];
    return record.x != INVALID || record.y != INVALID ||
           record.z != INVALID || record.w != INVALID;
}

uint sysv_integer_arg_reg(uint ordinal)
{
    if (ordinal == 0u) return X86_REG_EDI;
    if (ordinal == 1u) return X86_REG_ESI;
    if (ordinal == 2u) return X86_REG_EDX;
    if (ordinal == 3u) return X86_REG_ECX;
    if (ordinal == 4u) return X86_REG_R8D;
    if (ordinal == 5u) return X86_REG_R9D;
    return INVALID;
}

uint call_abi_base_row(uint call_node)
{
    return call_node * 2u;
}

uint function_node_for_resolver_target(uint resolver_fn_token)
{
    if (!valid_token(resolver_fn_token))
        return INVALID;

    uint key = resolver_fn_token;
    uint cap = lookup_capacity();
    uint start_slot = key % cap;
    [loop]
    for (uint probe = 0u; probe < cap; probe += 1u)
    {
        uint slot = (start_slot + probe) % cap;
        uint node = x86_func_lookup_node[slot];
        if (node == INVALID)
            return INVALID;
        if (x86_func_lookup_key[slot] == key)
            return node;
    }
    return INVALID;
}

void mark_call_abi_error(uint detail)
{
    call_abi_status[0u] = 0u;
    call_abi_status[1u] = X86_ERR_CALL_ABI;
    uint old_detail = 0u;
    InterlockedMin(call_abi_status[2u], detail, old_detail);
}

uint call_arg_lookup_slot(uint call_node, uint ordinal)
{
    return call_node * X86_SYSV_MAX_INTEGER_ARGS + ordinal;
}

bool lookup_arg_node_for_call(uint call_node, uint ordinal, out uint arg_node)
{
    arg_node = INVALID;
    if (!valid_node(call_node) || ordinal >= X86_SYSV_MAX_INTEGER_ARGS)
        return false;

    uint4 record = x86_call_arg_lookup_record[call_arg_lookup_slot(call_node, ordinal)];
    if (record.x != call_node || record.y != ordinal)
        return false;
    if (record.w != X86_CALL_ARG_VALUE_SCALAR &&
        record.w != X86_CALL_ARG_VALUE_BINARY_IMM &&
        record.w != X86_CALL_ARG_VALUE_PARAM)
        return false;

    arg_node = record.z;
    return valid_node(arg_node);
}

void project_call_record(uint call_node)
{
    uint4 call_record = x86_call_record[call_node];
    uint4 type_record = x86_call_type_record[call_node];
    uint owner_fn = call_record.x;
    uint target_fn = function_node_for_resolver_target(call_record.y);
    uint arg_count = call_record.w;
    uint return_ty = type_record.x;
    uint callee_token = type_record.z;
    uint intrinsic_tag = valid_token(callee_token) ? call_intrinsic_tag[callee_token] :
                                                     INTRINSIC_NONE;

    uint flags = X86_CALL_ABI_PRESENT;
    if (target_fn != INVALID)
        flags |= X86_CALL_ABI_DIRECT_TARGET;
    if (arg_count <= X86_SYSV_MAX_INTEGER_ARGS)
        flags |= X86_CALL_ABI_ARG_WINDOW;
    else
        mark_call_abi_error(call_node);
    if (return_ty != 0u && return_ty != INVALID)
        flags |= X86_CALL_ABI_TYPED_RETURN;

    uint arg0_node = INVALID;
    uint arg1_node = INVALID;
    uint arg2_node = INVALID;
    uint arg_value_mask = 0u;
    if (arg_count >= 1u && lookup_arg_node_for_call(call_node, 0u, arg0_node))
        arg_value_mask |= 1u;
    if (arg_count >= 2u && lookup_arg_node_for_call(call_node, 1u, arg1_node))
        arg_value_mask |= 2u;
    if (arg_count >= 3u && lookup_arg_node_for_call(call_node, 2u, arg2_node))
        arg_value_mask |= 4u;
    bool value_window_ok = arg_count == 0u ||
                           (arg_count == 1u && (arg_value_mask & 1u) != 0u) ||
                           (arg_count == 2u && (arg_value_mask & 3u) == 3u) ||
                           (arg_count == 3u && (arg_value_mask & 7u) == 7u);
    if (value_window_ok)
        flags |= X86_CALL_ABI_VALUE_ARG_WINDOW;

    uint row = call_abi_base_row(call_node);
    x86_call_abi_record[row] = uint4(owner_fn, target_fn, arg_count, intrinsic_tag);
    x86_call_abi_record[row + 1u] = uint4(arg0_node, arg1_node, arg_value_mask, INVALID);
    x86_call_abi_flags[call_node] = flags;

    uint old_count = 0u;
    InterlockedAdd(call_abi_status[3u], 1u, old_count);
}

void project_call_arg_record(uint arg_node)
{
    uint4 value_record = x86_call_arg_value_record[arg_node];
    if (value_record.z != X86_CALL_ARG_VALUE_SCALAR &&
        value_record.z != X86_CALL_ARG_VALUE_BINARY_IMM &&
        value_record.z != X86_CALL_ARG_VALUE_PARAM)
        return;

    uint call_node = value_record.x;
    if (!has_call_record(call_node))
        return;

    uint ordinal = value_record.y;
    uint arg_count = x86_call_record[call_node].w;
    bool ordinal_ok = ordinal < X86_SYSV_MAX_INTEGER_ARGS && ordinal < arg_count;
    uint arg_reg = ordinal_ok ? sysv_integer_arg_reg(ordinal) : INVALID;
    x86_call_arg_abi_record[arg_node] = uint4(call_node, ordinal, arg_reg, arg_node);
    if (!ordinal_ok)
        mark_call_abi_error(arg_node);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i == 0u && (!call_records_ok() || !call_arg_lookup_ok()))
    {
        call_abi_status[0u] = 0u;
        call_abi_status[1u] = call_records_ok() ? call_arg_lookup_status[1u] : call_record_status[1u];
        call_abi_status[2u] = call_records_ok() ? call_arg_lookup_status[2u] : call_record_status[2u];
        call_abi_status[3u] = 0u;
    }

    if (!call_records_ok() || !call_arg_lookup_ok() || node_i >= active_hir_node_count())
        return;

    if (has_call_record(node_i))
        project_call_record(node_i);

    project_call_arg_record(node_i);
}
