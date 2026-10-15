//! Kernel keys the compiler names but the build would not compile.
//!
//! The build compiles only shader files that contain an entry-point
//! attribute. A file the compiler names as a kernel without one (a variant
//! written as a `#define` plus an `#include` of another kernel, say) is never
//! built: graph registration then finds no reflection for it, and every
//! program fails with LNC0047 before any dispatch. The build refuses such a
//! key with `keys_without_entry_point`.

/// Whether shader source text contains an entry-point attribute.
pub(crate) fn has_entry_point_text(text: &str) -> bool {
    text.contains("[shader(")
}

/// The kernel keys among `literals` whose shader file exists but has no
/// entry point, sorted and deduplicated. `source(key)` returns the text of
/// `KEY.slang` below the shader root, or `None` when there is no such file.
/// A key names a file below a directory: top-level shader files are modules,
/// and some of their names are also kernel-key prefixes.
pub(crate) fn keys_without_entry_point<'a>(
    literals: impl IntoIterator<Item = &'a str>,
    source: impl Fn(&str) -> Option<String>,
) -> Vec<String> {
    let mut keys: Vec<String> = literals
        .into_iter()
        .filter(|&key| key.contains('/') && !key.starts_with('/') && !key.contains(".."))
        .filter(|&key| source(key).is_some_and(|text| !has_entry_point_text(&text)))
        .map(str::to_owned)
        .collect();
    keys.sort();
    keys.dedup();
    keys
}

#[cfg(test)]
mod tests {
    use super::*;

    fn source(key: &str) -> Option<String> {
        let text = match key {
            "type_checker/kernel" => "[shader(\"compute\")]\n[numthreads(256, 1, 1)]\nvoid main() {}\n",
            "type_checker/variant" => "#define FINAL 1\n#include \"kernel.slang\"\n",
            "type_checker/module" => "public uint helper() { return 0u; }\n",
            "status" => "public void record() {}\n",
            _ => return None,
        };
        Some(text.to_owned())
    }

    #[test]
    fn an_included_variant_without_its_own_entry_point_is_refused() {
        let keys = [
            "type_checker/variant",
            "type_checker/kernel",
            "type_checker/variant",
            "type_checker/missing",
        ];
        assert_eq!(keys_without_entry_point(keys, source), ["type_checker/variant"]);
    }

    #[test]
    fn modules_named_by_a_literal_are_refused_only_below_a_directory() {
        // A top-level module name is also a kernel-key prefix ("status").
        assert!(keys_without_entry_point(["status"], source).is_empty());
        assert_eq!(keys_without_entry_point(["type_checker/module"], source), ["type_checker/module"]);
        assert!(keys_without_entry_point(["/type_checker/module", "a/../type_checker/module"], source)
            .is_empty());
    }
}
