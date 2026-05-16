// GPU sorted declaration-key validation.
//
// Scheduling contract:
// - Dispatch after the declaration key radix sort has produced
//   sorted_decl_key_order.
// - Adjacent equal keys are duplicate declarations in the same module and
//   namespace. Equality compares interned name ids directly; no hashes or
//   source-byte comparisons are needed after GPU name interning.
// - This pass writes per-declaration validation results and reduces validation
//   failures into the compiler-wide type-check status buffer using
//   decl_token_start. It does not resolve names by token text.
// - It does not resolve imports, expand visibility, resolve type/value paths,
//   scan source bytes, use hashes, or apply same-source shortcuts.

struct Params
{
    uint decl_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> sorted_decl_key_order;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> decl_token_start;

RWStructuredBuffer<uint> decl_status;
RWStructuredBuffer<uint> decl_duplicate_of;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_NAMESPACE_VALUE = 2u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;

static const uint DECL_STATUS_OK = 0u;
static const uint DECL_STATUS_DUPLICATE = 1u;
static const uint DECL_STATUS_INVALID_MODULE = 2u;
static const uint DECL_STATUS_INVALID_NAMESPACE = 3u;
static const uint DECL_STATUS_INVALID_NAME = 4u;
static const uint ERR_BAD_HIR = 6u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_decl_count()
{
    return min(decl_count_out[0], gParams.decl_capacity);
}

uint active_module_count()
{
    return max(1u, min(module_count_out[0], gParams.decl_capacity));
}

bool valid_namespace(uint namespace)
{
    return namespace == HIR_ITEM_NAMESPACE_VALUE || namespace == HIR_ITEM_NAMESPACE_TYPE;
}

uint invalid_decl_status(uint decl_i)
{
    if (decl_i >= active_decl_count())
        return DECL_STATUS_INVALID_NAME;
    uint module_id = decl_module_id[decl_i];
    if (module_id == INVALID || module_id >= active_module_count())
        return DECL_STATUS_INVALID_MODULE;
    if (!valid_namespace(decl_namespace[decl_i]))
        return DECL_STATUS_INVALID_NAMESPACE;
    if (decl_name_id[decl_i] == INVALID)
        return DECL_STATUS_INVALID_NAME;
    return DECL_STATUS_OK;
}

bool decl_keys_equal(uint left_decl_i, uint right_decl_i)
{
    if (invalid_decl_status(left_decl_i) != DECL_STATUS_OK ||
        invalid_decl_status(right_decl_i) != DECL_STATUS_OK)
        return false;

    return decl_module_id[left_decl_i] == decl_module_id[right_decl_i] &&
           decl_namespace[left_decl_i] == decl_namespace[right_decl_i] &&
           decl_name_id[left_decl_i] == decl_name_id[right_decl_i];
}

uint error_token_for_decl(uint decl_i)
{
    if (decl_i < active_decl_count())
    {
        uint token_i = decl_token_start[decl_i];
        if (token_i != INVALID)
            return token_i;
    }
    return 0u;
}

void record_error(uint token_i, uint code, uint detail)
{
    uint old;
    InterlockedMin(status[1], token_i, old);
    if (token_i <= old)
    {
        status[0] = 0u;
        status[2] = code;
        status[3] = detail;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint decl_count = active_decl_count();
    if (i >= decl_count)
        return;

    uint decl_i = sorted_decl_key_order[i];
    if (decl_i >= decl_count)
        return;

    decl_duplicate_of[decl_i] = INVALID;

    uint status = invalid_decl_status(decl_i);
    if (status != DECL_STATUS_OK)
    {
        decl_status[decl_i] = status;
        record_error(error_token_for_decl(decl_i), ERR_BAD_HIR, status);
        return;
    }

    decl_status[decl_i] = DECL_STATUS_OK;
    if (i == 0u)
        return;

    uint prev_decl_i = sorted_decl_key_order[i - 1u];
    if (prev_decl_i >= decl_count)
        return;

    if (!decl_keys_equal(prev_decl_i, decl_i))
        return;

    decl_status[decl_i] = DECL_STATUS_DUPLICATE;
    decl_duplicate_of[decl_i] = prev_decl_i;
    record_error(error_token_for_decl(decl_i), ERR_BAD_HIR, DECL_STATUS_DUPLICATE);
}
