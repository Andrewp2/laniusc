// Shared view of the dependency-page pack plan (dependency_interface.rs).
//
// A job's dependency pages are packed on the GPU from the dependency
// semantic interfaces' encoded bytes, which sit back to back in
// pack_sources. The plan names, for every page, where its words go in
// pack_output, its precomputed 46-word header (counts and table offsets),
// and one descriptor per interface: its identity, its first row in every
// flattened table, and where each of its sections starts in pack_sources.
// A sentinel descriptor after the last interface holds the page totals.
//
// Plan words:
//   0 page count, 1 page words of all pages, 2 modules of all pages
//   PLAN_PAGES + PAGE_STRIDE * page: output word, word count, first row
//     thread, first module thread, module count, interface count, first
//     descriptor word, header word
//   descriptor: library id, unit id, 2 reserved, then per section the
//     page row base and the section's first source word (name bytes: the
//     page byte base and the word holding the interface's first name byte)

StructuredBuffer<uint> pack_plan;
StructuredBuffer<uint> pack_sources;
RWStructuredBuffer<uint> pack_output;

static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;
static const uint IMPLEMENTATION_OWNER_TAG = 0x80000000u;

static const uint PLAN_PAGES = 4u;
static const uint PAGE_STRIDE = 8u;
static const uint PAGE_OUTPUT_WORD = 0u;
static const uint PAGE_WORD_COUNT = 1u;
static const uint PAGE_FIRST_ROW_THREAD = 2u;
static const uint PAGE_FIRST_MODULE_THREAD = 3u;
static const uint PAGE_MODULE_COUNT = 4u;
static const uint PAGE_INTERFACE_COUNT = 5u;
static const uint PAGE_DESCRIPTOR_WORD = 6u;
static const uint PAGE_HEADER_WORD = 7u;

static const uint DESCRIPTOR_STRIDE = 28u;
static const uint DESCRIPTOR_LIBRARY = 0u;
static const uint DESCRIPTOR_UNIT = 1u;
static const uint DESCRIPTOR_SECTIONS = 4u;

static const uint SECTION_MODULE = 0u;
static const uint SECTION_SEGMENT = 1u;
static const uint SECTION_DECLARATION = 2u;
static const uint SECTION_TYPE = 3u;
static const uint SECTION_TYPE_EDGE = 4u;
static const uint SECTION_MEMBER = 5u;
static const uint SECTION_PREDICATE = 6u;
static const uint SECTION_PREDICATE_ARGUMENT = 7u;
static const uint SECTION_IMPLEMENTATION = 8u;
static const uint SECTION_IMPLEMENTATION_ARGUMENT = 9u;
static const uint SECTION_METHOD_BINDING = 10u;
static const uint SECTION_NAME = 11u;

static const uint HEADER_WORDS = 46u;
static const uint HEADER_MODULE_DECLARATION_START = 24u;
static const uint HEADER_MODULE_DECLARATION_COUNT = 25u;
static const uint HEADER_MODULE_DECLARATION_ORDER = 26u;
static const uint DECLARATION_WORDS = 14u;

uint thread_index(uint3 gid, uint3 ltid)
{
    return (gid.x + gid.y * MAX_GROUPS_X) * 256u + ltid.x;
}

uint page_word(uint page, uint field)
{
    return pack_plan[PLAN_PAGES + page * PAGE_STRIDE + field];
}

// The page whose threads, counted from the page field `first_thread`,
// include `thread`.
uint page_of_thread(uint thread, uint first_thread)
{
    uint page_count = pack_plan[0];
    uint page = 0u;
    for (uint candidate = 1u; candidate < page_count; candidate++) {
        if (page_word(candidate, first_thread) <= thread) page = candidate;
    }
    return page;
}

uint descriptor_word(uint descriptors, uint index, uint field)
{
    return pack_plan[descriptors + index * DESCRIPTOR_STRIDE + field];
}

uint section_base(uint descriptors, uint index, uint section)
{
    return descriptor_word(descriptors, index, DESCRIPTOR_SECTIONS + 2u * section);
}

uint section_source(uint descriptors, uint index, uint section)
{
    return descriptor_word(descriptors, index, DESCRIPTOR_SECTIONS + 2u * section + 1u);
}

// The interface holding page row `row` of `section`: the last interface
// whose first row is at most `row`. Interfaces without rows of the section
// share their successor's base, so the last one is the one that owns it.
uint interface_of_row(uint descriptors, uint interface_count, uint section, uint row)
{
    uint low = 0u;
    uint high = interface_count;
    while (high - low > 1u) {
        uint middle = (low + high) / 2u;
        if (section_base(descriptors, middle, section) <= row) {
            low = middle;
        } else {
            high = middle;
        }
    }
    return low;
}
