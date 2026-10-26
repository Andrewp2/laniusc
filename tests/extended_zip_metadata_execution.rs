#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command};

fn executable() -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/extended/archive_extraction/zip_metadata.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("ZIP creator metadata", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("ZIP creator metadata: {error}"));
    let executable = common::TempArtifact::new("laniusc_zip_metadata", "exe", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

// Empty stored records need no test-side CRC or compressor implementation.
// Creator words and attributes are independent raw central-directory fields.
fn archive() -> (Vec<u8>, Vec<u32>) {
    let creators = [0u16, 20, 0x0314, 0x1314, 0x0a3f, 0xff00, 0xffff, 0x03ff];
    let attributes = [
        0u32,
        0x10,
        0x81a4_0020,
        0x41ed_0010,
        0xffff_ffff,
        0x8000_0000,
        0xa1ff_0000,
        0x81a4_0020,
    ];
    let order = [6usize, 0, 4, 2, 7, 1, 5, 3];
    let mut bytes = Vec::new();
    let mut offsets = Vec::new();
    for index in 0..creators.len() {
        let name = format!("entry{index}");
        offsets.push(bytes.len() as u32);
        bytes.extend(0x0403_4b50u32.to_le_bytes());
        // Required version, flags, stored method, DOS time/date.
        for word in [10u16, 0, 0, 0, 0] {
            bytes.extend(word.to_le_bytes());
        }
        for _ in 0..3 {
            bytes.extend(0u32.to_le_bytes());
        }
        bytes.extend((name.len() as u16).to_le_bytes());
        bytes.extend(0u16.to_le_bytes());
        bytes.extend(name.as_bytes());
    }
    let directory = bytes.len() as u32;
    let mut expected = vec![20u32, 0]; // Unchanged canonical writer defaults.
    let mut rows = vec![creators.len() as u32];
    for index in order {
        let name = format!("entry{index}");
        bytes.extend(0x0201_4b50u32.to_le_bytes());
        for word in [creators[index], 10, 0, 0, 0, 0] {
            bytes.extend(word.to_le_bytes());
        }
        for _ in 0..3 {
            bytes.extend(0u32.to_le_bytes());
        }
        for word in [name.len() as u16, 0, 0, 0, 0] {
            bytes.extend(word.to_le_bytes());
        }
        bytes.extend(attributes[index].to_le_bytes());
        bytes.extend(offsets[index].to_le_bytes());
        bytes.extend(name.as_bytes());
        rows.extend([
            u32::from(creators[index]),
            attributes[index],
            offsets[index],
        ]);
    }
    let directory_size = bytes.len() as u32 - directory;
    bytes.extend(0x0605_4b50u32.to_le_bytes());
    for word in [0u16, 0, creators.len() as u16, creators.len() as u16] {
        bytes.extend(word.to_le_bytes());
    }
    bytes.extend(directory_size.to_le_bytes());
    bytes.extend(directory.to_le_bytes());
    bytes.extend(0u16.to_le_bytes());
    expected.extend_from_slice(&rows); // Packed stdin view.
    expected.extend_from_slice(&rows); // Nonzero native strided window.
    (bytes, expected)
}

#[test]
fn creator_words_and_host_attributes_survive_cursors_without_new_parse_restrictions() {
    let executable = executable();
    let (archive, expected) = archive();
    let input = common::TempArtifact::new("laniusc_zip_metadata", "input", Some("zip"));
    input.write_bytes(archive);
    let output = common::short_process_output_with_timeout(
        "ZIP creator metadata native",
        Command::new(executable.path()).stdin(std::fs::File::open(input.path()).unwrap()),
    );
    common::assert_command_success("ZIP creator metadata native", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout.len(), expected.len() * 4, "{output:?}");
    let actual: Vec<u32> = output
        .stdout
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect();
    assert_eq!(actual, expected);
}
