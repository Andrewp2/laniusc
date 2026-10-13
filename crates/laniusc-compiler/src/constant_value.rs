//! Validated scalar constant values retained from accepted GPU artifacts.
//!
//! This module checks a wire value's shape and preserves exact bits. Source
//! typing, substitution, expression evaluation, and layout remain GPU work.

use crate::primitive_types::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub(crate) struct CheckedConstantValue {
    scalar: u32,
    bits: [u32; 2],
}

impl CheckedConstantValue {
    /// Preserve a complete admitted atom. All integer bit patterns at the
    /// declared width are valid; u32::MAX is only a reserved storage index.
    pub(crate) fn from_words(scalar: u32, bits: [u32; 2]) -> Option<Self> {
        let raw = u64::from(bits[0]) | (u64::from(bits[1]) << 32);
        let width = integer_bits(scalar);
        let valid = match scalar {
            SCALAR_BOOL => raw <= 1,
            SCALAR_CHAR => u32::try_from(raw).ok().and_then(char::from_u32).is_some(),
            SCALAR_F32 => bits[1] == 0,
            SCALAR_F64 => true,
            _ if width == 64 => true,
            _ if width > 0 => raw < (1u64 << width),
            _ => false,
        };
        valid.then_some(Self { scalar, bits })
    }

    pub(crate) const fn scalar(self) -> u32 {
        self.scalar
    }
    pub(crate) const fn bits(self) -> [u32; 2] {
        self.bits
    }
    pub(crate) const fn words(self) -> [u32; 3] {
        [self.scalar, self.bits[0], self.bits[1]]
    }

    /// Serialization of a GPU-checked array count. The projection checks value
    /// shape only; resource bounds and native layout are separate GPU contracts.
    pub(crate) fn count(self) -> Option<u32> {
        let width = integer_bits(self.scalar);
        if width == 0 || self.bits[1] != 0 {
            return None;
        }
        if is_signed_integer(self.scalar)
            && width <= 32
            && self.bits[0] & (1u32 << (width - 1)) != 0
        {
            return None;
        }
        Some(self.bits[0])
    }
}

pub(crate) fn constant_scalar_is_supported(scalar: u32) -> bool {
    integer_bits(scalar) != 0
        || matches!(scalar, SCALAR_BOOL | SCALAR_CHAR | SCALAR_F32 | SCALAR_F64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scalar_constant_identity_preserves_type_and_every_value_bit() {
        let cases = [
            (SCALAR_U32, [u32::MAX, 0]),
            (SCALAR_U64, [u32::MAX, u32::MAX]),
            (SCALAR_I64, [0, 0x8000_0000]),
            (SCALAR_I8, [0x80, 0]),
            (SCALAR_BOOL, [0, 0]),
            (SCALAR_CHAR, [0x10ffff, 0]),
            (SCALAR_F32, [0x8000_0000, 0]),
            (SCALAR_F64, [0x1234_5678, 0x7ff8_0000]),
        ];
        for (scalar, bits) in cases {
            let value = CheckedConstantValue::from_words(scalar, bits).unwrap();
            assert_eq!(value.words(), [scalar, bits[0], bits[1]]);
        }
        let u32_value = CheckedConstantValue::from_words(SCALAR_U32, [1, 0]).unwrap();
        let i32_value = CheckedConstantValue::from_words(SCALAR_I32, [1, 0]).unwrap();
        assert_ne!(u32_value, i32_value);
        assert_ne!(
            CheckedConstantValue::from_words(SCALAR_U64, [1, 0]),
            CheckedConstantValue::from_words(SCALAR_U64, [1, 1])
        );
        assert_ne!(
            CheckedConstantValue::from_words(SCALAR_F64, [0, 0]),
            CheckedConstantValue::from_words(SCALAR_F64, [0, 0x8000_0000])
        );
        assert_ne!(
            CheckedConstantValue::from_words(SCALAR_F32, [0x7fc0_0001, 0]),
            CheckedConstantValue::from_words(SCALAR_F32, [0x7fc0_0002, 0])
        );
    }

    #[test]
    fn malformed_atoms_are_rejected_without_reserving_value_patterns() {
        for (scalar, bits) in [
            (SCALAR_BOOL, [2, 0]),
            (SCALAR_BOOL, [0, 1]),
            (SCALAR_CHAR, [0xd800, 0]),
            (SCALAR_CHAR, [0xdfff, 0]),
            (SCALAR_CHAR, [0x110000, 0]),
            (SCALAR_CHAR, [0, 1]),
            (SCALAR_I8, [0x100, 0]),
            (SCALAR_U16, [0x10000, 0]),
            (SCALAR_I32, [0, 1]),
            (SCALAR_F32, [0, 1]),
            (SCALAR_UNKNOWN, [0, 0]),
            (SCALAR_UNIT, [0, 0]),
            (SCALAR_PTR, [0, 0]),
            (u32::MAX, [0, 0]),
        ] {
            assert!(
                CheckedConstantValue::from_words(scalar, bits).is_none(),
                "{scalar}: {bits:?}"
            );
        }
        assert!(CheckedConstantValue::from_words(SCALAR_U64, [u32::MAX; 2]).is_some());
    }

    #[test]
    fn extent_projection_is_separate_from_typed_constant_admission() {
        for (scalar, bits, expected) in [
            (SCALAR_U32, [u32::MAX, 0], Some(u32::MAX)),
            (SCALAR_I32, [u32::MAX, 0], None),
            (SCALAR_I64, [u32::MAX, 0], Some(u32::MAX)),
            (SCALAR_I64, [0, 0x8000_0000], None),
            (SCALAR_U64, [0, 1], None),
            (SCALAR_I8, [127, 0], Some(127)),
            (SCALAR_I8, [128, 0], None),
            (SCALAR_U8, [255, 0], Some(255)),
            (SCALAR_BOOL, [1, 0], None),
            (SCALAR_CHAR, [65, 0], None),
            (SCALAR_F32, [0, 0], None),
        ] {
            let value = CheckedConstantValue::from_words(scalar, bits).unwrap();
            assert_eq!(value.count(), expected, "{scalar}: {bits:?}");
        }
    }
}
