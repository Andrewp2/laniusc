// The lowering's type-instance tables, indexed by TermId (03_layout).
__exported import type_checker.retention.projection.pj_common;

public RWStructuredBuffer<uint> ob_ti_kind;
public RWStructuredBuffer<uint> ob_ti_native_words;
public RWStructuredBuffer<uint> ob_ti_decl_token;
public RWStructuredBuffer<uint> ob_ti_elem_ref_tag;
public RWStructuredBuffer<uint> ob_ti_elem_ref_payload;
public RWStructuredBuffer<uint> ob_ti_len_kind;
public RWStructuredBuffer<uint> ob_ti_len_payload;
public RWStructuredBuffer<uint> ob_ti_arg_count;
public RWStructuredBuffer<uint> ob_ti_arg_start;
public RWStructuredBuffer<uint> ob_ext_library;
public RWStructuredBuffer<uint> ob_ext_unit;
public RWStructuredBuffer<uint> ob_ext_local;
public RWStructuredBuffer<uint> ob_imported_layout_kind;
public RWStructuredBuffer<uint4> ob_constant_atoms;


public uint pj_type_rows()
{
    uint a; uint b; uint s;
    pj_layout.GetDimensions(a, s);
    ob_ti_kind.GetDimensions(b, s);
    return min(a, b);
}

