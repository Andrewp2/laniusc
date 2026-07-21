// Canonical mapping from language runtime symbols to the fixed WASM import ABI.
// Compiler intrinsics are deliberately absent: they are emitted by their own
// semantic planners and must never masquerade as runtime calls.

import compact_expr_common;

static const uint HOST_SYMBOL_OPEN_READ_PATH = 20u;
static const uint HOST_SYMBOL_OPEN_WRITE_PATH = 21u;
static const uint HOST_SYMBOL_READ_I32 = 22u;
static const uint HOST_SYMBOL_WRITE_TEXT = 23u;
static const uint HOST_SYMBOL_WRITE_I32 = 24u;
static const uint HOST_SYMBOL_WRITE_BYTE = 25u;
static const uint HOST_SYMBOL_WRITE_NEWLINE = 26u;
static const uint HOST_SYMBOL_CLOSE_FILE = 27u;
static const uint HOST_SYMBOL_EXIT = 29u;
static const uint HOST_SYMBOL_SECURE_U32 = 30u;
static const uint HOST_SYMBOL_ALLOC = 31u;
static const uint HOST_SYMBOL_DEALLOC = 32u;
static const uint HOST_SYMBOL_ARGC = 33u;
static const uint HOST_SYMBOL_ARG_LEN = 34u;
static const uint HOST_SYMBOL_ARG_READ = 35u;
static const uint HOST_SYMBOL_UNIX_SECONDS = 36u;
static const uint HOST_SYMBOL_CURRENT_DIR_READ = 37u;
static const uint HOST_SYMBOL_VAR_COUNT = 38u;
static const uint HOST_SYMBOL_VAR_READ = 42u;
static const uint HOST_SYMBOL_CLOSE = 43u;
static const uint HOST_SYMBOL_OPEN_APPEND = 48u;
static const uint HOST_SYMBOL_WRITE_STDOUT = 49u;
static const uint HOST_SYMBOL_WRITE_STDERR = 50u;
static const uint HOST_SYMBOL_READ_STDIN = 51u;
static const uint HOST_SYMBOL_FILL_SECURE_BYTES = 53u;
static const uint HOST_SYMBOL_ALLOC_FAILED = 62u;

uint wasm_host_import_for_language_symbol(uint symbol)
{
    if (symbol == HOST_SYMBOL_OPEN_READ_PATH) return 28u;
    if (symbol == HOST_SYMBOL_OPEN_WRITE_PATH) return 29u;
    if (symbol == HOST_SYMBOL_READ_I32) return 24u;
    if (symbol == HOST_SYMBOL_WRITE_TEXT) return 30u;
    if (symbol >= HOST_SYMBOL_WRITE_I32 && symbol <= HOST_SYMBOL_WRITE_NEWLINE)
    {
        return symbol + 1u;
    }
    if (symbol == HOST_SYMBOL_CLOSE_FILE) return 14u;
    if (symbol == HOST_SYMBOL_EXIT) return 41u;
    if (symbol == HOST_SYMBOL_SECURE_U32) return 5u;
    if (symbol >= HOST_SYMBOL_ALLOC && symbol <= HOST_SYMBOL_DEALLOC)
        return symbol - 9u;
    if (symbol >= HOST_SYMBOL_ARGC && symbol <= HOST_SYMBOL_ARG_READ)
        return symbol - 31u;
    if (symbol >= HOST_SYMBOL_UNIX_SECONDS && symbol <= HOST_SYMBOL_CURRENT_DIR_READ)
    {
        return symbol - 30u;
    }
    if (symbol >= HOST_SYMBOL_VAR_COUNT && symbol <= HOST_SYMBOL_VAR_READ)
        return symbol - 29u;
    if (symbol >= HOST_SYMBOL_CLOSE && symbol <= HOST_SYMBOL_OPEN_APPEND)
        return symbol - 29u;
    if (symbol == HOST_SYMBOL_WRITE_STDOUT) return 1u;
    if (symbol >= HOST_SYMBOL_WRITE_STDERR && symbol <= HOST_SYMBOL_READ_STDIN)
        return symbol - 30u;
    if (symbol >= HOST_SYMBOL_FILL_SECURE_BYTES && symbol <= HOST_SYMBOL_ALLOC_FAILED)
    {
        return symbol - 22u;
    }
    return INVALID;
}

bool wasm_host_import_for_token(uint token, out uint wasm_func_index)
{
    wasm_func_index = INVALID;
    if (!valid_token(token)) return false;

    uint name_id = name_id_by_token[token];
    for (uint symbol = HOST_SYMBOL_OPEN_READ_PATH;
         symbol <= HOST_SYMBOL_ALLOC_FAILED;
         symbol += 1u)
    {
        uint import_index = wasm_host_import_for_language_symbol(symbol);
        if (import_index == INVALID) continue;
        uint language_id = language_name_id[symbol];
        if (language_id != INVALID && name_id == language_id)
        {
            wasm_func_index = import_index;
            return true;
        }
    }
    return false;
}

public bool wasm_host_import_for_call(
    uint callee_token,
    uint fn_token,
    out uint wasm_func_index)
{
    if (wasm_host_import_for_token(callee_token, wasm_func_index)) return true;
    return fn_token != callee_token &&
           wasm_host_import_for_token(fn_token, wasm_func_index);
}
