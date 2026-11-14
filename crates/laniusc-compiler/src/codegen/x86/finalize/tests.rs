//! Focused hardware tests for GPU symbol finalization.
//!
//! Fixtures and expected results are built on the CPU. Every rewrite under
//! test comes from the GPU kernels; the CPU only compares.

use std::num::NonZeroU32;

use super::*;
use crate::{
    codegen::x86::{
        GPU_X86_OBJECT_VERSION,
        GpuX86LinkInput,
        GpuX86Linker,
        GpuX86ObjectSection,
        GpuX86ObjectSymbolRecord,
        GpuX86RelocationKind,
        GpuX86RelocationRecord,
        GpuX86RelocationTargetKind,
        support::storage_u32_rw,
    },
    compiler::stable_name_hash,
};

fn words_bytes(identity: [u32; 3]) -> Vec<u8> {
    identity.into_iter().flat_map(u32::to_le_bytes).collect()
}

/// A symbol fixture: identity bytes plus definition range (None = undefined).
struct Sym {
    identity: Vec<u8>,
    defined: Option<(u32, u32)>,
}

fn undefined(identity: [u32; 3]) -> Sym {
    Sym {
        identity: words_bytes(identity),
        defined: None,
    }
}

fn defined(identity: [u32; 3], offset: u32, size: u32) -> Sym {
    Sym {
        identity: words_bytes(identity),
        defined: Some((offset, size)),
    }
}

/// Lays out symbols as the GPU object projection does: one identity range
/// per symbol, appended in symbol order.
fn object(
    library_id: u32,
    unit_id: u32,
    entry: bool,
    text: Vec<u8>,
    relocations: Vec<GpuX86RelocationRecord>,
    symbols: Vec<Sym>,
) -> GpuX86RelocatableObject {
    let mut identity_bytes = Vec::new();
    let mut rows = Vec::new();
    for symbol in symbols {
        let start = identity_bytes.len() as u32;
        let (identity_hash_lo, identity_hash_hi) = stable_name_hash(&symbol.identity);
        let (section, offset, size) = match symbol.defined {
            Some((offset, size)) => (GpuX86ObjectSection::Text, offset, size),
            None => (GpuX86ObjectSection::Undefined, 0, 0),
        };
        rows.push(GpuX86ObjectSymbolRecord {
            identity_hash_lo,
            identity_hash_hi,
            identity_byte_start: start,
            identity_byte_len: symbol.identity.len() as u32,
            section,
            offset,
            size,
            flags: 0,
        });
        identity_bytes.extend_from_slice(&symbol.identity);
    }
    let object = GpuX86RelocatableObject {
        version: GPU_X86_OBJECT_VERSION,
        library_id,
        unit_id,
        entry_offset: entry.then_some(0),
        body: None,
        text,
        rodata: b"rodata\0".to_vec(),
        relocations,
        symbols: rows,
        identity_bytes,
    };
    object.validate().expect("fixture object is valid");
    object
}

fn call(site: u32, symbol: u32) -> GpuX86RelocationRecord {
    GpuX86RelocationRecord {
        kind: GpuX86RelocationKind::CallRel32,
        site_section: GpuX86ObjectSection::Text,
        site_offset: site,
        target_kind: GpuX86RelocationTargetKind::Symbol,
        target_index: symbol,
        target_offset: 0,
        addend: -4,
    }
}

fn data_reference(site: u32) -> GpuX86RelocationRecord {
    GpuX86RelocationRecord {
        kind: GpuX86RelocationKind::Abs32,
        site_section: GpuX86ObjectSection::Text,
        site_offset: site,
        target_kind: GpuX86RelocationTargetKind::SectionOffset,
        target_index: GpuX86ObjectSection::Rodata as u32,
        target_offset: 2,
        addend: 0,
    }
}

/// Text with a call site at every fifth byte and a final `ret`.
fn call_text(calls: usize) -> Vec<u8> {
    let mut text = Vec::new();
    for _ in 0..calls {
        text.extend_from_slice(&[0xe8, 0, 0, 0, 0]);
    }
    text.extend_from_slice(&[0xb8, 1, 0, 0, 0, 0xc3]);
    text
}

const EXTERN_IDENTITY: [u32; 3] = [0x8000_0001, 0xdead_beef, 0x0102_0304];

/// Three objects in different libraries and units plus an instance batch.
///
/// Uses: 0 -> instance 0 (batch object), 1 -> DeclNative (3,0,0) in A,
/// 2 -> instance 0 again, 3 -> DeclNative (4,1,9) in B.
fn mixed_objects() -> Vec<GpuX86RelocatableObject> {
    let a = object(
        3,
        0,
        true,
        call_text(5),
        vec![
            call(1, 0),
            call(6, 1),
            call(11, 2),
            call(16, 4),
            call(21, 5),
            data_reference(26),
        ],
        vec![
            undefined(provisional_identity(0)),
            undefined(provisional_identity(2)),
            undefined([4, 1, 9]),
            defined([3, 0, 0], 25, 6),
            // A duplicated call site keeps the same use ordinal.
            undefined(provisional_identity(0)),
            undefined(EXTERN_IDENTITY),
        ],
    );
    let b = object(
        4,
        1,
        false,
        call_text(3),
        vec![call(1, 1), call(6, 2), call(11, 3)],
        vec![
            defined([4, 1, 9], 15, 6),
            undefined(provisional_identity(1)),
            undefined(provisional_identity(3)),
            undefined(instance_identity(1)),
        ],
    );
    let batch = object(
        NATIVE_RESERVED_LIBRARY,
        NATIVE_NS_INSTANCE,
        false,
        call_text(1),
        vec![call(1, 2)],
        vec![
            defined(instance_identity(0), 5, 6),
            defined(instance_identity(1), 0, 5),
            undefined([4, 1, 9]),
        ],
    );
    // Arbitrary extern identity bytes of another length stay untouched.
    let mut odd = object(
        6,
        2,
        false,
        call_text(1),
        vec![call(1, 0)],
        vec![undefined(provisional_identity(3))],
    );
    let extern_bytes = b"\x01abc\xff".to_vec();
    let (lo, hi) = stable_name_hash(&extern_bytes);
    odd.symbols.push(GpuX86ObjectSymbolRecord {
        identity_hash_lo: lo,
        identity_hash_hi: hi,
        identity_byte_start: odd.identity_bytes.len() as u32,
        identity_byte_len: extern_bytes.len() as u32,
        section: GpuX86ObjectSection::Undefined,
        offset: 0,
        size: 0,
        flags: 0,
    });
    odd.identity_bytes.extend_from_slice(&extern_bytes);
    odd.validate().expect("odd fixture");
    vec![a, b, batch, odd]
}

fn mixed_routes(generation: u32) -> Vec<[u32; 4]> {
    let route = |identity: [u32; 3]| [identity[0], identity[1], identity[2], generation];
    vec![
        route(instance_identity(0)),
        route([3, 0, 0]),
        route(instance_identity(0)),
        route([4, 1, 9]),
    ]
}

/// CPU expectation: provisional symbols take their route's identity.
fn expected(object: &GpuX86RelocatableObject, routes: &[[u32; 4]]) -> GpuX86RelocatableObject {
    let mut expected = object.clone();
    for symbol in &mut expected.symbols {
        if symbol.identity_byte_len != 12 {
            continue;
        }
        let start = symbol.identity_byte_start as usize;
        let original = &object.identity_bytes[start..start + 12];
        let words: [u32; 3] = std::array::from_fn(|i| {
            u32::from_le_bytes(original[i * 4..i * 4 + 4].try_into().unwrap())
        });
        if !is_provisional_identity(words) {
            continue;
        }
        let route = routes[words[2] as usize];
        let bytes = &mut expected.identity_bytes[start..start + 12];
        bytes.copy_from_slice(&words_bytes([route[0], route[1], route[2]]));
        (symbol.identity_hash_lo, symbol.identity_hash_hi) = stable_name_hash(bytes);
    }
    expected.validate().expect("expected object is valid");
    expected
}

struct Routes {
    routes: LaniusBuffer<u32>,
    readiness: LaniusBuffer<u32>,
    capacity: u32,
}

impl Routes {
    /// Stands in for discovery's GPU-written route table and readiness row.
    fn upload(rows: &[[u32; 4]], capacity: usize, readiness: [u32; 4]) -> Self {
        let gpu = crate::gpu::device::global();
        let routes = storage_u32_rw(
            &gpu.device,
            "test.finalize.routes",
            capacity * 4,
            wgpu::BufferUsages::empty(),
        );
        let words = rows.iter().flatten().copied().collect::<Vec<_>>();
        if !words.is_empty() {
            routes.write(&gpu.queue, 0, u32_words_bytes(&words));
        }
        let readiness_buffer = storage_u32_rw(
            &gpu.device,
            "test.finalize.readiness",
            4,
            wgpu::BufferUsages::empty(),
        );
        readiness_buffer.write(&gpu.queue, 0, u32_words_bytes(&readiness));
        Self {
            routes,
            readiness: readiness_buffer,
            capacity: capacity as u32,
        }
    }

    fn ready(rows: &[[u32; 4]], generation: u32, instances: u32) -> Self {
        Self::upload(
            rows,
            rows.len(),
            [
                generation,
                READY_ROUTES_PUBLISHED | READY_ABI_CERTIFIED,
                instances,
                rows.len() as u32,
            ],
        )
    }

    fn table(&self) -> X86RouteTable<'_> {
        X86RouteTable {
            routes: &self.routes,
            route_capacity: self.capacity,
            readiness: &self.readiness,
        }
    }
}

fn finalizer() -> GpuX86SymbolFinalizer {
    GpuX86SymbolFinalizer::new_with_device(crate::gpu::device::global()).expect("finalizer")
}

fn generation(value: u32) -> NonZeroU32 {
    NonZeroU32::new(value).unwrap()
}

fn columns(objects: &[GpuX86RelocatableObject]) -> Vec<X86SymbolColumns> {
    objects.iter().map(X86SymbolColumns::of_object).collect()
}

fn publish(
    finalizer: &GpuX86SymbolFinalizer,
    objects: &[GpuX86RelocatableObject],
    routes: &Routes,
    build: u32,
) -> Vec<GpuX86RelocatableObject> {
    let gpu = crate::gpu::device::global();
    let published = finalizer
        .finalize(
            &gpu.device,
            &gpu.queue,
            &columns(objects),
            &routes.table(),
            generation(build),
        )
        .expect("GPU finalization runs")
        .expect("GPU finalization publishes");
    objects
        .iter()
        .zip(published)
        .map(|(object, columns)| {
            let mut finalized = object.clone();
            columns
                .apply_to_object(&mut finalized)
                .expect("published columns are valid");
            finalized
        })
        .collect()
}

fn reject(
    finalizer: &GpuX86SymbolFinalizer,
    objects: &[GpuX86RelocatableObject],
    routes: &Routes,
    build: u32,
) -> X86FinalizeFailure {
    let gpu = crate::gpu::device::global();
    let inputs = columns(objects);
    let failure = finalizer
        .finalize(
            &gpu.device,
            &gpu.queue,
            &inputs,
            &routes.table(),
            generation(build),
        )
        .expect("GPU finalization runs")
        .expect_err("GPU finalization must not publish");
    assert_eq!(inputs, columns(objects), "inputs stay immutable");
    failure
}

fn assert_only_identities_changed(
    original: &GpuX86RelocatableObject,
    finalized: &GpuX86RelocatableObject,
) {
    assert_eq!(finalized.text, original.text);
    assert_eq!(finalized.rodata, original.rodata);
    assert_eq!(finalized.relocations, original.relocations);
    assert_eq!(finalized.entry_offset, original.entry_offset);
    assert_eq!(finalized.symbols.len(), original.symbols.len());
    for (index, (before, after)) in original.symbols.iter().zip(&finalized.symbols).enumerate() {
        assert_eq!(
            (
                before.identity_byte_start,
                before.identity_byte_len,
                before.section,
                before.offset,
                before.size,
                before.flags
            ),
            (
                after.identity_byte_start,
                after.identity_byte_len,
                after.section,
                after.offset,
                after.size,
                after.flags
            ),
            "symbol {index} keeps its row apart from the identity hash"
        );
        let range = before.identity_byte_start as usize
            ..(before.identity_byte_start + before.identity_byte_len) as usize;
        let identity = &original.identity_bytes[range.clone()];
        let provisional = identity.len() == 12
            && is_provisional_identity(std::array::from_fn(|i| {
                u32::from_le_bytes(identity[i * 4..i * 4 + 4].try_into().unwrap())
            }));
        if !provisional {
            assert_eq!(
                &finalized.identity_bytes[range], identity,
                "symbol {index} keeps its identity bytes"
            );
            assert_eq!(before, after, "symbol {index} keeps its row");
        }
    }
}

#[test]
fn gpu_finalization_rewrites_mixed_object_identities_and_hashes() {
    let finalizer = finalizer();
    let objects = mixed_objects();
    let rows = mixed_routes(7);
    let routes = Routes::ready(&rows, 7, 2);
    let finalized = publish(&finalizer, &objects, &routes, 7);
    for (original, finalized) in objects.iter().zip(&finalized) {
        assert_eq!(finalized, &expected(original, &rows));
        assert_only_identities_changed(original, finalized);
        // The existing object reader accepts the published columns.
        let reread = GpuX86RelocatableObject::from_bytes(&finalized.to_bytes().unwrap())
            .expect("reader accepts finalized object");
        assert_eq!(&reread, finalized);
    }
    // The linker accepts final identities and rejects provisional ones.
    let linkable = &finalized[..3];
    GpuX86LinkInput::for_executable(linkable).expect("finalized objects form link input");
    let error = GpuX86LinkInput::for_executable(&objects[..3]).unwrap_err();
    assert!(error.contains("provisional use"), "{error}");

    // Spilled originals re-upload their columns as an opaque file transfer.
    let directory = std::env::temp_dir().join(format!(
        "lanius-finalize-test-{}-{:x}",
        std::process::id(),
        rand::random::<u64>()
    ));
    std::fs::create_dir_all(&directory).unwrap();
    let path = directory.join("a.lno");
    std::fs::write(&path, objects[0].to_bytes().unwrap()).unwrap();
    let from_file = X86SymbolColumns::read_object_file(&path).expect("read spilled columns");
    std::fs::remove_dir_all(&directory).unwrap();
    assert_eq!(from_file, X86SymbolColumns::of_object(&objects[0]));
    let mut spilled = GpuX86FileObject::spill(objects[1].clone()).expect("spill object");
    assert_eq!(
        X86SymbolColumns::of_file_object(&spilled),
        X86SymbolColumns::of_object(&objects[1])
    );
    let gpu = crate::gpu::device::global();
    let published = finalizer
        .finalize(
            &gpu.device,
            &gpu.queue,
            &[from_file, X86SymbolColumns::of_file_object(&spilled)],
            &routes.table(),
            generation(7),
        )
        .unwrap()
        .unwrap();
    assert_eq!(published[0], X86SymbolColumns::of_object(&finalized[0]));
    published[1]
        .apply_to_file_object(&mut spilled)
        .expect("apply to spilled object");
    assert_eq!(spilled.symbols, finalized[1].symbols);
    assert_eq!(spilled.identity_bytes, finalized[1].identity_bytes);
}

#[test]
fn gpu_finalized_routes_link_and_execute() {
    let gpu = crate::gpu::device::global();
    let finalizer = finalizer();
    // main: eax = use0() ; ebx = eax ; eax = use1() + ebx ; exit(eax)
    let main_text = vec![
        0xe8, 0, 0, 0, 0, // call use 0
        0x89, 0xc3, // mov ebx, eax
        0xe8, 0, 0, 0, 0, // call use 1
        0x01, 0xd8, // add eax, ebx
        0x89, 0xc7, // mov edi, eax
        0xb8, 60, 0, 0, 0, // mov eax, SYS_exit
        0x0f, 0x05, // syscall
    ];
    let entry = object(
        3,
        0,
        true,
        main_text,
        vec![call(1, 0), call(8, 1)],
        vec![
            undefined(provisional_identity(0)),
            undefined(provisional_identity(1)),
        ],
    );
    let library = object(
        5,
        1,
        false,
        vec![
            0xb8, 40, 0, 0, 0, 0xc3, // DeclNative (5,1,0): return 40
            0xb8, 2, 0, 0, 0, 0xc3, // instance 0: return 2
        ],
        Vec::new(),
        vec![
            defined([5, 1, 0], 0, 6),
            defined(instance_identity(0), 6, 6),
        ],
    );
    let routes = Routes::ready(
        &[
            [5, 1, 0, 3],
            [NATIVE_RESERVED_LIBRARY, NATIVE_NS_INSTANCE, 0, 3],
        ],
        3,
        1,
    );
    let objects = [entry, library];
    let finalized = publish(&finalizer, &objects, &routes, 3);
    let linker = GpuX86Linker::new_with_device(gpu).expect("x86 linker");
    assert!(GpuX86LinkInput::for_executable(&objects).is_err());
    let input = GpuX86LinkInput::for_executable(&finalized).expect("link input");
    let executable = linker
        .link_executable(&gpu.device, &gpu.queue, &input)
        .expect("GPU link");

    let directory = std::env::temp_dir().join(format!(
        "lanius-finalize-exec-{}-{:x}",
        std::process::id(),
        rand::random::<u64>()
    ));
    std::fs::create_dir_all(&directory).unwrap();
    let path = directory.join("program");
    std::fs::write(&path, &executable).unwrap();
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o700)).unwrap();
    }
    let status = std::process::Command::new(&path)
        .status()
        .expect("run linked program");
    std::fs::remove_dir_all(&directory).unwrap();
    assert_eq!(status.code(), Some(42));
}

#[test]
fn gpu_finalization_rejects_invalid_routes_and_retries_capacity() {
    let gpu = crate::gpu::device::global();
    let finalizer = finalizer();
    let objects = mixed_objects();
    let good = mixed_routes(5);
    let ready = READY_ROUTES_PUBLISHED | READY_ABI_CERTIFIED;
    let kind_detail = |failure: X86FinalizeFailure| (failure.kind, failure.detail);

    let with_route = |use_i: usize, route: [u32; 4]| {
        let mut rows = good.clone();
        rows[use_i] = route;
        Routes::ready(&rows, 5, 2)
    };
    let cases = [
        (
            with_route(2, [NATIVE_RESERVED_LIBRARY, NATIVE_NS_INSTANCE, 0, 4]),
            (X86FinalizeFailureKind::RouteMissing, 2),
        ),
        (
            with_route(1, [NATIVE_RESERVED_LIBRARY, NATIVE_NS_INSTANCE, 2, 5]),
            (X86FinalizeFailureKind::RouteOutOfRange, 1),
        ),
        (
            with_route(3, [NATIVE_RESERVED_LIBRARY, NATIVE_NS_USE, 3, 5]),
            (X86FinalizeFailureKind::RouteToUse, 3),
        ),
        (
            with_route(0, [NATIVE_RESERVED_LIBRARY, NATIVE_NS_USE, 1, 5]),
            (X86FinalizeFailureKind::RouteToUse, 0),
        ),
        (
            with_route(1, [u32::MAX, u32::MAX, 0, 5]),
            (X86FinalizeFailureKind::RouteInvalidIdentity, 1),
        ),
        (
            with_route(2, [NATIVE_RESERVED_LIBRARY, 7, 0, 5]),
            (X86FinalizeFailureKind::RouteInvalidIdentity, 2),
        ),
        (
            Routes::upload(&good, 4, [5, READY_ROUTES_PUBLISHED, 2, 4]),
            (X86FinalizeFailureKind::Readiness, 2),
        ),
        (
            Routes::upload(&good, 4, [5, READY_ABI_CERTIFIED, 2, 4]),
            (X86FinalizeFailureKind::Readiness, 1),
        ),
        (
            Routes::upload(&good, 4, [4, ready, 2, 4]),
            (X86FinalizeFailureKind::Readiness, 0),
        ),
        (
            Routes::upload(&good, 4, [5, ready, 2, 9]),
            (X86FinalizeFailureKind::Readiness, 3),
        ),
        // Use 3 is referenced but beyond the published use count.
        (
            Routes::upload(&good, 4, [5, ready, 2, 3]),
            (X86FinalizeFailureKind::UseOutOfRange, 6 + 2),
        ),
        // A complete table must cover every use, referenced or not.
        (
            Routes::upload(&good, 5, [5, ready, 2, 5]),
            (X86FinalizeFailureKind::RouteMissing, 4),
        ),
    ];
    for (routes, expected) in &cases {
        for _ in 0..2 {
            assert_eq!(
                kind_detail(reject(&finalizer, &objects, routes, 5)),
                *expected
            );
        }
    }

    // Two failures at once: the lower failure code wins in every run.
    let mut rows = good.clone();
    rows[3] = [NATIVE_RESERVED_LIBRARY, NATIVE_NS_USE, 0, 5];
    rows[0] = [0, 0, 0, 0];
    let routes = Routes::ready(&rows, 5, 2);
    for _ in 0..3 {
        assert_eq!(
            kind_detail(reject(&finalizer, &objects, &routes, 5)),
            (X86FinalizeFailureKind::RouteMissing, 0)
        );
    }

    // A provisional identity can name only an undefined symbol.
    let mut defining = objects.clone();
    defining[0].symbols[1].section = GpuX86ObjectSection::Text;
    defining[0].symbols[1].size = 1;
    let routes = Routes::ready(&good, 5, 2);
    assert_eq!(
        kind_detail(reject(&finalizer, &defining, &routes, 5)),
        (X86FinalizeFailureKind::ProvisionalDefinition, 1)
    );
    // A corrupt provisional hash is malformed input, not a route.
    let mut corrupt = objects.clone();
    corrupt[1].symbols[2].identity_hash_lo ^= 1;
    assert_eq!(
        kind_detail(reject(&finalizer, &corrupt, &routes, 5)),
        (X86FinalizeFailureKind::SymbolMalformed, 6 + 2)
    );
    // A provisional identity whose words another symbol's bytes also cover.
    let mut overlapping = objects.clone();
    let start = overlapping[0].identity_bytes.len() as u32;
    overlapping[0]
        .identity_bytes
        .extend_from_slice(&words_bytes(provisional_identity(1)));
    overlapping[0]
        .identity_bytes
        .extend_from_slice(&0x55u32.to_le_bytes());
    for (symbol, len) in [(0usize, 12u32), (5, 16)] {
        let hash = stable_name_hash(
            &overlapping[0].identity_bytes[start as usize..(start + len) as usize],
        );
        let row = &mut overlapping[0].symbols[symbol];
        row.identity_byte_start = start;
        row.identity_byte_len = len;
        (row.identity_hash_lo, row.identity_hash_hi) = hash;
    }
    overlapping[0].validate().unwrap();
    assert_eq!(
        kind_detail(reject(&finalizer, &overlapping, &routes, 5)),
        (X86FinalizeFailureKind::IdentityOverlap, 0)
    );
    // Two symbols sharing one provisional range is one rewrite.
    let mut shared = objects.clone();
    shared[0].symbols[4].identity_byte_start = shared[0].symbols[0].identity_byte_start;
    shared[0].validate().unwrap();
    let shared_final = publish(&finalizer, &shared, &routes, 5);
    assert_eq!(shared_final[0], expected(&shared[0], &good));

    // Tiny staging reports the exact demand and publishes nothing; growing
    // it and replaying from the same inputs succeeds.
    let inputs = columns(&objects);
    finalizer.set_output_capacity(1, 1);
    let attempt = finalizer
        .finalize_once(
            &gpu.device,
            &gpu.queue,
            &inputs,
            &routes.table(),
            generation(5),
        )
        .unwrap();
    let symbol_total = objects
        .iter()
        .map(|object| object.symbols.len() as u32)
        .sum();
    let word_total = objects
        .iter()
        .map(|object| object.identity_bytes.len().div_ceil(4) as u32)
        .sum();
    assert_eq!(
        attempt,
        X86FinalizeAttempt::NeedsCapacity {
            symbols: symbol_total,
            identity_words: word_total,
        }
    );
    let finalized = publish(&finalizer, &objects, &routes, 5);
    for (original, finalized) in objects.iter().zip(&finalized) {
        assert_eq!(finalized, &expected(original, &good));
    }
}

#[test]
fn gpu_finalization_is_deterministic_across_reuse_order_and_batching() {
    let gpu = crate::gpu::device::global();
    let finalizer = finalizer();
    let objects = mixed_objects();
    let rows = mixed_routes(11);
    let routes = Routes::ready(&rows, 11, 2);
    let first = publish(&finalizer, &objects, &routes, 11);

    // An unrelated build's route table still holds build 11's rows past the
    // two uses build 12 wrote. Stale rows must not satisfy build 12.
    let unrelated = vec![object(
        8,
        0,
        true,
        call_text(2),
        vec![call(1, 0), call(6, 1)],
        vec![
            undefined(provisional_identity(0)),
            undefined(provisional_identity(1)),
        ],
    )];
    let stale = Routes::upload(
        &rows,
        4,
        [12, READY_ROUTES_PUBLISHED | READY_ABI_CERTIFIED, 2, 4],
    );
    stale
        .routes
        .write(&gpu.queue, 0, u32_words_bytes(&[9, 0, 4, 12, 9, 0, 5, 12]));
    finalizer.poison_workspace_for_test(&gpu.queue).unwrap();
    assert_eq!(
        reject(&finalizer, &unrelated, &stale, 12),
        X86FinalizeFailure {
            kind: X86FinalizeFailureKind::RouteMissing,
            detail: 2,
        }
    );
    let unrelated_routes = Routes::ready(&[[9, 0, 4, 13], [9, 0, 5, 13]], 13, 0);
    finalizer.poison_workspace_for_test(&gpu.queue).unwrap();
    let unrelated_final = publish(&finalizer, &unrelated, &unrelated_routes, 13);
    assert_eq!(
        unrelated_final[0],
        expected(&unrelated[0], &[[9, 0, 4, 13], [9, 0, 5, 13]])
    );

    // The first program again, after poisoning: identical bytes.
    finalizer.poison_workspace_for_test(&gpu.queue).unwrap();
    let routes = Routes::ready(&mixed_routes(14), 14, 2);
    let again = publish(&finalizer, &objects, &routes, 14);
    assert_eq!(again, first);

    // Batching does not change any object's result.
    let mut batched = publish(&finalizer, &objects[..1], &routes, 14);
    batched.extend(publish(&finalizer, &objects[1..3], &routes, 14));
    batched.extend(publish(&finalizer, &objects[3..], &routes, 14));
    assert_eq!(batched, first);
    let mut reversed = objects.clone();
    reversed.reverse();
    let mut reversed_final = publish(&finalizer, &reversed, &routes, 14);
    reversed_final.reverse();
    assert_eq!(reversed_final, first);

    // Symbol order does not change any symbol's final identity.
    let original = &objects[0];
    let order = [5usize, 2, 0, 4, 1, 3];
    let mut permuted = original.clone();
    permuted.symbols = order.iter().map(|&index| original.symbols[index]).collect();
    for relocation in &mut permuted.relocations {
        if relocation.target_kind == GpuX86RelocationTargetKind::Symbol {
            relocation.target_index = order
                .iter()
                .position(|&index| index == relocation.target_index as usize)
                .unwrap() as u32;
        }
    }
    let permuted_final = publish(&finalizer, &[permuted], &routes, 14).remove(0);
    let identity = |object: &GpuX86RelocatableObject, symbol: &GpuX86ObjectSymbolRecord| {
        let start = symbol.identity_byte_start as usize;
        object.identity_bytes[start..start + symbol.identity_byte_len as usize].to_vec()
    };
    for (position, &index) in order.iter().enumerate() {
        assert_eq!(
            identity(&permuted_final, &permuted_final.symbols[position]),
            identity(&first[0], &first[0].symbols[index])
        );
        assert_eq!(permuted_final.symbols[position], first[0].symbols[index]);
    }
}
