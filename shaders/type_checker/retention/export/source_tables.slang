// The lexer tables a body's source provenance is copied from: the job's
// token records (kind, byte start in the job's concatenated source, byte
// length), the source bytes and each source file's first byte. Bound by
// the export host from the lexer buffers of the job being exported.
import type_checker.retention.retention_store;

public struct RtJobToken
{
    public uint kind;
    public uint start;
    public uint len;
}

public StructuredBuffer<RtJobToken> rt_job_tokens;
public StructuredBuffer<uint> rt_job_source;
public StructuredBuffer<uint> rt_job_file_start;

public uint job_token_rows()
{
    uint count; uint stride;
    rt_job_tokens.GetDimensions(count, stride);
    return count;
}

public RtJobToken job_token(uint token)
{
    RtJobToken t;
    t.kind = 0u; t.start = 0u; t.len = 0u;
    if (token < job_token_rows()) t = rt_job_tokens[token];
    return t;
}

public uint job_source_byte(uint offset)
{
    uint words; uint stride;
    rt_job_source.GetDimensions(words, stride);
    uint word = offset >> 2u;
    return word < words ? (rt_job_source[word] >> ((offset & 3u) * 8u)) & 0xffu : 0u;
}

public uint job_file_start(uint file)
{
    uint count; uint stride;
    rt_job_file_start.GetDimensions(count, stride);
    return file < count ? rt_job_file_start[file] : 0u;
}

// A body's text: bytes [start, end) of the job source, from its first
// token's start to its last token's end.
public uint2 body_text_range(uint first_token, uint token_count)
{
    if (token_count == 0u) return uint2(0u, 0u);
    RtJobToken first = job_token(first_token);
    RtJobToken last = job_token(first_token + token_count - 1u);
    uint end = max(last.start + last.len, first.start);
    return uint2(first.start, end);
}
