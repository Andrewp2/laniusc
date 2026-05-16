// GPU method-key order seed.
//
// Scheduling contract:
// - Dispatch after method collect and metadata attach have published method
//   declaration records.
// - This pass initializes the method key order used by the radix passes and
//   clears method-key validation outputs.
// - It does not resolve methods, inspect source bytes, hash token text, perform
//   CPU lookup, or apply same-source shortcuts.

struct Params
{
    uint method_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> method_key_to_fn_token;
RWStructuredBuffer<uint> method_key_status;
RWStructuredBuffer<uint> method_key_duplicate_of;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint METHOD_KEY_STATUS_OK = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.method_capacity)
        return;

    method_key_to_fn_token[i] = i;
    method_key_status[i] = METHOD_KEY_STATUS_OK;
    method_key_duplicate_of[i] = INVALID;
}
