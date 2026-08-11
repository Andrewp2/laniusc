// Canonical shader view of a packed semantic-interface page.
// Header words 0..7 are table counts, 8..26 are word offsets, and 27
// identifies the first/final logical page streamed through the GPU slot.

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
