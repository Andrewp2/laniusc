mod common;

use std::{
    collections::HashMap,
    env,
    fs,
    path::{Path, PathBuf},
    process::Command,
    sync::mpsc,
};

use laniusc::gpu::{
    device,
    passes_core::{bind_group, make_pass_data},
};
use wgpu::util::DeviceExt;

const INVALID: u32 = 0xffff_ffff;
const HIR_ITEM_KIND_FN: u32 = 4;
const LANGUAGE_DECL_COUNT: usize = 18;
const LANGUAGE_DECL_ENTRYPOINT: u32 = 1;
const ENTRYPOINT_MAIN: u32 = 1;
const HIR_ITEM_IMPORT_TARGET_PATH: u32 = 1;

#[test]
fn entrypoint_pass_writes_hir_node_tags_without_token_aliases() {
    common::block_on_gpu_with_timeout("type checker entrypoint node tags", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let artifacts = compile_shader(&root, "type_check_calls_02b_entrypoints");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.type_checker.entrypoints",
            "main",
            leak_bytes(artifacts.0),
            leak_bytes(artifacts.1),
        )
        .expect("create entrypoints pass");

        let params = uniform_words(device, "tests.entrypoints.params", &[8, 0, 6]);
        let hir_status = storage_buffer(
            device,
            "tests.entrypoints.hir_status",
            &[0, 0, INVALID, 0, 0, 6],
        );
        let hir_token_pos = storage_buffer(
            device,
            "tests.entrypoints.hir_token_pos",
            &[0, INVALID, 4, INVALID, 7, INVALID],
        );
        let hir_item_kind = storage_buffer(
            device,
            "tests.entrypoints.hir_item_kind",
            &[0, 0, HIR_ITEM_KIND_FN, 0, HIR_ITEM_KIND_FN, 0],
        );
        let hir_item_name_token = storage_buffer(
            device,
            "tests.entrypoints.hir_item_name_token",
            &[INVALID, INVALID, 5, INVALID, 6, INVALID],
        );

        let mut name_id_by_token = vec![INVALID; 8];
        name_id_by_token[5] = 42;
        name_id_by_token[6] = 77;
        let name_id_by_token = storage_buffer(
            device,
            "tests.entrypoints.name_id_by_token",
            &name_id_by_token,
        );

        let mut language_decl_name_id = vec![INVALID; LANGUAGE_DECL_COUNT];
        let mut language_decl_kind = vec![0; LANGUAGE_DECL_COUNT];
        let mut language_decl_tag = vec![0; LANGUAGE_DECL_COUNT];
        language_decl_name_id[3] = 42;
        language_decl_kind[3] = LANGUAGE_DECL_ENTRYPOINT;
        language_decl_tag[3] = ENTRYPOINT_MAIN;
        let language_decl_name_id = storage_buffer(
            device,
            "tests.entrypoints.language_decl_name_id",
            &language_decl_name_id,
        );
        let language_decl_kind = storage_buffer(
            device,
            "tests.entrypoints.language_decl_kind",
            &language_decl_kind,
        );
        let language_decl_tag = storage_buffer(
            device,
            "tests.entrypoints.language_decl_tag",
            &language_decl_tag,
        );

        let fn_entrypoint_tag =
            storage_buffer(device, "tests.entrypoints.fn_entrypoint_tag", &[0; 8]);
        let readback = readback_buffer(device, "tests.entrypoints.readback", 8);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.type_checker.entrypoints.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &HashMap::from([
                ("gParams".to_string(), params.as_entire_binding()),
                ("hir_status".to_string(), hir_status.as_entire_binding()),
                (
                    "hir_token_pos".to_string(),
                    hir_token_pos.as_entire_binding(),
                ),
                (
                    "hir_item_kind".to_string(),
                    hir_item_kind.as_entire_binding(),
                ),
                (
                    "hir_item_name_token".to_string(),
                    hir_item_name_token.as_entire_binding(),
                ),
                (
                    "name_id_by_token".to_string(),
                    name_id_by_token.as_entire_binding(),
                ),
                (
                    "language_decl_name_id".to_string(),
                    language_decl_name_id.as_entire_binding(),
                ),
                (
                    "language_decl_kind".to_string(),
                    language_decl_kind.as_entire_binding(),
                ),
                (
                    "language_decl_tag".to_string(),
                    language_decl_tag.as_entire_binding(),
                ),
                (
                    "fn_entrypoint_tag".to_string(),
                    fn_entrypoint_tag.as_entire_binding(),
                ),
            ]),
        )
        .expect("create entrypoints bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.entrypoints.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.entrypoints.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&fn_entrypoint_tag, 0, &readback, 0, 8 * 4);
        queue.submit(Some(encoder.finish()));

        let tags = read_u32s(device, &readback, 8);
        assert_eq!(
            tags[2], ENTRYPOINT_MAIN,
            "entrypoint tag should be written to the HIR function node"
        );
        assert_eq!(
            tags[4], 0,
            "function token index must not be tagged because it can alias another HIR node"
        );
        assert_eq!(
            tags[5], 0,
            "function name token index must not be tagged because entrypoint tags are node keyed"
        );
    });
}

#[test]
fn module_record_scatters_consume_retained_path_id_records() {
    common::block_on_gpu_with_timeout("type checker module path-id records", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let module_artifacts =
            compile_shader(&root, "type_check_modules_02_scatter_module_records");
        let import_artifacts =
            compile_shader(&root, "type_check_modules_02b_scatter_import_records");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let module_pass = make_pass_data(
            device,
            "tests.type_checker.module_records",
            "main",
            leak_bytes(module_artifacts.0),
            leak_bytes(module_artifacts.1),
        )
        .expect("create module scatter pass");
        let import_pass = make_pass_data(
            device,
            "tests.type_checker.import_records",
            "main",
            leak_bytes(import_artifacts.0),
            leak_bytes(import_artifacts.1),
        )
        .expect("create import scatter pass");

        let module_params = uniform_words(device, "tests.module_records.params", &[6, 4, 1, 0]);
        let module_record_flag =
            storage_buffer(device, "tests.module_records.flag", &[0, 1, 0, 1, 0, 1]);
        let module_record_prefix =
            storage_buffer(device, "tests.module_records.prefix", &[0, 0, 1, 1, 2, 2]);
        let hir_item_file_id = storage_buffer(
            device,
            "tests.module_records.file_id",
            &[20, 21, 22, 23, 24, 25],
        );
        let path_id_by_owner_hir = storage_buffer(
            device,
            "tests.module_records.path_id_by_owner_hir",
            &[INVALID, 77, INVALID, 88, INVALID, 99],
        );
        let module_file_id = storage_buffer(device, "tests.module_records.module_file_id", &[0; 4]);
        let module_path_id =
            storage_buffer(device, "tests.module_records.module_path_id", &[INVALID; 4]);
        let module_owner_hir = storage_buffer(
            device,
            "tests.module_records.module_owner_hir",
            &[INVALID; 4],
        );
        let module_readback = readback_buffer(device, "tests.module_records.readback", 12);

        let module_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.type_checker.module_records.bind_group"),
            &module_pass.bind_group_layouts[0],
            &module_pass.reflection,
            0,
            &HashMap::from([
                ("gParams".to_string(), module_params.as_entire_binding()),
                (
                    "module_record_flag".to_string(),
                    module_record_flag.as_entire_binding(),
                ),
                (
                    "module_record_prefix".to_string(),
                    module_record_prefix.as_entire_binding(),
                ),
                (
                    "hir_item_file_id".to_string(),
                    hir_item_file_id.as_entire_binding(),
                ),
                (
                    "path_id_by_owner_hir".to_string(),
                    path_id_by_owner_hir.as_entire_binding(),
                ),
                (
                    "module_file_id".to_string(),
                    module_file_id.as_entire_binding(),
                ),
                (
                    "module_path_id".to_string(),
                    module_path_id.as_entire_binding(),
                ),
                (
                    "module_owner_hir".to_string(),
                    module_owner_hir.as_entire_binding(),
                ),
            ]),
        )
        .expect("create module scatter bind group");

        let import_params = uniform_words(device, "tests.import_records.params", &[16, 0, 6]);
        let import_record_flag =
            storage_buffer(device, "tests.import_records.flag", &[0, 1, 0, 1, 0, 1]);
        let import_record_prefix =
            storage_buffer(device, "tests.import_records.prefix", &[0, 0, 1, 1, 2, 2]);
        let hir_item_import_target_kind = storage_buffer(
            device,
            "tests.import_records.target_kind",
            &[
                0,
                HIR_ITEM_IMPORT_TARGET_PATH,
                0,
                2,
                0,
                HIR_ITEM_IMPORT_TARGET_PATH,
            ],
        );
        let import_module_file_id =
            storage_buffer(device, "tests.import_records.module_file_id", &[0; 4]);
        let import_path_id =
            storage_buffer(device, "tests.import_records.import_path_id", &[INVALID; 4]);
        let import_kind = storage_buffer(device, "tests.import_records.kind", &[0; 4]);
        let import_owner_hir =
            storage_buffer(device, "tests.import_records.owner_hir", &[INVALID; 4]);
        let import_readback = readback_buffer(device, "tests.import_records.readback", 16);

        let import_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.type_checker.import_records.bind_group"),
            &import_pass.bind_group_layouts[0],
            &import_pass.reflection,
            0,
            &HashMap::from([
                ("gParams".to_string(), import_params.as_entire_binding()),
                (
                    "import_record_flag".to_string(),
                    import_record_flag.as_entire_binding(),
                ),
                (
                    "import_record_prefix".to_string(),
                    import_record_prefix.as_entire_binding(),
                ),
                (
                    "hir_item_file_id".to_string(),
                    hir_item_file_id.as_entire_binding(),
                ),
                (
                    "hir_item_import_target_kind".to_string(),
                    hir_item_import_target_kind.as_entire_binding(),
                ),
                (
                    "path_id_by_owner_hir".to_string(),
                    path_id_by_owner_hir.as_entire_binding(),
                ),
                (
                    "import_module_file_id".to_string(),
                    import_module_file_id.as_entire_binding(),
                ),
                (
                    "import_path_id".to_string(),
                    import_path_id.as_entire_binding(),
                ),
                ("import_kind".to_string(), import_kind.as_entire_binding()),
                (
                    "import_owner_hir".to_string(),
                    import_owner_hir.as_entire_binding(),
                ),
            ]),
        )
        .expect("create import scatter bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.module_records.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.module_records.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&module_pass.pipeline);
            compute.set_bind_group(0, &module_bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
            compute.set_pipeline(&import_pass.pipeline);
            compute.set_bind_group(0, &import_bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&module_file_id, 0, &module_readback, 0, 4 * 4);
        encoder.copy_buffer_to_buffer(&module_path_id, 0, &module_readback, 4 * 4, 4 * 4);
        encoder.copy_buffer_to_buffer(&module_owner_hir, 0, &module_readback, 8 * 4, 4 * 4);
        encoder.copy_buffer_to_buffer(&import_module_file_id, 0, &import_readback, 0, 4 * 4);
        encoder.copy_buffer_to_buffer(&import_path_id, 0, &import_readback, 4 * 4, 4 * 4);
        encoder.copy_buffer_to_buffer(&import_kind, 0, &import_readback, 8 * 4, 4 * 4);
        encoder.copy_buffer_to_buffer(&import_owner_hir, 0, &import_readback, 12 * 4, 4 * 4);
        queue.submit(Some(encoder.finish()));

        let module_words = read_u32s(device, &module_readback, 12);
        assert_eq!(&module_words[0..3], &[21, 23, 25]);
        assert_eq!(
            &module_words[4..7],
            &[77, 88, 99],
            "module records should use retained path_id_by_owner_hir values"
        );
        assert_eq!(&module_words[8..11], &[1, 3, 5]);

        let import_words = read_u32s(device, &import_readback, 16);
        assert_eq!(&import_words[0..3], &[21, 23, 25]);
        assert_eq!(
            &import_words[4..7],
            &[77, INVALID, 99],
            "path imports should use retained path ids while string imports remain invalid"
        );
        assert_eq!(
            &import_words[8..11],
            &[HIR_ITEM_IMPORT_TARGET_PATH, 2, HIR_ITEM_IMPORT_TARGET_PATH]
        );
        assert_eq!(&import_words[12..15], &[1, 3, 5]);
    });
}

fn compile_shader(root: &Path, stem: &str) -> (Vec<u8>, Vec<u8>) {
    let shader = root
        .join("shaders/type_checker")
        .join(format!("{stem}.slang"));
    let spv = common::TempArtifact::new("laniusc_entrypoints", stem, Some("spv"));
    let reflection = common::TempArtifact::new("laniusc_entrypoints", stem, Some("reflect.json"));
    let output = Command::new(slangc_command())
        .arg("-target")
        .arg("spirv")
        .arg("-profile")
        .arg("glsl_450")
        .arg("-fvk-use-entrypoint-name")
        .arg("-reflection-json")
        .arg(reflection.path())
        .arg("-emit-spirv-directly")
        .arg("-O1")
        .arg("-I")
        .arg(root.join("shaders"))
        .arg("-I")
        .arg(root.join("shaders/type_checker"))
        .arg("-o")
        .arg(spv.path())
        .arg(&shader)
        .output()
        .unwrap_or_else(|err| panic!("run slangc for {}: {err}", shader.display()));
    common::assert_command_success(format!("compile {stem}"), &output);
    (
        fs::read(spv.path()).unwrap_or_else(|err| panic!("read {}: {err}", spv.path().display())),
        fs::read(reflection.path())
            .unwrap_or_else(|err| panic!("read {}: {err}", reflection.path().display())),
    )
}

fn slangc_command() -> PathBuf {
    env::var_os("SLANGC")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("slangc"))
}

fn uniform_words(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &u32_bytes(words),
        usage: wgpu::BufferUsages::UNIFORM,
    })
}

fn storage_buffer(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &u32_bytes(words),
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_DST
            | wgpu::BufferUsages::COPY_SRC,
    })
}

fn readback_buffer(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}

fn read_u32s(device: &wgpu::Device, buffer: &wgpu::Buffer, count: usize) -> Vec<u32> {
    let slice = buffer.slice(..);
    let (tx, rx) = mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| {
        tx.send(result).expect("send map result");
    });
    device
        .poll(wgpu::PollType::wait_indefinitely())
        .expect("poll readback");
    rx.recv()
        .expect("receive map result")
        .expect("map readback");
    let data = slice.get_mapped_range();
    let words = data[..count * 4]
        .chunks_exact(4)
        .map(|bytes| u32::from_le_bytes(bytes.try_into().expect("u32 bytes")))
        .collect::<Vec<_>>();
    drop(data);
    buffer.unmap();
    words
}

fn leak_bytes(bytes: Vec<u8>) -> &'static [u8] {
    Box::leak(bytes.into_boxed_slice())
}

fn u32_bytes(words: &[u32]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(words.len() * 4);
    for word in words {
        bytes.extend_from_slice(&word.to_le_bytes());
    }
    bytes
}
