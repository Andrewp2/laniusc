// Shared exact-name hashing and open-addressed table helpers.

import atomics;
import byte_packing;
import gpu_index;
import status;

struct Params
{
    uint name_count;
    uint source_len;
    uint table_half_capacity;
    uint reserved;
};

ConstantBuffer<Params> gParams;

struct NameSpan
{
    uint start;
    uint len;
    uint kind;
    uint token_index;
};

StructuredBuffer<NameSpan> name_spans;
StructuredBuffer<uint> name_count_in;
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;

RWStructuredBuffer<uint> name_hash_lo;
RWStructuredBuffer<uint> name_hash_hi;
RWStructuredBuffer<uint> name_hash_table_a;
RWStructuredBuffer<uint> name_hash_table_b;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
static const uint WG_SIZE = 256u;
static const uint NAME_KIND_LANGUAGE_SYMBOL = 3u;
static const uint NAME_HASH_MAX_BYTES = 64u;
static const uint ERR_NAME_LIMIT = 11u;

uint linear_thread_id(uint3 dtid)
{
    return linear_dispatch_thread_id_2d(dtid, MAX_GROUPS_X * WG_SIZE);
}

uint active_name_count()
{
    return min(name_count_in[0u], gParams.name_count);
}

uint table_capacity()
{
    return gParams.table_half_capacity * 2u;
}

uint load_name_byte(NameSpan span, uint byte_offset)
{
    uint index = span.start + byte_offset;
    return span.kind == NAME_KIND_LANGUAGE_SYMBOL
               ? byte_address_load_u8(language_symbol_bytes, index)
               : byte_address_load_u8_bounded(source_bytes, index, gParams.source_len);
}

uint hash_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

uint2 hash_name(NameSpan span)
{
    uint lo = 2166136261u ^ span.len;
    uint hi = 0x9e3779b9u + span.len * 0x85ebca6bu;
    for (uint i = 0u; i < NAME_HASH_MAX_BYTES; i += 1u)
    {
        if (i >= span.len)
            break;
        uint byte_value = load_name_byte(span, i);
        lo = (lo ^ byte_value) * 16777619u;
        hi ^= byte_value + 0x9e3779b9u + (hi << 6u) + (hi >> 2u);
    }
    return uint2(hash_mix(lo), hash_mix(hi));
}

bool names_equal(uint left, uint right)
{
    uint count = active_name_count();
    if (left >= count || right >= count)
        return false;
    if (name_hash_lo[left] != name_hash_lo[right] ||
        name_hash_hi[left] != name_hash_hi[right])
    {
        return false;
    }

    NameSpan a = name_spans[left];
    NameSpan b = name_spans[right];
    if (a.len != b.len || a.len > NAME_HASH_MAX_BYTES)
        return false;
    for (uint i = 0u; i < NAME_HASH_MAX_BYTES; i += 1u)
    {
        if (i >= a.len)
            break;
        if (load_name_byte(a, i) != load_name_byte(b, i))
            return false;
    }
    return true;
}

uint table_load(uint slot)
{
    return slot < gParams.table_half_capacity
               ? name_hash_table_a[slot]
               : name_hash_table_b[slot - gParams.table_half_capacity];
}

void table_store_invalid(uint slot)
{
    if (slot < gParams.table_half_capacity)
        name_hash_table_a[slot] = INVALID;
    else
        name_hash_table_b[slot - gParams.table_half_capacity] = INVALID;
}

uint table_claim(uint slot, uint name_i)
{
    return slot < gParams.table_half_capacity
               ? atomic_u32_compare_exchange(name_hash_table_a, slot, INVALID, name_i)
               : atomic_u32_compare_exchange(
                     name_hash_table_b,
                     slot - gParams.table_half_capacity,
                     INVALID,
                     name_i);
}

void table_min(uint slot, uint name_i)
{
    if (slot < gParams.table_half_capacity)
        atomic_u32_min(name_hash_table_a, slot, name_i);
    else
        atomic_u32_min(name_hash_table_b, slot - gParams.table_half_capacity, name_i);
}

uint first_slot(uint name_i)
{
    uint capacity = table_capacity();
    return capacity == 0u
               ? 0u
               : (name_hash_lo[name_i] ^ (name_hash_hi[name_i] * 0x9e3779b9u)) % capacity;
}

void record_hash_table_error(uint name_i)
{
    NameSpan span = name_spans[name_i];
    uint token = span.kind == NAME_KIND_LANGUAGE_SYMBOL ? 0u : span.token_index;
    record_min_token_error(status, token, ERR_NAME_LIMIT, table_capacity());
}
