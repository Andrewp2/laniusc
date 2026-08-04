/// Dense canonical HIR identity and source span.
public struct HirCore
{
    public uint kind;
    public uint parent;
    public uint token_start;
    public uint token_end;
}

/// Dense canonical HIR navigation and source-file identity.
public struct HirLinks
{
    public uint first_child;
    public uint next_sibling;
    public uint subtree_end;
    public uint file_id;
}

/// Kind-dependent canonical HIR payload.
public struct HirPayload
{
    public uint a;
    public uint b;
    public uint c;
    public uint d;
}

public struct HirRange
{
    public uint start;
    public uint count;
}

public struct HirCallArg
{
    public uint call;
    public uint value;
    public uint ordinal;
    public uint file_id;
}

public struct HirParam
{
    public uint owner;
    public uint name_token;
    public uint type_node;
    public uint ordinal;
}

public struct HirTypeArg
{
    public uint owner;
    public uint value;
    public uint ordinal;
    public uint file_id;
}

public struct HirGenericParam
{
    public uint owner;
    public uint name_token;
    public uint kind;
    public uint file_id;
}

public struct HirPath
{
    public uint owner;
    public uint segment_start;
    public uint segment_count;
    public uint kind;
}

public struct HirPathSegment
{
    public uint path;
    public uint name_token;
    public uint ordinal;
    public uint file_id;
}

public struct HirField
{
    public uint owner;
    public uint name_token;
    public uint value;
    public uint ordinal;
}

public struct HirVariant
{
    public uint owner;
    public uint name_token;
    public uint ordinal;
    public uint file_id;
}

public struct HirVariantPayload
{
    public uint variant;
    public uint type_node;
    public uint ordinal;
    public uint file_id;
}

public struct HirMatchArm
{
    public uint owner;
    public uint pattern;
    public uint result;
    public uint ordinal;
}

public struct HirMatchPayload
{
    public uint arm;
    public uint pattern;
    public uint ordinal;
    public uint file_id;
}

public struct HirArrayElement
{
    public uint array;
    public uint value;
    public uint ordinal;
    public uint file_id;
}

public struct HirString
{
    public uint node;
    public uint data_offset;
    public uint decoded_len;
    public uint file_id;
}

public struct HirMethodCore
{
    public uint node;
    public uint owner;
    public uint impl_node;
    public uint name_token;
}

public struct HirMethodSignature
{
    public uint first_param_token;
    public uint impl_receiver_type;
    public uint receiver_mode;
    public uint metadata;
}

public struct HirPredicate
{
    public uint owner;
    public uint subject;
    public uint bound;
    public uint metadata;
}

/// Dense facts recovered from temporary predicate grammar productions.
///
/// The canonical HIR keeps only semantic nodes.  These fields preserve the
/// relationships that predicate collection needs without retaining the raw
/// parser tree: the owning predicate, its subject, and the compact side-table
/// references for paths and arguments.
public struct HirPredicateFacts
{
    public uint production;
    public uint token_start;
    public uint type_path_leaf;
    public uint type_arg_start;
    public uint type_arg_count;
    public uint type_arg_next;
    public uint method_impl_receiver_type;
    public uint expr_result_root;
    public uint struct_lit_head;
    public uint bound_path_owner;
    public uint predicate_owner;
    public uint predicate_subject;
}
