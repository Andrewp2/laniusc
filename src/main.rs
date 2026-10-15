fn main() -> std::process::ExitCode {
    // The compiler library configures NVIDIA's shader disk cache before main
    // (see `gpu::device`), so this binary and its test binaries share it.
    laniusc_compiler::cli::run_from_env()
}
