// x86_64 node-instruction-generation input status aggregation.
//
// This tiny pass keeps x86_node_inst_gen below the per-stage storage-buffer
// limit without dropping upstream failure checks. It condenses the stage status
// records that the generator needs into one status row.

import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_node_inst_location_status;
StructuredBuffer<uint> x86_const_value_status;
StructuredBuffer<uint> x86_decl_layout_status;
StructuredBuffer<uint> x86_local_literal_status;
StructuredBuffer<uint> x86_param_reg_status;
StructuredBuffer<uint> call_abi_status;
StructuredBuffer<uint> x86_struct_record_status;

RWStructuredBuffer<uint> x86_node_inst_gen_input_status;

static const uint INVALID = 0xffffffffu;
static const uint X86_ERR_NODE_VIRTUAL_INST = 11u;
static const uint X86_NODE_INST_GEN_INPUTS_OK = 1u;
static const uint X86_NODE_INST_LOCATIONS_OK = 1u;
static const uint X86_CONST_VALUES_OK = 1u;
static const uint X86_DECL_LAYOUT_OK = 1u;
static const uint X86_LOCAL_LITERALS_OK = 1u;
static const uint X86_PARAM_REGS_OK = 1u;
static const uint X86_CALL_ABI_OK = 1u;
static const uint X86_STRUCT_RECORDS_OK = 1u;

void absorb_upstream(
    StructuredBuffer<uint> upstream_status,
    uint ok_code,
    inout bool ok,
    inout uint error,
    inout uint detail)
{
    if (!ok || stage_status4_ok(upstream_status, ok_code))
        return;

    ok = false;
    error = stage_status4_error_or(upstream_status, X86_ERR_NODE_VIRTUAL_INST);
    detail = stage_status4_detail_or(upstream_status, 0u);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x != 0u || tid.y != 0u || tid.z != 0u)
        return;

    bool ok = true;
    uint error = 0u;
    uint detail = INVALID;
    absorb_upstream(x86_node_inst_location_status, X86_NODE_INST_LOCATIONS_OK, ok, error, detail);
    absorb_upstream(x86_const_value_status, X86_CONST_VALUES_OK, ok, error, detail);
    absorb_upstream(x86_decl_layout_status, X86_DECL_LAYOUT_OK, ok, error, detail);
    absorb_upstream(x86_local_literal_status, X86_LOCAL_LITERALS_OK, ok, error, detail);
    absorb_upstream(x86_param_reg_status, X86_PARAM_REGS_OK, ok, error, detail);
    absorb_upstream(call_abi_status, X86_CALL_ABI_OK, ok, error, detail);
    absorb_upstream(x86_struct_record_status, X86_STRUCT_RECORDS_OK, ok, error, detail);

    uint total_rows = x86_node_inst_location_status[3u];
    if (ok && total_rows > gParams.inst_capacity)
    {
        ok = false;
        error = X86_ERR_NODE_VIRTUAL_INST;
        detail = total_rows;
    }

    x86_node_inst_gen_input_status[0u] = ok ? X86_NODE_INST_GEN_INPUTS_OK : 0u;
    x86_node_inst_gen_input_status[1u] = ok ? 0u : error;
    x86_node_inst_gen_input_status[2u] = ok ? INVALID : detail;
    x86_node_inst_gen_input_status[3u] = ok ? total_rows : 0u;
}
