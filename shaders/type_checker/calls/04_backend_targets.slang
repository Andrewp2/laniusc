// Project semantic call targets into the function-start-token domain consumed
// by code generators. Type checking keeps declaration-name tokens as semantic
// identities; backends use source-span starts to index function body records.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> fn_start_token_by_decl_token;
StructuredBuffer<uint> call_param_row_count_out;
RWStructuredBuffer<uint> backend_call_fn_index;
RWStructuredBuffer<uint> call_param_row_fn_token;
RWStructuredBuffer<uint> call_param_row_start;
RWStructuredBuffer<uint> call_param_row_count;
RWStructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> method_decl_param_offset;
RWStructuredBuffer<uint> method_decl_receiver_mode;

static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token_i = linear_dispatch_thread_id_2d(dtid, 16776960u);
    if (token_i >= gParams.n_tokens)
        return;

    uint semantic_target = call_fn_index[token_i];
    if (semantic_target == INVALID || semantic_target >= gParams.n_tokens)
    {
        backend_call_fn_index[token_i] = INVALID;
    }
    else
    {
        uint start_token = fn_start_token_by_decl_token[semantic_target];
        backend_call_fn_index[token_i] = start_token < gParams.n_tokens
            ? start_token
            : semantic_target;
    }

    uint declaration_start = fn_start_token_by_decl_token[token_i];
    if (declaration_start < gParams.n_tokens)
    {
        call_param_count[declaration_start] = call_param_count[token_i];
        call_param_row_start[declaration_start] = call_param_row_start[token_i];
        call_param_row_count[declaration_start] = call_param_row_count[token_i];

        // Semantic method records use the declaration-name token, while body
        // ownership and backend function slots use the function span's start
        // token. Project the ABI fields at the same explicit boundary as call
        // targets and parameter ranges so backend shaders never have to guess
        // which token domain a function record belongs to.
        method_decl_param_offset[declaration_start] =
            method_decl_param_offset[token_i];
        method_decl_receiver_mode[declaration_start] =
            method_decl_receiver_mode[token_i];
    }

    uint row_count = min(call_param_row_count_out[0u], gParams.n_tokens);
    if (token_i < row_count)
    {
        uint owner = call_param_row_fn_token[token_i];
        if (owner < gParams.n_tokens)
        {
            uint owner_start = fn_start_token_by_decl_token[owner];
            if (owner_start < gParams.n_tokens)
                call_param_row_fn_token[token_i] = owner_start;
        }
    }
}
