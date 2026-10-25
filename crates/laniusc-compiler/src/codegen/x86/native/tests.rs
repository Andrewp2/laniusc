use proptest::prelude::*;

use super::*;
use crate::codegen::x86::{GPU_X86_OBJECT_VERSION, GpuX86RelocationRecord};

const LOCAL: Identity = [1, 2, 3];
const FOREIGN: Identity = [8, 9, 10];

fn bridge() -> NativeMainBridge {
    NativeMainBridge {
        object_index: 0,
        text_offset: 16,
        byte_len: 4,
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
        text: (0u8..32).collect(),
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
    let outputs =
        emit_native_elf_objects(std::slice::from_ref(&object), &[binding()], bridge()).unwrap();
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
    let outputs = emit_native_elf_objects(&[object()], &[binding()], bridge()).unwrap();
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
    let outputs = emit_native_elf_objects(&[consumer, provider], &[], bridge()).unwrap();
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
    emit_native_elf_objects(&[object()], &[first.clone(), second.clone()], bridge()).unwrap();
    second.signature.result = NativeCType::Ptr;
    let error = emit_native_elf_objects(&[object()], &[first, second], bridge()).unwrap_err();
    assert!(
        error.to_string().contains("conflicting checked signatures"),
        "{error:#}"
    );
}

#[test]
fn rejects_unbound_symbols_duplicate_definitions_and_conflicting_bindings() {
    let error = emit_native_elf_objects(&[object()], &[], bridge()).unwrap_err();
    assert!(
        error
            .to_string()
            .contains("no Lanius definition or checked foreign binding")
    );
    let first = object();
    let mut second = first.clone();
    second.entry_offset = None;
    let error = emit_native_elf_objects(&[first, second], &[binding()], bridge()).unwrap_err();
    assert!(error.to_string().contains("defined more than once"));
    let mut conflict = binding();
    conflict.identity = LOCAL;
    let error = emit_native_elf_objects(&[object()], &[binding(), conflict], bridge()).unwrap_err();
    assert!(
        error
            .to_string()
            .contains("both a Lanius definition and a foreign binding")
    );
    let mut conflict = binding();
    conflict.name.push('_');
    let error = emit_native_elf_objects(&[object()], &[binding(), conflict], bridge()).unwrap_err();
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
    ] {
        assert!(emit_native_elf_objects(&[object()], &[binding()], invalid).is_err());
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
            emit_native_elf_objects(&[object()], &[invalid], bridge()).is_err(),
            "{name:?}"
        );
    }
    let mut invalid = binding();
    invalid.signature.parameters = vec![NativeCType::Void];
    assert!(emit_native_elf_objects(&[object()], &[invalid], bridge()).is_err());
    let mut stack_arguments = binding();
    stack_arguments.signature.parameters = vec![NativeCType::U64; 32];
    emit_native_elf_objects(&[object()], &[stack_arguments.clone()], bridge()).unwrap();
    stack_arguments.signature.parameters.push(NativeCType::U64);
    assert!(emit_native_elf_objects(&[object()], &[stack_arguments], bridge()).is_err());
}

#[test]
fn rejects_relocation_addend_overflow_without_patching_bytes() {
    let mut object = object();
    object.relocations[1].addend = i64::MAX;
    let error = emit_native_elf_objects(&[object], &[binding()], bridge()).unwrap_err();
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
        text in prop::collection::vec(any::<u8>(), 20..256),
        rodata in prop::collection::vec(any::<u8>(), 4..256),
    ) {
        let mut object = object();
        object.text = text.clone();
        object.rodata = rodata.clone();
        // Keep the fixed section-relative target in range for every generated
        // rodata input; all instruction bytes remain intentionally opaque.
        let outputs = emit_native_elf_objects(&[object], &[binding()], bridge()).unwrap();
        let elf = Elf::parse(&outputs[0]);
        prop_assert_eq!(elf.section(".text"), text.as_slice());
        prop_assert_eq!(elf.section(".rodata"), rodata.as_slice());
        for header in elf.sections.values() {
            let align = read64(header, 48);
            prop_assert!(align == 0 || read64(header, 24) % align == 0);
        }
    }
}
