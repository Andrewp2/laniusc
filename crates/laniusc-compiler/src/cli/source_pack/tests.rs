use std::{
    env,
    fs,
    time::{SystemTime, UNIX_EPOCH},
};

use super::{
    DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS,
    DEFAULT_SOURCE_PACK_MAX_ITEMS,
    DEFAULT_SOURCE_PACK_MAX_READY_ITEMS,
    DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES,
    DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES,
    Options,
    artifacts::has_prepared_build,
    build_max_items,
    compile_direct,
    compile_from_metadata,
    compile_library_manifest,
    compile_manifest,
    manifest,
    max_items,
    max_ready_items,
    metadata_max_libraries,
    metadata_max_source_files,
    prepare_build_from_metadata_chunk_only,
    prepare_inputs_chunk_only,
    prepare_metadata_only,
};
use crate::{codegen::unit::SourcePackArtifactTarget, compiler::FilesystemArtifactStore};

#[test]
fn source_pack_metadata_only_stores_persisted_library_records() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-metadata-only-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    fs::create_dir_all(&source_root).expect("create source dir");
    fs::write(source_root.join("core.lani"), "let core = 1;\n").expect("write source");
    fs::write(source_root.join("app.lani"), "let app = 2;\n").expect("write source");
    fs::write(
        root.join("core.paths"),
        format!("{}\n", source_root.join("core.lani").display()),
    )
    .expect("write core path list");
    fs::write(
        root.join("app.paths"),
        format!("{}\n", source_root.join("app.lani").display()),
    )
    .expect("write app path list");
    let manifest_path = root.join("libraries.jsonl");
    fs::write(
            &manifest_path,
            concat!(
                "{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"core.paths\"}\n",
                "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"app.paths\",\"dependency_library_ids\":[1]}\n",
            ),
        )
        .expect("write library manifest");

    let mut source_pack = Options::default();
    source_pack.library_manifest = Some(manifest_path);
    source_pack.metadata_only = true;
    source_pack.artifact_root = Some(artifact_root.clone());
    prepare_metadata_only("wasm", &[], &[], &source_pack).expect("prepare metadata only");

    let store = FilesystemArtifactStore::new(&artifact_root);
    assert!(
        store
            .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    assert!(
        !store
            .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "metadata-only phase must not prepare the work queue build state"
    );

    let library_manifest_path = source_pack
        .library_manifest
        .as_ref()
        .expect("test source pack should keep a library manifest path")
        .clone();
    fs::remove_file(&library_manifest_path).expect("remove library manifest after metadata");
    fs::remove_dir_all(&source_root).expect("remove source files after metadata");
    prepare_metadata_only("wasm", &[], &[], &source_pack)
        .expect("metadata-only rerun should reuse the completed persisted metadata marker");

    fs::remove_dir_all(&root).expect("remove temp metadata-only root");
}

#[test]
fn source_pack_metadata_only_library_manifest_defaults_to_bounded_chunk() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-metadata-only-default-chunk-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    fs::create_dir_all(&source_root).expect("create source dir");

    let mut manifest = String::new();
    for index in 0..DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES {
        let library_id = (index + 1) as u32;
        let source_file_name = format!("lib_{library_id}.lani");
        let source_path = source_root.join(&source_file_name);
        fs::write(
            &source_path,
            format!("let lib_{library_id} = {library_id};\n"),
        )
        .expect("write source");
        let path_list_name = format!("lib_{library_id}.paths");
        fs::write(
            root.join(&path_list_name),
            format!("{}\n", source_path.display()),
        )
        .expect("write path list");
        manifest.push_str(&format!(
                "{{\"library_id\":{library_id},\"source_file_count\":1,\"path_list\":\"{path_list_name}\"}}\n"
            ));
    }
    manifest.push_str(&format!(
        "{{\"library_id\":{},\"source_file_count\":1,\"path_list\":\"missing-later.paths\"}}\n",
        DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES + 1
    ));
    let manifest_path = root.join("libraries.jsonl");
    fs::write(&manifest_path, manifest).expect("write library manifest");

    let mut source_pack = Options::default();
    source_pack.library_manifest = Some(manifest_path);
    source_pack.metadata_only = true;
    source_pack.artifact_root = Some(artifact_root.clone());

    prepare_metadata_only("wasm", &[], &[], &source_pack)
        .expect("metadata-only should stop after the default bounded chunk");

    let store = FilesystemArtifactStore::new(&artifact_root);
    assert!(
        store
            .library_partition_path_for_target(
                SourcePackArtifactTarget::Wasm,
                DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES - 1
            )
            .is_file()
    );
    assert!(
        !store
            .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "metadata-only must leave a later library manifest entry for a future chunk"
    );
    let progress_path = manifest::progress_path(&artifact_root, SourcePackArtifactTarget::Wasm);
    let progress = serde_json::from_slice::<manifest::Progress>(
        &fs::read(&progress_path).expect("read manifest progress"),
    )
    .expect("parse manifest progress");
    assert_eq!(
        progress.library_count,
        DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES
    );

    fs::remove_dir_all(&root).expect("remove temp metadata-only default chunk root");
}

#[test]
fn source_pack_library_manifest_reader_rejects_overlong_records() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-library-manifest-line-cap-test-{}-{suffix}",
        std::process::id()
    ));
    fs::create_dir_all(&root).expect("create line cap root");
    let manifest_path = root.join("libraries.jsonl");
    let overlong_path = "x".repeat(manifest::LIBRARY_MANIFEST_MAX_LINE_BYTES);
    fs::write(
        &manifest_path,
        format!("{{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"{overlong_path}\"}}\n"),
    )
    .expect("write overlong library manifest record");

    let chunk_err = match manifest::load_entries_chunk_from_offset(&manifest_path, 0, 1, 1) {
        Ok(_) => panic!("chunked manifest reader should reject an overlong record"),
        Err(err) => err,
    };
    assert!(
        chunk_err.contains("exceeds line byte limit"),
        "unexpected overlong chunk error: {chunk_err}"
    );

    let progress_err = manifest::offset_after_entry_count(&manifest_path, 1)
        .expect_err("progress replay should reject an overlong record");
    assert!(
        progress_err.contains("exceeds line byte limit"),
        "unexpected overlong progress error: {progress_err}"
    );

    fs::remove_dir_all(&root).expect("remove line cap root");
}

#[test]
fn source_pack_path_list_reader_rejects_overlong_records() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-path-list-line-cap-test-{}-{suffix}",
        std::process::id()
    ));
    fs::create_dir_all(&root).expect("create path-list line cap root");
    let path_list = root.join("library.paths");
    let overlong_path = "x".repeat(manifest::PATH_LIST_MAX_LINE_BYTES);
    fs::write(&path_list, format!("{overlong_path}\n")).expect("write overlong path list");

    let message = manifest::load_path_list(&path_list, 1)
        .expect_err("path-list reader should reject an overlong path record");
    assert!(
        message.contains("exceeds line byte limit"),
        "unexpected overlong path-list error: {message}"
    );

    fs::remove_dir_all(&root).expect("remove path-list line cap root");
}

#[test]
fn source_pack_stream_readers_reject_unbounded_blank_records() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-stream-blank-cap-test-{}-{suffix}",
        std::process::id()
    ));
    fs::create_dir_all(&root).expect("create blank cap root");

    let blank_manifest_prefix =
        "\n".repeat(manifest::LIBRARY_MANIFEST_MAX_BLANK_LINES_PER_CHUNK + 1);
    let manifest_path = root.join("libraries.jsonl");
    fs::write(
            &manifest_path,
            format!(
                "{blank_manifest_prefix}{{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"library.paths\"}}\n"
            ),
        )
        .expect("write blank-heavy library manifest");

    let chunk_err = match manifest::load_entries_chunk_from_offset(&manifest_path, 0, 1, 1) {
        Ok(_) => panic!("manifest chunk reader should reject too many blank records"),
        Err(err) => err,
    };
    assert!(
        chunk_err.contains("blank lines"),
        "unexpected manifest blank chunk error: {chunk_err}"
    );

    let progress_err = manifest::offset_after_entry_count(&manifest_path, 1)
        .expect_err("manifest progress replay should reject too many blank records");
    assert!(
        progress_err.contains("blank lines"),
        "unexpected manifest blank progress error: {progress_err}"
    );

    let path_list = root.join("library.paths");
    fs::write(
        &path_list,
        format!(
            "{}{}\n",
            "\n".repeat(manifest::PATH_LIST_MAX_BLANK_LINES_PER_ITEM + 1),
            root.join("source.lani").display()
        ),
    )
    .expect("write blank-heavy path list");
    let message = manifest::load_path_list(&path_list, 1)
        .expect_err("path-list reader should reject too many blank records");
    assert!(
        message.contains("blank lines"),
        "unexpected path-list blank error: {message}"
    );

    fs::remove_dir_all(&root).expect("remove blank cap root");
}

#[test]
fn source_pack_library_manifest_rejects_duplicate_dependency_edges_before_paths() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-library-manifest-duplicate-dependency-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    fs::create_dir_all(&root).expect("create duplicate-dependency root");
    let manifest_path = root.join("libraries.jsonl");
    fs::write(
        &manifest_path,
        "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"missing.paths\",\"dependency_library_ids\":[1,1]}\n",
    )
    .expect("write duplicate-dependency library manifest");

    let mut source_pack = Options::default();
    source_pack.library_manifest = Some(manifest_path);
    source_pack.metadata_only = true;
    source_pack.artifact_root = Some(artifact_root.clone());

    let err = prepare_metadata_only("wasm", &[], &[], &source_pack)
        .expect_err("library manifest metadata must reject duplicate dependency edges");
    assert!(
        err.contains("duplicate dependency library 1"),
        "unexpected duplicate dependency error: {err}"
    );
    assert!(
        !err.contains("missing.paths"),
        "duplicate dependency validation should run before opening path lists"
    );
    let store = FilesystemArtifactStore::new(&artifact_root);
    assert!(
        !store
            .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "rejected dependency metadata must not publish a completed partition index"
    );

    fs::remove_dir_all(&root).expect("remove duplicate dependency root");
}

#[test]
fn source_pack_cli_limits_default_override_and_cap() {
    struct LimitCase {
        name: &'static str,
        configure: fn(&mut Options, usize),
        read: fn(&Options) -> usize,
        default_limit: usize,
        override_value: usize,
    }

    let cases = [
        LimitCase {
            name: "metadata libraries",
            configure: |source_pack, value| source_pack.metadata_max_libraries = Some(value),
            read: metadata_max_libraries,
            default_limit: DEFAULT_SOURCE_PACK_METADATA_MAX_LIBRARIES,
            override_value: 3,
        },
        LimitCase {
            name: "metadata source files",
            configure: |source_pack, value| source_pack.metadata_max_source_files = Some(value),
            read: metadata_max_source_files,
            default_limit: DEFAULT_SOURCE_PACK_METADATA_MAX_SOURCE_FILES,
            override_value: 5,
        },
        LimitCase {
            name: "build items",
            configure: |source_pack, value| source_pack.build_max_items = value,
            read: build_max_items,
            default_limit: DEFAULT_SOURCE_PACK_BUILD_MAX_ITEMS,
            override_value: 3,
        },
        LimitCase {
            name: "worker items",
            configure: |source_pack, value| source_pack.max_items = value,
            read: max_items,
            default_limit: DEFAULT_SOURCE_PACK_MAX_ITEMS,
            override_value: 5,
        },
        LimitCase {
            name: "ready items",
            configure: |source_pack, value| source_pack.max_ready_items = value,
            read: max_ready_items,
            default_limit: DEFAULT_SOURCE_PACK_MAX_READY_ITEMS,
            override_value: 7,
        },
    ];

    for case in cases {
        let default_options = Options::default();
        assert_eq!(
            (case.read)(&default_options),
            case.default_limit,
            "{} should default to its bounded limit",
            case.name
        );

        let mut overridden = Options::default();
        (case.configure)(&mut overridden, case.override_value);
        assert_eq!(
            (case.read)(&overridden),
            case.override_value,
            "{} should preserve explicit values below the cap",
            case.name
        );

        let mut unbounded = Options::default();
        (case.configure)(&mut unbounded, usize::MAX);
        assert_eq!(
            (case.read)(&unbounded),
            case.default_limit,
            "{} should cap unbounded CLI values",
            case.name
        );
    }
}

#[test]
fn source_pack_build_prepare_only_runs_one_bounded_metadata_chunk() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-build-prepare-only-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    fs::create_dir_all(&source_root).expect("create source dir");
    fs::write(source_root.join("core.lani"), "let core = 1;\n").expect("write source");
    fs::write(source_root.join("app.lani"), "let app = 2;\n").expect("write source");
    fs::write(
        root.join("core.paths"),
        format!("{}\n", source_root.join("core.lani").display()),
    )
    .expect("write core path list");
    fs::write(
        root.join("app.paths"),
        format!("{}\n", source_root.join("app.lani").display()),
    )
    .expect("write app path list");
    let manifest_path = root.join("libraries.jsonl");
    fs::write(
            &manifest_path,
            concat!(
                "{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"core.paths\"}\n",
                "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"app.paths\",\"dependency_library_ids\":[1]}\n",
            ),
        )
        .expect("write library manifest");

    let mut metadata_pack = Options::default();
    metadata_pack.library_manifest = Some(manifest_path);
    metadata_pack.metadata_only = true;
    metadata_pack.artifact_root = Some(artifact_root.clone());
    prepare_metadata_only("wasm", &[], &[], &metadata_pack)
        .expect("prepare metadata only before build chunk");
    fs::remove_dir_all(&source_root).expect("remove source files after metadata");

    let mut build_pack = Options::default();
    build_pack.build_from_metadata = true;
    build_pack.build_prepare_only = true;
    build_pack.build_max_items = 1;
    build_pack.artifact_root = Some(artifact_root.clone());
    prepare_build_from_metadata_chunk_only("wasm", &build_pack)
        .expect("prepare one bounded build chunk from metadata");

    let store = FilesystemArtifactStore::new(&artifact_root);
    assert!(
        store
            .library_build_unit_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    assert!(
        !store
            .library_build_unit_page_path_for_target(SourcePackArtifactTarget::Wasm, 1)
            .is_file(),
        "prepare-only chunk must not loop through every metadata-derived library"
    );
    assert!(
        !store
            .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "prepare-only chunk must not submit work or mark the build prepared"
    );

    fs::remove_dir_all(&root).expect("remove temp build-prepare-only root");
}

#[test]
fn prepare_only_advances_metadata_then_build_chunks() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-prepare-only-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    fs::create_dir_all(&source_root).expect("create source dir");
    fs::write(source_root.join("core.lani"), "let core = 1;\n").expect("write core source");
    fs::write(source_root.join("app.lani"), "let app = 2;\n").expect("write app source");
    fs::write(
        root.join("core.paths"),
        format!("{}\n", source_root.join("core.lani").display()),
    )
    .expect("write core path list");
    fs::write(
        root.join("app.paths"),
        format!("{}\n", source_root.join("app.lani").display()),
    )
    .expect("write app path list");
    let manifest_path = root.join("libraries.jsonl");
    fs::write(
            &manifest_path,
            concat!(
                "{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"core.paths\"}\n",
                "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"app.paths\",\"dependency_library_ids\":[1]}\n",
            ),
        )
        .expect("write library manifest");

    let mut source_pack = Options::default();
    source_pack.library_manifest = Some(manifest_path);
    source_pack.prepare_only = true;
    source_pack.metadata_max_libraries = Some(1);
    source_pack.build_max_items = 1;
    source_pack.artifact_root = Some(artifact_root.clone());

    prepare_inputs_chunk_only("wasm", &[], &[], &source_pack)
        .expect("prepare first source-pack metadata chunk");
    let store = FilesystemArtifactStore::new(&artifact_root);
    assert!(
        store
            .library_partition_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    let progress = store
        .load_library_metadata_prepare_progress_for_target(SourcePackArtifactTarget::Wasm)
        .expect("first metadata chunk should persist resumable progress");
    assert_eq!(progress.library_partition_count, 1);
    assert_eq!(progress.source_file_count, 1);
    assert!(
        !store
            .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "first prepare-only chunk must stop before finalizing all metadata"
    );
    assert!(
        !store
            .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "metadata chunks must not submit descriptor work"
    );

    prepare_inputs_chunk_only("wasm", &[], &[], &source_pack)
        .expect("prepare final source-pack metadata chunk");
    assert!(
        store
            .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file()
    );
    fs::remove_dir_all(&source_root).expect("remove source files after metadata");

    prepare_inputs_chunk_only("wasm", &[], &[], &source_pack)
        .expect("prepare one build chunk from source-pack metadata");
    assert!(
        store
            .library_build_unit_page_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    assert!(
        !store
            .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "source-pack prepare-only mode must not submit descriptor work or complete the full build in one bounded chunk"
    );

    fs::remove_dir_all(&root).expect("remove temp prepare-only root");
}

#[test]
fn prepare_only_library_manifest_skips_later_paths() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-library-manifest-prefix-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    fs::create_dir_all(&source_root).expect("create source dir");
    fs::write(source_root.join("core.lani"), "let core = 1;\n").expect("write source");
    fs::write(
        root.join("core.paths"),
        format!("{}\n", source_root.join("core.lani").display()),
    )
    .expect("write first path list");
    let manifest_path = root.join("libraries.jsonl");
    fs::write(
            &manifest_path,
            concat!(
                "{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"core.paths\"}\n",
                "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"missing.paths\",\"dependency_library_ids\":[1]}\n",
            ),
        )
        .expect("write library manifest with missing later path list");

    let mut source_pack = Options::default();
    source_pack.library_manifest = Some(manifest_path);
    source_pack.prepare_only = true;
    source_pack.metadata_max_libraries = Some(1);
    source_pack.artifact_root = Some(artifact_root.clone());

    prepare_inputs_chunk_only("wasm", &[], &[], &source_pack)
        .expect("first metadata chunk should not open a later library path list");
    let store = FilesystemArtifactStore::new(&artifact_root);
    assert!(
        store
            .library_partition_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    assert!(
        !store
            .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "a later manifest entry must keep the metadata chunk incomplete"
    );

    fs::remove_dir_all(&root).expect("remove temp library manifest prefix root");
}

#[test]
fn source_pack_prepare_only_library_manifest_chunk_stops_at_source_file_limit() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-library-manifest-source-limit-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    fs::create_dir_all(&source_root).expect("create source dir");
    fs::write(source_root.join("core.lani"), "let core = 1;\n").expect("write source");
    fs::write(
        root.join("core.paths"),
        format!("{}\n", source_root.join("core.lani").display()),
    )
    .expect("write first path list");
    let first_line = "{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"core.paths\"}\n";
    let second_line = "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"missing.paths\",\"dependency_library_ids\":[1]}\n";
    let manifest_path = root.join("libraries.jsonl");
    fs::write(&manifest_path, format!("{first_line}{second_line}"))
        .expect("write library manifest with missing later path list");

    let mut source_pack = Options::default();
    source_pack.library_manifest = Some(manifest_path);
    source_pack.prepare_only = true;
    source_pack.metadata_max_libraries = Some(64);
    source_pack.metadata_max_source_files = Some(1);
    source_pack.artifact_root = Some(artifact_root.clone());

    prepare_inputs_chunk_only("wasm", &[], &[], &source_pack)
        .expect("first metadata chunk should stop before the source-file limit overflow");
    let store = FilesystemArtifactStore::new(&artifact_root);
    assert!(
        store
            .library_partition_path_for_target(SourcePackArtifactTarget::Wasm, 0)
            .is_file()
    );
    assert!(
        !store
            .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "a later source-file-limited manifest entry must keep metadata incomplete"
    );
    let progress_path = manifest::progress_path(&artifact_root, SourcePackArtifactTarget::Wasm);
    let progress = serde_json::from_slice::<manifest::Progress>(
        &fs::read(&progress_path).expect("read manifest progress"),
    )
    .expect("parse manifest progress");
    assert_eq!(progress.library_count, 1);
    assert_eq!(progress.next_byte_offset, first_line.len() as u64);

    fs::remove_dir_all(&root).expect("remove temp library manifest source-limit root");
}

#[test]
fn prepare_only_rejects_oversized_library_before_paths() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-library-manifest-oversized-library-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    fs::create_dir_all(&root).expect("create root dir");
    let manifest_path = root.join("libraries.jsonl");
    fs::write(
        &manifest_path,
        "{\"library_id\":1,\"source_file_count\":2,\"path_list\":\"missing.paths\"}\n",
    )
    .expect("write oversized library manifest");

    let mut source_pack = Options::default();
    source_pack.library_manifest = Some(manifest_path);
    source_pack.prepare_only = true;
    source_pack.metadata_max_libraries = Some(64);
    source_pack.metadata_max_source_files = Some(1);
    source_pack.artifact_root = Some(artifact_root);

    let err = prepare_inputs_chunk_only("wasm", &[], &[], &source_pack)
        .expect_err("oversized single-library chunk should fail before opening path list");
    assert!(err.contains("per-chunk source-file limit"));
    assert!(
        !err.contains("missing.paths"),
        "single-library source-file limit rejection should happen before opening path list"
    );

    fs::remove_dir_all(&root).expect("remove temp oversized library root");
}

#[test]
fn source_pack_prepare_only_library_manifest_chunk_resumes_from_byte_offset() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-library-manifest-offset-test-{}-{suffix}",
        std::process::id()
    ));
    let source_root = root.join("sources");
    let artifact_root = root.join("artifacts");
    fs::create_dir_all(&source_root).expect("create source dir");
    fs::write(source_root.join("core.lani"), "let core = 1;\n").expect("write core source");
    fs::write(source_root.join("app.lani"), "let app = 2;\n").expect("write app source");
    fs::write(
        root.join("core.paths"),
        format!("{}\n", source_root.join("core.lani").display()),
    )
    .expect("write core path list");
    fs::write(
        root.join("app.paths"),
        format!("{}\n", source_root.join("app.lani").display()),
    )
    .expect("write app path list");
    let manifest_path = root.join("libraries.jsonl");
    let first_line = "{\"library_id\":1,\"source_file_count\":1,\"path_list\":\"core.paths\"}\n";
    let second_line = "{\"library_id\":2,\"source_file_count\":1,\"path_list\":\"app.paths\",\"dependency_library_ids\":[1]}\n";
    fs::write(&manifest_path, format!("{first_line}{second_line}"))
        .expect("write library manifest");

    let mut source_pack = Options::default();
    source_pack.library_manifest = Some(manifest_path.clone());
    source_pack.prepare_only = true;
    source_pack.metadata_max_libraries = Some(1);
    source_pack.artifact_root = Some(artifact_root.clone());

    prepare_inputs_chunk_only("wasm", &[], &[], &source_pack)
        .expect("prepare first metadata chunk");
    let progress_path = manifest::progress_path(&artifact_root, SourcePackArtifactTarget::Wasm);
    let progress = serde_json::from_slice::<manifest::Progress>(
        &fs::read(&progress_path).expect("read manifest progress"),
    )
    .expect("parse manifest progress");
    assert_eq!(progress.library_count, 1);
    assert_eq!(progress.next_byte_offset, first_line.len() as u64);

    let invalid_first_line = format!("{}\n", "x".repeat(first_line.len() - 1));
    assert_eq!(invalid_first_line.len(), first_line.len());
    fs::write(&manifest_path, format!("{invalid_first_line}{second_line}"))
        .expect("rewrite earlier manifest prefix with invalid JSON");

    prepare_inputs_chunk_only("wasm", &[], &[], &source_pack)
        .expect("second metadata chunk should seek past the prior manifest entry");
    let store = FilesystemArtifactStore::new(&artifact_root);
    assert!(
        store
            .library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .is_file(),
        "second chunk should complete metadata without reparsing the corrupted prefix"
    );

    fs::remove_dir_all(&root).expect("remove temp library manifest offset root");
}

#[test]
fn source_pack_json_manifest_chunk_modes_reject_before_manifest_read() {
    enum Mode {
        PrepareOnlyChunk,
        MetadataOnly,
    }

    let cases = [
        (
            "prepare-only-chunk",
            Mode::PrepareOnlyChunk,
            "chunked JSON manifest metadata prep should be rejected as unbounded",
        ),
        (
            "metadata-only",
            Mode::MetadataOnly,
            "metadata-only JSON manifest prep should be rejected as unbounded",
        ),
    ];

    for (case_name, mode, expected_context) in cases {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-json-manifest-reject-test-{case_name}-{}-{suffix}",
            std::process::id()
        ));
        let artifact_root = root.join("artifacts");
        let missing_manifest = root.join("missing-source-pack.json");
        let mut source_pack = Options {
            manifest: Some(missing_manifest),
            artifact_root: Some(artifact_root),
            ..Options::default()
        };

        let err = match mode {
            Mode::PrepareOnlyChunk => {
                source_pack.prepare_only = true;
                source_pack.metadata_max_libraries = Some(1);
                prepare_inputs_chunk_only("wasm", &[], &[], &source_pack)
            }
            Mode::MetadataOnly => {
                source_pack.metadata_only = true;
                prepare_metadata_only("wasm", &[], &[], &source_pack)
            }
        }
        .expect_err(expected_context);
        assert!(err.contains("--source-pack-library-manifest"));
        assert!(
            !err.contains("read source-pack manifest"),
            "{case_name} rejection should happen before reading the manifest"
        );

        let _ = fs::remove_dir_all(&root);
    }
}

#[test]
fn source_pack_prepare_only_rejects_raw_paths_before_source_metadata_read() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-raw-path-prepare-reject-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let missing_source = root.join("missing.lani");
    let mut source_pack = Options::default();
    source_pack.prepare_only = true;
    source_pack.artifact_root = Some(artifact_root);

    let err = prepare_inputs_chunk_only(
        "wasm",
        &[],
        std::slice::from_ref(&missing_source),
        &source_pack,
    )
    .expect_err("raw path prepare-only should be rejected as unbounded");
    assert!(err.contains("--source-pack-library-manifest"));
    assert!(
        !err.contains("missing.lani"),
        "raw path prepare-only rejection should happen before reading source metadata"
    );

    let _ = fs::remove_dir_all(&root);
}

#[test]
fn direct_descriptor_compile_requires_prepared_root() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-direct-prepare-required-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let mut source_pack = Options::default();
    source_pack.artifact_root = Some(artifact_root);

    let manifest_err = compile_manifest("wasm", &source_pack)
        .expect_err("fresh explicit artifact roots must be prepared before manifest parsing");
    assert!(manifest_err.contains("no persisted metadata"));
    assert!(manifest_err.contains("--source-pack-prepare-only"));
    assert!(
        !manifest_err.contains("read source-pack manifest"),
        "compile should fail before reading source-pack manifests"
    );

    let library_manifest_err = compile_library_manifest("wasm", &source_pack).expect_err(
        "fresh explicit artifact roots must be prepared before library manifest parsing",
    );
    assert!(library_manifest_err.contains("no persisted metadata"));
    assert!(
        !library_manifest_err.contains("open source-pack library manifest"),
        "compile should fail before reading source-pack library manifests"
    );

    let default_manifest_err = compile_manifest("wasm", &Options::default())
        .expect_err("manifest descriptor compile must name an artifact root before parsing");
    assert!(default_manifest_err.contains("--source-pack-artifact-root"));
    assert!(
        !default_manifest_err.contains("read source-pack manifest"),
        "manifest compile without an artifact root should fail before reading source-pack manifests"
    );

    let default_library_manifest_err = compile_library_manifest("wasm", &Options::default())
        .expect_err(
            "library manifest descriptor compile must name an artifact root before parsing",
        );
    assert!(default_library_manifest_err.contains("--source-pack-artifact-root"));
    assert!(
        !default_library_manifest_err.contains("open source-pack library manifest"),
        "library manifest compile without an artifact root should fail before reading source-pack library manifests"
    );

    let default_source_err = compile_direct("wasm", &Options::default()).expect_err(
        "source-pack descriptor compile must name an artifact root before reading sources",
    );
    assert!(default_source_err.contains("--source-pack-artifact-root"));
    assert!(
        !default_source_err.contains("missing.lani"),
        "source-pack compile without an artifact root should fail before touching explicit source paths"
    );

    let source_err = compile_direct("wasm", &source_pack)
        .expect_err("fresh explicit artifact roots must be prepared before source parsing");
    assert!(source_err.contains("no persisted metadata"));
    assert!(
        !source_err.contains("missing.lani"),
        "compile should fail before touching explicit source paths"
    );

    let _ = fs::remove_dir_all(&root);
}

#[test]
fn descriptor_compile_requires_build_queue_after_metadata() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let root = env::temp_dir().join(format!(
        "laniusc-cli-build-queue-required-test-{}-{suffix}",
        std::process::id()
    ));
    let artifact_root = root.join("artifacts");
    let store = FilesystemArtifactStore::new(&artifact_root);
    let metadata_index_path =
        store.library_partition_index_path_for_target(SourcePackArtifactTarget::Wasm);
    fs::create_dir_all(
        metadata_index_path
            .parent()
            .expect("metadata index path should have a parent"),
    )
    .expect("create metadata index dir");
    fs::write(&metadata_index_path, b"{}").expect("write metadata index marker");
    let mut source_pack = Options::default();
    source_pack.artifact_root = Some(artifact_root.clone());

    let err = compile_from_metadata("wasm", &source_pack)
        .expect_err("metadata alone must not trigger full build-queue preparation");
    assert!(err.contains("no prepared build queue"));
    assert!(err.contains("--source-pack-build-from-metadata --source-pack-build-prepare-only"));
    assert!(
        !store
            .build_state_path_for_target(SourcePackArtifactTarget::Wasm)
            .exists(),
        "descriptor compile must not synthesize build state in the compile path"
    );

    let _ = fs::remove_dir_all(&root);
}

#[test]
fn source_pack_resume_detection_is_target_specific() {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock")
        .as_nanos();
    let artifact_root = env::temp_dir().join(format!(
        "laniusc-cli-resume-detection-test-{}-{suffix}",
        std::process::id()
    ));
    let store = FilesystemArtifactStore::new(&artifact_root);
    let wasm_state_path = store.build_state_path_for_target(SourcePackArtifactTarget::Wasm);
    fs::create_dir_all(
        wasm_state_path
            .parent()
            .expect("target build state path should have a parent"),
    )
    .expect("create build state dir");
    fs::write(&wasm_state_path, b"{}").expect("write wasm build state marker");

    assert!(has_prepared_build(&artifact_root, "wasm"));
    assert!(!has_prepared_build(&artifact_root, "x86_64"));

    fs::remove_dir_all(&artifact_root).expect("remove temp artifact root");
}
