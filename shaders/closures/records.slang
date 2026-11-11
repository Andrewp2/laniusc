// Per closure start: the parameter, its type, the optional result type and
// the body, as token indices. `depth_scan` holds, per token, the depth after
// it (x) and the count of closure starts through it (y).
import gpu_index;
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
StructuredBuffer<uint4> depth_scan;
RWStructuredBuffer<uint> records;
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    uint count = token_count[0];
    if (i >= count)
        return;
    uint through = depth_scan[i].y;
    uint before = i > 0u ? depth_scan[i - 1u].y : 0u;
    if (through == before)
        return;

    uint k = through - 1u;
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

    if (error == 0u && depth_scan[body_last].y != through)
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
    records[row + REC_START] = moved ? i - 1u : i;
    records[row + REC_PARAM] = param;
    records[row + REC_PTYPE_FIRST] = ptype_first;
    records[row + REC_PTYPE_LAST] = ptype_last;
    records[row + REC_RTYPE_FIRST] = rtype_first;
    records[row + REC_RTYPE_LAST] = rtype_last;
    records[row + REC_BODY_FIRST] = body_first;
    records[row + REC_BODY_LAST] = body_last;
    records[row + REC_FLAGS] = flags;
    records[row + REC_FILE] = file;
    records[row + REC_CAP_FIRST] = 0u;
    records[row + REC_CAP_COUNT] = 0u;
}
