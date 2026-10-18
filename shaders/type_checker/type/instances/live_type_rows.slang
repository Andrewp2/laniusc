// The checked type rows a job can own, for passes that visit every row.
//
// Rows are laid out as one source row per token of the workspace, the body
// graph's BODY_GRAPH_NODES rows, then one generated row per
// type_application_count ordinal (allocate_application.slang, ct_realize).
// A job owns the source rows of its own tokens, the body graph rows and its
// generated rows. type_instances.clear (00_clear) zeroes every row's kind at
// the start of the job and nothing else gives one a kind, so a pass that
// skips a row without a kind may visit only these.
//
// A workspace retained from a larger job keeps its capacity. Bounding such a
// pass by capacity made a small job after a large one walk the large job's
// rows from one lane per token.
#ifndef LANIUS_LIVE_TYPE_ROWS
#define LANIUS_LIVE_TYPE_ROWS
#include "body_graph_layout.slang"

// The number of live rows. `tokens` is the job's token count, `source_rows`
// the workspace's source rows, `capacity` its row count and `generated`
// type_application_count[0] (an allocation that failed still counted).
uint live_type_row_count(uint tokens, uint source_rows, uint capacity, uint generated)
{
    uint source = min(tokens, min(source_rows, capacity));
    if (source_rows >= capacity) return source;
    uint tail = capacity - source_rows;
    uint body = min(tail, BODY_GRAPH_NODES);
    return source + body + min(generated, tail - body);
}

// The row of live index `index` (below live_type_row_count): the source rows
// first, then the body graph and generated rows from `source_rows` on.
uint live_type_row(uint index, uint tokens, uint source_rows)
{
    uint source = min(tokens, source_rows);
    return index < source ? index : source_rows + (index - source);
}
#endif
