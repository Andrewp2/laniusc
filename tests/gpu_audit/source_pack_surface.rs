use super::support::source_between;

#[test]
fn explicit_source_pack_path_surface_is_runtime_only() {
    let compiler = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/compiler.rs"));
    let loader = source_between(
        compiler,
        "pub fn load_explicit_source_pack_from_paths",
        "fn read_explicit_source_paths",
    );
    let reader = source_between(
        compiler,
        "fn read_explicit_source_paths",
        "fn prepare_source_for_gpu_codegen",
    );
    let impl_compile = source_between(
        compiler,
        "pub async fn compile_explicit_source_pack_paths_to_wasm",
        "async fn compile_expanded_source_to_wasm",
    );
    let impl_compile_x86 = source_between(
        compiler,
        "pub async fn compile_explicit_source_pack_paths_to_x86_64",
        "async fn compile_expanded_source_to_x86_64",
    );
    let public_compile = source_between(
        compiler,
        "pub async fn compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen",
        "pub async fn type_check_source_with_gpu_using_path",
    );
    let public_compile_x86 = source_between(
        compiler,
        "pub async fn compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen",
        "pub async fn compile_source_to_x86_64_with_gpu_codegen_using",
    );

    assert!(
        loader.contains("stdlib_paths")
            && loader.contains("user_paths")
            && loader.contains("read_explicit_source_paths(\"stdlib\", stdlib_paths")
            && loader.contains("read_explicit_source_paths(\"user\", user_paths")
            && loader.contains("explicit source pack has no source files"),
        "explicit source-pack loader should accept caller-supplied stdlib and user path lists"
    );
    assert!(
        reader.contains("fs::read_to_string(path)")
            && reader.contains("sources.push(source)")
            && reader.contains("read explicit {label} source file"),
        "explicit source-pack loader should only read the named files and collect their source strings"
    );
    assert!(
        impl_compile.contains("load_explicit_source_pack_from_paths(stdlib_paths, user_paths)?")
            && impl_compile.contains("self.compile_source_pack_to_wasm(&sources).await"),
        "compiler method should route explicit path lists to the existing GPU source-pack WASM path"
    );
    assert!(
        public_compile.contains("load_explicit_source_pack_from_paths(stdlib_paths, user_paths)?")
            && public_compile.contains(".compile_source_pack_to_wasm(&sources)")
            && public_compile.contains("compile_explicit_source_pack_paths_to_wasm("),
        "public API should expose the explicit source-pack path surface for CLI/runtime callers"
    );
    assert!(
        impl_compile_x86
            .contains("load_explicit_source_pack_from_paths(stdlib_paths, user_paths)?")
            && impl_compile_x86.contains("self.compile_source_pack_to_x86_64(&sources).await"),
        "compiler method should route explicit path lists to the existing GPU source-pack x86 path"
    );
    assert!(
        public_compile_x86
            .contains("load_explicit_source_pack_from_paths(stdlib_paths, user_paths)?")
            && public_compile_x86.contains(".compile_source_pack_to_x86_64(&sources)")
            && public_compile_x86
                .contains("compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen"),
        "public API should expose the explicit source-pack x86 path surface for CLI/runtime callers"
    );

    for forbidden in [
        "expand_source_imports",
        "parse_source",
        "hir::parse_source",
        "type_check_explicit_source_pack",
        "record_resident_token_buffer_with_hir_items_on_gpu",
        "read_dir",
        "walkdir",
    ] {
        assert!(
            !loader.contains(forbidden)
                && !reader.contains(forbidden)
                && !impl_compile.contains(forbidden)
                && !public_compile.contains(forbidden),
            "explicit source-pack path surface must not discover imports, parse, or type-check on the host: {forbidden}"
        );
        assert!(
            !impl_compile_x86.contains(forbidden) && !public_compile_x86.contains(forbidden),
            "explicit x86 source-pack path surface must not discover imports, parse, or type-check on the host: {forbidden}"
        );
    }
}

#[test]
fn cli_explicit_source_pack_paths_are_named_file_lists() {
    let main = include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/src/main.rs"));

    assert!(
        main.contains("compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen")
            && main.contains("compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen")
            && main.contains("let mut stdlib_paths: Vec<PathBuf>")
            && main.contains("let mut inputs: Vec<PathBuf>")
            && main.contains("\"--stdlib\"")
            && main.contains("flag.starts_with(\"--stdlib=\")")
            && main.contains("stdlib_paths.push(PathBuf::from")
            && main.contains("inputs.push(PathBuf::from(path))")
            && main.contains(
                "let source_pack_requested = !stdlib_paths.is_empty() || inputs.len() > 1"
            )
            && main.contains("explicit source-pack compilation requires at least one input file")
            && !main.contains("x86_64 source-pack compilation is unavailable")
            && main.contains("&stdlib_paths")
            && main.contains("&inputs"),
        "CLI should expose explicit source-pack file lists without inventing package discovery"
    );

    assert!(
        main.contains("imports are not loaded from the filesystem")
            && !main.contains("only one input file is supported right now"),
        "CLI help/errors should describe explicit source packs instead of the old single-file-only surface"
    );

    for forbidden in [
        "read_dir",
        "walkdir",
        "canonicalize",
        "expand_source_imports",
        "load import",
        "import closure",
    ] {
        assert!(
            !main.contains(forbidden),
            "CLI source-pack handling must not discover imports or directories: {forbidden}"
        );
    }
}
