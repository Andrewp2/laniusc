//! Writes the dependency file of one compile: `--depfile PATH` on the command
//! line, or the `depfile` field of a daemon compile request.
//!
//! A build tool reads the file to decide whether the output is current. The
//! file is one JSON object:
//!
//! ```json
//! {
//!   "schema": "lanius.depfile.v1",
//!   "output": "/project/build/app",
//!   "compiler": "/usr/bin/laniusc",
//!   "sources": ["/project/src/main.lani", "/project/src/ui/button.lani"],
//!   "native_inputs": ["/usr/lib/x86_64-linux-gnu/libc.so", "/project/shim.o"],
//!   "absent_paths": ["/project/vendor/ui/button.lani"],
//!   "unlocated_native_libraries": ["gcc_s"]
//! }
//! ```
//!
//! The output is current while:
//! - `compiler`, every file in `sources` and every file in `native_inputs`
//!   is unchanged;
//! - no path in `absent_paths` exists.
//!
//! Every path is absolute, and each list is sorted and has no duplicates.
//!
//! - `output` is the file the compile wrote, or `null` for a check or for
//!   output written to standard output.
//! - `sources` holds the entry and every source file import discovery read.
//!   Modules of the embedded `core` are part of `compiler`.
//! - `absent_paths` holds every path the compiler looked up and did not find:
//!   the other places an import could have come from, and library file names
//!   in search directories ahead of the one that held the library. A file
//!   created at one of them changes which file the compile selects.
//! - `native_inputs` holds the native objects of the request and the shared
//!   libraries, archives and linker scripts that its `-l` names select. It
//!   is empty without native linking.
//! - `unlocated_native_libraries` holds the `-l` names whose files the C
//!   driver chooses (`NativeLinkDependencies::unlocated_libraries`). When it
//!   is not empty, `native_inputs` does not list every library file. The C
//!   driver's startup objects are never listed.
//!
//! The file is written after the output, to a temporary name that is then
//! renamed. A compile that fails writes nothing and leaves an earlier
//! dependency file as it was.

use std::{
    fs,
    path::{Path, PathBuf},
};

use serde_json::{Value, json};

use crate::compiler::{EntrySourceDependencies, NativeLinkOptions, native_link_dependencies};

const DEPFILE_SCHEMA: &str = "lanius.depfile.v1";

/// Writes the dependency file at `path` for a compile that wrote `output`.
/// `native_link` holds the canonical native options of a native link.
pub(super) fn write(
    path: &Path,
    output: Option<&Path>,
    sources: &EntrySourceDependencies,
    native_link: Option<&NativeLinkOptions>,
) -> Result<(), String> {
    let native = native_link.map(native_link_dependencies).unwrap_or_default();
    let mut absent_paths = sources
        .absent_paths
        .iter()
        .chain(&native.absent_paths)
        .cloned()
        .collect::<Vec<_>>();
    absent_paths.sort_unstable();
    absent_paths.dedup();
    let compiler =
        std::env::current_exe().map_err(|err| format!("find the compiler executable: {err}"))?;
    let output = match output {
        Some(output) => Value::String(text(&absolute(output)?)?),
        None => Value::Null,
    };
    let document = json!({
        "schema": DEPFILE_SCHEMA,
        "output": output,
        "compiler": text(&compiler)?,
        "sources": texts(&sources.sources)?,
        "native_inputs": texts(&native.inputs)?,
        "absent_paths": texts(&absent_paths)?,
        "unlocated_native_libraries": native.unlocated_libraries,
    });
    let mut bytes = serde_json::to_vec_pretty(&document)
        .map_err(|err| format!("encode depfile {}: {err}", path.display()))?;
    bytes.push(b'\n');
    replace_file(path, &bytes)
}

fn absolute(path: &Path) -> Result<PathBuf, String> {
    fs::canonicalize(path)
        .or_else(|_| std::path::absolute(path))
        .map_err(|err| format!("resolve {}: {err}", path.display()))
}

fn text(path: &Path) -> Result<String, String> {
    path.to_str()
        .map(str::to_owned)
        .ok_or_else(|| format!("depfile path {} is not UTF-8", path.display()))
}

fn texts(paths: &[PathBuf]) -> Result<Vec<String>, String> {
    paths.iter().map(|path| text(path)).collect()
}

/// Writes `bytes` to a temporary file beside `path` and renames it, so a
/// reader sees the earlier file or the complete new one.
fn replace_file(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let name = path
        .file_name()
        .ok_or_else(|| format!("depfile path {} names no file", path.display()))?;
    let mut temporary_name = std::ffi::OsString::from(".");
    temporary_name.push(name);
    temporary_name.push(format!(".{}.tmp", std::process::id()));
    let temporary = path.with_file_name(temporary_name);
    let written = fs::write(&temporary, bytes)
        .map_err(|err| format!("write depfile {}: {err}", temporary.display()))
        .and_then(|()| {
            fs::rename(&temporary, path)
                .map_err(|err| format!("rename depfile to {}: {err}", path.display()))
        });
    if written.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    written
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn depfile_lists_sources_absent_paths_and_native_inputs() {
        let directory = std::env::temp_dir().join(format!(
            "laniusc-depfile-{}-{}",
            std::process::id(),
            line!()
        ));
        fs::create_dir_all(&directory).expect("create depfile fixture directory");
        let object = directory.join("shim.o");
        fs::write(&object, b"not an object").expect("write native object fixture");
        let object = fs::canonicalize(&object).expect("canonical native object fixture");
        let output = directory.join("app");
        fs::write(&output, b"output").expect("write output fixture");
        let depfile = directory.join("app.deps.json");
        fs::write(&depfile, b"earlier").expect("write earlier depfile");
        let sources = EntrySourceDependencies {
            sources: vec![PathBuf::from("/project/main.lani")],
            absent_paths: vec![PathBuf::from("/project/vendor/unit.lani")],
        };
        let native = NativeLinkOptions {
            objects: vec![object.clone()],
            libraries: vec!["laniusc-depfile-test-missing".into()],
            ..NativeLinkOptions::default()
        };

        write(&depfile, Some(&output), &sources, Some(&native)).expect("write depfile");

        let document: Value =
            serde_json::from_slice(&fs::read(&depfile).expect("read depfile")).expect("parse");
        assert_eq!(document["schema"], DEPFILE_SCHEMA);
        assert_eq!(
            document["output"],
            fs::canonicalize(&output).expect("canonical output").to_str().expect("UTF-8")
        );
        assert_eq!(document["sources"], json!(["/project/main.lani"]));
        let listed = |field: &str, path: &str| {
            document[field]
                .as_array()
                .expect("a list")
                .iter()
                .any(|entry| entry == path)
        };
        assert!(listed("native_inputs", object.to_str().expect("UTF-8")));
        assert!(listed("absent_paths", "/project/vendor/unit.lani"));
        // A library that no search directory holds is looked up in each one.
        assert!(listed("absent_paths", "/usr/lib/liblaniusc-depfile-test-missing.so"));
        assert_eq!(
            document["unlocated_native_libraries"],
            json!(["laniusc-depfile-test-missing"])
        );
        // The temporary file is gone.
        let entries = fs::read_dir(&directory).expect("list fixture directory").count();
        assert_eq!(entries, 3);
        fs::remove_dir_all(&directory).expect("remove depfile fixture directory");
    }
}
