// Per identifier in a closure body: whether it captures a local of the
// enclosing function, and where that local's declared type is.
//
// A capture is the first use, in the body, of a name that a typed `let` or a
// parameter of the enclosing function declares before the closure. The body
// is copied unchanged into the generated method behind one `let` per
// capture, so the names the body declares itself still shadow them there.
// The site evaluates each captured name where the closure stands, so a type
// taken from the wrong declaration is a type error and never a wrong value.
import gpu_index;
import byte_packing;
import generated_token_ids;
import closure_common;

struct TokenOut
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> token_file_id;
ByteAddressBuffer in_bytes;
StructuredBuffer<uint> roles;
StructuredBuffer<uint4> depth_scan;
StructuredBuffer<uint> records;
StructuredBuffer<uint> summary;
RWStructuredBuffer<uint4> capture_marks;
RWStructuredBuffer<uint> status;

static const uint DISPATCH_X_STRIDE = 16776960u;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint u = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    uint count = token_count[0];
    uint closure_count = summary[1];
    if (u >= count || closure_count == 0u)
        return;
    uint kind = tokens_out[u].kind;
    if (kind != TK_IDENT && kind != TK_SELF_VALUE)
        return;

    // The last closure that starts at or before this token.
    uint lo = 0u;
    uint hi = closure_count;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (records[mid * REC_WORDS + REC_START] <= u)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo == 0u)
        return;
    uint row = (lo - 1u) * REC_WORDS;
    uint body_first = records[row + REC_BODY_FIRST];
    uint body_last = records[row + REC_BODY_LAST];
    if (u < body_first || u > body_last)
        return;
    if (kind == TK_SELF_VALUE)
    {
        closure_error(status, u, ERR_SELF);
        return;
    }

    uint file = token_file_id[u];
    if (!value_use(u, count, file))
        return;
    uint param = records[row + REC_PARAM];
    if (param != CL_INVALID && same_text(u, param))
        return;
    for (uint earlier = body_first; earlier < u; earlier += 1u)
    {
        if (value_use(earlier, count, file) && same_text(earlier, u))
            return;
    }

    // Walk back from the closure to the `fn` keyword. A `let` is in scope
    // when no token between it and the closure is shallower than it.
    uint start = records[row + REC_START];
    int shallowest = depth_before(start);
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
        int dj = depth_before(j);
        if (kj == TK_IDENT)
        {
            uint role = roles[j];
            bool in_scope = (role & ROLE_PARAM) != 0u || dj <= shallowest;
            if (role != 0u && in_scope && same_text(j, u))
            {
                if ((role & ROLE_TYPED) == 0u)
                {
                    closure_error(status, u, ERR_CAPTURE_TYPE);
                    return;
                }
                binder = j;
                break;
            }
        }
        shallowest = min(shallowest, dj);
    }
    if (binder == CL_INVALID)
        return;

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
        return;
    }
    capture_marks[u] = uint4(1u, type_first, q - 1u, lo - 1u);
}
