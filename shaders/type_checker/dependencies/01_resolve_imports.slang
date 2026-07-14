// Resolve locally-unmatched imports against canonical dependency modules.
// Each import probes the GPU-built module table independently.

import atomics;
import byte_packing;
import gpu_index;
import status;

struct Params
{
    uint module_count;
    uint lookup_capacity;
    uint import_capacity;
    uint source_len;
};

struct NameSpan
{
    uint start;
    uint len;
    uint kind;
    uint token_index;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_path_id;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_name_id;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> name_hash_lo;
StructuredBuffer<uint> name_hash_hi;
StructuredBuffer<NameSpan> name_spans;
ByteAddressBuffer source_bytes;
StructuredBuffer<uint> dependency_module_words;
StructuredBuffer<uint> dependency_module_segment_words;
StructuredBuffer<uint> dependency_name_byte_words;
StructuredBuffer<uint> dependency_module_lookup;
RWStructuredBuffer<uint> import_target_dependency_module_id;
RWStructuredBuffer<uint> import_status;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint MODULE_WORDS = 2u;
static const uint SEGMENT_WORDS = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint IMPORT_STATUS_OK = 0u;
static const uint IMPORT_STATUS_UNRESOLVED = 1u;
static const uint IMPORT_STATUS_AMBIGUOUS = 5u;
static const uint ERR_UNRESOLVED_IMPORT = 15u;
static const uint ERR_DUPLICATE_MODULE = 18u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint mix(uint hash, uint value)
{
    hash ^= value;
    hash *= 16777619u;
    return hash;
}

uint path_hash(uint path_id)
{
    uint count = path_segment_count[path_id];
    uint first = path_segment_base[path_id];
    uint hash = mix(2166136261u, count);
    for (uint segment_i = 0u; segment_i < 8u; segment_i += 1u)
    {
        if (segment_i >= count)
            break;
        uint name_id = path_segment_name_id[first + segment_i];
        hash = mix(hash, name_hash_lo[name_id]);
        hash = mix(hash, name_hash_hi[name_id]);
    }
    return hash;
}

uint dependency_name_byte(uint byte_i)
{
    uint word = dependency_name_byte_words[byte_i >> 2u];
    return (word >> ((byte_i & 3u) * 8u)) & 0xffu;
}

bool segment_equal(uint name_id, uint dependency_segment)
{
    uint segment = dependency_segment * SEGMENT_WORDS;
    if (name_hash_lo[name_id] != dependency_module_segment_words[segment + 0u] ||
        name_hash_hi[name_id] != dependency_module_segment_words[segment + 1u])
        return false;
    NameSpan span = name_spans[name_id];
    uint dependency_start = dependency_module_segment_words[segment + 2u];
    uint dependency_len = dependency_module_segment_words[segment + 3u];
    if (span.len != dependency_len)
        return false;
    for (uint byte_i = 0u; byte_i < 64u; byte_i += 1u)
    {
        if (byte_i >= span.len)
            break;
        if (byte_address_load_u8_bounded(source_bytes, span.start + byte_i, gParams.source_len) !=
            dependency_name_byte(dependency_start + byte_i))
            return false;
    }
    return true;
}

bool module_equal(uint path_id, uint module_i)
{
    uint module = module_i * MODULE_WORDS;
    uint module_first = dependency_module_words[module + 0u];
    uint module_count = dependency_module_words[module + 1u];
    uint path_count = path_segment_count[path_id];
    if (path_count != module_count || path_count > 8u)
        return false;
    uint path_first = path_segment_base[path_id];
    for (uint segment_i = 0u; segment_i < 8u; segment_i += 1u)
    {
        if (segment_i >= path_count)
            break;
        uint name_id = path_segment_name_id[path_first + segment_i];
        if (!segment_equal(name_id, module_first + segment_i))
            return false;
    }
    return true;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint import_i = linear_thread_id(dtid);
    if (import_i >= gParams.import_capacity)
        return;
    import_target_dependency_module_id[import_i] = INVALID;
    if (import_i >= min(import_count_out[0u], gParams.import_capacity) ||
        import_status[import_i] != IMPORT_STATUS_UNRESOLVED)
        return;

    uint path_id = import_path_id[import_i];
    uint token = path_owner_token[path_id];
    uint mask = gParams.lookup_capacity - 1u;
    uint slot = path_hash(path_id) & mask;
    uint match = INVALID;
    for (uint probe = 0u; probe < gParams.lookup_capacity; probe += 1u)
    {
        uint module_i = dependency_module_lookup[slot];
        if (module_i == INVALID)
            break;
        if (module_i < gParams.module_count && module_equal(path_id, module_i))
        {
            if (match != INVALID)
            {
                import_status[import_i] = IMPORT_STATUS_AMBIGUOUS;
                record_error(token, ERR_DUPLICATE_MODULE, IMPORT_STATUS_AMBIGUOUS);
                return;
            }
            match = module_i;
        }
        slot = (slot + 1u) & mask;
    }
    if (match == INVALID)
    {
        record_error(token, ERR_UNRESOLVED_IMPORT, IMPORT_STATUS_UNRESOLVED);
        return;
    }
    import_target_dependency_module_id[import_i] = match;
    import_status[import_i] = IMPORT_STATUS_OK;
}
