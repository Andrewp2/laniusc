import type_checker.dependency_pack.plan;

// Builds each dependency page's module declaration index: for every module,
// the start and count of its declarations in the order table, and the order
// table itself, which lists the page's declarations grouped by module and in
// declaration order within a module. One thread per page module.
//
// A declaration's module belongs to its own interface, so a module's start
// is its interface's first declaration row plus the interface's
// declarations in lower modules.

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint thread = thread_index(gid, ltid);
    if (thread >= pack_plan[2]) return;
    uint page = page_of_thread(thread, PAGE_FIRST_MODULE_THREAD);
    uint module = thread - page_word(page, PAGE_FIRST_MODULE_THREAD);
    uint header = page_word(page, PAGE_HEADER_WORD);
    uint output = page_word(page, PAGE_OUTPUT_WORD);
    uint descriptors = page_word(page, PAGE_DESCRIPTOR_WORD);
    uint interface_count = page_word(page, PAGE_INTERFACE_COUNT);
    uint index = interface_of_row(descriptors, interface_count, SECTION_MODULE, module);
    uint local_module = module - section_base(descriptors, index, SECTION_MODULE);
    uint first_declaration = section_base(descriptors, index, SECTION_DECLARATION);
    uint declaration_count =
        section_base(descriptors, index + 1u, SECTION_DECLARATION) - first_declaration;
    uint source = section_source(descriptors, index, SECTION_DECLARATION);
    uint before = 0u;
    uint count = 0u;
    for (uint declaration = 0u; declaration < declaration_count; declaration++) {
        uint declaration_module = pack_sources[source + declaration * DECLARATION_WORDS];
        before += uint(declaration_module < local_module);
        count += uint(declaration_module == local_module);
    }
    uint start = first_declaration + before;
    pack_output[output + pack_plan[header + HEADER_MODULE_DECLARATION_START] + module] = start;
    pack_output[output + pack_plan[header + HEADER_MODULE_DECLARATION_COUNT] + module] = count;
    uint order = output + pack_plan[header + HEADER_MODULE_DECLARATION_ORDER] + start;
    uint written = 0u;
    for (uint declaration = 0u; declaration < declaration_count && written < count; declaration++) {
        if (pack_sources[source + declaration * DECLARATION_WORDS] == local_module) {
            pack_output[order + written] = first_declaration + declaration;
            written++;
        }
    }
}
