// Scalars supported by a Lanius function's System V entry stub. Both
// retained projection and native lowering validate the same boundary.
import primitive_types;
bool native_c_entry_scalar(uint type, bool result)
{
    return type == SCALAR_I32 || type == SCALAR_U32 || type == SCALAR_I64 ||
        type == SCALAR_U64 || type == SCALAR_ISIZE || type == SCALAR_USIZE ||
        type == SCALAR_PTR || (result && (type == SCALAR_UNIT || type == SCALAR_UNKNOWN));
}
