use proptest::prelude::*;

use super::*;
use crate::codegen::x86::{
    GPU_X86_CRT_MAIN_BRIDGE_BYTES,
    GPU_X86_OBJECT_VERSION,
    GpuX86RelocatableObject,
    GpuX86RelocationRecord,
};

const LOCAL: Identity = [1, 2, 3];
const FOREIGN: Identity = [8, 9, 10];

// Small test fixtures keep their independent byte oracle in memory; production
// accepts only file-backed inputs and writes one exported ELF file at a time.
fn export_objects(
    objects: &[GpuX86RelocatableObject],
    bindings: &[NativeCFunction],
    main: NativeMainBridge,
) -> Result<Vec<Vec<u8>>> {
    let objects = objects
        .iter()
        .cloned()
        .map(GpuX86FileObject::spill)
        .collect::<std::result::Result<Vec<_>, _>>()
        .map_err(anyhow::Error::msg)?;
    let directory = NativeTempDirectory::create()?;
    super::emit_native_elf_objects(&objects, bindings, main, &directory)?
        .into_iter()
        .map(|path| fs::read(path).map_err(anyhow::Error::from))
        .collect()
}

fn executable_object() -> GpuX86FileObject {
    // Test-only opaque payload: a C main returning 37, independent of GPU code
    // generation. Production merely transfers the admitted payload unchanged.
    GpuX86FileObject::spill(GpuX86RelocatableObject {
        version: GPU_X86_OBJECT_VERSION,
        library_id: 1,
        unit_id: 2,
        entry_offset: Some(0),
        text: [vec![0xb8, 37, 0, 0, 0, 0xc3], vec![0x90; 219]].concat(),
        rodata: vec![],
        relocations: vec![],
        symbols: vec![],
        identity_bytes: vec![],
    })
    .unwrap()
}

fn executable_bridge() -> NativeMainBridge {
    NativeMainBridge {
        object_index: 0,
        text_offset: 0,
        byte_len: GPU_X86_CRT_MAIN_BRIDGE_BYTES,
    }
}

fn bridge() -> NativeMainBridge {
    NativeMainBridge {
        object_index: 0,
        text_offset: 31,
        byte_len: GPU_X86_CRT_MAIN_BRIDGE_BYTES,
    }
}

fn binding() -> NativeCFunction {
    NativeCFunction {
        identity: FOREIGN,
        name: "native_fixture".to_owned(),
        signature: NativeCSignature {
            parameters: vec![NativeCType::Ptr, NativeCType::Usize],
            result: NativeCType::I32,
        },
    }
}

fn add_symbol(
    object: &mut GpuX86RelocatableObject,
    identity: Identity,
    section: GpuX86ObjectSection,
    offset: u32,
    size: u32,
) -> u32 {
    let identity_byte_start = object.identity_bytes.len() as u32;
    let mut bytes = Vec::new();
    for word in identity {
        bytes.extend_from_slice(&word.to_le_bytes());
    }
    let (identity_hash_lo, identity_hash_hi) = crate::compiler::stable_name_hash(&bytes);
    object.identity_bytes.extend(bytes);
    let index = object.symbols.len() as u32;
    object.symbols.push(GpuX86ObjectSymbolRecord {
        identity_hash_lo,
        identity_hash_hi,
        identity_byte_start,
        identity_byte_len: 12,
        section,
        offset,
        size,
        flags: 0,
    });
    index
}

fn object() -> GpuX86RelocatableObject {
    let mut object = GpuX86RelocatableObject {
        version: GPU_X86_OBJECT_VERSION,
        library_id: 1,
        unit_id: 2,
        entry_offset: Some(0),
        text: (0u8..=255).collect(),
        rodata: b"opaque\0bytes".to_vec(),
        relocations: vec![],
        symbols: vec![],
        identity_bytes: vec![],
    };
    add_symbol(&mut object, LOCAL, GpuX86ObjectSection::Text, 8, 8);
    let foreign = add_symbol(&mut object, FOREIGN, GpuX86ObjectSection::Undefined, 0, 0);
    object.relocations = vec![
        GpuX86RelocationRecord {
            kind: GpuX86RelocationKind::CallRel32,
            site_section: GpuX86ObjectSection::Text,
            site_offset: 1,
            target_kind: GpuX86RelocationTargetKind::Symbol,
            target_index: foreign,
            target_offset: 0,
            addend: -4,
        },
        GpuX86RelocationRecord {
            kind: GpuX86RelocationKind::Abs32,
            site_section: GpuX86ObjectSection::Text,
            site_offset: 12,
            target_kind: GpuX86RelocationTargetKind::SectionOffset,
            target_index: GpuX86ObjectSection::Rodata as u32,
            target_offset: 3,
            addend: 2,
        },
        GpuX86RelocationRecord {
            kind: GpuX86RelocationKind::Rel32,
            site_section: GpuX86ObjectSection::Rodata,
            site_offset: 0,
            target_kind: GpuX86RelocationTargetKind::Symbol,
            target_index: 0,
            target_offset: 0,
            addend: -7,
        },
    ];
    object
}

// Parse the ELF fields independently of the writer's section constants and
// helper structures. Assertions describe linker-visible metadata contracts.
struct Elf<'a> {
    bytes: &'a [u8],
    sections: BTreeMap<String, &'a [u8]>,
}
impl<'a> Elf<'a> {
    fn parse(bytes: &'a [u8]) -> Self {
        assert_eq!(&bytes[..7], b"\x7fELF\x02\x01\x01");
        assert_eq!(read16(bytes, 16), 1, "ET_REL");
        assert_eq!(read16(bytes, 18), 62, "x86_64");
        assert_eq!(
            read16(bytes, 56),
            0,
            "relocatable objects have no program headers"
        );
        let start = read64(bytes, 40) as usize;
        let stride = read16(bytes, 58) as usize;
        let count = read16(bytes, 60) as usize;
        let names_index = read16(bytes, 62) as usize;
        let names_header = &bytes[start + stride * names_index..start + stride * (names_index + 1)];
        let names = section_bytes(bytes, names_header);
        let mut sections = BTreeMap::new();
        for index in 1..count {
            let header = &bytes[start + stride * index..start + stride * (index + 1)];
            let name = string(names, read32(header, 0) as usize).to_owned();
            sections.insert(name, header);
        }
        Self { bytes, sections }
    }
    fn header(&self, name: &str) -> &'a [u8] {
        self.sections[name]
    }
    fn section(&self, name: &str) -> &'a [u8] {
        section_bytes(self.bytes, self.header(name))
    }
    fn symbols(&self) -> Vec<(&'a str, &'a [u8])> {
        let names = self.section(".strtab");
        self.section(".symtab")
            .chunks_exact(24)
            .map(|row| (string(names, read32(row, 0) as usize), row))
            .collect()
    }
}
fn section_bytes<'a>(bytes: &'a [u8], header: &[u8]) -> &'a [u8] {
    let start = read64(header, 24) as usize;
    &bytes[start..start + read64(header, 32) as usize]
}
fn string(bytes: &[u8], start: usize) -> &str {
    let length = bytes[start..].iter().position(|byte| *byte == 0).unwrap();
    std::str::from_utf8(&bytes[start..start + length]).unwrap()
}
fn read16(bytes: &[u8], offset: usize) -> u16 {
    u16::from_le_bytes(bytes[offset..offset + 2].try_into().unwrap())
}
fn read32(bytes: &[u8], offset: usize) -> u32 {
    u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap())
}
fn read64(bytes: &[u8], offset: usize) -> u64 {
    u64::from_le_bytes(bytes[offset..offset + 8].try_into().unwrap())
}

#[test]
fn elf_preserves_payload_and_exports_sized_symbols_and_explicit_bridge() {
    let object = object();
    let outputs = export_objects(std::slice::from_ref(&object), &[binding()], bridge()).unwrap();
    let elf = Elf::parse(&outputs[0]);
    assert_eq!(elf.section(".text"), object.text);
    assert_eq!(elf.section(".rodata"), object.rodata);
    assert_eq!(
        read64(elf.header(".text"), 8),
        6,
        "allocatable executable text"
    );
    assert_eq!(read64(elf.header(".rodata"), 8), 2, "read-only data");
    assert_eq!(
        read64(elf.header(".note.GNU-stack"), 8),
        0,
        "no executable stack request"
    );
    let symbols = elf.symbols();
    let (_, function) = symbols
        .iter()
        .find(|(name, _)| *name == "__lanius_1_2_3")
        .unwrap();
    assert_eq!(function[4], 0x12, "global function");
    assert_eq!(read16(function, 6), 1);
    assert_eq!(read64(function, 8), 8);
    assert_eq!(read64(function, 16), 8);
    let (_, main) = symbols.iter().find(|(name, _)| *name == "main").unwrap();
    assert_eq!(read64(main, 8), bridge().text_offset as u64);
    assert_eq!(read64(main, 16), bridge().byte_len as u64);
    let (_, foreign) = symbols
        .iter()
        .find(|(name, _)| *name == "native_fixture")
        .unwrap();
    assert_eq!(
        read16(foreign, 6),
        0,
        "undefined C function resolved by the native linker"
    );
    assert_eq!(
        read32(elf.header(".symtab"), 44),
        3,
        "only null and two section symbols are local"
    );
}

#[test]
fn elf_relocations_retain_sites_targets_addends_and_section_links() {
    let outputs = export_objects(&[object()], &[binding()], bridge()).unwrap();
    let elf = Elf::parse(&outputs[0]);
    let symbols = elf.symbols();
    let text = elf.section(".rela.text");
    assert_eq!(text.len(), 48);
    assert_eq!(read64(text, 0), 1);
    let info = read64(text, 8);
    assert_eq!(
        info as u32, 4,
        "PLT32 lets the linker create a shared-library call stub"
    );
    assert_eq!(symbols[(info >> 32) as usize].0, "native_fixture");
    assert_eq!(read64(text, 16) as i64, -4);
    assert_eq!(read64(text, 24), 12);
    assert_eq!(read64(text, 32) as u32, 10, "32-bit absolute address field");
    assert_eq!(read64(text, 32) >> 32, 2, "rodata section symbol");
    assert_eq!(
        read64(text, 40) as i64,
        5,
        "section offset contributes to addend"
    );
    let rodata = elf.section(".rela.rodata");
    assert_eq!(read64(rodata, 8) as u32, 2, "PC32");
    assert_eq!(
        symbols[(read64(rodata, 8) >> 32) as usize].0,
        "__lanius_1_2_3"
    );
    assert_eq!(read64(rodata, 16) as i64, -7);
    assert_eq!(
        read32(elf.header(".rela.text"), 40),
        5,
        "relocations link to symtab"
    );
    assert_eq!(
        read32(elf.header(".rela.text"), 44),
        1,
        "relocations apply to text"
    );
    assert_eq!(
        read32(elf.header(".rela.rodata"), 44),
        2,
        "relocations apply to rodata"
    );
}

#[test]
fn repeated_call_records_share_one_symbol_and_local_definition_resolves_across_objects() {
    let mut consumer = object();
    let repeated = add_symbol(&mut consumer, FOREIGN, GpuX86ObjectSection::Undefined, 0, 0);
    let mut relocation = consumer.relocations[0];
    relocation.target_index = repeated;
    relocation.site_offset = 24;
    consumer.relocations.push(relocation);
    let mut provider = object();
    provider.entry_offset = None;
    provider.symbols.clear();
    provider.relocations.clear();
    add_symbol(&mut provider, FOREIGN, GpuX86ObjectSection::Text, 0, 8);
    let outputs = export_objects(&[consumer, provider], &[], bridge()).unwrap();
    let consumer_elf = Elf::parse(&outputs[0]);
    assert_eq!(
        consumer_elf
            .symbols()
            .iter()
            .filter(|(name, _)| *name == "__lanius_8_9_10")
            .count(),
        1
    );
    let records = consumer_elf.section(".rela.text");
    assert_eq!(
        read64(records, 8),
        read64(records, 56),
        "both call records refer to the same ELF symbol"
    );
    let provider_elf = Elf::parse(&outputs[1]);
    assert!(
        !provider_elf
            .symbols()
            .iter()
            .any(|(name, _)| *name == "main")
    );
    assert!(
        provider_elf
            .symbols()
            .iter()
            .any(|(name, row)| *name == "__lanius_8_9_10" && read16(row, 6) == 1)
    );
}

#[test]
fn foreign_aliases_require_identical_checked_signatures() {
    let first = binding();
    let mut second = first.clone();
    second.identity[2] += 1;
    export_objects(&[object()], &[first.clone(), second.clone()], bridge()).unwrap();
    second.signature.result = NativeCType::Ptr;
    let error = export_objects(&[object()], &[first, second], bridge()).unwrap_err();
    assert!(
        error.to_string().contains("conflicting checked signatures"),
        "{error:#}"
    );
}

#[test]
fn rejects_unbound_symbols_duplicate_definitions_and_conflicting_bindings() {
    let error = export_objects(&[object()], &[], bridge()).unwrap_err();
    assert!(
        error
            .to_string()
            .contains("no Lanius definition or checked foreign binding")
    );
    let first = object();
    let mut second = first.clone();
    second.entry_offset = None;
    let error = export_objects(&[first, second], &[binding()], bridge()).unwrap_err();
    assert!(error.to_string().contains("defined more than once"));
    let mut conflict = binding();
    conflict.identity = LOCAL;
    let error = export_objects(&[object()], &[binding(), conflict], bridge()).unwrap_err();
    assert!(
        error
            .to_string()
            .contains("both a Lanius definition and a foreign binding")
    );
    let mut conflict = binding();
    conflict.name.push('_');
    let error = export_objects(&[object()], &[binding(), conflict], bridge()).unwrap_err();
    assert!(error.to_string().contains("conflicting bindings"));
}

#[test]
fn rejects_invalid_bridge_ranges_names_and_parameter_shapes() {
    for invalid in [
        NativeMainBridge {
            object_index: 1,
            ..bridge()
        },
        NativeMainBridge {
            byte_len: 0,
            ..bridge()
        },
        NativeMainBridge {
            text_offset: u32::MAX,
            ..bridge()
        },
        NativeMainBridge {
            text_offset: 30,
            ..bridge()
        },
        NativeMainBridge {
            text_offset: 0,
            byte_len: 1,
            ..bridge()
        },
        NativeMainBridge {
            byte_len: GPU_X86_CRT_MAIN_BRIDGE_BYTES - 1,
            ..bridge()
        },
    ] {
        assert!(export_objects(&[object()], &[binding()], invalid).is_err());
    }
    for name in [
        "",
        "main",
        "__lanius_1_2_3",
        "x\0y",
        "native@VERSION",
        "1native",
    ] {
        let mut invalid = binding();
        invalid.name = name.to_owned();
        assert!(
            export_objects(&[object()], &[invalid], bridge()).is_err(),
            "{name:?}"
        );
    }
    let mut invalid = binding();
    invalid.signature.parameters = vec![NativeCType::Void];
    assert!(export_objects(&[object()], &[invalid], bridge()).is_err());
    let mut stack_arguments = binding();
    stack_arguments.signature.parameters = vec![NativeCType::U64; 32];
    export_objects(&[object()], &[stack_arguments.clone()], bridge()).unwrap();
    stack_arguments.signature.parameters.push(NativeCType::U64);
    assert!(export_objects(&[object()], &[stack_arguments], bridge()).is_err());
}

#[test]
fn rejects_relocation_addend_overflow_without_patching_bytes() {
    let mut object = object();
    object.relocations[1].addend = i64::MAX;
    let error = export_objects(&[object], &[binding()], bridge()).unwrap_err();
    assert!(format!("{error:#}").contains("relocation addend overflows"));
}

#[test]
fn native_link_options_reject_shell_arguments_and_unbounded_work() {
    validate_options(&NativeLinkOptions::default()).unwrap();
    for name in [
        "",
        "-lcrypto",
        "crypto;echo",
        "crypto/../../evil",
        "crypto:archive.a",
        "crypto\0",
    ] {
        let options = NativeLinkOptions {
            libraries: vec![name.to_owned()],
            ..Default::default()
        };
        assert!(validate_options(&options).is_err(), "{name:?}");
    }
    for name in ["crypto", "sqlite3", "stdc++", "name-1.2"] {
        validate_options(&NativeLinkOptions {
            libraries: vec![name.to_owned()],
            ..Default::default()
        })
        .unwrap();
    }
    for linker in ["", "./cc", "dir/cc", "../cc"] {
        assert!(
            validate_options(&NativeLinkOptions {
                linker: Some(PathBuf::from(linker)),
                ..Default::default()
            })
            .is_err()
        );
    }
    for timeout in [Duration::ZERO, Duration::from_secs(121)] {
        assert!(
            validate_options(&NativeLinkOptions {
                timeout,
                ..Default::default()
            })
            .is_err()
        );
    }
    assert!(
        validate_options(&NativeLinkOptions {
            max_output_bytes: 0,
            ..Default::default()
        })
        .is_err()
    );
    assert!(
        validate_options(&NativeLinkOptions {
            objects: vec![PathBuf::from("relative.o")],
            ..Default::default()
        })
        .is_err()
    );
    assert!(
        validate_options(&NativeLinkOptions {
            library_paths: vec![PathBuf::from("relative")],
            ..Default::default()
        })
        .is_err()
    );
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]
    #[test]
    fn elf_packaging_preserves_arbitrary_gpu_bytes(
        text in prop::collection::vec(any::<u8>(), 225..512),
        rodata in prop::collection::vec(any::<u8>(), 4..256),
    ) {
        let mut object = object();
        object.text = text.clone();
        object.rodata = rodata.clone();
        // Keep the fixed section-relative target in range for every generated
        // rodata input; all instruction bytes remain intentionally opaque.
        let main = NativeMainBridge {
            text_offset: text.len() as u32 - GPU_X86_CRT_MAIN_BRIDGE_BYTES,
            ..bridge()
        };
        let outputs = export_objects(&[object], &[binding()], main).unwrap();
        let elf = Elf::parse(&outputs[0]);
        prop_assert_eq!(elf.section(".text"), text.as_slice());
        prop_assert_eq!(elf.section(".rodata"), rodata.as_slice());
        for header in elf.sections.values() {
            let align = read64(header, 48);
            prop_assert!(align == 0 || read64(header, 24) % align == 0);
        }
    }
}

#[test]
fn invalid_late_metadata_rejects_before_any_elf_file_is_written() {
    let first = executable_object();
    let mut bad = object();
    bad.entry_offset = None;
    let bad = GpuX86FileObject::spill(bad).unwrap();
    let directory = NativeTempDirectory::create().unwrap();
    let error = super::emit_native_elf_objects(&[first, bad], &[], executable_bridge(), &directory)
        .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("no Lanius definition or checked foreign binding")
    );
    assert_eq!(fs::read_dir(&directory.path).unwrap().count(), 0);
    let mut malformed = executable_object();
    malformed.layout.text_byte_len += 1;
    assert!(
        super::emit_native_elf_objects(&[malformed], &[], executable_bridge(), &directory).is_err()
    );
    assert_eq!(fs::read_dir(&directory.path).unwrap().count(), 0);
}

#[test]
fn guarded_output_rejects_changed_or_oversized_files_before_transfer() {
    let directory = NativeTempDirectory::create().unwrap();
    let path = directory.path.join("program");
    write_private_file(&path, b"data").unwrap();
    let output = NativeLinkedExecutable {
        directory,
        byte_len: 4,
        max_output_bytes: 4,
    };
    assert_eq!(output.read_bytes(4).unwrap(), b"data");
    assert!(output.read_bytes(3).is_err());
    let mut copied = vec![];
    assert_eq!(output.write_to(&mut copied).unwrap(), 4);
    assert_eq!(copied, b"data");
    for changed in [b"grown".as_slice(), b"x".as_slice(), b"".as_slice()] {
        fs::write(&path, changed).unwrap();
        let mut destination = b"prior destination".to_vec();
        assert!(output.write_to(&mut destination).is_err());
        assert_eq!(destination, b"prior destination");
        assert!(output.read_bytes(4).is_err());
    }
    let directory_path = output.directory.path.clone();
    drop(output);
    assert!(!directory_path.exists());
}

#[test]
fn guarded_copy_never_exceeds_admitted_length_if_output_grows_during_transfer() {
    struct GrowingWriter {
        path: PathBuf,
        bytes: Vec<u8>,
    }
    impl Write for GrowingWriter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            fs::OpenOptions::new()
                .append(true)
                .open(&self.path)?
                .write_all(b"growth")?;
            self.bytes.extend_from_slice(bytes);
            Ok(bytes.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    let directory = NativeTempDirectory::create().unwrap();
    let path = directory.path.join("program");
    write_private_file(&path, b"data").unwrap();
    let output = NativeLinkedExecutable {
        directory,
        byte_len: 4,
        max_output_bytes: 4,
    };
    let mut destination = GrowingWriter {
        path,
        bytes: vec![],
    };
    assert!(output.write_to(&mut destination).is_err());
    assert_eq!(destination.bytes, b"data");
}

#[test]
fn response_writer_checks_limits_before_writing_an_argument() {
    let directory = NativeTempDirectory::create().unwrap();
    let path = directory.path.join("bounded.rsp");
    let mut response = LinkResponse {
        file: BufWriter::new(create_private_file(&path).unwrap()),
        byte_len: MAX_RESPONSE_BYTES - 3,
    };
    assert!(response.argument("x".as_ref()).is_err());
    assert_eq!(response.byte_len, MAX_RESPONSE_BYTES - 3);
    response.file.flush().unwrap();
    assert_eq!(fs::metadata(path).unwrap().len(), 0);
}

#[test]
fn system_cc_links_streamed_objects_and_enforces_the_output_limit() {
    let object = executable_object();
    let options = NativeLinkOptions::default();
    let output = link_native_file_executable(
        std::slice::from_ref(&object),
        &[],
        executable_bridge(),
        &options,
    )
    .unwrap();
    let copied = output.read_bytes(options.max_output_bytes).unwrap();
    assert_eq!(&copied[..4], b"\x7fELF");
    let status = Command::new(output.directory.path.join("program"))
        .status()
        .unwrap();
    assert_eq!(status.code(), Some(37));
    let error = match link_native_file_executable(
        &[object],
        &[],
        executable_bridge(),
        &NativeLinkOptions {
            max_output_bytes: 1,
            ..options
        },
    ) {
        Ok(_) => panic!("one-byte native output limit admitted an ELF"),
        Err(error) => error,
    };
    assert!(
        error.to_string().contains("output limit") || error.to_string().contains("admitted range"),
        "{error:#}"
    );
}

#[test]
fn actual_cc_response_grammar_preserves_quotes_backslashes_whitespace_and_many_paths() {
    let directory = NativeTempDirectory::create().unwrap();
    let source = directory.path.join("main.c");
    fs::write(&source, "int main(void) { return 19; }\n").unwrap();
    let main_object = directory.path.join("main.o");
    let status = Command::new("cc")
        .arg("-c")
        .arg(&source)
        .arg("-o")
        .arg(&main_object)
        .status()
        .unwrap();
    assert!(status.success());
    let mut nested = directory.path.clone();
    for index in 0..4 {
        nested.push(format!("{index} {}", "q".repeat(220)));
    }
    fs::create_dir_all(&nested).unwrap();
    let empty_object = nested.join("@empty \" quote ' slash\\ tab\t line\n.o");
    fs::write(&source, "/* no global symbols */\n").unwrap();
    let status = Command::new("cc")
        .arg("-c")
        .arg(&source)
        .arg("-o")
        .arg(&empty_object)
        .status()
        .unwrap();
    assert!(status.success());
    let options = NativeLinkOptions {
        objects: vec![empty_object; 4096],
        ..Default::default()
    };
    validate_options(&options).unwrap();
    let output = directory.path.join("program \" quote \\ tab\t line\n");
    let response = directory.path.join("inputs.rsp");
    write_link_response(&options, &[main_object], &output, &response).unwrap();
    assert!(fs::metadata(&response).unwrap().len() > 2 * 1024 * 1024);
    let status = link_command(&options, &response).unwrap().status().unwrap();
    assert!(status.success());
    assert_eq!(Command::new(&output).status().unwrap().code(), Some(19));
}

#[test]
fn diagnostic_collector_bounds_the_spool_before_writing_excess() {
    let directory = NativeTempDirectory::create().unwrap();
    let path = directory.path.join("stderr");
    let overflow = AtomicBool::new(false);
    collect_diagnostics(
        std::io::Cursor::new(vec![b'x'; MAX_DIAGNOSTIC_BYTES as usize * 3]),
        create_private_file(&path).unwrap(),
        &overflow,
    )
    .unwrap();
    assert!(overflow.load(Ordering::Relaxed));
    assert_eq!(fs::metadata(&path).unwrap().len(), MAX_DIAGNOSTIC_BYTES);
    assert_eq!(
        fs::read(path).unwrap(),
        vec![b'x'; MAX_DIAGNOSTIC_BYTES as usize]
    );
}

fn fake_driver(directory: &NativeTempDirectory, body: &str) -> NativeLinkOptions {
    use std::os::unix::fs::PermissionsExt;
    let path = directory.path.join("driver");
    write_private_file(&path, format!("#!/bin/sh\n{body}").as_bytes()).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).unwrap();
    NativeLinkOptions {
        linker: Some(path),
        timeout: Duration::from_secs(2),
        ..Default::default()
    }
}

#[test]
fn diagnostic_flood_ends_the_driver_at_the_spool_limit() {
    let directory = NativeTempDirectory::create().unwrap();
    let options = fake_driver(
        &directory,
        "while :; do printf 'diagnostic diagnostic diagnostic diagnostic diagnostic\\n' >&2; done\n",
    );
    let error = match link_native_file_executable(
        &[executable_object()],
        &[],
        executable_bridge(),
        &options,
    ) {
        Ok(_) => panic!("unbounded linker diagnostic flood was admitted"),
        Err(error) => error,
    };
    assert!(
        error.to_string().contains("diagnostics exceeded"),
        "{error:#}"
    );
}

#[test]
fn nonzero_driver_exit_terminates_descendants_holding_stderr_open() {
    let directory = NativeTempDirectory::create().unwrap();
    let options = fake_driver(
        &directory,
        "sleep 30 &\nprintf '%s' \"$!\" > \"$(dirname \"$0\")/descendant.pid\"\nexit 7\n",
    );
    let started = Instant::now();
    let error = match link_native_file_executable(
        &[executable_object()],
        &[],
        executable_bridge(),
        &options,
    ) {
        Ok(_) => panic!("nonzero fake linker was admitted"),
        Err(error) => error,
    };
    assert!(
        error.to_string().contains("native C linker failed"),
        "{error:#}"
    );
    assert!(started.elapsed() < Duration::from_secs(2));
    let pid = fs::read_to_string(directory.path.join("descendant.pid")).unwrap();
    let process = PathBuf::from(format!("/proc/{pid}/stat"));
    let deadline = Instant::now() + Duration::from_secs(1);
    loop {
        let running = fs::read_to_string(&process).is_ok_and(|stat| {
            !matches!(
                stat.rsplit_once(") ").unwrap().1.split_whitespace().next(),
                Some("Z" | "X")
            )
        });
        if !running {
            break;
        }
        assert!(
            Instant::now() < deadline,
            "linker descendant {pid} survived its failed driver"
        );
        thread::sleep(Duration::from_millis(2));
    }
}
