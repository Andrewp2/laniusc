//! Primitive identity shared with GPU schemas. Machine class is a separate fact.
#![allow(dead_code)]
include!(concat!(env!("OUT_DIR"), "/primitive_types.rs"));

pub(crate) const fn is_known(scalar: u32) -> bool {
    scalar >= SCALAR_UNIT && scalar <= SCALAR_USIZE
}

pub(crate) const fn is_signed_integer(scalar: u32) -> bool {
    matches!(scalar, SCALAR_I8 | SCALAR_I16 | SCALAR_I32 | SCALAR_I64 | SCALAR_ISIZE)
}

pub(crate) const fn is_unsigned_integer(scalar: u32) -> bool {
    matches!(scalar, SCALAR_U8 | SCALAR_U16 | SCALAR_U32 | SCALAR_U64 | SCALAR_USIZE)
}

pub(crate) const fn integer_bits(scalar: u32) -> u32 {
    match scalar {
        SCALAR_I8 | SCALAR_U8 => 8,
        SCALAR_I16 | SCALAR_U16 => 16,
        SCALAR_I32 | SCALAR_U32 => 32,
        SCALAR_I64 | SCALAR_U64 | SCALAR_ISIZE | SCALAR_USIZE => 64,
        _ => 0,
    }
}


pub(crate) fn name(scalar: u32) -> Option<&'static str> {
    Some(match scalar {
        SCALAR_UNIT => "void", SCALAR_BOOL => "bool", SCALAR_I32 => "i32",
        SCALAR_U32 => "u32", SCALAR_F32 => "f32", SCALAR_CHAR => "char",
        SCALAR_STR => "str", SCALAR_PTR => "ptr", SCALAR_I64 => "i64",
        SCALAR_U64 => "u64", SCALAR_I8 => "i8", SCALAR_I16 => "i16",
        SCALAR_U8 => "u8", SCALAR_U16 => "u16", SCALAR_F64 => "f64",
        SCALAR_ISIZE => "isize", SCALAR_USIZE => "usize", _ => return None,
    })
}
