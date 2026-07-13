use super::WASM_BODY_PLAN_WORDS;

const WASM_BODY_PLAN_FEATURE_MASK: usize = 35;

pub(super) const WASM_BODY_FEATURE_EXPR_CONTROL: u32 = 1 << 0;
pub(super) const WASM_BODY_FEATURE_DIRECT: u32 = 1 << 1;
pub(super) const WASM_BODY_FEATURE_HOST: u32 = 1 << 2;
pub(super) const WASM_BODY_FEATURE_ARRAYS: u32 = 1 << 3;
pub(super) const WASM_BODY_FEATURE_MEMBER_EXPR: u32 = 1 << 4;
pub(super) const WASM_BODY_FEATURE_BINARY_DIRECT: u32 = 1 << 5;
pub(super) const WASM_BODY_FEATURE_LET_DIRECT: u32 = 1 << 6;
pub(super) const WASM_BODY_FEATURE_RETURN_NESTED_DIRECT: u32 = 1 << 7;
pub(super) const WASM_BODY_FEATURE_RETURN_DIRECT: u32 = 1 << 8;
pub(super) const WASM_BODY_FEATURE_LET_AGG_DIRECT: u32 = 1 << 9;
pub(super) const WASM_BODY_FEATURE_RETURN_AGG_DIRECT: u32 = 1 << 10;
pub(super) const WASM_BODY_FEATURE_AGG_COPY: u32 = 1 << 11;
pub(super) const WASM_BODY_FEATURE_ARRAY_ALLOC: u32 = 1 << 12;
pub(super) const WASM_BODY_FEATURE_ASSIGN: u32 = 1 << 13;
pub(super) const WASM_BODY_FEATURE_CONTROL: u32 = 1 << 14;
pub(super) const WASM_BODY_FEATURE_STMT_CALL: u32 = 1 << 15;
pub(super) const WASM_BODY_FEATURE_HOST_BASIC: u32 = 1 << 16;
pub(super) const WASM_BODY_FEATURE_HOST_ENV: u32 = 1 << 17;
pub(super) const WASM_BODY_FEATURE_HOST_IO: u32 = 1 << 18;
pub(super) const WASM_BODY_FEATURE_HOST_VOID: u32 = 1 << 19;
pub(super) const WASM_BODY_FEATURE_STMT_PRINT: u32 = 1 << 20;
pub(super) const WASM_BODY_FEATURE_STMT_HOST_VOID: u32 = 1 << 21;
pub(super) const WASM_BODY_FEATURE_STMT_PRINT_DIRECT: u32 = 1 << 22;
pub(super) const WASM_BODY_FEATURE_CONTROL_IF_SIMPLE: u32 = 1 << 23;
pub(super) const WASM_BODY_FEATURE_HOST_IO_I32: u32 = 1 << 24;
pub(super) const WASM_BODY_FEATURE_HOST_IO_STRING: u32 = 1 << 25;
pub(super) const WASM_BODY_FEATURE_HOST_IO_RETURN: u32 = 1 << 26;
pub(super) const WASM_BODY_FEATURE_RETURN_SCALAR: u32 = 1 << 27;
pub(super) const WASM_BODY_FEATURE_LET_CONST: u32 = 1 << 28;
pub(super) const WASM_BODY_FEATURE_RETURN_MEMBER_EXPR: u32 = 1 << 29;
pub(super) const WASM_BODY_FEATURE_MEMBER_EXPR_SCATTER: u32 = 1 << 30;
pub(super) const WASM_BODY_FEATURE_RETURN_EXPR: u32 = 1u32 << 31;

#[derive(Clone, Copy, Debug, Default)]
pub(super) struct WasmBodyFeatures {
    mask: u32,
}

impl WasmBodyFeatures {
    pub(super) fn from_body_plan(words: &[u32; WASM_BODY_PLAN_WORDS]) -> Self {
        Self {
            mask: words[WASM_BODY_PLAN_FEATURE_MASK],
        }
    }

    pub(super) fn has(self, bit: u32) -> bool {
        self.mask & bit != 0
    }

    pub(super) fn mask(self) -> u32 {
        self.mask
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_feature_mask_from_body_plan_contract_word() {
        let mut words = [0; WASM_BODY_PLAN_WORDS];
        words[WASM_BODY_PLAN_FEATURE_MASK] = WASM_BODY_FEATURE_DIRECT | WASM_BODY_FEATURE_HOST_IO;

        let features = WasmBodyFeatures::from_body_plan(&words);

        assert!(features.has(WASM_BODY_FEATURE_DIRECT));
        assert!(features.has(WASM_BODY_FEATURE_HOST_IO));
        assert!(!features.has(WASM_BODY_FEATURE_ARRAYS));
    }
}
