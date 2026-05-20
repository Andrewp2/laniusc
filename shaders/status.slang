import atomics;

public static const uint STATUS_OK_SLOT = 0u;
public static const uint STATUS_TOKEN_SLOT = 1u;
public static const uint STATUS_CODE_SLOT = 2u;
public static const uint STATUS_DETAIL_SLOT = 3u;

public struct StageStatus4
{
    public uint ok;
    public uint error;
    public uint detail;
    public uint count;
}

public StageStatus4 make_stage_status4(uint ok, uint error, uint detail, uint count)
{
    StageStatus4 status;
    status.ok = ok;
    status.error = error;
    status.detail = detail;
    status.count = count;
    return status;
}

public StageStatus4 read_stage_status4(StructuredBuffer<uint> input)
{
    return make_stage_status4(input[0u], input[1u], input[2u], input[3u]);
}

public StageStatus4 read_stage_status4_at(StructuredBuffer<uint> input, uint base)
{
    return make_stage_status4(
        input[base + 0u],
        input[base + 1u],
        input[base + 2u],
        input[base + 3u]);
}

public bool stage_status4_ok(StructuredBuffer<uint> status, uint ok_code)
{
    return status[0u] == ok_code && status[1u] == 0u;
}

public uint stage_status4_error_or(StructuredBuffer<uint> status, uint fallback_error)
{
    return status[1u] == 0u ? fallback_error : status[1u];
}

public uint stage_status4_detail_or(StructuredBuffer<uint> status, uint fallback_detail)
{
    return status[1u] == 0u ? fallback_detail : status[2u];
}

public void write_stage_status4(RWStructuredBuffer<uint> output, StageStatus4 status)
{
    output[0u] = status.ok;
    output[1u] = status.error;
    output[2u] = status.detail;
    output[3u] = status.count;
}

public void write_stage_status4_at(
    RWStructuredBuffer<uint> output,
    uint base,
    StageStatus4 status)
{
    output[base + 0u] = status.ok;
    output[base + 1u] = status.error;
    output[base + 2u] = status.detail;
    output[base + 3u] = status.count;
}

public uint increment_stage_count4_at(
    RWStructuredBuffer<uint> output,
    uint base,
    uint amount)
{
    return atomic_u32_add(output, base + 3u, amount);
}

public uint increment_stage_count4(
    RWStructuredBuffer<uint> output,
    uint amount)
{
    return increment_stage_count4_at(output, 0u, amount);
}

public void publish_stage_error_min_detail4_at(
    RWStructuredBuffer<uint> output,
    uint base,
    uint error,
    uint detail)
{
    output[base + 0u] = 0u;
    atomic_u32_compare_exchange(output, base + 1u, 0u, error);
    atomic_u32_min(output, base + 2u, detail);
}

public void publish_stage_error_min_detail4(
    RWStructuredBuffer<uint> output,
    uint error,
    uint detail)
{
    publish_stage_error_min_detail4_at(output, 0u, error, detail);
}

public void publish_stage_error_min_detail_extra4_at(
    RWStructuredBuffer<uint> output,
    uint base,
    uint error,
    uint detail,
    uint extra)
{
    output[base + 0u] = 0u;
    atomic_u32_compare_exchange(output, base + 1u, 0u, error);
    uint old_detail = atomic_u32_min(output, base + 2u, detail);
    if (detail <= old_detail)
        output[base + 3u] = extra;
}

public void publish_stage_error_min_detail_extra4(
    RWStructuredBuffer<uint> output,
    uint error,
    uint detail,
    uint extra)
{
    publish_stage_error_min_detail_extra4_at(output, 0u, error, detail, extra);
}

public bool publish_stage_error_first4_at(
    RWStructuredBuffer<uint> output,
    uint base,
    uint error,
    uint detail,
    uint extra)
{
    output[base + 0u] = 0u;
    uint old_error = atomic_u32_compare_exchange(output, base + 1u, 0u, error);
    if (old_error == 0u)
    {
        output[base + 2u] = detail;
        output[base + 3u] = extra;
        return true;
    }
    return false;
}

public bool publish_stage_error_first4(
    RWStructuredBuffer<uint> output,
    uint error,
    uint detail,
    uint extra)
{
    return publish_stage_error_first4_at(output, 0u, error, detail, extra);
}

public StageStatus4 make_stage_status4_from_result(
    bool ok,
    uint ok_code,
    uint success_detail,
    uint fallback_error,
    uint error,
    uint fallback_detail,
    uint detail,
    uint success_count)
{
    return make_stage_status4(
        ok ? ok_code : 0u,
        ok ? 0u : (error == 0u ? fallback_error : error),
        ok ? success_detail : (error == 0u ? fallback_detail : detail),
        ok ? success_count : 0u);
}

public void write_stage_status4_from_result(
    RWStructuredBuffer<uint> output,
    bool ok,
    uint ok_code,
    uint success_detail,
    uint fallback_error,
    uint error,
    uint fallback_detail,
    uint detail,
    uint success_count)
{
    write_stage_status4(
        output,
        make_stage_status4_from_result(
            ok,
            ok_code,
            success_detail,
            fallback_error,
            error,
            fallback_detail,
            detail,
            success_count));
}

public StageStatus4 make_stage_status4_from_upstream1(
    bool ok,
    uint ok_code,
    uint success_detail,
    uint success_count,
    StageStatus4 upstream_status,
    uint fallback_error,
    uint fallback_detail)
{
    if (ok)
        return make_stage_status4(ok_code, 0u, success_detail, success_count);

    uint error = upstream_status.error == 0u ? fallback_error : upstream_status.error;
    uint detail = upstream_status.error == 0u ? fallback_detail : upstream_status.detail;
    return make_stage_status4(0u, error, detail, 0u);
}

public void write_stage_status4_from_upstream1(
    RWStructuredBuffer<uint> output,
    bool ok,
    uint ok_code,
    uint success_detail,
    uint success_count,
    StructuredBuffer<uint> upstream_status,
    uint fallback_error,
    uint fallback_detail)
{
    write_stage_status4(
        output,
        make_stage_status4_from_upstream1(
            ok,
            ok_code,
            success_detail,
            success_count,
            read_stage_status4(upstream_status),
            fallback_error,
            fallback_detail));
}

public StageStatus4 make_stage_status4_from_upstream2(
    bool ok,
    uint ok_code,
    uint success_detail,
    uint success_count,
    bool first_ok,
    StageStatus4 first_status,
    StageStatus4 second_status,
    uint fallback_error,
    uint fallback_detail)
{
    if (ok)
        return make_stage_status4(ok_code, 0u, success_detail, success_count);

    uint selected_error = first_ok ? second_status.error : first_status.error;
    uint selected_detail = first_ok ? second_status.detail : first_status.detail;
    uint error = selected_error == 0u ? fallback_error : selected_error;
    uint detail = selected_error == 0u ? fallback_detail : selected_detail;
    return make_stage_status4(0u, error, detail, 0u);
}

public void write_stage_status4_from_upstream2(
    RWStructuredBuffer<uint> output,
    bool ok,
    uint ok_code,
    uint success_detail,
    uint success_count,
    bool first_ok,
    StructuredBuffer<uint> first_status,
    StructuredBuffer<uint> second_status,
    uint fallback_error,
    uint fallback_detail)
{
    write_stage_status4(
        output,
        make_stage_status4_from_upstream2(
            ok,
            ok_code,
            success_detail,
            success_count,
            first_ok,
            read_stage_status4(first_status),
            read_stage_status4(second_status),
            fallback_error,
            fallback_detail));
}

public void record_min_token_error(
    RWStructuredBuffer<uint> status,
    uint token_i,
    uint code,
    uint detail)
{
    uint old = atomic_u32_min(status, STATUS_TOKEN_SLOT, token_i);
    if (token_i <= old)
    {
        status[STATUS_OK_SLOT] = 0u;
        status[STATUS_CODE_SLOT] = code;
        status[STATUS_DETAIL_SLOT] = detail;
    }
}

public void record_min_detail_error(
    RWStructuredBuffer<uint> status,
    uint code,
    uint detail)
{
    uint old = atomic_u32_min(status, STATUS_DETAIL_SLOT, detail);
    if (detail <= old)
    {
        status[STATUS_OK_SLOT] = 0u;
        status[STATUS_CODE_SLOT] = code;
    }
}
