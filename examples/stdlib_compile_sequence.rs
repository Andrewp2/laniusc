//! Reduce compiler state failures by compiling a list of stdlib entries in one process.
#[path = "../tests/common/mod.rs"]
mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn main() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (index, entry) in std::env::args().skip(1).enumerate() {
        let entry_path = root.join(&entry);
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("stdlib compile sequence", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry_path, &stdlib))
        })
        .unwrap_or_else(|error| panic!("step {index} {entry}: {error}"));
        println!("step {index} {entry}: {} native bytes", bytes.len());
    }
}
