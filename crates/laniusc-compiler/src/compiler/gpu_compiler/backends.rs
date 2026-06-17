#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuCompilerBackends {
    pub wasm: bool,
    pub x86: bool,
}

impl GpuCompilerBackends {
    pub const fn all() -> Self {
        Self {
            wasm: true,
            x86: true,
        }
    }

    pub const fn frontend_only() -> Self {
        Self {
            wasm: false,
            x86: false,
        }
    }

    pub const fn wasm_only() -> Self {
        Self {
            wasm: true,
            x86: false,
        }
    }

    pub const fn x86_only() -> Self {
        Self {
            wasm: false,
            x86: true,
        }
    }
}
