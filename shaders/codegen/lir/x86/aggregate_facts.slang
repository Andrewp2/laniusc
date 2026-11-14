// Per-aggregate facts that lir/x86/optimize_elements gathers in parallel, one
// lane per element row, so that no single lane loops over a wide literal.
// x86_aggregate_facts[row] counts the element rows of aggregate `row` that
// fit the dense array layout; optimize_init clears it for every row of the
// job.

import codegen.lowering_ir;

// Whether element row `row` fits the dense layout of the aggregate whose
// element range starts at `start`: it belongs to `aggregate`, and it holds
// words [k * width, (k + 1) * width) for k = row - start, where width is the
// first element's nonzero word count.
bool x86_dense_element(SemanticLirAggregateElement element, uint aggregate,
                       uint row, uint start, uint width)
{
    if (element.aggregate_instruction != aggregate || row < start) return false;
    if (width == 0u || width == 0xffffffffu || element.word_count != width)
        return false;
    // offset == (row - start) * width, checked without overflowing.
    uint offset = element.word_offset;
    return offset % width == 0u && offset / width == row - start &&
        offset <= 0xffffffffu - width;
}

// Whether all `count` element rows of the aggregate's range fit the dense
// layout, so element k holds words [k * width, (k + 1) * width) and no other
// element row in the range covers them. Readers then index the element directly
// instead of scanning the range.
bool x86_dense_aggregate(StructuredBuffer<uint> facts, uint aggregate, uint count)
{
    return count != 0u && facts[aggregate] == count;
}
