fn main() -> std::process::ExitCode {
    // SAFETY: the first statement of main, before any other thread exists.
    unsafe { laniusc_compiler::gpu::device::configure_driver_shader_cache() };
    laniusc_compiler::cli::run_from_env()
}
