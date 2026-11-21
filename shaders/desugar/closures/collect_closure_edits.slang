// Each group owns a closure. Its leader reads the body once and the lanes
// find captures in parallel, in order of first use. The body holds the
// temporary capture list because valid closure bodies are disjoint.
import shared.buffers.gpu_index;
import shared.collectives.prefix_scan;
import desugar.tokens.desugaring_layout;
import shared.syntax.generated_token_ids;
import closure_layout;
import shared.buffers.byte_packing;
import shared.search.blocked_search_tree;
import shared.search.segment_tree;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

struct RoleParams
{
    uint leaf_base;
};

StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint4> depth_scan;
ByteAddressBuffer in_bytes;
StructuredBuffer<int> depth_local_min;
StructuredBuffer<int> depth_min_tree;
ConstantBuffer<RoleParams> gRoles;
RWStructuredBuffer<uint> records;
RWStructuredBuffer<uint4> captures;
RWStructuredBuffer<uint4> counts;
RWStructuredBuffer<uint> drop;
RWStructuredBuffer<uint> status;

static const uint CLOSURE_LANES = 256u;

struct ClosureBody
{
    uint start;
    uint param;
    uint first;
    uint last;
};

groupshared ClosureBody closure_body;
groupshared uint capture_prefix[CLOSURE_LANES];

uint kind_in_file(uint i, uint count, uint file)
{
    if (i >= count || token_file_id[i] != file)
        return 0u;
    return tokens_out[i].kind;
}

int depth_after(uint i)
{
    return int(depth_scan[i].x);
}

int depth_before(uint i)
{
    return int(depth_scan[i].x - tk_depth_delta(tokens_out[i].kind));
}

public struct DepthTree : IBlockedSearchTree<int>
{
    public static uint row_count() { return token_count[0]; }
    public static int row_value(uint row) { return row == 0u ? 0 : int(depth_scan[row - 1u].x); }
    public static int local_node(uint block, uint node) { return depth_local_min[block * 256u + node]; }
    public static uint block_leaf_base() { return gRoles.leaf_base; }
    public static int block_node(uint node) { return depth_min_tree[node]; }
}

public struct DepthAtMost : IRangeSearchPredicate<int, int>
{
    public static bool aggregate_may_match(int aggregate, int query) { return aggregate <= query; }
    public static bool leaf_matches(int leaf, int query) { return leaf <= query; }
}

bool inside_parentheses(uint i, uint file)
{
    // An identifier leaves the depth unchanged. The last earlier row at
    // smaller depth is precisely its nearest unmatched opener. This holds
    // even for malformed nesting, which the frontend diagnoses later.
    uint open = blocked_search_last_before<int, int, DepthTree, DepthAtMost>(i, int(depth_scan[i].x) - 1);
    return open != CL_INVALID && token_file_id[open] == file && tk_paren_open(tokens_out[open].kind);
}

bool same_text(uint a, uint b)
{
    uint len = tokens_out[a].len;
    if (len != tokens_out[b].len)
        return false;
    uint a_start = tokens_out[a].start;
    uint b_start = tokens_out[b].start;
    for (uint at = 0u; at < len; at += 1u)
    {
        if (byte_address_load_u8(in_bytes, a_start + at) != byte_address_load_u8(in_bytes, b_start + at))
            return false;
    }
    return true;
}

// A bare name used as a value: no member, path segment, call, field name or
// binder.
bool value_use(uint i, uint count, uint file)
{
    if (tokens_out[i].kind != TK_IDENT)
        return false;
    uint previous = i > 0u ? kind_in_file(i - 1u, count, file) : 0u;
    uint before_previous = i > 1u ? kind_in_file(i - 2u, count, file) : 0u;
    uint next = kind_in_file(i + 1u, count, file);
    if (previous == TK_DOT || previous == TK_LET || previous == TK_FOR)
        return false;
    if (previous == TK_COLON && before_previous == TK_COLON)
        return false;
    if (next == TK_COLON || tk_paren_open(next))
        return false;
    return true;
}

uint binder_role(uint i, uint count, uint file)
{
    uint previous = i > 0u ? kind_in_file(i - 1u, count, file) : 0u;
    uint next = kind_in_file(i + 1u, count, file);
    uint after_next = kind_in_file(i + 2u, count, file);
    bool typed = next == TK_COLON && after_next != TK_COLON;
    if (previous == TK_LET)
        return ROLE_LET | (typed ? ROLE_TYPED : 0u);
    if (previous == TK_FOR)
        return ROLE_FOR;
    if (typed && (tk_paren_open(previous) || tk_comma(previous)) && inside_parentheses(i, file))
        return ROLE_PARAM | ROLE_TYPED;
    return 0u;
}

bool find_capture(uint u, uint start, uint count, uint file, out uint4 capture)
{
    capture = uint4(0u);
    // Walk back from the closure to the `fn` keyword. A `let` is in scope
    // when no token between it and the closure is shallower than it.
    int depth = depth_before(start);
    int shallowest = depth;
    uint binder = CL_INVALID;
    uint j = start;
    while (j > 0u)
    {
        j -= 1u;
        if (token_file_id[j] != file)
            break;
        uint kj = tokens_out[j].kind;
        if (kj == TK_FN)
            break;
        depth -= int(tk_depth_delta(kj));
        if (kj == TK_IDENT && same_text(j, u))
        {
            uint role = binder_role(j, count, file);
            bool in_scope = (role & ROLE_PARAM) != 0u || depth <= shallowest;
            if (role != 0u && in_scope)
            {
                if ((role & ROLE_TYPED) == 0u)
                {
                    closure_error(status, u, ERR_CAPTURE_TYPE);
                    return false;
                }
                binder = j;
                break;
            }
        }
        shallowest = min(shallowest, depth);
    }
    if (binder == CL_INVALID)
        return false;

    // The type runs from after the `:` to the `=` or `;` of a let, or to
    // the `,` or `)` that ends a parameter.
    uint type_first = binder + 2u;
    int binder_depth = depth_before(binder);
    int angle = 0;
    uint q = type_first;
    while (true)
    {
        uint kq = kind_in_file(q, count, file);
        if (kq == 0u || depth_after(q) < binder_depth)
            break;
        bool own_depth = depth_before(q) == binder_depth;
        if (own_depth && (tk_assign(kq) || tk_semicolon(kq) || (tk_comma(kq) && angle <= 0)))
            break;
        if (kq == TK_LT || kq == TK_ANGLE_GENERIC)
            angle += 1;
        else if (kq == TK_GT)
            angle -= 1;
        else if (kq == TK_SHR)
            angle -= 2;
        q += 1u;
    }
    if (q == type_first)
    {
        closure_error(status, u, ERR_CAPTURE_TYPE);
        return false;
    }
    capture = uint4(0u, u, type_first, q - 1u);
    return true;
}

void read_closure(uint i, uint count, uint k)
{
    uint file = token_file_id[i];
    uint param = CL_INVALID;
    uint ptype_first = CL_INVALID;
    uint ptype_last = CL_INVALID;
    uint rtype_first = CL_INVALID;
    uint rtype_last = CL_INVALID;
    uint flags = 0u;
    uint at = i + 1u;
    uint error = 0u;

    if (tokens_out[i].kind == TK_OROR)
    {
        flags |= FLAG_NO_PARAM;
    }
    else
    {
        uint name = i + 1u;
        uint after_name = kind_in_file(name + 1u, count, file);
        if (kind_in_file(name, count, file) != TK_IDENT)
        {
            error = ERR_HEADER;
        }
        else if (after_name != TK_COLON)
        {
            error = after_name == TK_PIPE ? ERR_PARAM_TYPE : ERR_HEADER;
        }
        else
        {
            // The type runs to the closing `|`. A single `:` inside it
            // belongs to a second parameter.
            uint q = name + 2u;
            bool second = false;
            int header_depth = depth_before(name);
            while (true)
            {
                uint kq = kind_in_file(q, count, file);
                if (kq == 0u || kq == TK_PIPE || kq == TK_OROR || tk_brace_open(kq) || depth_after(q) < header_depth)
                    break;
                if (tk_semicolon(kq) && depth_before(q) == header_depth)
                    break;
                if (kq == TK_COLON && kind_in_file(q - 1u, count, file) != TK_COLON &&
                    kind_in_file(q + 1u, count, file) != TK_COLON)
                    second = true;
                q += 1u;
            }
            if (kind_in_file(q, count, file) != TK_PIPE || q == name + 2u || second)
            {
                error = ERR_HEADER;
            }
            else
            {
                param = name;
                ptype_first = name + 2u;
                ptype_last = q - 1u;
                at = q + 1u;
            }
        }
    }

    if (error == 0u && kind_in_file(at, count, file) == TK_ARROW)
    {
        // `-> Type` needs a braced body: the type runs to its `{`.
        uint q = at + 1u;
        int arrow_depth = depth_before(at);
        while (true)
        {
            uint kq = kind_in_file(q, count, file);
            if (kq == 0u || tk_brace_open(kq) || depth_after(q) < arrow_depth)
                break;
            if (tk_semicolon(kq) && depth_before(q) == arrow_depth)
                break;
            q += 1u;
        }
        if (!tk_brace_open(kind_in_file(q, count, file)) || q == at + 1u)
        {
            error = ERR_RTYPE_BODY;
        }
        else
        {
            rtype_first = at + 1u;
            rtype_last = q - 1u;
            flags |= FLAG_RTYPE;
            at = q;
        }
    }

    uint body_first = 1u;
    uint body_last = 0u;
    if (error == 0u)
    {
        uint first_kind = kind_in_file(at, count, file);
        if (first_kind == 0u)
        {
            error = ERR_BODY;
        }
        else if (tk_brace_open(first_kind))
        {
            int outer = depth_before(at);
            uint q = at + 1u;
            while (kind_in_file(q, count, file) != 0u && depth_after(q) != outer)
                q += 1u;
            if (kind_in_file(q, count, file) == 0u)
            {
                error = ERR_BODY;
            }
            else
            {
                flags |= FLAG_BRACED;
                body_first = at;
                body_last = q;
            }
        }
        else
        {
            // An expression ends at a `,` or `;` of its own depth, or at
            // the bracket that closes around it.
            int outer = depth_before(at);
            uint q = at;
            while (true)
            {
                uint kq = kind_in_file(q, count, file);
                if (kq == 0u || depth_after(q) < outer)
                    break;
                if ((tk_comma(kq) || tk_semicolon(kq)) && depth_before(q) == outer)
                    break;
                q += 1u;
            }
            if (q == at)
            {
                error = ERR_BODY;
            }
            else
            {
                body_first = at;
                body_last = q - 1u;
            }
        }
    }

    if (error == 0u && depth_scan[body_last].y != k + 1u)
        error = ERR_NESTED;
    if (error != 0u)
    {
        closure_error(status, i, error);
        param = CL_INVALID;
        body_first = 1u;
        body_last = 0u;
    }

    // A start after an identifier is a `move` closure: `mark` admits no
    // other identifier there. The site then begins at the word.
    bool moved = i > 0u && kind_in_file(i - 1u, count, file) == TK_IDENT;
    if (moved)
        flags |= FLAG_MOVE;

    uint row = k * REC_WORDS;
    uint start = moved ? i - 1u : i;
    records[row + REC_START] = start;
    records[row + REC_PARAM] = param;
    records[row + REC_PTYPE_FIRST] = ptype_first;
    records[row + REC_PTYPE_LAST] = ptype_last;
    records[row + REC_RTYPE_FIRST] = rtype_first;
    records[row + REC_RTYPE_LAST] = rtype_last;
    records[row + REC_BODY_FIRST] = body_first;
    records[row + REC_BODY_LAST] = body_last;
    records[row + REC_FLAGS] = flags;
    records[row + REC_FILE] = file;
    closure_body = { start, param, body_first, body_last };
}

bool capture_use(uint u, ClosureBody body, uint count, uint file, out uint4 capture)
{
    capture = uint4(0u);
    if (u > body.last)
        return false;
    if (tokens_out[u].kind == TK_SELF_VALUE)
    {
        closure_error(status, u, ERR_SELF);
        return false;
    }
    if (!value_use(u, count, file) || (body.param != CL_INVALID && same_text(u, body.param)))
        return false;
    for (uint earlier = body.first; earlier < u; earlier += 1u)
    {
        if (value_use(earlier, count, file) && same_text(earlier, u))
            return false;
    }
    return find_capture(u, body.start, count, file, capture);
}

[shader("compute")]
[numthreads(CLOSURE_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint lane : SV_GroupIndex)
{
    uint k = linear_group_id_2d(group, DESUGAR_MAX_GROUPS_X);
    if (k >= token_count[S_F0])
        return;
    uint count = token_count[S_TOKENS];
    if (lane == 0u)
    {
        uint lo = 0u;
        uint hi = count;
        while (lo < hi)
        {
            uint mid = lo + ((hi - lo) >> 1u);
            if (depth_scan[mid].y <= k)
                lo = mid + 1u;
            else
                hi = mid;
        }
        read_closure(lo, count, k);
    }
    GroupMemoryBarrierWithGroupSync();
    ClosureBody body = closure_body;
    if (body.last < body.first)
        return;

    uint file = token_file_id[body.start];
    uint captures_found = 0u;
    for (uint first = body.first; first <= body.last; first += CLOSURE_LANES)
    {
        uint4 capture;
        bool found = capture_use(first + lane, body, count, file, capture);
        uint pos = prefix_scan_inclusive<uint, PrefixScanU32Add, CLOSURE_LANES>(
            lane, found ? 1u : 0u, capture_prefix);
        uint width = capture_prefix[CLOSURE_LANES - 1u];
        GroupMemoryBarrierWithGroupSync();
        if (found)
            captures[body.first + captures_found + pos - 1u] = capture;
        captures_found += width;
    }
    if (lane == 0u)
    {
        uint row = k * REC_WORDS;
        records[row + REC_CAP_FIRST] = body.first;
        records[row + REC_CAP_COUNT] = captures_found;
        counts[k] = uint4(SITE_FIXED + SITE_PER_CAPTURE * captures_found,
                          APPENDIX_FIXED + APPENDIX_PER_CAPTURE * captures_found, 0u, 0u);
    }
    for (uint t = body.start + lane; t <= body.last; t += CLOSURE_LANES)
        InterlockedOr(drop[t], 1u);
}
