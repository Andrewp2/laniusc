// Fixed native runtime block for target-independent host services.
//
// Call sites always emit the same `call rel32` shape. Service-specific bytes
// live once in this block, so adding calls does not multiply byte fragments.

import codegen.lowering_ir;

static const uint X86_RUNTIME_INVALID = 0xffffffffu;
static const uint X86_RUNTIME_PRINT_I32_OFFSET = 78u;
static const uint X86_RUNTIME_LENGTH = 162u;

uint x86_runtime_service_offset(uint service)
{
    if (service == HOST_SERVICE_ARGC) return 0u;
    if (service == HOST_SERVICE_EXIT) return 4u;
    if (service == HOST_SERVICE_CLOSE_FILE || service == HOST_SERVICE_CLOSE) return 12u;
    if (service == HOST_SERVICE_READ) return 20u;
    if (service == HOST_SERVICE_WRITE || service == HOST_SERVICE_WRITE_TEXT) return 25u;
    if (service == HOST_SERVICE_WRITE_STDOUT) return 33u;
    if (service == HOST_SERVICE_WRITE_STDERR) return 50u;
    if (service == HOST_SERVICE_READ_STDIN) return 67u;
    return X86_RUNTIME_INVALID;
}

bool x86_runtime_service_supported(uint service)
{
    return x86_runtime_service_offset(service) != X86_RUNTIME_INVALID;
}

bool x86_runtime_service_has_result(uint service)
{
    return service != HOST_SERVICE_EXIT;
}

uint x86_runtime_byte(uint pos)
{
    // argc: the entry wrapper retains the original process stack in r15.
    static const uint argc_bytes[4] = {0x41u, 0x8bu, 0x07u, 0xc3u};
    if (pos < 4u) return argc_bytes[pos];

    static const uint exit_bytes[8] =
        {0xb8u, 60u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u};
    if (pos < 12u) return exit_bytes[pos - 4u];

    static const uint close_bytes[8] =
        {0xb8u, 3u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u};
    if (pos < 20u) return close_bytes[pos - 12u];

    static const uint read_bytes[5] = {0x31u, 0xc0u, 0x0fu, 0x05u, 0xc3u};
    if (pos < 25u) return read_bytes[pos - 20u];

    static const uint write_bytes[8] =
        {0xb8u, 1u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u};
    if (pos < 33u) return write_bytes[pos - 25u];

    static const uint stdout_bytes[17] = {
        0x89u, 0xf2u, 0x89u, 0xfeu, 0xbfu, 1u, 0u, 0u, 0u,
        0xb8u, 1u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u
    };
    if (pos < 50u) return stdout_bytes[pos - 33u];

    static const uint stderr_bytes[17] = {
        0x89u, 0xf2u, 0x89u, 0xfeu, 0xbfu, 2u, 0u, 0u, 0u,
        0xb8u, 1u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u
    };
    if (pos < 67u) return stderr_bytes[pos - 50u];

    static const uint stdin_bytes[11] = {
        0x89u, 0xf2u, 0x89u, 0xfeu, 0x31u, 0xffu,
        0x31u, 0xc0u, 0x0fu, 0x05u, 0xc3u
    };
    if (pos < X86_RUNTIME_PRINT_I32_OFFSET) return stdin_bytes[pos - 67u];

    // print_i32: one shared runtime routine, addressed by the explicit
    // X86_LIR_OP_PRINT_I32 target instruction. It accepts the value in EDI,
    // formats the complete signed i32 domain into a stack buffer, appends a
    // newline, and writes it to stdout with one syscall.
    static const uint print_i32_bytes[84] = {
        0x48u, 0x83u, 0xecu, 0x18u, 0x48u, 0x8du, 0x74u, 0x24u, 0x17u,
        0xc6u, 0x06u, 0x0au, 0x89u, 0xf8u, 0x41u, 0x89u, 0xc0u, 0x41u,
        0xc1u, 0xf8u, 0x1fu, 0x44u, 0x31u, 0xc0u, 0x44u, 0x29u, 0xc0u,
        0xb9u, 0x0au, 0x00u, 0x00u, 0x00u, 0x31u, 0xd2u, 0xf7u, 0xf1u,
        0x80u, 0xc2u, 0x30u, 0x48u, 0xffu, 0xceu, 0x88u, 0x16u, 0x85u,
        0xc0u, 0x75u, 0xf0u, 0x45u, 0x85u, 0xc0u, 0x74u, 0x06u, 0x48u,
        0xffu, 0xceu, 0xc6u, 0x06u, 0x2du, 0x48u, 0x8du, 0x54u, 0x24u,
        0x18u, 0x48u, 0x29u, 0xf2u, 0xbfu, 0x01u, 0x00u, 0x00u, 0x00u,
        0xb8u, 0x01u, 0x00u, 0x00u, 0x00u, 0x0fu, 0x05u, 0x48u, 0x83u,
        0xc4u, 0x18u, 0xc3u
    };
    return pos < X86_RUNTIME_LENGTH
        ? print_i32_bytes[pos - X86_RUNTIME_PRINT_I32_OFFSET] : 0u;
}
