// GPU declaration-key order seed.
//
// Scheduling contract:
// - Dispatch after declaration records have been scattered and after
//   type_check_modules_05d_attach_record_modules.slang has written
//   decl_module_id for each compact declaration row.
// - This pass initializes the dense declaration key order used by the radix
//   passes and clears declaration-key validation outputs.
// - It does not resolve imports, perform declaration lookup, expand visibility,
//   scan source bytes, use hashes, apply same-source shortcuts, or ask the CPU
//   to inspect declarations.

struct Params
{
    uint decl_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_count_out;

RWStructuredBuffer<uint> decl_key_to_decl_id;
RWStructuredBuffer<uint> decl_status;
RWStructuredBuffer<uint> decl_duplicate_of;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint DECL_STATUS_OK = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_decl_count()
{
    return min(decl_count_out[0], gParams.decl_capacity);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.decl_capacity)
        return;

    uint decl_count = active_decl_count();
    decl_key_to_decl_id[i] = i < decl_count ? i : INVALID;
    decl_status[i] = DECL_STATUS_OK;
    decl_duplicate_of[i] = INVALID;
}
