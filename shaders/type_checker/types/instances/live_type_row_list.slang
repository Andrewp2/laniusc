// The live type rows the inference rounds' row passes visit (the rounds'
// index_closed_applications, project_listed_imported_field_types): the
// source rows that hold a type, listed once before the rounds
// (list_type_rows), then the generated rows as in live_type_rows.slang.
//
// A source row without a kind holds no type, and these passes skip it. Inside
// the rounds only method call keys (mark_method_call_keys) give a source row a kind, a
// path receiver's token; it appends the row when it does
// (type_row_list_push). Generated rows get theirs from allocate_application
// and ct_realize, past the source rows, and stay a range.
//
// type_live_row_count: [0] source rows listed, [1] lanes the listed passes
// launch (write_type_row_dispatch_args), which they stride by.
#ifndef LANIUS_LIVE_TYPE_ROW_LIST
#define LANIUS_LIVE_TYPE_ROW_LIST
#include "live_type_rows.slang"

StructuredBuffer<uint> type_live_rows;
StructuredBuffer<uint> type_live_row_count;

struct ListedTypeRows
{
    uint listed;  // listed source rows
    uint lanes;   // launched lanes
};

// Every lane of a wave gets the same value; the words are loaded once per
// wave.
ListedTypeRows listed_type_rows()
{
    uint2 words = uint2(0u, 1u);
    if (WaveIsFirstLane()) words = uint2(type_live_row_count[0u], type_live_row_count[1u]);
    words = WaveReadLaneFirst(words);
    uint capacity; uint stride;
    type_live_rows.GetDimensions(capacity, stride);
    ListedTypeRows rows;
    rows.listed = min(words.x, capacity);
    rows.lanes = max(words.y, 1u);
    return rows;
}

// The number of live rows: the listed source rows, then the generated rows
// (`generated` is type_application_count[0]).
uint listed_type_row_count(ListedTypeRows rows, uint source_rows, uint capacity, uint generated)
{
    uint tail = source_rows >= capacity ? 0u : min(generated, capacity - source_rows);
    return rows.listed + tail;
}

// The row of live index `index` (below listed_type_row_count).
uint listed_type_row(ListedTypeRows rows, uint index, uint source_rows)
{
    return index < rows.listed ? type_live_rows[index] : source_rows + (index - rows.listed);
}
#endif
