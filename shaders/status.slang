import atomics;

public static const uint STATUS_OK_SLOT = 0u;
public static const uint STATUS_TOKEN_SLOT = 1u;
public static const uint STATUS_CODE_SLOT = 2u;
public static const uint STATUS_DETAIL_SLOT = 3u;

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
