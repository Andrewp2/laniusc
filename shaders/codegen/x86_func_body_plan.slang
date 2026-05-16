// x86_64 function body planning quarantine.
//
// This pass used to classify whole callee return bodies into narrow shapes.
// That is not the paper/Pareas backend shape. Calee codegen must be rebuilt as
// node-local instruction counting and node-local instruction generation from
// attributed HIR/AST records. Until that exists, this stage only propagates
// upstream status and deliberately publishes no callee body rows.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

struct StatusRecord
{
    uint state;
    uint error;
    uint detail;
    uint count;
};

ConstantBuffer<Params> gParams;
ConstantBuffer<StatusRecord> x86_param_reg_status;
ConstantBuffer<StatusRecord> x86_local_literal_status;
ConstantBuffer<StatusRecord> x86_func_return_stmt_status;
ConstantBuffer<StatusRecord> x86_terminal_if_status;
ConstantBuffer<StatusRecord> call_abi_status;

RWStructuredBuffer<uint> x86_func_body_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_FUNC_BODY_OK = 1u;
static const uint X86_PARAM_REGS_OK = 1u;
static const uint X86_LOCAL_LITERALS_OK = 1u;
static const uint X86_FUNC_RETURN_STMTS_OK = 1u;
static const uint X86_TERMINAL_IFS_OK = 1u;
static const uint X86_CALL_ABI_OK = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

bool status_ok(StatusRecord status, uint expected_state)
{
    return status.state == expected_state && status.error == 0u;
}

bool upstream_ok()
{
    return status_ok(x86_param_reg_status, X86_PARAM_REGS_OK) &&
           status_ok(x86_local_literal_status, X86_LOCAL_LITERALS_OK) &&
           status_ok(x86_func_return_stmt_status, X86_FUNC_RETURN_STMTS_OK) &&
           status_ok(x86_terminal_if_status, X86_TERMINAL_IFS_OK) &&
           status_ok(call_abi_status, X86_CALL_ABI_OK);
}

StatusRecord first_upstream_error()
{
    if (!status_ok(x86_param_reg_status, X86_PARAM_REGS_OK))
        return x86_param_reg_status;
    if (!status_ok(x86_local_literal_status, X86_LOCAL_LITERALS_OK))
        return x86_local_literal_status;
    if (!status_ok(x86_func_return_stmt_status, X86_FUNC_RETURN_STMTS_OK))
        return x86_func_return_stmt_status;
    if (!status_ok(x86_terminal_if_status, X86_TERMINAL_IFS_OK))
        return x86_terminal_if_status;
    return call_abi_status;
}

void publish_status(bool ok, uint error, uint detail)
{
    x86_func_body_status[0u] = ok ? X86_FUNC_BODY_OK : 0u;
    x86_func_body_status[1u] = ok ? 0u : error;
    x86_func_body_status[2u] = ok ? INVALID : detail;
    x86_func_body_status[3u] = 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (linear_dispatch_id(tid) != 0u)
        return;

    if (upstream_ok())
    {
        publish_status(true, 0u, INVALID);
        return;
    }

    StatusRecord status = first_upstream_error();
    publish_status(false, status.error, status.detail);
}
