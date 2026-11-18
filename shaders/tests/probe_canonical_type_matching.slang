// Cases for ct_match (type_checker/match/ct_match.slang). One lane interns
// the patterns and actuals of every case, runs each case through one
// ct_match call site, then interns the expected bindings, so a binding that
// ct_match interned itself must have the key the builders below give it.
// Records are described by spec(j) and interned at one site into
// match_ids[j]; a reference REF | j names spec j. Check i that fails sets
// bit i % 32 of word i / 32 of match_errors and stores its actual value at
// match_errors[4 + i]. match_errors[3] counts the cases run.
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_spare;
import type_checker.match.ct_match;
import primitive_types;

RWStructuredBuffer<uint> match_errors;
RWStructuredBuffer<uint> match_ids;

static const uint INVALID = 0xffffffffu;
static const uint CASES = 25u;
static const uint CHECKS_PER_CASE = 4u;
static const uint INPUT_SPECS = 35u;
static const uint EXPECTED_SPECS = 2u;
static const uint REF = 0x10000000u;

// Callee parameters: T 0, U 1 (type slots), N 0 (usize), M 1 (u8)
// (constant slots). Caller parameters in the actuals: X (a type), K (u32),
// J (usize), L (u16).
static const uint TOKEN_T = 100u;
static const uint TOKEN_U = 101u;
static const uint TOKEN_N = 102u;
static const uint TOKEN_M = 103u;
static const uint TOKEN_X = 200u;
static const uint TOKEN_K = 201u;
static const uint TOKEN_J = 202u;
static const uint TOKEN_L = 203u;

struct CaseSlots : ICtSlots
{
    uint type_slot(uint token)
    { return token == TOKEN_T ? 0u : token == TOKEN_U ? 1u : token == TOKEN_X ? 9u : CT_SLOT_NONE; }
    uint const_slot(uint token)
    {
        return token == TOKEN_N ? 0u : token == TOKEN_M ? 1u : token == TOKEN_K ? 10u
            : token == TOKEN_J ? 11u : token == TOKEN_L ? 12u : CT_SLOT_NONE;
    }
    uint const_scalar(uint token)
    {
        return token == TOKEN_N || token == TOKEN_J ? SCALAR_USIZE : token == TOKEN_M ? SCALAR_U8
            : token == TOKEN_K ? SCALAR_U32 : token == TOKEN_L ? SCALAR_U16 : 0u;
    }
}

void check(uint index, uint actual, uint expected)
{
    if (actual == expected) return;
    InterlockedOr(match_errors[index / 32u], 1u << (index % 32u));
    match_errors[4u + index] = actual;
}

uint resolve(uint ref)
{
    return (ref & 0xf0000000u) == REF ? match_ids[ref & 0xffffu] : ref;
}

static const uint T = 0x80000000u | TOKEN_T;
static const uint U = 0x80000000u | TOKEN_U;
static const uint N = 0xc0000000u | TOKEN_N;
static const uint M = 0xc0000000u | TOKEN_M;
static const uint X = 0x80000000u | TOKEN_X;
static const uint K = 0xc0000000u | TOKEN_K;
static const uint J = 0xc0000000u | TOKEN_J;
static const uint L = 0xc0000000u | TOKEN_L;
static const uint I = SCALAR_I32;
static const uint B = SCALAR_BOOL;

// Spec kinds: 1 count (n), 2 value (scalar, n), 3 cast (target, child),
// 4 array (element, length), 5 slice (element), 6 named (declaration,
// first, second), 7 an environment binding type slot (slot, binding).
uint4 spec(uint j)
{
    switch (j)
    {
    case 0u: return uint4(1u, 3u, 0u, 0u);
    case 1u: return uint4(1u, 4u, 0u, 0u);
    case 2u: return uint4(1u, 300u, 0u, 0u);
    case 3u: return uint4(1u, 200u, 0u, 0u);
    case 4u: return uint4(2u, SCALAR_USIZE, 3u, 0u);
    case 5u: return uint4(2u, SCALAR_U32, 3u, 0u);
    case 6u: return uint4(4u, T, N, 0u);
    case 7u: return uint4(6u, 1u, REF | 6u, 0u);          // Wrap<[T; N]>
    case 8u: return uint4(4u, I, REF | 0u, 0u);           // [i32; 3]
    case 9u: return uint4(6u, 1u, REF | 8u, 0u);
    case 10u: return uint4(4u, I, L, 0u);
    case 11u: return uint4(6u, 1u, REF | 10u, 0u);        // Wrap<[i32; L]>
    case 12u: return uint4(4u, I, J, 0u);
    case 13u: return uint4(6u, 1u, REF | 12u, 0u);
    case 14u: return uint4(6u, 2u, T, T);                 // Pair<T, T>
    case 15u: return uint4(6u, 2u, I, I);
    case 16u: return uint4(6u, 2u, I, B);
    case 17u: return uint4(6u, 3u, T, N);                 // Buffer<T, N>
    case 18u: return uint4(6u, 3u, I, REF | 4u);
    case 19u: return uint4(6u, 3u, I, REF | 5u);
    case 20u: return uint4(4u, I, REF | 1u, 0u);          // [i32; 4]
    case 21u: return uint4(5u, T, 0u, 0u);                // [T]
    case 22u: return uint4(6u, 2u, T, U);
    case 23u: return uint4(7u, 0u, I, 0u);
    case 24u: return uint4(7u, 0u, B, 0u);
    case 25u: return uint4(4u, T, M, 0u);
    case 26u: return uint4(4u, I, REF | 2u, 0u);
    case 27u: return uint4(4u, I, REF | 3u, 0u);
    case 28u: return uint4(4u, ct_dep_type_param(0u), ct_dep_const_param(0u, SCALAR_USIZE), 0u);
    case 29u: return uint4(6u, 1u, X, 0u);
    case 30u: return uint4(6u, 3u, I, J);
    case 31u: return uint4(3u, SCALAR_USIZE, K, 0u);
    case 32u: return uint4(6u, 3u, I, REF | 31u);
    case 33u: return uint4(6u, 3u, T, T);
    case 34u: return uint4(4u, I, K, 0u);
    // Expected bindings that only ct_match interns before they are checked.
    case 35u: return uint4(3u, SCALAR_USIZE, L, 0u);
    default: return uint4(2u, SCALAR_U8, 200u, 0u);
    }
}

uint intern_spec(uint j, inout uint spare)
{
    uint4 s = spec(j);
    uint a = resolve(s.y);
    uint b = resolve(s.z);
    uint kind = s.x;
    if (kind == 6u || kind == 7u)
    {
        // Named: Wrap<A> 1, Pair<A, B> 2, Buffer<A, const N> 3. Environment:
        // type slot s.y bound to s.z.
        uint arity = kind == 7u || s.y == 1u ? 1u : 2u;
        uint types = kind == 7u ? 1u : s.y == 3u ? 1u : arity;
        uint3 words = kind == 7u ? uint3(0u, 1u << s.y, 0u) : uint3(1u, 2u, s.y);
        CtKey key = ct_key_begin(kind == 7u ? CT_KIND_ENV : CT_KIND_NAMED, arity, types, words);
        if (!ct_key_reserve_args(key)) return CT_UNKNOWN;
        ct_key_arg(key, 0u, b);
        if (arity > 1u) ct_key_arg(key, 1u, resolve(s.w));
        uint record = ct_alloc_record();
        uint mask = kind == 7u ? 0u : ((1u << arity) - 1u) & ~((1u << types) - 1u);
        ct_key_store(key, record, uint2(INVALID, mask));
        return ct_intern(record, key);
    }
    uint count = kind == 1u ? s.y : kind == 2u ? s.z : 0u;
    uint klass = kind == 2u ? cc_intern_count(count, spare) : CT_NONE;
    uint record_kind = kind == 1u ? CC_KIND_COUNT : kind == 2u ? CC_KIND_VALUE : kind == 3u ? CC_KIND_CAST
        : kind == 4u ? CT_KIND_ARRAY : CT_KIND_SLICE;
    uint arity = kind <= 2u ? 0u : kind == 4u ? 2u : 1u;
    uint3 words = kind == 1u ? uint3(count, 0u, 0u) : kind == 2u ? uint3(s.y, count, 0u)
        : kind == 3u ? uint3(s.y, 0u, 0u) : uint3(0u, 0u, 0u);
    uint2 args = kind == 3u ? uint2(b, 0u) : kind == 4u ? uint2(a, cc_count_class(b)) : uint2(a, 0u);
    uint2 extra = kind == 1u ? uint2(count, CT_NONE) : kind == 2u ? uint2(count, klass)
        : kind == 3u ? uint2(INVALID, cc_count_class(b)) : uint2(INVALID, 0u);
    return ct_intern_small(record_kind, arity, words, args, extra, spare);
}

struct Case
{
    uint4 roots;     // pattern 0, actual 0, pattern 1 (CT_NONE: one root), actual 1
    uint prior;
    uint flags;      // bit 31: do not intern
    bool matches;
    uint2 masks;     // expected type and constant masks
    uint count_mask;
    uint2 bindings;  // expected type slot (0 or 1) and constant slot (0 or 1) bindings
};

Case make_case(uint4 roots, uint prior, uint flags, bool matches, uint2 masks, uint count_mask, uint2 bindings)
{
    Case c;
    c.roots = roots; c.prior = prior; c.flags = flags; c.matches = matches;
    c.masks = masks; c.count_mask = count_mask; c.bindings = bindings;
    return c;
}

Case case_input(uint i)
{
    uint one = CT_NONE;
    uint2 tn = uint2(1u, 1u);
    uint2 none = uint2(0u, 0u);
    uint2 none_bound = uint2(CT_NONE, CT_NONE);
    uint v3 = REF | 4u;
    switch (i)
    {
    case 0u: return make_case(uint4(REF | 7u, REF | 9u, one, 0u), CT_NONE, 0u, true, tn, 1u, uint2(I, v3));
    // A count claim of a parameter of another scalar is a symbolic cast.
    case 1u: return make_case(uint4(REF | 7u, REF | 11u, one, 0u), CT_NONE, 0u, true, tn, 1u, uint2(I, REF | 35u));
    case 2u: return make_case(uint4(REF | 7u, REF | 13u, one, 0u), CT_NONE, 0u, true, tn, 1u, uint2(I, J));
    case 3u: return make_case(uint4(REF | 14u, REF | 15u, one, 0u), CT_NONE, 0u, true, uint2(1u, 0u), 0u, uint2(I, CT_NONE));
    case 4u: return make_case(uint4(REF | 14u, REF | 16u, one, 0u), CT_NONE, 0u, false, none, 0u, none_bound);
    case 5u: return make_case(uint4(REF | 17u, REF | 18u, one, 0u), CT_NONE, 0u, true, tn, 0u, uint2(I, v3));
    case 6u: return make_case(uint4(REF | 17u, REF | 19u, one, 0u), CT_NONE, 0u, false, none, 0u, none_bound);
    // Exact and count claims agree; the exact claim wins.
    case 7u: return make_case(uint4(REF | 17u, REF | 18u, REF | 6u, REF | 8u), CT_NONE, 0u, true, tn, 0u, uint2(I, v3));
    case 8u: return make_case(uint4(REF | 6u, REF | 8u, REF | 6u, REF | 20u), CT_NONE, 0u, false, none, 0u, none_bound);
    // The root slice coercion, only when asked for.
    case 9u: return make_case(uint4(REF | 21u, REF | 8u, one, 0u), CT_NONE, CT_MATCH_SLICE_ROOT0, true,
        uint2(1u, 0u), 0u, uint2(I, CT_NONE));
    case 10u: return make_case(uint4(REF | 21u, REF | 8u, one, 0u), CT_NONE, 0u, false, none, 0u, none_bound);
    // Prior bindings are checked, and kept.
    case 11u: return make_case(uint4(REF | 22u, REF | 16u, one, 0u), REF | 23u, 0u, true, uint2(3u, 0u), 0u,
        uint2(I, CT_NONE));
    case 12u: return make_case(uint4(REF | 22u, REF | 16u, one, 0u), REF | 24u, 0u, false, none, 0u, none_bound);
    case 13u: return make_case(uint4(I, I, one, 0u), CT_NONE, 0u, true, none, 0u, none_bound);
    case 14u: return make_case(uint4(I, B, one, 0u), CT_NONE, 0u, false, none, 0u, none_bound);
    case 15u: return make_case(uint4(T, REF | 8u, one, 0u), CT_NONE, 0u, true, uint2(1u, 0u), 0u, uint2(REF | 8u, CT_NONE));
    // A count must fit the declared scalar (M: u8).
    case 16u: return make_case(uint4(REF | 25u, REF | 26u, one, 0u), CT_NONE, 0u, false, none, 0u, none_bound);
    case 17u: return make_case(uint4(REF | 25u, REF | 27u, one, 0u), CT_NONE, 0u, true, uint2(1u, 2u), 2u,
        uint2(I, REF | 36u));
    // Dependency signature parameters carry their slot and scalar.
    case 18u: return make_case(uint4(REF | 28u, REF | 8u, one, 0u), CT_NONE, 0u, true, tn, 1u, uint2(I, v3));
    case 19u: return make_case(uint4(REF | 7u, REF | 9u, one, 0u), CT_NONE, 0x80000000u, true, tn, 1u, none_bound);
    case 20u: return make_case(uint4(REF | 7u, REF | 29u, one, 0u), CT_NONE, 0u, false, none, 0u, none_bound);
    case 21u: return make_case(uint4(REF | 17u, REF | 30u, one, 0u), CT_NONE, 0u, true, tn, 0u, uint2(I, J));
    case 22u: return make_case(uint4(REF | 6u, REF | 34u, REF | 17u, REF | 32u), CT_NONE, 0u, true, tn, 0u,
        uint2(I, REF | 31u));
    // A type parameter in a constant position never matches.
    case 23u: return make_case(uint4(REF | 33u, REF | 18u, one, 0u), CT_NONE, 0u, false, none, 0u, none_bound);
    default: return make_case(uint4(REF | 7u, REF | 9u, one, 0u), CT_NONE, 0u, true, tn, 1u, uint2(I, v3));
    }
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    ct_counts[CT_COUNT_NEXT_RECORD] = CT_FIRST_RECORD;
    CaseSlots slots;
    CtSpare spare = ct_spare_none();
    uint intern_spare = CT_NONE;
    // Steps: intern the inputs, run the cases (results in match_ids[64 + i]
    // and count masks in match_ids[96 + i]), intern the expected bindings,
    // then check the cases.
    for (uint step = 0u; step < INPUT_SPECS + CASES + EXPECTED_SPECS + CASES; step++)
    {
        bool interning = step < INPUT_SPECS || step - INPUT_SPECS - CASES < EXPECTED_SPECS;
        if (interning)
        {
            uint j = step < INPUT_SPECS ? step : step - CASES;
            match_ids[j] = intern_spec(j, intern_spare);
            continue;
        }
        bool running = step < INPUT_SPECS + CASES;
        uint i = running ? step - INPUT_SPECS : step - INPUT_SPECS - CASES - EXPECTED_SPECS;
        Case c = case_input(i);
        if (running)
        {
            uint count_mask;
            match_ids[64u + i] = ct_match<CaseSlots>(slots, resolve(c.roots.x), resolve(c.roots.y),
                resolve(c.roots.z), resolve(c.roots.w), resolve(c.prior), c.flags & 3u,
                (c.flags & 0x80000000u) == 0u, spare, count_mask);
            match_ids[96u + i] = count_mask;
            match_ids[127u] = i + 1u;
            continue;
        }
        uint result = match_ids[64u + i];
        uint base = i * CHECKS_PER_CASE;
        if (!c.matches) { check(base, result, CT_MATCH_FAILED); continue; }
        if ((c.flags & 0x80000000u) != 0u) { check(base, result, CT_MATCH_OK); continue; }
        uint3 words = ct_words(result);
        check(base, ct_kind(result) == CT_KIND_ENV && words.x == 0u ? words.y | (words.z << 16u) : INVALID,
            c.masks.x | (c.masks.y << 16u));
        uint type_slot = (c.masks.x & 2u) != 0u && (c.masks.x & 1u) == 0u ? 1u : 0u;
        uint const_slot = (c.masks.y & 2u) != 0u ? 1u : 0u;
        if (c.bindings.x != CT_NONE) check(base + 1u, ct_env_binding(result, type_slot, false), resolve(c.bindings.x));
        if (c.bindings.y != CT_NONE) check(base + 2u, ct_env_binding(result, const_slot, true), resolve(c.bindings.y));
        // The last case repeats case 0: the same bindings are the same environment.
        check(base + 3u, i == CASES - 1u ? result : match_ids[96u + i], i == CASES - 1u ? match_ids[64u] : c.count_mask);
    }
}
