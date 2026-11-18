import atomics;

public static const uint STATUS_OK_SLOT = 0u;
public static const uint STATUS_TOKEN_SLOT = 1u;
public static const uint STATUS_CODE_SLOT = 2u;
public static const uint STATUS_DETAIL_SLOT = 3u;

// Whether `prior`, a copy of the status words made before this pass, holds
// a language error at a token in [first, end). A follow-on check skips its
// own error when the construct it checks already contains one: that error
// comes first and explains it. A compiler-boundary report (code 6 tagged
// 0x474e) explains nothing: it is often itself the follow-on of a language
// error a later check reports, so that check still records. The copy is made
// between dispatches, so the answer does not depend on what other lanes of
// this pass record.
public bool language_error_recorded_within(StructuredBuffer<uint> prior, uint first, uint end)
{
    uint token = prior[STATUS_TOKEN_SLOT];
    bool boundary = prior[STATUS_CODE_SLOT] == 6u && (prior[STATUS_DETAIL_SLOT] & 0xffff0000u) == 0x474e0000u;
    return prior[STATUS_OK_SLOT] == 0u && !boundary && token >= first && token < end;
}

public void record_min_token_error(
    RWStructuredBuffer<uint> status,
    uint token_i,
    uint code,
    uint detail)
{
    uint old = atomic_u32_min(status, STATUS_TOKEN_SLOT, token_i);
    if (token_i <= old && status[STATUS_TOKEN_SLOT] == token_i)
    {
        status[STATUS_OK_SLOT] = 0u;
        status[STATUS_CODE_SLOT] = code;
        status[STATUS_DETAIL_SLOT] = detail;
    }
}

// Record a compiler-boundary report (code 6 tagged 0x474e) unless a language
// error is already recorded at `token_i`. The boundary is then a follow-on of
// that error, and a later report at the same token would replace it.
public void record_boundary_error(
    RWStructuredBuffer<uint> status,
    uint token_i,
    uint detail)
{
    bool boundary = status[STATUS_CODE_SLOT] == 6u && (status[STATUS_DETAIL_SLOT] & 0xffff0000u) == 0x474e0000u;
    if (status[STATUS_OK_SLOT] == 0u && status[STATUS_TOKEN_SLOT] == token_i && !boundary)
        return;
    record_min_token_error(status, token_i, 6u, 0x474e0000u | detail);
}
