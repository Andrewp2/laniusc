// Fixed native runtime block for target-independent host services.
//
// Call sites always emit the same `call rel32` shape. Service-specific bytes
// live once in this block, so adding calls does not multiply byte fragments.

import codegen.lowering_ir;

static const uint X86_RUNTIME_INVALID = 0xffffffffu;
static const uint X86_RUNTIME_ARG_READ_OFFSET = 78u;
static const uint X86_RUNTIME_ALLOC_OFFSET = 134u;
static const uint X86_RUNTIME_DEALLOC_OFFSET = 166u;
static const uint X86_RUNTIME_REALLOC_OFFSET = 174u;
static const uint X86_RUNTIME_ALLOC_FAILED_OFFSET = 188u;
static const uint X86_RUNTIME_PRINT_I32_OFFSET = 201u;
static const uint X86_RUNTIME_MONOTONIC_READ_OFFSET = 285u;
static const uint X86_RUNTIME_SYSTEM_READ_OFFSET = 311u;
static const uint X86_RUNTIME_SLEEP_MS_I32_OFFSET = 337u;
static const uint X86_RUNTIME_OPEN_READ_OFFSET = 392u;
static const uint X86_RUNTIME_OPEN_WRITE_OFFSET = 404u;
static const uint X86_RUNTIME_OPEN_APPEND_OFFSET = 422u;
static const uint X86_RUNTIME_REMOVE_FILE_OFFSET = 440u;
static const uint X86_RUNTIME_CREATE_DIR_OFFSET = 448u;
static const uint X86_RUNTIME_REMOVE_DIR_OFFSET = 461u;
static const uint X86_RUNTIME_RENAME_OFFSET = 469u;
static const uint X86_RUNTIME_WRITE_TEXT_OFFSET = 479u;
static const uint X86_RUNTIME_WRITE_I32_OFFSET = 487u;
static const uint X86_RUNTIME_WRITE_BYTE_OFFSET = 579u;
static const uint X86_RUNTIME_WRITE_NEWLINE_OFFSET = 607u;
static const uint X86_RUNTIME_READ_I32_OFFSET = 635u;
static const uint X86_RUNTIME_OPEN_READ_NUL_OFFSET = 810u;
static const uint X86_RUNTIME_OPEN_WRITE_NUL_OFFSET = 886u;
static const uint X86_RUNTIME_OPEN_APPEND_NUL_OFFSET = 962u;
static const uint X86_RUNTIME_VAR_KEY_LEN_OFFSET = 1038u;
static const uint X86_RUNTIME_VAR_COUNT_OFFSET = 1106u;
static const uint X86_RUNTIME_VAR_KEY_READ_OFFSET = 1128u;
static const uint X86_RUNTIME_VAR_LEN_OFFSET = 1215u;
static const uint X86_RUNTIME_VAR_READ_OFFSET = 1296u;
static const uint X86_RUNTIME_CURRENT_DIR_READ_OFFSET = 1398u;
static const uint X86_RUNTIME_UNIX_SECONDS_OFFSET = 1425u;
static const uint X86_RUNTIME_SECURE_U32_OFFSET = 1435u;
static const uint X86_RUNTIME_FILL_SECURE_BYTES_OFFSET = 1479u;
static const uint X86_RUNTIME_ARG_LEN_OFFSET = 1487u;
static const uint X86_RUNTIME_LENGTH = 1527u;

uint x86_runtime_service_offset(uint service)
{
    if (service == HOST_SERVICE_ARGC) return 0u;
    if (service == HOST_SERVICE_EXIT) return 4u;
    if (service == HOST_SERVICE_CLOSE_FILE || service == HOST_SERVICE_CLOSE) return 12u;
    if (service == HOST_SERVICE_READ) return 20u;
    if (service == HOST_SERVICE_WRITE) return 25u;
    if (service == HOST_SERVICE_WRITE_STDOUT) return 33u;
    if (service == HOST_SERVICE_WRITE_STDERR) return 50u;
    if (service == HOST_SERVICE_READ_STDIN) return 67u;
    if (service == HOST_SERVICE_ARG_READ) return X86_RUNTIME_ARG_READ_OFFSET;
    if (service == HOST_SERVICE_ALLOC) return X86_RUNTIME_ALLOC_OFFSET;
    if (service == HOST_SERVICE_DEALLOC) return X86_RUNTIME_DEALLOC_OFFSET;
    if (service == HOST_SERVICE_REALLOC) return X86_RUNTIME_REALLOC_OFFSET;
    if (service == HOST_SERVICE_ALLOC_FAILED) return X86_RUNTIME_ALLOC_FAILED_OFFSET;
    if (service == HOST_SERVICE_MONOTONIC_READ) return X86_RUNTIME_MONOTONIC_READ_OFFSET;
    if (service == HOST_SERVICE_SYSTEM_READ) return X86_RUNTIME_SYSTEM_READ_OFFSET;
    if (service == HOST_SERVICE_SLEEP_MS_I32) return X86_RUNTIME_SLEEP_MS_I32_OFFSET;
    if (service == HOST_SERVICE_OPEN_READ_PATH || service == HOST_SERVICE_OPEN_READ)
        return X86_RUNTIME_OPEN_READ_NUL_OFFSET;
    if (service == HOST_SERVICE_OPEN_WRITE_PATH || service == HOST_SERVICE_OPEN_WRITE)
        return X86_RUNTIME_OPEN_WRITE_NUL_OFFSET;
    if (service == HOST_SERVICE_OPEN_APPEND) return X86_RUNTIME_OPEN_APPEND_NUL_OFFSET;
    if (service == HOST_SERVICE_REMOVE_FILE) return X86_RUNTIME_REMOVE_FILE_OFFSET;
    if (service == HOST_SERVICE_CREATE_DIR) return X86_RUNTIME_CREATE_DIR_OFFSET;
    if (service == HOST_SERVICE_REMOVE_DIR) return X86_RUNTIME_REMOVE_DIR_OFFSET;
    if (service == HOST_SERVICE_RENAME) return X86_RUNTIME_RENAME_OFFSET;
    if (service == HOST_SERVICE_WRITE_TEXT) return X86_RUNTIME_WRITE_TEXT_OFFSET;
    if (service == HOST_SERVICE_WRITE_I32) return X86_RUNTIME_WRITE_I32_OFFSET;
    if (service == HOST_SERVICE_WRITE_BYTE) return X86_RUNTIME_WRITE_BYTE_OFFSET;
    if (service == HOST_SERVICE_WRITE_NEWLINE) return X86_RUNTIME_WRITE_NEWLINE_OFFSET;
    if (service == HOST_SERVICE_READ_I32) return X86_RUNTIME_READ_I32_OFFSET;
    if (service == HOST_SERVICE_CURRENT_DIR_READ) return X86_RUNTIME_CURRENT_DIR_READ_OFFSET;
    if (service == HOST_SERVICE_VAR_COUNT) return X86_RUNTIME_VAR_COUNT_OFFSET;
    if (service == HOST_SERVICE_VAR_KEY_LEN) return X86_RUNTIME_VAR_KEY_LEN_OFFSET;
    if (service == HOST_SERVICE_VAR_KEY_READ) return X86_RUNTIME_VAR_KEY_READ_OFFSET;
    if (service == HOST_SERVICE_VAR_LEN) return X86_RUNTIME_VAR_LEN_OFFSET;
    if (service == HOST_SERVICE_VAR_READ) return X86_RUNTIME_VAR_READ_OFFSET;
    if (service == HOST_SERVICE_UNIX_SECONDS) return X86_RUNTIME_UNIX_SECONDS_OFFSET;
    if (service == HOST_SERVICE_SECURE_U32) return X86_RUNTIME_SECURE_U32_OFFSET;
    if (service == HOST_SERVICE_FILL_SECURE_BYTES) return X86_RUNTIME_FILL_SECURE_BYTES_OFFSET;
    if (service == HOST_SERVICE_ARG_LEN) return X86_RUNTIME_ARG_LEN_OFFSET;
    return X86_RUNTIME_INVALID;
}

bool x86_runtime_service_supported(uint service)
{
    return x86_runtime_service_offset(service) != X86_RUNTIME_INVALID;
}

bool x86_runtime_service_has_result(uint service)
{
    return service != HOST_SERVICE_EXIT && service != HOST_SERVICE_DEALLOC &&
        service != HOST_SERVICE_ALLOC_FAILED;
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
        0x89u, 0xf2u, 0x57u, 0x5eu, 0xbfu, 1u, 0u, 0u, 0u,
        0xb8u, 1u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u
    };
    if (pos < 50u) return stdout_bytes[pos - 33u];

    static const uint stderr_bytes[17] = {
        0x89u, 0xf2u, 0x57u, 0x5eu, 0xbfu, 2u, 0u, 0u, 0u,
        0xb8u, 1u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u
    };
    if (pos < 67u) return stderr_bytes[pos - 50u];

    static const uint stdin_bytes[11] = {
        0x89u, 0xf2u, 0x57u, 0x5eu, 0x31u, 0xffu,
        0x31u, 0xc0u, 0x0fu, 0x05u, 0xc3u
    };
    if (pos < X86_RUNTIME_ARG_READ_OFFSET) return stdin_bytes[pos - 67u];

    // Copy argv[index] into the caller's bounded allocation and
    // return the number of bytes copied, excluding the terminating NUL.
    static const uint arg_read_bytes[56] = {
        // Reject negative and out-of-range indices before reading argv.
        0x85u, 0xffu, 0x78u, 0x2eu, 0x41u, 0x8bu, 0x07u, 0x39u,
        0xc7u, 0x73u, 0x27u,
        0x56u, 0x41u, 0x58u, 0x41u, 0x89u, 0xd1u, 0x89u, 0xf8u,
        0xffu, 0xc0u, 0x49u, 0x8bu, 0x34u, 0xc7u, 0x31u, 0xc0u,
        0x44u, 0x39u, 0xc8u, 0x73u, 0x11u, 0x80u, 0x3cu, 0x06u,
        0u, 0x74u, 0x0bu, 0x8au, 0x0cu, 0x06u, 0x41u, 0x88u,
        0x0cu, 0u, 0xffu, 0xc0u, 0xebu, 0xeau, 0xc3u,
        0xb8u, 0xffu, 0xffu, 0xffu, 0xffu, 0xc3u
    };
    if (pos < X86_RUNTIME_ALLOC_OFFSET)
        return arg_read_bytes[pos - X86_RUNTIME_ARG_READ_OFFSET];

    // mmap(..., MAP_PRIVATE | MAP_ANONYMOUS | MAP_32BIT, -1, 0) returns
    // page-aligned storage for every supported alignment. MAP_32BIT is not an
    // ABI requirement now that source pointers are target-sized.
    static const uint alloc_bytes[32] = {
        0x89u, 0xfeu, 0x31u, 0xffu, 0xbau, 3u, 0u, 0u, 0u,
        0x41u, 0xbau, 0x62u, 0u, 0u, 0u, 0x41u, 0xb8u, 0xffu, 0xffu,
        0xffu, 0xffu, 0x45u, 0x31u, 0xc9u, 0xb8u, 9u, 0u, 0u, 0u,
        0x0fu, 0x05u, 0xc3u
    };
    if (pos < X86_RUNTIME_DEALLOC_OFFSET)
        return alloc_bytes[pos - X86_RUNTIME_ALLOC_OFFSET];

    static const uint dealloc_bytes[8] =
        {0xb8u, 11u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u};
    if (pos < X86_RUNTIME_REALLOC_OFFSET)
        return dealloc_bytes[pos - X86_RUNTIME_DEALLOC_OFFSET];

    static const uint realloc_bytes[14] = {
        0x41u, 0xbau, 1u, 0u, 0u, 0u, 0xb8u, 25u, 0u, 0u, 0u,
        0x0fu, 0x05u, 0xc3u
    };
    if (pos < X86_RUNTIME_ALLOC_FAILED_OFFSET)
        return realloc_bytes[pos - X86_RUNTIME_REALLOC_OFFSET];

    // Allocation failure is a non-returning host ABI boundary. The size and
    // alignment arguments arrive in EDI/ESI but Linux process exit needs only
    // the stable failure status in EDI.
    static const uint alloc_failed_bytes[13] = {
        0xbfu, 1u, 0u, 0u, 0u, 0xb8u, 60u, 0u, 0u, 0u,
        0x0fu, 0x05u, 0xc3u
    };
    if (pos < X86_RUNTIME_PRINT_I32_OFFSET)
        return alloc_failed_bytes[pos - X86_RUNTIME_ALLOC_FAILED_OFFSET];

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
    if (pos >= X86_RUNTIME_MONOTONIC_READ_OFFSET &&
        pos < X86_RUNTIME_MONOTONIC_READ_OFFSET + 26u)
    {
        static const uint monotonic_read_bytes[26] = {
            0x83u, 0xfeu, 0x10u, 0x72u, 0x0fu,
            0x57u, 0x5eu, 0xbfu, 1u, 0u, 0u, 0u,
            0xb8u, 228u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u,
            0xb8u, 0xffu, 0xffu, 0xffu, 0xffu, 0xc3u
        };
        return monotonic_read_bytes[pos - X86_RUNTIME_MONOTONIC_READ_OFFSET];
    }
    if (pos >= X86_RUNTIME_SYSTEM_READ_OFFSET &&
        pos < X86_RUNTIME_SYSTEM_READ_OFFSET + 26u)
    {
        static const uint system_read_bytes[26] = {
            0x83u, 0xfeu, 0x10u, 0x72u, 0x0fu,
            0x57u, 0x5eu, 0xbfu, 0u, 0u, 0u, 0u,
            0xb8u, 228u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u,
            0xb8u, 0xffu, 0xffu, 0xffu, 0xffu, 0xc3u
        };
        return system_read_bytes[pos - X86_RUNTIME_SYSTEM_READ_OFFSET];
    }
    if (pos >= X86_RUNTIME_SLEEP_MS_I32_OFFSET &&
        pos < X86_RUNTIME_SLEEP_MS_I32_OFFSET + 55u)
    {
        static const uint sleep_ms_i32_bytes[55] = {
            0x85u, 0xffu, 0x78u, 0x2du,
            0x48u, 0x83u, 0xecu, 0x10u,
            0x89u, 0xf8u, 0x31u, 0xd2u,
            0xb9u, 0xe8u, 3u, 0u, 0u, 0xf7u, 0xf1u,
            0x89u, 4u, 0x24u,
            0x69u, 0xd2u, 0x40u, 0x42u, 0x0fu, 0u,
            0x89u, 0x54u, 0x24u, 8u,
            0x31u, 0xf6u, 0x48u, 0x89u, 0xe7u,
            0xb8u, 35u, 0u, 0u, 0u, 0x0fu, 0x05u,
            0x48u, 0x83u, 0xc4u, 0x10u, 0xc3u,
            0xb8u, 0xffu, 0xffu, 0xffu, 0xffu, 0xc3u
        };
        return sleep_ms_i32_bytes[pos - X86_RUNTIME_SLEEP_MS_I32_OFFSET];
    }
    if (pos >= X86_RUNTIME_OPEN_READ_OFFSET && pos < X86_RUNTIME_OPEN_READ_OFFSET + 12u)
    {
        static const uint open_read_bytes[12] = {
            0x31u, 0xf6u, 0x31u, 0xd2u,
            0xb8u, 2u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u
        };
        return open_read_bytes[pos - X86_RUNTIME_OPEN_READ_OFFSET];
    }
    if (pos >= X86_RUNTIME_OPEN_WRITE_OFFSET && pos < X86_RUNTIME_OPEN_WRITE_OFFSET + 18u)
    {
        static const uint open_write_bytes[18] = {
            0xbeu, 0x41u, 2u, 0u, 0u,
            0xbau, 0xb6u, 1u, 0u, 0u,
            0xb8u, 2u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u
        };
        return open_write_bytes[pos - X86_RUNTIME_OPEN_WRITE_OFFSET];
    }
    if (pos >= X86_RUNTIME_OPEN_APPEND_OFFSET && pos < X86_RUNTIME_OPEN_APPEND_OFFSET + 18u)
    {
        static const uint open_append_bytes[18] = {
            0xbeu, 0x41u, 4u, 0u, 0u,
            0xbau, 0xb6u, 1u, 0u, 0u,
            0xb8u, 2u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u
        };
        return open_append_bytes[pos - X86_RUNTIME_OPEN_APPEND_OFFSET];
    }
    if (pos >= X86_RUNTIME_REMOVE_FILE_OFFSET && pos < X86_RUNTIME_REMOVE_FILE_OFFSET + 8u)
    {
        static const uint remove_file_bytes[8] =
            {0xb8u, 87u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u};
        return remove_file_bytes[pos - X86_RUNTIME_REMOVE_FILE_OFFSET];
    }
    if (pos >= X86_RUNTIME_CREATE_DIR_OFFSET && pos < X86_RUNTIME_CREATE_DIR_OFFSET + 13u)
    {
        static const uint create_dir_bytes[13] = {
            0xbeu, 0xffu, 1u, 0u, 0u,
            0xb8u, 83u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u
        };
        return create_dir_bytes[pos - X86_RUNTIME_CREATE_DIR_OFFSET];
    }
    if (pos >= X86_RUNTIME_REMOVE_DIR_OFFSET && pos < X86_RUNTIME_REMOVE_DIR_OFFSET + 8u)
    {
        static const uint remove_dir_bytes[8] =
            {0xb8u, 84u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u};
        return remove_dir_bytes[pos - X86_RUNTIME_REMOVE_DIR_OFFSET];
    }
    if (pos >= X86_RUNTIME_RENAME_OFFSET && pos < X86_RUNTIME_RENAME_OFFSET + 10u)
    {
        static const uint rename_bytes[10] = {
            0x89u, 0xd6u, 0xb8u, 82u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u
        };
        return rename_bytes[pos - X86_RUNTIME_RENAME_OFFSET];
    }
    if (pos >= X86_RUNTIME_WRITE_TEXT_OFFSET && pos < X86_RUNTIME_WRITE_TEXT_OFFSET + 8u)
    {
        static const uint write_text_bytes[8] =
            {0xb8u, 1u, 0u, 0u, 0u, 0x0fu, 0x05u, 0xc3u};
        return write_text_bytes[pos - X86_RUNTIME_WRITE_TEXT_OFFSET];
    }
    if (pos >= X86_RUNTIME_WRITE_I32_OFFSET && pos < X86_RUNTIME_WRITE_I32_OFFSET + 92u)
    {
        static const uint write_i32_bytes[92] = {
            0x41u, 0x89u, 0xfau, 0x89u, 0xf7u,
            0x48u, 0x83u, 0xecu, 0x18u, 0x48u, 0x8du, 0x74u, 0x24u, 0x17u,
            0x90u, 0x90u, 0x90u, 0x41u, 0x89u, 0xc0u, 0x41u,
            0xc1u, 0xf8u, 0x1fu, 0x44u, 0x31u, 0xc0u, 0x44u, 0x29u, 0xc0u,
            0xb9u, 0x0au, 0u, 0u, 0u, 0x31u, 0xd2u, 0xf7u, 0xf1u,
            0x80u, 0xc2u, 0x30u, 0x48u, 0xffu, 0xceu, 0x88u, 0x16u,
            0x85u, 0xc0u, 0x75u, 0xf0u, 0x45u, 0x85u, 0xc0u, 0x74u, 0x06u,
            0x48u, 0xffu, 0xceu, 0xc6u, 0x06u, 0x2du, 0x48u, 0x8du,
            0x54u, 0x24u, 0x17u, 0x48u, 0x29u, 0xf2u, 0x44u, 0x89u, 0xd7u,
            0xb8u, 1u, 0u, 0u, 0u, 0x0fu, 0x05u,
            // The language service reports status, not the Linux byte count:
            // preserve negative errno values and canonicalize success to zero.
            0x85u, 0xc0u, 0x78u, 0x02u, 0x31u, 0xc0u,
            0x48u, 0x83u, 0xc4u, 0x18u, 0xc3u, 0u
        };
        return write_i32_bytes[pos - X86_RUNTIME_WRITE_I32_OFFSET];
    }
    if (pos >= X86_RUNTIME_WRITE_BYTE_OFFSET && pos < X86_RUNTIME_WRITE_BYTE_OFFSET + 28u)
    {
        static const uint write_byte_bytes[28] = {
            0x48u, 0x83u, 0xecu, 8u, 0x40u, 0x88u, 0x34u, 0x24u,
            0xbau, 1u, 0u, 0u, 0u, 0x48u, 0x89u, 0xe6u,
            0xb8u, 1u, 0u, 0u, 0u, 0x0fu, 0x05u,
            0x48u, 0x83u, 0xc4u, 8u, 0xc3u
        };
        return write_byte_bytes[pos - X86_RUNTIME_WRITE_BYTE_OFFSET];
    }
    if (pos >= X86_RUNTIME_WRITE_NEWLINE_OFFSET && pos < X86_RUNTIME_WRITE_NEWLINE_OFFSET + 28u)
    {
        static const uint write_newline_bytes[28] = {
            0x48u, 0x83u, 0xecu, 8u, 0xc6u, 0x04u, 0x24u, 0x0au,
            0xbau, 1u, 0u, 0u, 0u, 0x48u, 0x89u, 0xe6u,
            0xb8u, 1u, 0u, 0u, 0u, 0x0fu, 0x05u,
            0x48u, 0x83u, 0xc4u, 8u, 0xc3u
        };
        return write_newline_bytes[pos - X86_RUNTIME_WRITE_NEWLINE_OFFSET];
    }
    if (pos >= X86_RUNTIME_READ_I32_OFFSET && pos < X86_RUNTIME_READ_I32_OFFSET + 175u)
    {
        // Read and parse one signed decimal line without consuming bytes from
        // following lines. The fallback is returned for EOF or no digits.
        // The routine is 129 bytes; the stable 175-byte slot remains padded.
        static const uint read_i32_bytes[175] = {
            0x41u, 0x89u, 0xf8u, 0x41u, 0x89u, 0xf1u, 0x48u, 0x83u,
            0xecu, 0x08u, 0xc6u, 0x44u, 0x24u, 0x01u, 0x00u, 0xc6u,
            0x44u, 0x24u, 0x02u, 0x00u, 0x45u, 0x31u, 0xd2u, 0x44u,
            0x89u, 0xc7u, 0x48u, 0x8du, 0x34u, 0x24u, 0xbau, 0x01u,
            0x00u, 0x00u, 0x00u, 0x31u, 0xc0u, 0x0fu, 0x05u, 0x48u,
            0x83u, 0xf8u, 0x01u, 0x75u, 0x34u, 0x0fu, 0xb6u, 0x04u,
            0x24u, 0x3cu, 0x0au, 0x74u, 0x2cu, 0x3cu, 0x0du, 0x74u,
            0xdeu, 0x80u, 0x7cu, 0x24u, 0x02u, 0x00u, 0x75u, 0x0bu,
            0x3cu, 0x2du, 0x75u, 0x07u, 0xc6u, 0x44u, 0x24u, 0x01u,
            0x01u, 0xebu, 0xccu, 0x83u, 0xe8u, 0x30u, 0x83u, 0xf8u,
            0x09u, 0x77u, 0x0eu, 0x45u, 0x6bu, 0xd2u, 0x0au, 0x41u,
            0x01u, 0xc2u, 0xc6u, 0x44u, 0x24u, 0x02u, 0x01u, 0xebu,
            0xb6u, 0x80u, 0x7cu, 0x24u, 0x02u, 0x00u, 0x74u, 0x11u,
            0x44u, 0x89u, 0xd0u, 0x80u, 0x7cu, 0x24u, 0x01u, 0x00u,
            0x74u, 0x02u, 0xf7u, 0xd8u, 0x48u, 0x83u, 0xc4u, 0x08u,
            0xc3u, 0x44u, 0x89u, 0xc8u, 0x48u, 0x83u, 0xc4u, 0x08u,
            0xc3u,
            0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
            0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
            0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
            0u, 0u, 0u, 0u, 0u, 0u, 0u
        };
        return read_i32_bytes[pos - X86_RUNTIME_READ_I32_OFFSET];
    }
    if (pos >= X86_RUNTIME_OPEN_READ_NUL_OFFSET && pos < X86_RUNTIME_OPEN_READ_NUL_OFFSET + 76u)
    {
        // The source-language string ABI supplies (pointer, length), while
        // Linux open(2) requires a NUL-terminated path.  Copy the bounded
        // slice to private stack storage before issuing the syscall.
        static const uint open_read_nul_bytes[76] = {
            0x41u, 0x89u, 0xf0u, 0x41u, 0x81u, 0xf8u, 0xffu, 0u, 0u, 0u,
            0x76u, 6u, 0x41u, 0xb8u, 0xffu, 0u, 0u, 0u,
            0x48u, 0x81u, 0xecu, 0u, 1u, 0u, 0u,
            0x48u, 0x89u, 0xfeu, 0x48u, 0x89u, 0xe7u, 0x4cu, 0x89u, 0xc1u,
            0xfcu, 0xf3u, 0xa4u, 0x42u, 0xc6u, 0x04u, 0x04u, 0u,
            0x4cu, 0x29u, 0xc7u,
            0x31u, 0xf6u, 0x31u, 0xd2u, 0xb8u, 2u, 0u, 0u, 0u,
            0x0fu, 0x05u, 0x48u, 0x81u, 0xc4u, 0u, 1u, 0u, 0u, 0xc3u,
            0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u
        };
        return open_read_nul_bytes[pos - X86_RUNTIME_OPEN_READ_NUL_OFFSET];
    }
    if (pos >= X86_RUNTIME_OPEN_WRITE_NUL_OFFSET && pos < X86_RUNTIME_OPEN_WRITE_NUL_OFFSET + 76u)
    {
        static const uint open_write_nul_bytes[76] = {
            0x41u, 0x89u, 0xf0u, 0x41u, 0x81u, 0xf8u, 0xffu, 0u, 0u, 0u,
            0x76u, 6u, 0x41u, 0xb8u, 0xffu, 0u, 0u, 0u,
            0x48u, 0x81u, 0xecu, 0u, 1u, 0u, 0u,
            0x48u, 0x89u, 0xfeu, 0x48u, 0x89u, 0xe7u, 0x4cu, 0x89u, 0xc1u,
            0xfcu, 0xf3u, 0xa4u, 0x42u, 0xc6u, 0x04u, 0x04u, 0u,
            0x4cu, 0x29u, 0xc7u,
            0xbeu, 0x41u, 2u, 0u, 0u, 0xbau, 0xb6u, 1u, 0u, 0u,
            0xb8u, 2u, 0u, 0u, 0u, 0x0fu, 0x05u,
            0x48u, 0x81u, 0xc4u, 0u, 1u, 0u, 0u, 0xc3u,
            0u, 0u, 0u, 0u, 0u, 0u
        };
        return open_write_nul_bytes[pos - X86_RUNTIME_OPEN_WRITE_NUL_OFFSET];
    }
    if (pos >= X86_RUNTIME_OPEN_APPEND_NUL_OFFSET && pos < X86_RUNTIME_OPEN_APPEND_NUL_OFFSET + 76u)
    {
        static const uint open_append_nul_bytes[76] = {
            0x41u, 0x89u, 0xf0u, 0x41u, 0x81u, 0xf8u, 0xffu, 0u, 0u, 0u,
            0x76u, 6u, 0x41u, 0xb8u, 0xffu, 0u, 0u, 0u,
            0x48u, 0x81u, 0xecu, 0u, 1u, 0u, 0u,
            0x48u, 0x89u, 0xfeu, 0x48u, 0x89u, 0xe7u, 0x4cu, 0x89u, 0xc1u,
            0xfcu, 0xf3u, 0xa4u, 0x42u, 0xc6u, 0x04u, 0x04u, 0u,
            0x4cu, 0x29u, 0xc7u,
            0xbeu, 0x41u, 4u, 0u, 0u, 0xbau, 0xb6u, 1u, 0u, 0u,
            0xb8u, 2u, 0u, 0u, 0u, 0x0fu, 0x05u,
            0x48u, 0x81u, 0xc4u, 0u, 1u, 0u, 0u, 0xc3u,
            0u, 0u, 0u, 0u, 0u, 0u
        };
        return open_append_nul_bytes[pos - X86_RUNTIME_OPEN_APPEND_NUL_OFFSET];
    }
    if (pos >= X86_RUNTIME_VAR_KEY_LEN_OFFSET && pos < X86_RUNTIME_VAR_KEY_LEN_OFFSET + 68u)
    {
        static const uint var_key_len_bytes[68] = {
            0x4du, 0x8bu, 0x07u, 0x4fu, 0x8du, 0x44u, 0xc7u, 0x10u,
            0x41u, 0x89u, 0xf9u, 0x45u, 0x85u, 0xc9u, 0x78u, 0x2eu,
            0x4du, 0x89u, 0xc2u, 0x4du, 0x8bu, 0x1au, 0x4du, 0x85u,
            0xdbu, 0x74u, 0x23u, 0x45u, 0x85u, 0xc9u, 0x74u, 0x09u,
            0x49u, 0x83u, 0xc2u, 0x08u, 0x41u, 0xffu, 0xc9u, 0xebu,
            0xeau, 0x31u, 0xc0u, 0x41u, 0x80u, 0x3cu, 0x03u, 0x00u,
            0x74u, 0x0bu, 0x41u, 0x80u, 0x3cu, 0x03u, 0x3du, 0x74u,
            0x04u, 0xffu, 0xc0u, 0xebu, 0xeeu, 0xc3u, 0xb8u, 0xffu,
            0xffu, 0xffu, 0xffu, 0xc3u
        };
        return var_key_len_bytes[pos - X86_RUNTIME_VAR_KEY_LEN_OFFSET];
    }
    if (pos >= X86_RUNTIME_VAR_COUNT_OFFSET && pos < X86_RUNTIME_VAR_COUNT_OFFSET + 22u)
    {
        static const uint var_count_bytes[22] = {
            0x4du, 0x8bu, 0x07u, 0x4fu, 0x8du, 0x44u, 0xc7u, 0x10u,
            0x31u, 0xc0u, 0x49u, 0x83u, 0x3cu, 0xc0u, 0x00u, 0x74u,
            0x04u, 0xffu, 0xc0u, 0xebu, 0xf5u, 0xc3u
        };
        return var_count_bytes[pos - X86_RUNTIME_VAR_COUNT_OFFSET];
    }
    if (pos >= X86_RUNTIME_VAR_KEY_READ_OFFSET && pos < X86_RUNTIME_VAR_KEY_READ_OFFSET + 87u)
    {
        static const uint var_key_read_bytes[87] = {
            0x4du, 0x8bu, 0x07u, 0x4fu, 0x8du, 0x44u, 0xc7u, 0x10u,
            0x41u, 0x89u, 0xf9u, 0x45u, 0x85u, 0xc9u, 0x78u, 0x41u,
            0x4du, 0x89u, 0xc2u, 0x4du, 0x8bu, 0x1au, 0x4du, 0x85u,
            0xdbu, 0x74u, 0x36u, 0x45u, 0x85u, 0xc9u, 0x74u, 0x09u,
            0x49u, 0x83u, 0xc2u, 0x08u, 0x41u, 0xffu, 0xc9u, 0xebu,
            0xeau, 0x56u, 0x41u, 0x5au, 0x41u, 0x89u, 0xd1u, 0x31u,
            0xc0u, 0x45u, 0x85u, 0xc9u, 0x74u, 0x1au, 0x45u, 0x8au,
            0x04u, 0x03u, 0x45u, 0x84u, 0xc0u, 0x74u, 0x11u, 0x41u,
            0x80u, 0xf8u, 0x3du, 0x74u, 0x0bu, 0x45u, 0x88u, 0x04u,
            0x02u, 0xffu, 0xc0u, 0x41u, 0xffu, 0xc9u, 0xebu, 0xe1u,
            0xc3u, 0xb8u, 0xffu, 0xffu, 0xffu, 0xffu, 0xc3u
        };
        return var_key_read_bytes[pos - X86_RUNTIME_VAR_KEY_READ_OFFSET];
    }
    if (pos >= X86_RUNTIME_VAR_LEN_OFFSET && pos < X86_RUNTIME_VAR_LEN_OFFSET + 81u)
    {
        static const uint var_len_bytes[81] = {
            0x57u, 0x41u, 0x5au, 0x41u, 0x89u, 0xf1u, 0x4du, 0x8bu,
            0x07u, 0x4fu, 0x8du, 0x44u, 0xc7u, 0x10u, 0x4du, 0x8bu,
            0x18u, 0x4du, 0x85u, 0xdbu, 0x74u, 0x35u, 0x31u, 0xc0u,
            0x44u, 0x39u, 0xc8u, 0x73u, 0x0eu, 0x41u, 0x8au, 0x14u,
            0x02u, 0x41u, 0x38u, 0x14u, 0x03u, 0x75u, 0x1du, 0xffu,
            0xc0u, 0xebu, 0xedu, 0x41u, 0x80u, 0x3cu, 0x03u, 0x3du,
            0x75u, 0x12u, 0x4du, 0x8du, 0x5cu, 0x03u, 0x01u, 0x31u,
            0xc0u, 0x41u, 0x80u, 0x3cu, 0x03u, 0x00u, 0x74u, 0x0au,
            0xffu, 0xc0u, 0xebu, 0xf5u, 0x49u, 0x83u, 0xc0u, 0x08u,
            0xebu, 0xc4u, 0xc3u, 0xb8u, 0xffu, 0xffu, 0xffu, 0xffu,
            0xc3u
        };
        return var_len_bytes[pos - X86_RUNTIME_VAR_LEN_OFFSET];
    }
    if (pos >= X86_RUNTIME_VAR_READ_OFFSET && pos < X86_RUNTIME_VAR_READ_OFFSET + 102u)
    {
        static const uint var_read_bytes[102] = {
            0x57u, 0x41u, 0x5au, 0x52u, 0x5fu, 0x41u, 0x89u, 0xf1u,
            0x4du, 0x8bu, 0x07u, 0x4fu, 0x8du, 0x44u, 0xc7u, 0x10u,
            0x4du, 0x8bu, 0x18u, 0x4du, 0x85u, 0xdbu, 0x74u, 0x48u,
            0x31u, 0xc0u, 0x44u, 0x39u, 0xc8u, 0x73u, 0x0eu, 0x41u,
            0x8au, 0x14u, 0x02u, 0x41u, 0x38u, 0x14u, 0x03u, 0x75u,
            0x31u, 0xffu, 0xc0u, 0xebu, 0xedu, 0x41u, 0x80u, 0x3cu,
            0x03u, 0x3du, 0x75u, 0x26u, 0x4du, 0x8du, 0x5cu, 0x03u,
            0x01u, 0x57u, 0x41u, 0x5au, 0x41u, 0x89u, 0xc9u, 0x31u,
            0xc0u, 0x45u, 0x85u, 0xc9u, 0x74u, 0x13u, 0x41u, 0x8au,
            0x14u, 0x03u, 0x84u, 0xd2u, 0x74u, 0x0bu, 0x41u, 0x88u,
            0x14u, 0x02u, 0xffu, 0xc0u, 0x41u, 0xffu, 0xc9u, 0xebu,
            0xe8u, 0xc3u, 0x49u, 0x83u, 0xc0u, 0x08u, 0xebu, 0xb0u,
            0xb8u, 0xffu, 0xffu, 0xffu, 0xffu, 0xc3u
        };
        return var_read_bytes[pos - X86_RUNTIME_VAR_READ_OFFSET];
    }
    if (pos >= X86_RUNTIME_CURRENT_DIR_READ_OFFSET && pos < X86_RUNTIME_CURRENT_DIR_READ_OFFSET + 27u)
    {
        static const uint current_dir_read_bytes[27] = {
            0x85u, 0xf6u, 0x74u, 0x11u, 0x89u, 0xf2u, 0xb8u, 0x4fu,
            0x00u, 0x00u, 0x00u, 0x0fu, 0x05u, 0x48u, 0x85u, 0xc0u,
            0x78u, 0x03u, 0xffu, 0xc8u, 0xc3u, 0xb8u, 0xffu, 0xffu,
            0xffu, 0xffu, 0xc3u
        };
        return current_dir_read_bytes[pos - X86_RUNTIME_CURRENT_DIR_READ_OFFSET];
    }
    if (pos >= X86_RUNTIME_UNIX_SECONDS_OFFSET && pos < X86_RUNTIME_UNIX_SECONDS_OFFSET + 10u)
    {
        static const uint unix_seconds_bytes[10] = {
            0x31u, 0xffu, 0xb8u, 0xc9u, 0x00u, 0x00u, 0x00u, 0x0fu,
            0x05u, 0xc3u
        };
        return unix_seconds_bytes[pos - X86_RUNTIME_UNIX_SECONDS_OFFSET];
    }
    if (pos >= X86_RUNTIME_SECURE_U32_OFFSET && pos < X86_RUNTIME_SECURE_U32_OFFSET + 44u)
    {
        static const uint secure_u32_bytes[44] = {
            0x48u, 0x83u, 0xecu, 0x08u, 0x48u, 0x89u, 0xe7u, 0xbeu,
            0x04u, 0x00u, 0x00u, 0x00u, 0x31u, 0xd2u, 0xb8u, 0x3eu,
            0x01u, 0x00u, 0x00u, 0x0fu, 0x05u, 0x83u, 0xf8u, 0x04u,
            0x75u, 0x08u, 0x8bu, 0x04u, 0x24u, 0x48u, 0x83u, 0xc4u,
            0x08u, 0xc3u, 0xb8u, 0xffu, 0xffu, 0xffu, 0xffu, 0x48u,
            0x83u, 0xc4u, 0x08u, 0xc3u
        };
        return secure_u32_bytes[pos - X86_RUNTIME_SECURE_U32_OFFSET];
    }
    if (pos >= X86_RUNTIME_FILL_SECURE_BYTES_OFFSET && pos < X86_RUNTIME_FILL_SECURE_BYTES_OFFSET + 8u)
    {
        static const uint fill_secure_bytes[8] = {
            0xb8u, 0x3eu, 0x01u, 0x00u, 0x00u, 0x0fu, 0x05u,
            0xc3u
        };
        return fill_secure_bytes[pos - X86_RUNTIME_FILL_SECURE_BYTES_OFFSET];
    }
    if (pos >= X86_RUNTIME_ARG_LEN_OFFSET && pos < X86_RUNTIME_ARG_LEN_OFFSET + 40u)
    {
        static const uint arg_len_bytes[40] = {
            0x45u, 0x8bu, 0x07u, 0x85u, 0xffu, 0x78u, 0x1bu, 0x44u,
            0x39u, 0xc7u, 0x73u, 0x16u, 0x41u, 0x89u, 0xf9u, 0x4fu,
            0x8bu, 0x54u, 0xcfu, 0x08u, 0x31u, 0xc0u, 0x41u, 0x80u,
            0x3cu, 0x02u, 0x00u, 0x74u, 0x04u, 0xffu, 0xc0u, 0xebu,
            0xf5u, 0xc3u, 0xb8u, 0xffu, 0xffu, 0xffu, 0xffu, 0xc3u
        };
        return arg_len_bytes[pos - X86_RUNTIME_ARG_LEN_OFFSET];
    }
    return pos < X86_RUNTIME_LENGTH
        ? print_i32_bytes[pos - X86_RUNTIME_PRINT_I32_OFFSET] : 0u;
}
