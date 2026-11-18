// Shared by the body steps (11, 12): the body a row belongs to, as a
// segment context, and the relative encodings of row, token and side-table
// references inside it.
import hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export_rows.retained_body_side_tables;

public struct SegmentContext
{
    public BodySpan span;
    public uint segment;   // segment index, RT_INVALID when not staged
    public uint decl;      // the function's DeclId
    public uint parent;    // its container's DeclId or 0
    public uint row_base;  // first segment row of the body
}

public SegmentContext segment_context(uint function)
{
    SegmentContext c;
    c.span.function = function;
    c.span.count = compact_hir_links[function].subtree_end - function;
    c.span.token = compact_hir_core[function].token_start;
    c.span.token_end = max(max(rt_x_span[function], compact_hir_core[function].token_end), c.span.token);
    uint4 info = rt_x_row[function];
    c.decl = info.x;
    c.segment = info.z;
    c.parent = info.y != RT_INVALID ? rt_dir[info.y * RT_DIR_WORDS].z : 0u;
    c.row_base = c.segment != RT_INVALID ? rt_segments[c.segment * RT_SEG_WORDS].y : RT_INVALID;
    return c;
}

// Index `index` of side table k relative to the body's block of that table.
public uint rel_side(SegmentContext c, uint k, uint index, inout uint foreign)
{
    if (index == 0xffffffffu) return index;
    uint first = side_lower_bound(k, c.span.function);
    uint end = side_lower_bound(k, c.span.function + c.span.count);
    if (index >= first && index <= end) return index - first;
    foreign++;
    return RT_REL_FOREIGN;
}

// Statement/expression context word: STMT bit + row id, or the "none" id.
public uint rel_context(SegmentContext c, uint encoded, inout uint foreign)
{
    uint id = encoded & 0x7fffffffu;
    if (id == 0x7fffffffu) return encoded;
    return (encoded & 0x80000000u) | (rel_row(c.span, id, foreign) & 0x7fffffffu);
}

// A term reference stored in a body; ownership is checked against the
// function's binder chain.
public uint body_term(SegmentContext c, uint tag, uint payload, inout uint untranslated, inout uint unowned)
{
    uint term = translate_checked(tag, payload);
    if (term == RT_UNKNOWN || term == RT_FIT_FAILED) untranslated++;
    else if (!owned_by(term, c.decl, c.parent)) unowned++;
    return term;
}
