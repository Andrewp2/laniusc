/// Backend selection used by compile/check entry points.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GpuCompilerBackends {
    /// Whether WASM target codegen should be available.
    pub wasm: bool,
    /// Whether x86 target codegen should be available.
    pub x86: bool,
}

impl GpuCompilerBackends {
    /// Enables every backend supported by the compiler instance.
    pub const fn all() -> Self {
        Self {
            wasm: true,
            x86: true,
        }
    }

    /// Disables target codegen while keeping frontend validation available.
    pub const fn frontend_only() -> Self {
        Self {
            wasm: false,
            x86: false,
        }
    }

    /// Enables only the WASM backend.
    pub const fn wasm_only() -> Self {
        Self {
            wasm: true,
            x86: false,
        }
    }

    /// Enables only the x86 backend.
    pub const fn x86_only() -> Self {
        Self {
            wasm: false,
            x86: true,
        }
    }
}
