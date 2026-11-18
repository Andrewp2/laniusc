// Native symbol identities of retained x86 objects, without bindings: the
// identity words, the identity hash (`stable_name_hash` of the 12 identity
// bytes) and the lane index. The finalizer (symbol_finalization_layout.slang)
// and the original-call provisionalization
// (type_checker/retention/native/00_provisional.slang) share them.

import shared.buffers.gpu_index;

static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint RESERVED_LIB = 0xfffffffeu;
static const uint NS_USE = 0xffff0001u;
static const uint NS_INSTANCE = 0xffff0002u;
static const uint OBJECT_LOCAL = 0xffffffffu;

static const uint SECTION_UNDEFINED = 0u;
static const uint SYMBOL_WORDS = 8u;
static const uint PROVISIONAL_IDENTITY_BYTES = 12u;

uint finalize_lane(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
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

// `stable_name_hash` over the 12 little-endian bytes of a native identity.
uint2 identity_hash(uint3 identity)
{
    uint lo = 2166136261u ^ PROVISIONAL_IDENTITY_BYTES;
    uint hi = 0x9e3779b9u + PROVISIONAL_IDENTITY_BYTES * 0x85ebca6bu;
    for (uint i = 0u; i < PROVISIONAL_IDENTITY_BYTES; i += 1u)
    {
        uint byte_value = (identity[i >> 2u] >> ((i & 3u) * 8u)) & 0xffu;
        lo = (lo ^ byte_value) * 16777619u;
        hi ^= byte_value + 0x9e3779b9u + (hi << 6u) + (hi >> 2u);
    }
    return uint2(hash_mix(lo), hash_mix(hi));
}
