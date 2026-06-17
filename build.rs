fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=CARGO_TARGET_DIR");
    println!(
        "cargo:rustc-env=LANIUS_SHADER_ARTIFACT_ROOT={}",
        laniusc_shaders::artifact_root().display()
    );
}
