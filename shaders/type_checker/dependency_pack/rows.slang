import type_checker.dependency_pack.plan;

// Packs every word of the job's dependency pages except the module
// declaration index (module_index.slang): one thread per page word.
//
// A page is its header followed by its tables in a fixed order. Each table
// is either an identity column (library, unit or local row of a flattened
// section), the records of one section with their references into flattened
// storage rebased by the owning interface's row bases, or the name bytes of
// all interfaces back to back.

static const uint TABLE_COUNT = 30u;
static const uint KIND_LIBRARY = 0u;
static const uint KIND_UNIT = 1u;
static const uint KIND_LOCAL = 2u;
static const uint KIND_RECORDS = 3u;
static const uint KIND_MODULE_INDEX = 4u;
static const uint KIND_NAMES = 5u;

// Tables in page order: header word holding the table's offset, section,
// kind and record width.
static const uint TABLE_HEADER[30] = {
    8u, 9u, 10u, 11u, 12u, 13u, 14u, 15u, 16u, 17u, 21u, 22u, 23u, 24u, 25u,
    26u, 18u, 19u, 30u, 31u, 32u, 33u, 34u, 38u, 39u, 40u, 41u, 42u, 43u, 20u,
};
static const uint TABLE_SECTION[30] = {
    0u, 0u, 0u, 0u, 1u, 2u, 2u, 2u, 2u, 3u, 3u, 3u, 3u, 0u, 0u,
    0u, 4u, 5u, 6u, 6u, 6u, 6u, 7u, 8u, 8u, 8u, 8u, 9u, 10u, 11u,
};
static const uint TABLE_KIND[30] = {
    0u, 1u, 2u, 3u, 3u, 0u, 1u, 2u, 3u, 3u, 0u, 1u, 2u, 4u, 4u,
    4u, 3u, 3u, 0u, 1u, 2u, 3u, 3u, 0u, 1u, 2u, 3u, 3u, 3u, 5u,
};
static const uint TABLE_WIDTH[30] = {
    1u, 1u, 1u, 2u, 4u, 1u, 1u, 1u, 14u, 9u, 1u, 1u, 1u, 1u, 1u,
    1u, 1u, 12u, 1u, 1u, 1u, 8u, 1u, 1u, 1u, 1u, 15u, 1u, 6u, 1u,
};

static const uint TYPE_KIND_GENERIC_PARAMETER = 2u;
static const uint TYPE_KIND_CONST_PARAMETER = 8u;

uint rebase_optional(uint value, uint base)
{
    return value == INVALID ? INVALID : value + base;
}

uint rebase_owner(uint value, uint descriptors, uint index)
{
    uint tag = value & IMPLEMENTATION_OWNER_TAG;
    uint section = tag != 0u ? SECTION_IMPLEMENTATION : SECTION_DECLARATION;
    return tag | ((value & ~IMPLEMENTATION_OWNER_TAG) + section_base(descriptors, index, section));
}

// One record field with its references into flattened storage rebased.
// `row_source` is the source word of the record's first field.
uint rebase_field(uint section, uint field, uint value, uint row_source,
    uint descriptors, uint index)
{
    switch (section) {
    case SECTION_MODULE:
        if (field == 0u) return value + section_base(descriptors, index, SECTION_SEGMENT);
        return value;
    case SECTION_SEGMENT:
        if (field == 2u) return value + section_base(descriptors, index, SECTION_NAME);
        return value;
    case SECTION_DECLARATION:
        if (field == 0u) return value + section_base(descriptors, index, SECTION_MODULE);
        if (field == 3u) return value + section_base(descriptors, index, SECTION_NAME);
        if (field == 7u) return rebase_optional(value, section_base(descriptors, index, SECTION_TYPE));
        if (field == 8u) return value + section_base(descriptors, index, SECTION_MEMBER);
        if (field == 10u) return rebase_optional(value, section_base(descriptors, index, SECTION_DECLARATION));
        return value;
    case SECTION_TYPE:
        if (field == 1u) {
            uint kind = pack_sources[row_source];
            if (kind == TYPE_KIND_GENERIC_PARAMETER || kind == TYPE_KIND_CONST_PARAMETER) {
                return value + section_base(descriptors, index, SECTION_MEMBER);
            }
            return value;
        }
        if (field == 3u) {
            if (pack_sources[row_source + 4u] == 0u) return 0u;
            return value + section_base(descriptors, index, SECTION_TYPE_EDGE);
        }
        return value;
    case SECTION_TYPE_EDGE:
    case SECTION_PREDICATE_ARGUMENT:
    case SECTION_IMPLEMENTATION_ARGUMENT:
        return value + section_base(descriptors, index, SECTION_TYPE);
    case SECTION_MEMBER:
        if (field == 0u) return rebase_owner(value, descriptors, index);
        if (field == 5u) return value + section_base(descriptors, index, SECTION_NAME);
        if (field == 7u || field == 10u) {
            return rebase_optional(value, section_base(descriptors, index, SECTION_TYPE));
        }
        return value;
    case SECTION_PREDICATE:
        if (field == 0u) return rebase_owner(value, descriptors, index);
        if (field == 2u) return value + section_base(descriptors, index, SECTION_TYPE);
        if (field == 6u) return value + section_base(descriptors, index, SECTION_PREDICATE_ARGUMENT);
        return value;
    case SECTION_IMPLEMENTATION:
        if (field == 0u) return value + section_base(descriptors, index, SECTION_MODULE);
        if (field == 5u) return value + section_base(descriptors, index, SECTION_TYPE);
        if (field == 6u) return value + section_base(descriptors, index, SECTION_IMPLEMENTATION_ARGUMENT);
        if (field == 8u) return value + section_base(descriptors, index, SECTION_MEMBER);
        if (field == 10u) return value + section_base(descriptors, index, SECTION_PREDICATE);
        if (field == 12u) return value + section_base(descriptors, index, SECTION_METHOD_BINDING);
        return value;
    case SECTION_METHOD_BINDING:
        if (field == 0u) return value + section_base(descriptors, index, SECTION_IMPLEMENTATION);
        if (field == 2u) return value + section_base(descriptors, index, SECTION_MEMBER);
        return value;
    default:
        return value;
    }
}

uint name_byte(uint descriptors, uint interface_count, uint byte)
{
    uint index = interface_of_row(descriptors, interface_count, SECTION_NAME, byte);
    uint source_byte = section_source(descriptors, index, SECTION_NAME) * 4u
        + (byte - section_base(descriptors, index, SECTION_NAME));
    return (pack_sources[source_byte >> 2u] >> ((source_byte & 3u) * 8u)) & 0xffu;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint thread = thread_index(gid, ltid);
    if (thread >= pack_plan[1]) return;
    uint page = page_of_thread(thread, PAGE_FIRST_ROW_THREAD);
    uint word = thread - page_word(page, PAGE_FIRST_ROW_THREAD);
    uint header = page_word(page, PAGE_HEADER_WORD);
    uint output = page_word(page, PAGE_OUTPUT_WORD) + word;
    if (word < HEADER_WORDS) {
        pack_output[output] = pack_plan[header + word];
        return;
    }
    // The last table starting at or before the word holds it: empty tables
    // start where their successor does.
    uint low = 0u;
    uint high = TABLE_COUNT;
    while (high - low > 1u) {
        uint middle = (low + high) / 2u;
        if (pack_plan[header + TABLE_HEADER[middle]] <= word) {
            low = middle;
        } else {
            high = middle;
        }
    }
    uint kind = TABLE_KIND[low];
    if (kind == KIND_MODULE_INDEX) return;
    uint descriptors = page_word(page, PAGE_DESCRIPTOR_WORD);
    uint interface_count = page_word(page, PAGE_INTERFACE_COUNT);
    uint section = TABLE_SECTION[low];
    uint offset = word - pack_plan[header + TABLE_HEADER[low]];
    if (kind == KIND_NAMES) {
        uint name_bytes = section_base(descriptors, interface_count, SECTION_NAME);
        uint packed = 0u;
        for (uint lane = 0u; lane < 4u; lane++) {
            uint byte = offset * 4u + lane;
            if (byte < name_bytes) {
                packed |= name_byte(descriptors, interface_count, byte) << (lane * 8u);
            }
        }
        pack_output[output] = packed;
        return;
    }
    uint width = TABLE_WIDTH[low];
    uint row = offset / width;
    uint field = offset - row * width;
    uint index = interface_of_row(descriptors, interface_count, section, row);
    uint local = row - section_base(descriptors, index, section);
    uint value;
    if (kind == KIND_LIBRARY) {
        value = descriptor_word(descriptors, index, DESCRIPTOR_LIBRARY);
    } else if (kind == KIND_UNIT) {
        value = descriptor_word(descriptors, index, DESCRIPTOR_UNIT);
    } else if (kind == KIND_LOCAL) {
        value = local;
    } else {
        uint row_source = section_source(descriptors, index, section) + local * width;
        value = rebase_field(section, field, pack_sources[row_source + field], row_source,
            descriptors, index);
    }
    pack_output[output] = value;
}
