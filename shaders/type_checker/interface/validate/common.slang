// Shared view of one encoded semantic-interface artifact for its GPU
// validation (crates/laniusc-compiler/src/compiler/semantic_interface/
// gpu_validation.rs). The artifact is the exact persisted byte stream: the
// 8-byte magic, a 16-word header, the record sections in a fixed order, then
// the name bytes.
//
// Every check reports a failure key with one atomic minimum:
//   phase << 27 | min(row, 0xfffff) << 7 | code
// Phases follow the order of the checks; within a row, a thread runs its
// checks in order and reports only the first that fails. The smallest key
// is therefore the first failure of the ordered check sequence.
//
// Validation state words (validate_state):
//   0 failure key (INVALID when the artifact passed)
//   1 1 when the framing is valid and the record kernels may read it
//   2..13 section counts, 14..25 section starts (words; the name start is a
//   byte offset), 26 library id, 27 unit id, 28 artifact word count
//   29..32 scratch offsets, 33 scratch words, 34 symbol table capacity,
//   35..36 scratch offsets of the predicate summaries, 37..38 of the
//   implementation row results
__exported import primitive_types;
__exported import constant_value;
__exported import atomics;

public StructuredBuffer<uint> validate_artifact_words;
public StructuredBuffer<uint> validate_artifact_length;
public RWStructuredBuffer<uint> validate_state;
public RWStructuredBuffer<uint> validate_scratch;

public static const uint INVALID = 0xffffffffu;
public static const uint WG = 256u;
public static const uint OWNER_TAG = 0x80000000u;
public static const uint SCOPE_MASK = 0xc0000000u;
public static const uint SCOPE_METHOD = 0x80000000u;
public static const uint SCOPE_IMPL = 0xc0000000u;
public static const uint SCOPE_PRIVATE_TARGET = 0x40000000u;
public static const uint MAX_NAME_BYTES = 64u;
public static const uint ROW_LIMIT = 0xfffffu;
// Graph walks keep an explicit stack; a walk past these bounds is reported
// as a failure of its own (code CODE_WORK_LIMIT).
public static const uint STACK_LIMIT = 96u;
public static const uint VISIT_LIMIT = 16384u;
public static const uint CODE_WORK_LIMIT = 127u;

// State words.
public static const uint STATE_KEY = 0u;
public static const uint STATE_FRAMED = 1u;
public static const uint STATE_COUNTS = 2u;
public static const uint STATE_STARTS = 14u;
public static const uint STATE_LIBRARY = 26u;
public static const uint STATE_UNIT = 27u;
public static const uint STATE_WORDS = 28u;
public static const uint STATE_PARG_OWNERS = 29u;
public static const uint STATE_IARG_OWNERS = 30u;
public static const uint STATE_BIND_OWNERS = 31u;
public static const uint STATE_SYMBOLS = 32u;
public static const uint STATE_SCRATCH_WORDS = 33u;
public static const uint STATE_SYMBOL_CAPACITY = 34u;
public static const uint STATE_IMPL_PREDICATES = 35u;
public static const uint STATE_MEMBER_PREDICATES = 36u;
public static const uint STATE_MEMBER_RESULTS = 37u;
public static const uint STATE_BINDING_RESULTS = 38u;
public static const uint STATE_WORD_COUNT = 40u;

// Kernels with indirect arguments, in dispatch order.
public static const uint ARGS_CLEAR = 0u;
public static const uint ARGS_OWNERS = 1u;
public static const uint ARGS_RECORDS = 2u;
public static const uint ARGS_SCOPES = 3u;
public static const uint ARGS_IMPLEMENTATION_ROWS = 4u;
public static const uint ARGS_IMPLEMENTATIONS = 5u;
public static const uint ARGS_PREDICATES = 6u;
public static const uint ARGS_COUNT = 7u;

// Sections.
public static const uint S_MODULE = 0u;
public static const uint S_SEGMENT = 1u;
public static const uint S_DECL = 2u;
public static const uint S_TYPE = 3u;
public static const uint S_EDGE = 4u;
public static const uint S_MEMBER = 5u;
public static const uint S_PRED = 6u;
public static const uint S_PARG = 7u;
public static const uint S_IMPL = 8u;
public static const uint S_IARG = 9u;
public static const uint S_BIND = 10u;
public static const uint S_NAME = 11u;

// Type kinds.
public static const uint T_SCALAR = 1u;
public static const uint T_GENERIC = 2u;
public static const uint T_DECL = 3u;
public static const uint T_ARRAY = 4u;
public static const uint T_SLICE = 5u;
public static const uint T_REF = 6u;
public static const uint T_FUNCTION = 7u;
public static const uint T_CONST_PARAM = 8u;
public static const uint T_CONST_VALUE = 9u;
public static const uint T_COUNT = 10u;

// Member kinds.
public static const uint M_PARAMETER = 1u;
public static const uint M_GENERIC_TYPE = 2u;
public static const uint M_GENERIC_CONST = 3u;
public static const uint M_FIELD = 4u;
public static const uint M_VARIANT = 5u;
public static const uint M_TRAIT_METHOD = 7u;
public static const uint M_IMPL_METHOD = 8u;

public static const uint IMPL_INHERENT = 1u;
public static const uint IMPL_TRAIT = 2u;

// Declaration fields.
public static const uint D_MODULE = 0u;
public static const uint D_HASH_LO = 1u;
public static const uint D_HASH_HI = 2u;
public static const uint D_NAME_START = 3u;
public static const uint D_NAME_LEN = 4u;
public static const uint D_NAMESPACE = 5u;
public static const uint D_KIND = 6u;
public static const uint D_SIGNATURE = 7u;
public static const uint D_FIRST_MEMBER = 8u;
public static const uint D_MEMBER_COUNT = 9u;
public static const uint D_OWNER = 10u;
public static const uint D_FLAGS = 11u;
public static const uint D_VALUE_LO = 12u;
public static const uint D_VALUE_HI = 13u;

// Type fields.
public static const uint Y_KIND = 0u;
public static const uint Y_PAYLOAD_LO = 1u;
public static const uint Y_PAYLOAD_HI = 2u;
public static const uint Y_FIRST_EDGE = 3u;
public static const uint Y_EDGE_COUNT = 4u;
public static const uint Y_LENGTH_KIND = 5u;
public static const uint Y_LENGTH_LO = 6u;
public static const uint Y_LENGTH_HI = 7u;
public static const uint Y_NOMINAL_UNIT = 8u;

// Member fields.
public static const uint B_OWNER = 0u;
public static const uint B_KIND = 1u;
public static const uint B_ORDINAL = 2u;
public static const uint B_HASH_LO = 3u;
public static const uint B_HASH_HI = 4u;
public static const uint B_NAME_START = 5u;
public static const uint B_NAME_LEN = 6u;
public static const uint B_TYPE = 7u;
public static const uint B_VALUE_LO = 8u;
public static const uint B_VALUE_HI = 9u;
public static const uint B_RECEIVER = 10u;
public static const uint B_GENERIC_ORDINAL = 11u;

// Predicate fields.
public static const uint P_OWNER = 0u;
public static const uint P_SCOPE = 1u;
public static const uint P_SUBJECT = 2u;
public static const uint P_TRAIT_LIBRARY = 3u;
public static const uint P_TRAIT_UNIT = 4u;
public static const uint P_TRAIT_DECL = 5u;
public static const uint P_FIRST_ARG = 6u;
public static const uint P_ARG_COUNT = 7u;

// Implementation fields.
public static const uint I_MODULE = 0u;
public static const uint I_VISIBILITY = 1u;
public static const uint I_TRAIT_LIBRARY = 2u;
public static const uint I_TRAIT_UNIT = 3u;
public static const uint I_TRAIT_DECL = 4u;
public static const uint I_SUBJECT = 5u;
public static const uint I_FIRST_ARG = 6u;
public static const uint I_ARG_COUNT = 7u;
public static const uint I_FIRST_MEMBER = 8u;
public static const uint I_MEMBER_COUNT = 9u;
public static const uint I_FIRST_PREREQ = 10u;
public static const uint I_PREREQ_COUNT = 11u;
public static const uint I_FIRST_BINDING = 12u;
public static const uint I_BINDING_COUNT = 13u;
public static const uint I_KIND = 14u;

// Method binding fields.
public static const uint N_IMPL = 0u;
public static const uint N_REQUIRED = 1u;
public static const uint N_MEMBER = 2u;
public static const uint N_TARGET_LIBRARY = 3u;
public static const uint N_TARGET_UNIT = 4u;
public static const uint N_TARGET_SYMBOL = 5u;

public static const uint WIDTHS[11] = { 2u, 4u, 14u, 9u, 1u, 12u, 8u, 1u, 15u, 1u, 6u };

// Phases, in check order.
public static const uint PH_HEADER = 1u;
public static const uint PH_MODULES = 2u;
public static const uint PH_SEGMENTS = 3u;
public static const uint PH_DECL_IDENTITY = 4u;
public static const uint PH_DECLARATIONS = 5u;
public static const uint PH_IMPL_RANGES = 6u;
public static const uint PH_BINDING_ROWS = 7u;
public static const uint PH_TYPES = 8u;
public static const uint PH_MEMBERS = 9u;
public static const uint PH_NOMINAL = 10u;
public static const uint PH_TRAIT_HEADERS = 11u;
public static const uint PH_METHODS = 12u;
public static const uint PH_SCOPED_PARAMS = 13u;
public static const uint PH_GENERIC_PARAMS = 14u;
public static const uint PH_PARAM_ORDERS = 15u;
public static const uint PH_METHOD_SIGNATURES = 16u;
public static const uint PH_IMPLEMENTATIONS = 17u;
public static const uint PH_PREDICATES = 18u;
public static const uint PH_NATIVE_C = 19u;

public uint thread_index(uint3 gid, uint3 ltid)
{
    return gid.x * WG + ltid.x;
}

// Kernels that walk type graphs run WALK_WG threads per workgroup, each
// with WALK_WORDS words of workgroup memory for its stacks.
public static const uint WALK_WG = 32u;
public static const uint WALK_WORDS = 2u * STACK_LIMIT;
groupshared uint g_walk_stack[WALK_WG * WALK_WORDS];
static uint g_walk_base = 0u;

// The thread's row in a walking kernel; binds its stack region.
public uint walk_thread_index(uint3 gid, uint3 ltid)
{
    g_walk_base = ltid.x * WALK_WORDS;
    return gid.x * WALK_WG + ltid.x;
}

public bool framed()
{
    return validate_state[STATE_FRAMED] == 1u;
}

public uint count_of(uint section)
{
    return validate_state[STATE_COUNTS + section];
}

public uint start_of(uint section)
{
    return validate_state[STATE_STARTS + section];
}

public uint library_id()
{
    return validate_state[STATE_LIBRARY];
}

public uint unit_id()
{
    return validate_state[STATE_UNIT];
}

public uint word(uint index)
{
    return index < validate_state[STATE_WORDS] ? validate_artifact_words[index] : 0u;
}

public uint field(uint section, uint row, uint f)
{
    return word(start_of(section) + row * WIDTHS[section] + f);
}

public uint decl(uint row, uint f) { return field(S_DECL, row, f); }
public uint ty(uint row, uint f) { return field(S_TYPE, row, f); }
public uint edge(uint row) { return word(start_of(S_EDGE) + row); }
public uint mem(uint row, uint f) { return field(S_MEMBER, row, f); }
public uint pred(uint row, uint f) { return field(S_PRED, row, f); }
public uint parg(uint row) { return word(start_of(S_PARG) + row); }
public uint impl(uint row, uint f) { return field(S_IMPL, row, f); }
public uint iarg(uint row) { return word(start_of(S_IARG) + row); }
public uint bind(uint row, uint f) { return field(S_BIND, row, f); }

public uint name_byte(uint index)
{
    uint at = start_of(S_NAME) + index;
    return (word(at >> 2u) >> ((at & 3u) * 8u)) & 0xffu;
}

public void fail(uint phase, uint row, uint code)
{
    uint key = (phase << 27u) | (min(row, ROW_LIMIT) << 7u) | code;
    atomic_u32_min(validate_state, STATE_KEY, key);
}

// start + count <= len without overflow.
public bool range_ok(uint start, uint count, uint len)
{
    return count <= len && start <= len - count;
}

public bool optional_index_ok(uint index, uint len)
{
    return index == INVALID || index < len;
}

public uint member_slot(uint row)
{
    return mem(row, B_VALUE_HI) == 0u ? mem(row, B_ORDINAL) : mem(row, B_VALUE_LO);
}

public uint method_parameter_count(uint row) { return mem(row, B_VALUE_LO) & 0xffffu; }
public uint method_type_count(uint row) { return (mem(row, B_VALUE_LO) >> 16u) & 63u; }
public uint method_constant_count(uint row) { return (mem(row, B_VALUE_LO) >> 22u) & 63u; }
public uint method_receiver_mode(uint row) { return (mem(row, B_VALUE_LO) >> 28u) & 3u; }
public bool method_is_public(uint row) { return (mem(row, B_VALUE_LO) & (1u << 30u)) != 0u; }

public bool member_kind_known(uint kind)
{
    return (kind >= M_PARAMETER && kind <= M_VARIANT) || kind == M_TRAIT_METHOD || kind == M_IMPL_METHOD;
}

public bool is_generic_member(uint kind)
{
    return kind == M_GENERIC_TYPE || kind == M_GENERIC_CONST;
}

public bool is_constant_kind(uint kind)
{
    return kind == T_CONST_PARAM || kind == T_CONST_VALUE || kind == T_COUNT;
}

public bool is_parameter_leaf(uint kind)
{
    return kind == T_GENERIC || kind == T_CONST_PARAM;
}

// The owner reference's member range; false when the owner or its range is
// invalid.
public bool owner_valid(uint owner_ref)
{
    if (owner_ref == INVALID)
        return false;
    uint index = owner_ref & ~OWNER_TAG;
    return (owner_ref & OWNER_TAG) == 0u ? index < count_of(S_DECL) : index < count_of(S_IMPL);
}

public bool owner_member_range(uint owner_ref, out uint first, out uint count)
{
    uint index = owner_ref & ~OWNER_TAG;
    if ((owner_ref & OWNER_TAG) == 0u)
    {
        first = decl(index, D_FIRST_MEMBER);
        count = decl(index, D_MEMBER_COUNT);
    }
    else
    {
        first = impl(index, I_FIRST_MEMBER);
        count = impl(index, I_MEMBER_COUNT);
    }
    return range_ok(first, count, count_of(S_MEMBER));
}

// Strict UTF-8, as Rust's str::from_utf8 accepts it.
public bool utf8_valid(uint start, uint len)
{
    uint i = 0u;
    while (i < len)
    {
        uint b = name_byte(start + i);
        if (b < 0x80u)
        {
            i += 1u;
            continue;
        }
        uint width = 0u;
        uint low = 0x80u;
        uint high = 0xbfu;
        if (b >= 0xc2u && b <= 0xdfu)
            width = 2u;
        else if (b >= 0xe0u && b <= 0xefu)
        {
            width = 3u;
            if (b == 0xe0u) low = 0xa0u;
            if (b == 0xedu) high = 0x9fu;
        }
        else if (b >= 0xf0u && b <= 0xf4u)
        {
            width = 4u;
            if (b == 0xf0u) low = 0x90u;
            if (b == 0xf4u) high = 0x8fu;
        }
        else
            return false;
        if (len - i < width)
            return false;
        uint second = name_byte(start + i + 1u);
        if (second < low || second > high)
            return false;
        for (uint k = 2u; k < width; ++k)
        {
            uint next = name_byte(start + i + k);
            if (next < 0x80u || next > 0xbfu)
                return false;
        }
        i += width;
    }
    return true;
}

uint hash_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    return value ^ (value >> 16u);
}

public uint2 name_hash(uint start, uint len)
{
    uint lo = 2166136261u ^ len;
    uint hi = 0x9e3779b9u + len * 0x85ebca6bu;
    for (uint i = 0u; i < len; ++i)
    {
        uint b = name_byte(start + i);
        lo = (lo ^ b) * 16777619u;
        hi ^= b + 0x9e3779b9u + (hi << 6u) + (hi >> 2u);
    }
    return uint2(hash_mix(lo), hash_mix(hi));
}

// 0 when the name is valid; otherwise the failing check (1 range, 2 shape,
// 3 hash).
public uint name_failure(uint hash_lo, uint hash_hi, uint start, uint len)
{
    if (!range_ok(start, len, count_of(S_NAME)))
        return 1u;
    if (len == 0u || len > MAX_NAME_BYTES || !utf8_valid(start, len))
        return 2u;
    uint2 hash = name_hash(start, len);
    if (hash.x != hash_lo || hash.y != hash_hi)
        return 3u;
    return 0u;
}

// The declared scalar of a constant parameter member, or INVALID.
public uint constant_parameter_scalar(uint member)
{
    if (member >= count_of(S_MEMBER) || mem(member, B_KIND) != M_GENERIC_CONST)
        return INVALID;
    uint leaf = mem(member, B_TYPE);
    if (leaf >= count_of(S_TYPE))
        return INVALID;
    if (ty(leaf, Y_KIND) == T_SCALAR && ty(leaf, Y_EDGE_COUNT) == 0u &&
        constant_scalar_is_supported(ty(leaf, Y_PAYLOAD_LO)))
        return ty(leaf, Y_PAYLOAD_LO);
    return INVALID;
}

// The scalar of an admitted constant expression root, or INVALID.
public uint constant_scalar(uint root)
{
    if (root >= count_of(S_TYPE))
        return INVALID;
    uint kind = ty(root, Y_KIND);
    uint scalar = ty(root, Y_PAYLOAD_LO);
    if (kind == T_CONST_VALUE)
        return constant_value_is_valid(uint3(scalar, ty(root, Y_LENGTH_LO), ty(root, Y_LENGTH_HI)))
            ? scalar : INVALID;
    if (kind == T_CONST_PARAM)
        return constant_parameter_scalar(scalar);
    if (kind == T_COUNT)
        return scalar_integer_bits(scalar) != 0u ? scalar : INVALID;
    return INVALID;
}

public bool parameter_operand_domain_matches(uint member, uint argument)
{
    if (member >= count_of(S_MEMBER))
        return false;
    uint kind = mem(member, B_KIND);
    if (kind == M_GENERIC_CONST)
    {
        uint expected = constant_parameter_scalar(member);
        return expected != INVALID && expected == constant_scalar(argument);
    }
    if (kind == M_GENERIC_TYPE)
        return argument < count_of(S_TYPE) && !is_constant_kind(ty(argument, Y_KIND));
    return false;
}

// The member ranks of an owner's own generic header: the row of the
// parameter at `ordinal` when the owner's value_hi == 0 generic parameters
// are sorted by generic ordinal (ties by row), or INVALID.
public uint header_parameter_at(uint first, uint count, uint ordinal)
{
    for (uint row = first; row < first + count; ++row)
    {
        if (mem(row, B_VALUE_HI) != 0u || !is_generic_member(mem(row, B_KIND)))
            continue;
        uint key = mem(row, B_GENERIC_ORDINAL);
        uint rank = 0u;
        for (uint other = first; other < first + count; ++other)
        {
            if (other == row || mem(other, B_VALUE_HI) != 0u || !is_generic_member(mem(other, B_KIND)))
                continue;
            uint other_key = mem(other, B_GENERIC_ORDINAL);
            if (other_key < key || (other_key == key && other < row))
                rank += 1u;
        }
        if (rank == ordinal)
            return row;
    }
    return INVALID;
}

public uint header_parameter_count(uint first, uint count)
{
    uint n = 0u;
    for (uint row = first; row < first + count; ++row)
        if (mem(row, B_VALUE_HI) == 0u && is_generic_member(mem(row, B_KIND)))
            n += 1u;
    return n;
}

// Open-addressed table of method symbols: two words per slot, the symbol
// and the least member row that has it. Only symbols with the method scope
// tag are inserted, so INVALID never names one.
public void symbol_insert(uint symbol, uint row)
{
    uint capacity = validate_state[STATE_SYMBOL_CAPACITY];
    uint base = validate_state[STATE_SYMBOLS];
    uint slot = (symbol * 0x9e3779b9u) & (capacity - 1u);
    for (uint probe = 0u; probe < capacity; ++probe)
    {
        uint at = base + 2u * slot;
        uint prior = atomic_u32_compare_exchange(validate_scratch, at, INVALID, symbol);
        if (prior == INVALID || prior == symbol)
        {
            atomic_u32_min(validate_scratch, at + 1u, row);
            return;
        }
        slot = (slot + 1u) & (capacity - 1u);
    }
}

public uint symbol_first_row(uint symbol)
{
    uint capacity = validate_state[STATE_SYMBOL_CAPACITY];
    uint base = validate_state[STATE_SYMBOLS];
    uint slot = (symbol * 0x9e3779b9u) & (capacity - 1u);
    for (uint probe = 0u; probe < capacity; ++probe)
    {
        uint at = base + 2u * slot;
        uint key = validate_scratch[at];
        if (key == symbol)
            return validate_scratch[at + 1u];
        if (key == INVALID)
            return INVALID;
        slot = (slot + 1u) & (capacity - 1u);
    }
    return INVALID;
}

public uint parg_owner(uint row) { return validate_scratch[validate_state[STATE_PARG_OWNERS] + row]; }
public uint iarg_owner(uint row) { return validate_scratch[validate_state[STATE_IARG_OWNERS] + row]; }
public uint bind_owner(uint row) { return validate_scratch[validate_state[STATE_BIND_OWNERS] + row]; }

// Predicates owned by implementation `index` whose scope has the impl tag:
// the least and greatest row and scope symbol. Four words per
// implementation, each an atomic minimum (the greatest values stored
// complemented); `INVALID` least row means there is none.
public uint impl_predicate_summary(uint index, uint word)
{ return validate_scratch[validate_state[STATE_IMPL_PREDICATES] + 4u * index + word]; }

// Zero when some predicate owned by this member's owner has the member's
// symbol as its scope; INVALID otherwise. Only implementation members are
// marked.
public bool member_has_owner_predicate(uint row)
{ return validate_scratch[validate_state[STATE_MEMBER_PREDICATES] + row] == 0u; }

// A depth-first walk over the type nodes reachable from some roots. Type
// edges point to earlier nodes, so the walk ends; nodes reached twice are
// visited twice, which the callers' per-node checks allow. The stack is the
// first STACK_LIMIT words of the thread's walk region; no walk runs during
// another walk or a types_match.
public struct TypeWalk
{
    public uint depth;
    public uint visits;
    public bool overflow;

    [mutating]
    public void init()
    {
        depth = 0u;
        visits = 0u;
        overflow = false;
    }

    [mutating]
    public void push(uint node)
    {
        if (depth >= STACK_LIMIT)
        {
            overflow = true;
            return;
        }
        g_walk_stack[g_walk_base + depth] = node;
        depth += 1u;
    }

    // The next node, or INVALID when the walk is done or over its bounds.
    [mutating]
    public uint next()
    {
        if (overflow || depth == 0u)
            return INVALID;
        visits += 1u;
        if (visits > VISIT_LIMIT)
        {
            overflow = true;
            return INVALID;
        }
        depth -= 1u;
        uint node = g_walk_stack[g_walk_base + depth];
        uint first = ty(node, Y_FIRST_EDGE);
        uint count = ty(node, Y_EDGE_COUNT);
        for (uint k = 0u; k < count; ++k)
            push(edge(first + k));
        return node;
    }
};

// Graph equality with substitution of exact trait header members, as
// implementation_types_match. The substitutions are the trait header's
// leaves (header edges from `header_first`) mapped to the implementation's
// argument roots (from `roots_first`); an empty map has `pairs` zero.
// Returns 0 (differs), 1 (equal) or 2 (walk exceeded its bounds). The
// pair stack is the thread's walk region: left nodes, then right nodes.
public uint types_match(uint expected, uint actual, uint header_first, uint roots_first, uint pairs)
{
    uint left_stack = g_walk_base;
    uint right_stack = g_walk_base + STACK_LIMIT;
    uint depth = 1u;
    g_walk_stack[left_stack] = expected;
    g_walk_stack[right_stack] = actual;
    uint visits = 0u;
    while (depth != 0u)
    {
        visits += 1u;
        if (visits > VISIT_LIMIT)
            return 2u;
        depth -= 1u;
        uint left = g_walk_stack[left_stack + depth];
        uint right = g_walk_stack[right_stack + depth];
        // Follow substitutions; a chain longer than the header revisits a
        // pair, which the reference skips.
        bool skip = false;
        for (uint hop = 0u; hop <= 33u; ++hop)
        {
            if (!is_parameter_leaf(ty(left, Y_KIND)))
                break;
            uint member = ty(left, Y_PAYLOAD_LO);
            uint replacement = INVALID;
            for (uint o = 0u; o < pairs; ++o)
                if (ty(edge(header_first + o), Y_PAYLOAD_LO) == member)
                    replacement = iarg(roots_first + o);
            if (replacement == INVALID)
                break;
            if (hop == 33u)
            {
                skip = true;
                break;
            }
            left = replacement;
        }
        if (skip)
            continue;
        uint kind = ty(left, Y_KIND);
        if (kind != ty(right, Y_KIND) || ty(left, Y_EDGE_COUNT) != ty(right, Y_EDGE_COUNT))
            return 0u;
        bool equal = true;
        if (kind == T_SCALAR || kind == T_GENERIC || kind == T_CONST_PARAM || kind == T_COUNT || kind == T_REF)
            equal = ty(left, Y_PAYLOAD_LO) == ty(right, Y_PAYLOAD_LO);
        else if (kind == T_DECL)
            equal = ty(left, Y_PAYLOAD_LO) == ty(right, Y_PAYLOAD_LO) &&
                ty(left, Y_NOMINAL_UNIT) == ty(right, Y_NOMINAL_UNIT) &&
                ty(left, Y_PAYLOAD_HI) == ty(right, Y_PAYLOAD_HI);
        else if (kind == T_CONST_VALUE)
            equal = ty(left, Y_PAYLOAD_LO) == ty(right, Y_PAYLOAD_LO) &&
                ty(left, Y_LENGTH_LO) == ty(right, Y_LENGTH_LO) &&
                ty(left, Y_LENGTH_HI) == ty(right, Y_LENGTH_HI);
        if (!equal)
            return 0u;
        uint count = ty(left, Y_EDGE_COUNT);
        uint left_first = ty(left, Y_FIRST_EDGE);
        uint right_first = ty(right, Y_FIRST_EDGE);
        for (uint k = 0u; k < count; ++k)
        {
            if (depth >= STACK_LIMIT)
                return 2u;
            g_walk_stack[left_stack + depth] = edge(left_first + k);
            g_walk_stack[right_stack + depth] = edge(right_first + k);
            depth += 1u;
        }
    }
    return 1u;
}
