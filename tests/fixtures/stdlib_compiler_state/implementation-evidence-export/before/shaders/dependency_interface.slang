import semantic_interface_layout;
// Canonical shader view of a packed semantic-interface page.
// Header words 0..7 are table counts, 8..26 are word offsets, and 27
// identifies the first/final logical page streamed through the GPU slot.
// Words 28..34 contain predicate counts and table offsets.

StructuredBuffer<uint> dependency_words;

static const uint DEPENDENCY_MODULE_LIBRARY_OFFSET = 8u;
static const uint DEPENDENCY_MODULE_UNIT_OFFSET = 9u;
static const uint DEPENDENCY_MODULE_LOCAL_OFFSET = 10u;
static const uint DEPENDENCY_MODULE_OFFSET = 11u;
static const uint DEPENDENCY_MODULE_SEGMENT_OFFSET = 12u;
static const uint DEPENDENCY_DECLARATION_LIBRARY_OFFSET = 13u;
static const uint DEPENDENCY_DECLARATION_UNIT_OFFSET = 14u;
static const uint DEPENDENCY_DECLARATION_LOCAL_OFFSET = 15u;
static const uint DEPENDENCY_DECLARATION_OFFSET = 16u;
static const uint DEPENDENCY_TYPE_OFFSET = 17u;
static const uint DEPENDENCY_TYPE_EDGE_OFFSET = 18u;
static const uint DEPENDENCY_MEMBER_OFFSET = 19u;
static const uint DEPENDENCY_NAME_BYTE_OFFSET = 20u;
static const uint DEPENDENCY_TYPE_LIBRARY_OFFSET = 21u;
static const uint DEPENDENCY_TYPE_UNIT_OFFSET = 22u;
static const uint DEPENDENCY_TYPE_LOCAL_OFFSET = 23u;
static const uint DEPENDENCY_MODULE_DECLARATION_START_OFFSET = 24u;
static const uint DEPENDENCY_MODULE_DECLARATION_COUNT_OFFSET = 25u;
static const uint DEPENDENCY_MODULE_DECLARATION_ORDER_OFFSET = 26u;
static const uint DEPENDENCY_PAGE_FLAGS_OFFSET = 27u;
static const uint DEPENDENCY_PREDICATE_COUNT = 28u;
static const uint DEPENDENCY_PREDICATE_ARGUMENT_COUNT = 29u;
static const uint DEPENDENCY_PREDICATE_LIBRARY_OFFSET = 30u;
static const uint DEPENDENCY_PREDICATE_UNIT_OFFSET = 31u;
static const uint DEPENDENCY_PREDICATE_LOCAL_OFFSET = 32u;
static const uint DEPENDENCY_PREDICATE_OFFSET = 33u;
static const uint DEPENDENCY_PREDICATE_ARGUMENT_OFFSET = 34u;

bool dependency_is_first_page()
{
    return (dependency_words[DEPENDENCY_PAGE_FLAGS_OFFSET] & 1u) != 0u;
}

bool dependency_is_final_page()
{
    return (dependency_words[DEPENDENCY_PAGE_FLAGS_OFFSET] & 2u) != 0u;
}

uint dependency_count(uint index)
{
    return dependency_words[index];
}

uint dependency_module_count()
{
    return dependency_count(1u);
}

uint dependency_declaration_count()
{
    return dependency_count(3u);
}

uint dependency_type_count()
{
    return dependency_count(4u);
}

uint dependency_member_count()
{
    return dependency_count(6u);
}

uint dependency_table_word(uint offset_header, uint index)
{
    return dependency_words[dependency_words[offset_header] + index];
}

uint dependency_module_library_id(uint index)
{
    return dependency_table_word(DEPENDENCY_MODULE_LIBRARY_OFFSET, index);
}

uint dependency_module_unit_id(uint index)
{
    return dependency_table_word(DEPENDENCY_MODULE_UNIT_OFFSET, index);
}

uint dependency_module_local_index(uint index)
{
    return dependency_table_word(DEPENDENCY_MODULE_LOCAL_OFFSET, index);
}

uint dependency_module_word(uint index)
{
    return dependency_table_word(DEPENDENCY_MODULE_OFFSET, index);
}

uint dependency_module_segment_word(uint index)
{
    return dependency_table_word(DEPENDENCY_MODULE_SEGMENT_OFFSET, index);
}

uint dependency_module_declaration_start(uint module_i)
{
    return dependency_table_word(DEPENDENCY_MODULE_DECLARATION_START_OFFSET, module_i);
}

uint dependency_module_declaration_count(uint module_i)
{
    return dependency_table_word(DEPENDENCY_MODULE_DECLARATION_COUNT_OFFSET, module_i);
}

uint dependency_module_declaration(uint ordered_i)
{
    return dependency_table_word(DEPENDENCY_MODULE_DECLARATION_ORDER_OFFSET, ordered_i);
}

uint dependency_declaration_library_id(uint index)
{
    return dependency_table_word(DEPENDENCY_DECLARATION_LIBRARY_OFFSET, index);
}

uint dependency_declaration_unit_id(uint index)
{
    return dependency_table_word(DEPENDENCY_DECLARATION_UNIT_OFFSET, index);
}

uint dependency_declaration_local_index(uint index)
{
    return dependency_table_word(DEPENDENCY_DECLARATION_LOCAL_OFFSET, index);
}

uint dependency_declaration_word(uint index)
{
    return dependency_table_word(DEPENDENCY_DECLARATION_OFFSET, index);
}

uint dependency_type_word(uint index)
{
    return dependency_table_word(DEPENDENCY_TYPE_OFFSET, index);
}

uint dependency_type_library_id(uint index)
{
    return dependency_table_word(DEPENDENCY_TYPE_LIBRARY_OFFSET, index);
}

uint dependency_type_unit_id(uint index)
{
    return dependency_table_word(DEPENDENCY_TYPE_UNIT_OFFSET, index);
}

uint dependency_type_local_index(uint index)
{
    return dependency_table_word(DEPENDENCY_TYPE_LOCAL_OFFSET, index);
}

uint dependency_type_edge_word(uint index)
{
    return dependency_table_word(DEPENDENCY_TYPE_EDGE_OFFSET, index);
}

uint dependency_member_word(uint index)
{
    return dependency_table_word(DEPENDENCY_MEMBER_OFFSET, index);
}

// These row numbers belong to the active page. Retained contracts use the
// parallel library/unit/local identity and reacquire a row after page replacement.
uint dependency_predicate_count() { return dependency_words[DEPENDENCY_PREDICATE_COUNT]; }
uint dependency_predicate_argument_count() { return dependency_words[DEPENDENCY_PREDICATE_ARGUMENT_COUNT]; }
uint dependency_predicate_library_id(uint index)
{ return dependency_table_word(DEPENDENCY_PREDICATE_LIBRARY_OFFSET, index); }
uint dependency_predicate_unit_id(uint index)
{ return dependency_table_word(DEPENDENCY_PREDICATE_UNIT_OFFSET, index); }
uint dependency_predicate_local_index(uint index)
{ return dependency_table_word(DEPENDENCY_PREDICATE_LOCAL_OFFSET, index); }
uint dependency_predicate_word(uint index)
{ return dependency_table_word(DEPENDENCY_PREDICATE_OFFSET, index); }
uint dependency_predicate_argument(uint index)
{ return dependency_table_word(DEPENDENCY_PREDICATE_ARGUMENT_OFFSET, index); }

// A generic type node stores a member identity. Resolve that member's ordinal
// before indexing a concrete instance or a call's generic claims; its absolute
// index changes when other declarations precede it in the dependency page.
uint dependency_generic_type_slot(uint type_index)
{
    if (type_index >= dependency_type_count() ||
        dependency_type_word(type_index * 9u) != 2u)
        return 0xffffffffu;
    uint member = dependency_type_word(type_index * 9u + 1u);
    if (member >= dependency_member_count() ||
        dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 1u) != 2u)
        return 0xffffffffu;
    return dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 9u) == 0u
        ? dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 2u) : dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 8u);
}

// Array constant lengths carry member identities, as type parameters do.
// Constant slots start at zero in their own domain; member ordinals include
// the declaration's preceding type parameters.
uint dependency_generic_const_slot(uint type_index)
{
    if (type_index >= dependency_type_count()) return 0xffffffffu;
    uint kind = dependency_type_word(type_index * 9u);
    if (kind != 8u && (kind != 4u || dependency_type_word(type_index * 9u + 5u) != 2u)) return 0xffffffffu;
    uint member = dependency_type_word(type_index * 9u + (kind == 8u ? 1u : 6u));
    if (member >= dependency_member_count() || dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 1u) != 3u)
        return 0xffffffffu;
    if (dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 9u) != 0u)
        return dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 8u);
    uint owner = dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS);
    if (owner >= dependency_declaration_count()) return 0xffffffffu;
    uint start = dependency_declaration_word(owner * 14u + 8u);
    uint count = dependency_declaration_word(owner * 14u + 9u);
    if (start > member || member - start >= count) return 0xffffffffu;
    uint type_count = 0u;
    for (; type_count < min(count, 32u); type_count++)
        if (dependency_member_word((start + type_count) * SEMANTIC_INTERFACE_MEMBER_WORDS + 1u) != 2u) break;
    uint ordinal = dependency_member_word(member * SEMANTIC_INTERFACE_MEMBER_WORDS + 2u);
    return ordinal >= type_count && ordinal - type_count < 32u ? ordinal - type_count : 0xffffffffu;
}

uint dependency_name_byte_word(uint index)
{
    return dependency_table_word(DEPENDENCY_NAME_BYTE_OFFSET, index);
}

int dependency_identity_compare(
    uint row_library,
    uint row_unit,
    uint row_local,
    uint library_id,
    uint unit_id,
    uint local_index)
{
    if (row_library != library_id) return row_library < library_id ? -1 : 1;
    if (row_unit != unit_id) return row_unit < unit_id ? -1 : 1;
    if (row_local != local_index) return row_local < local_index ? -1 : 1;
    return 0;
}

// Identity side tables are lexicographically ordered by the CPU page packer.
// Binary search recovers an active-page row without another resident lookup
// allocation and without leaking page-local row numbers across submissions.
uint dependency_find_declaration(uint library_id, uint unit_id, uint local_index)
{
    uint lo = 0u;
    uint hi = dependency_declaration_count();
    for (uint step = 0u; step < 32u && lo < hi; step += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        int order = dependency_identity_compare(
            dependency_declaration_library_id(mid),
            dependency_declaration_unit_id(mid),
            dependency_declaration_local_index(mid),
            library_id,
            unit_id,
            local_index);
        if (order < 0) lo = mid + 1u;
        else hi = mid;
    }
    return lo < dependency_declaration_count() &&
           dependency_declaration_library_id(lo) == library_id &&
           dependency_declaration_unit_id(lo) == unit_id &&
           dependency_declaration_local_index(lo) == local_index
        ? lo
        : 0xffffffffu;
}

// Associated-method parameters are ordinary typed Parameter members of the
// public receiver declaration. value_hi identifies the stable method symbol;
// value_lo is the source parameter ordinal. Syntactic self / &self is omitted;
// its remaining parameters start at one. Typed first parameters start at zero
// and can be passed explicitly or consumed by a dotted receiver call.
uint dependency_find_method(uint library_id, uint unit_id, uint method_symbol)
{
    if (method_symbol == 0xffffffffu || (method_symbol & 0x80000000u) == 0u)
        return 0xffffffffu;
    uint count = dependency_member_count();
    for (uint row = 0u; row < count; row += 1u)
    {
        uint base = row * SEMANTIC_INTERFACE_MEMBER_WORDS;
        if (dependency_member_word(base + 1u) != 6u ||
            dependency_member_word(base + 9u) != method_symbol)
            continue;
        uint owner = dependency_member_word(base);
        if (owner < dependency_declaration_count() &&
            dependency_declaration_library_id(owner) == library_id &&
            dependency_declaration_unit_id(owner) == unit_id)
            return row;
    }
    return 0xffffffffu;
}

uint dependency_method_parameter_type(uint method_row, uint ordinal)
{
    if (method_row >= dependency_member_count()) return 0xffffffffu;
    uint method_base = method_row * SEMANTIC_INTERFACE_MEMBER_WORDS;
    uint owner = dependency_member_word(method_base);
    if (owner >= dependency_declaration_count()) return 0xffffffffu;
    uint start = dependency_declaration_word(owner * 14u + 8u);
    uint count = dependency_declaration_word(owner * 14u + 9u);
    uint total = dependency_member_count();
    if (start > total || count > total - start) return 0xffffffffu;
    uint symbol = dependency_member_word(method_base + 9u);
    uint found = 0xffffffffu;
    for (uint row = start; row < start + count; row += 1u)
    {
        uint base = row * SEMANTIC_INTERFACE_MEMBER_WORDS;
        if (dependency_member_word(base + 1u) != 1u ||
            dependency_member_word(base + 9u) != symbol ||
            dependency_member_word(base + 8u) != ordinal)
            continue;
        if (found != 0xffffffffu) return 0xffffffffu;
        found = dependency_member_word(base + 7u);
    }
    return found < dependency_type_count() ? found : 0xffffffffu;
}

// Version 6 method value words carry declared requirements, not signature uses.
uint dependency_method_parameter_count(uint method) { return dependency_member_word(method * SEMANTIC_INTERFACE_MEMBER_WORDS + 8u) & 0xffffu; }
uint dependency_method_type_count(uint method) { return (dependency_member_word(method * SEMANTIC_INTERFACE_MEMBER_WORDS + 8u) >> 16u) & 63u; }
uint dependency_method_constant_count(uint method) { return (dependency_member_word(method * SEMANTIC_INTERFACE_MEMBER_WORDS + 8u) >> 22u) & 63u; }

uint dependency_callable_return_type(uint library, uint unit, uint symbol)
{
    uint declaration = dependency_find_declaration(library, unit, symbol);
    if (declaration != 0xffffffffu)
    {
        uint signature = dependency_declaration_word(declaration * 14u + 7u);
        if (signature >= dependency_type_count()) return 0xffffffffu;
        uint base = signature * 9u;
        uint count = dependency_type_word(base + 4u);
        uint start = dependency_type_word(base + 3u);
        uint edges = dependency_count(5u);
        if (dependency_type_word(base) != 7u || count == 0u || start > edges || count > edges - start)
            return 0xffffffffu;
        return dependency_type_edge_word(start + count - 1u);
    }
    uint method = dependency_find_method(library, unit, symbol);
    return method == 0xffffffffu ? 0xffffffffu : dependency_member_word(method * SEMANTIC_INTERFACE_MEMBER_WORDS + 7u);
}

// Source order is independent of member position and type/constant slot.
uint dependency_generic_parameter_ordinal(uint member)
{
    if (member >= dependency_member_count()) return 0xffffffffu;
    uint base = member * SEMANTIC_INTERFACE_MEMBER_WORDS;
    uint kind = dependency_member_word(base + 1u);
    return (kind == 2u || kind == 3u)
        ? dependency_member_word(base + 11u) : 0xffffffffu;
}
