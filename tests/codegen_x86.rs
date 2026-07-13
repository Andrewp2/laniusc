mod common;

use laniusc_compiler::compiler::{
    CompileError,
    GpuCompiler,
    GpuCompilerBackends,
    compile_source_pack_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen_from_path,
};

#[test]
fn x86_same_compiler_retries_speculative_frontend_capacity_and_feature_growth() {
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 speculative frontend capacity and feature growth",
        move || {
            pollster::block_on(async {
                let compiler = GpuCompiler::new_with_device_and_backends(
                    laniusc_compiler::gpu::device::global(),
                    GpuCompilerBackends::x86_only(),
                )
                .await?;
                compiler
                    .compile_source_pack_to_x86_64(&["fn main() -> i32 { return 1; }"])
                    .await?;
                compiler
                    .compile_source_pack_to_x86_64(&["fn broken( { return 2; }"])
                    .await
                    .expect_err("a rejected speculative parse must discard downstream commands");

                let mut larger = String::new();
                for function in 0..64 {
                    larger.push_str(&format!(
                        "fn f{function}(value: i32) -> i32 {{ return value + {function}; }}\n"
                    ));
                }
                larger.push_str("fn main() -> i32 { return f63(0); }\n");
                compiler
                    .compile_source_pack_to_x86_64(&[larger.as_str()])
                    .await?;
                let fitting = larger.replace("return f63(0)", "return f62(0)");
                compiler
                    .compile_source_pack_to_x86_64(&[fitting.as_str()])
                    .await?;
                compiler
                    .compile_source_pack_to_x86_64(&[r#"
struct Pair {
    left: i32,
    right: i32,
}

fn main() -> i32 {
    let pair: Pair = Pair { left: 7, right: 5 };
    return pair.left + pair.right;
}
"#])
                    .await
            })
        },
    )
    .expect("capacity and feature growth should safely retry after speculation underfits");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 speculative frontend capacity and feature growth",
        "x86_speculative_frontend_capacity_and_feature_growth",
        &bytes,
        12,
    );
}

fn make_x86_test_pass(
    device: &wgpu::Device,
    label: &str,
    shader: &str,
) -> laniusc_compiler::gpu::passes_core::PassData {
    laniusc_compiler::gpu::passes_core::make_pass_data_from_shader_key(
        device, label, "main", shader,
    )
    .unwrap_or_else(|err| panic!("create {label} pass: {err}"))
}

fn assert_x86_64_elf_header(bytes: &[u8]) {
    const ELF64_HEADER_SIZE: usize = 64;
    const ELF64_PROGRAM_HEADER_SIZE: usize = 56;
    const PT_LOAD: u32 = 1;
    const PF_X: u32 = 1;

    fn read_u16(bytes: &[u8], offset: usize) -> u16 {
        u16::from_le_bytes(bytes[offset..offset + 2].try_into().unwrap())
    }

    fn read_u32(bytes: &[u8], offset: usize) -> u32 {
        u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap())
    }

    fn read_u64(bytes: &[u8], offset: usize) -> u64 {
        u64::from_le_bytes(bytes[offset..offset + 8].try_into().unwrap())
    }

    assert!(
        bytes.len() >= ELF64_HEADER_SIZE,
        "ELF output too small: {}",
        bytes.len()
    );
    assert_eq!(&bytes[0..4], b"\x7fELF");
    assert_eq!(bytes[4], 2, "ELF64 class");
    assert_eq!(bytes[5], 1, "little-endian ELF");
    assert_eq!(read_u16(bytes, 16), 2, "executable ELF type");
    assert_eq!(read_u16(bytes, 18), 62, "x86_64 machine type");

    let entry = read_u64(bytes, 24);
    let program_header_offset =
        usize::try_from(read_u64(bytes, 32)).expect("program header offset should fit usize");
    let elf_header_size = read_u16(bytes, 52) as usize;
    let program_header_size = read_u16(bytes, 54) as usize;
    let program_header_count = read_u16(bytes, 56) as usize;
    assert_eq!(elf_header_size, ELF64_HEADER_SIZE, "ELF header size");
    assert!(
        program_header_size >= ELF64_PROGRAM_HEADER_SIZE,
        "program header entries must be large enough for ELF64"
    );
    assert!(
        program_header_count > 0,
        "ELF output should include at least one program header"
    );
    let program_header_table_size = program_header_size
        .checked_mul(program_header_count)
        .expect("program header table size overflowed");
    let program_header_table_end = program_header_offset
        .checked_add(program_header_table_size)
        .expect("program header table end overflowed");
    assert!(
        program_header_table_end <= bytes.len(),
        "program header table must fit in returned ELF bytes"
    );

    let mut entry_in_executable_segment = false;
    for header_i in 0..program_header_count {
        let base = program_header_offset + header_i * program_header_size;
        let segment_type = read_u32(bytes, base);
        if segment_type != PT_LOAD {
            continue;
        }

        let flags = read_u32(bytes, base + 4);
        let file_offset = read_u64(bytes, base + 8);
        let virtual_address = read_u64(bytes, base + 16);
        let file_size = read_u64(bytes, base + 32);
        let memory_size = read_u64(bytes, base + 40);
        assert!(
            file_size <= memory_size,
            "load segment file size must not exceed memory size"
        );

        let file_end = file_offset
            .checked_add(file_size)
            .expect("load segment file range overflowed");
        let file_end_usize =
            usize::try_from(file_end).expect("load segment file end should fit usize");
        assert!(
            file_end_usize <= bytes.len(),
            "load segment file range must fit in returned ELF bytes"
        );

        let memory_end = virtual_address
            .checked_add(memory_size)
            .expect("load segment memory range overflowed");
        if flags & PF_X != 0 && entry >= virtual_address && entry < memory_end {
            let entry_file_offset = file_offset + (entry - virtual_address);
            assert!(
                entry_file_offset >= file_offset && entry_file_offset < file_end,
                "ELF entry point must map to bytes in the executable segment"
            );
            entry_in_executable_segment = true;
        }
    }
    assert!(
        entry_in_executable_segment,
        "ELF entry point should be inside an executable load segment"
    );
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn assert_x86_exit_code(context: &str, artifact_stem: &str, bytes: &[u8], expected: i32) {
    use std::os::unix::process::ExitStatusExt;

    let output = common::run_x86_64_elf_output(context, artifact_stem, bytes);
    assert_eq!(
        output.status.code(),
        Some(expected),
        "{context}: signal={:?}\nstdout:\n{}\nstderr:\n{}",
        output.status.signal(),
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn compile_source(context: &str, source: &str) -> Vec<u8> {
    let source = source.to_owned();
    common::run_gpu_codegen_with_timeout(context, move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .unwrap_or_else(|err| panic!("{context} should compile to x86_64: {err}"))
}

fn x86_words_as_bytes(words: &[u32]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(words.len() * 4);
    for word in words {
        bytes.extend_from_slice(&word.to_le_bytes());
    }
    bytes
}

fn x86_buffer_from_u32s(
    device: &wgpu::Device,
    label: &str,
    usage: wgpu::BufferUsages,
    words: &[u32],
) -> wgpu::Buffer {
    use wgpu::util::DeviceExt;

    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &x86_words_as_bytes(words),
        usage,
    })
}

fn x86_read_u32s(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    buffer: &wgpu::Buffer,
    label: &str,
    count: usize,
) -> Vec<u32> {
    let byte_len = (count * 4) as wgpu::BufferAddress;
    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_len,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder =
        device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) });
    encoder.copy_buffer_to_buffer(buffer, 0, &readback, 0, byte_len);
    queue.submit(Some(encoder.finish()));

    let slice = readback.slice(..byte_len);
    let (tx, rx) = std::sync::mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| {
        tx.send(result).expect("send readback map result");
    });
    device
        .poll(wgpu::PollType::wait_indefinitely())
        .expect("poll readback");
    rx.recv()
        .expect("receive readback map result")
        .expect("map readback");

    let mapped = slice.get_mapped_range();
    let words = mapped
        .chunks_exact(4)
        .map(|chunk| u32::from_le_bytes(chunk.try_into().expect("u32 readback chunk")))
        .collect::<Vec<_>>();
    drop(mapped);
    readback.unmap();
    words
}

fn x86_read_bytes(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    buffer: &wgpu::Buffer,
    label: &str,
    byte_len: usize,
) -> Vec<u8> {
    let words = x86_read_u32s(device, queue, buffer, label, byte_len.div_ceil(4));
    let mut bytes = x86_words_as_bytes(&words);
    bytes.truncate(byte_len);
    bytes
}

#[test]
fn x86_rodata_offsets_follow_parser_string_literal_ranges() {
    common::run_gpu_codegen_with_timeout("x86 rodata string offsets", || {
        const INVALID: u32 = 0xffff_ffff;
        const HIR_EXPR_STRING: u32 = 28;
        const X86_RODATA_OK: u32 = 1;

        let gpu = laniusc_compiler::gpu::device::GpuDevice::new();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let sizes_pass =
            make_x86_test_pass(device, "test.x86_rodata_sizes", "codegen/x86/rodata/sizes");
        let scan_pass = make_x86_test_pass(
            device,
            "test.x86_rodata_scan",
            "codegen/x86/rodata/scan_local",
        );
        let offsets_pass = make_x86_test_pass(
            device,
            "test.x86_rodata_offsets",
            "codegen/x86/rodata/offsets",
        );

        let params = x86_buffer_from_u32s(
            device,
            "x86_rodata.params",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[8, 8, 512, 4],
        );
        let scan_params = x86_buffer_from_u32s(
            device,
            "x86_rodata.scan_params",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[4, 1, 0, 4],
        );
        let hir_status = x86_buffer_from_u32s(
            device,
            "x86_rodata.hir_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[1, 0, INVALID, 0, 0, 4],
        );
        let expr_record = x86_buffer_from_u32s(
            device,
            "x86_rodata.expr_record",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[
                HIR_EXPR_STRING,
                INVALID,
                INVALID,
                0,
                0,
                INVALID,
                INVALID,
                INVALID,
                HIR_EXPR_STRING,
                INVALID,
                INVALID,
                2,
                0,
                INVALID,
                INVALID,
                INVALID,
            ],
        );
        let decoded_len = x86_buffer_from_u32s(
            device,
            "x86_rodata.decoded_len",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[3, 0, 1, 0],
        );
        let size_by_node = x86_buffer_from_u32s(
            device,
            "x86_rodata.size_by_node",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0; 4],
        );
        let scan_local = x86_buffer_from_u32s(
            device,
            "x86_rodata.scan_local",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0; 4],
        );
        let scan_block_prefix = x86_buffer_from_u32s(
            device,
            "x86_rodata.scan_block_prefix",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0],
        );
        let scan_block_sum = x86_buffer_from_u32s(
            device,
            "x86_rodata.scan_block_sum",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0],
        );
        let offset_by_node = x86_buffer_from_u32s(
            device,
            "x86_rodata.offset_by_node",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0; 4],
        );
        let rodata_len = x86_buffer_from_u32s(
            device,
            "x86_rodata.len",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0],
        );
        let rodata_status = x86_buffer_from_u32s(
            device,
            "x86_rodata.status",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[X86_RODATA_OK, 0, INVALID, 0],
        );

        let sizes_bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_rodata_sizes.bind_group"),
                &sizes_pass,
                0,
                &[
                    ("gParams", params.as_entire_binding()),
                    ("hir_status", hir_status.as_entire_binding()),
                    ("hir_expr_record", expr_record.as_entire_binding()),
                    ("hir_string_decoded_len", decoded_len.as_entire_binding()),
                    ("x86_rodata_size_by_node", size_by_node.as_entire_binding()),
                    ("x86_rodata_status", rodata_status.as_entire_binding()),
                ],
            )
            .expect("create x86 rodata sizes bind group");
        let scan_bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_rodata_scan.bind_group"),
                &scan_pass,
                0,
                &[
                    ("gScan", scan_params.as_entire_binding()),
                    ("x86_rodata_size_by_node", size_by_node.as_entire_binding()),
                    ("x86_rodata_status", rodata_status.as_entire_binding()),
                    (
                        "x86_rodata_scan_local_prefix",
                        scan_local.as_entire_binding(),
                    ),
                    (
                        "x86_rodata_scan_block_sum",
                        scan_block_sum.as_entire_binding(),
                    ),
                ],
            )
            .expect("create x86 rodata scan bind group");
        let offsets_bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_rodata_offsets.bind_group"),
                &offsets_pass,
                0,
                &[
                    ("gScan", scan_params.as_entire_binding()),
                    ("x86_rodata_size_by_node", size_by_node.as_entire_binding()),
                    (
                        "x86_rodata_scan_local_prefix",
                        scan_local.as_entire_binding(),
                    ),
                    (
                        "x86_rodata_scan_block_prefix",
                        scan_block_prefix.as_entire_binding(),
                    ),
                    (
                        "x86_rodata_offset_by_node",
                        offset_by_node.as_entire_binding(),
                    ),
                    ("x86_rodata_len", rodata_len.as_entire_binding()),
                    ("x86_rodata_status", rodata_status.as_entire_binding()),
                ],
            )
            .expect("create x86 rodata offsets bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.x86_rodata.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.x86_rodata"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&sizes_pass.pipeline);
            compute.set_bind_group(0, &sizes_bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
            compute.set_pipeline(&scan_pass.pipeline);
            compute.set_bind_group(0, &scan_bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
            compute.set_pipeline(&offsets_pass.pipeline);
            compute.set_bind_group(0, &offsets_bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            x86_read_u32s(device, queue, &size_by_node, "x86 rodata sizes", 4),
            vec![4, 0, 2, 0],
        );
        assert_eq!(
            x86_read_u32s(device, queue, &offset_by_node, "x86 rodata offsets", 4),
            vec![0, 4, 4, 6],
        );
        assert_eq!(
            x86_read_u32s(device, queue, &rodata_len, "x86 rodata len", 1),
            vec![6],
        );
        assert_eq!(
            x86_read_u32s(device, queue, &rodata_status, "x86 rodata status", 4),
            vec![X86_RODATA_OK, 0, INVALID, 4],
        );
    });
}

#[test]
fn x86_rodata_write_copies_parser_string_payload_bytes_after_text() {
    common::run_gpu_codegen_with_timeout("x86 rodata byte write", || {
        const INVALID: u32 = 0xffff_ffff;
        const X86_RODATA_OK: u32 = 1;
        const X86_LAYOUT_OK: u32 = 1;
        const RODATA_OFFSET: usize = 0x7e;
        const RODATA_LEN: usize = 6;
        const FILE_LEN: usize = RODATA_OFFSET + RODATA_LEN;

        let gpu = laniusc_compiler::gpu::device::GpuDevice::new();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let write_pass =
            make_x86_test_pass(device, "test.x86_rodata_write", "codegen/x86/rodata/write");

        let params = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.params",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[8, 8, 160, 4],
        );
        let string_data_words = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.string_data_words",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0x0a63_6261],
        );
        let hir_status = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.hir_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[1, 0, INVALID, 0, 0, 4],
        );
        let string_data_offset = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.string_data_offset",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 0, 3, 0],
        );
        let decoded_len = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.decoded_len",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[3, 0, 1, 0],
        );
        let string_node = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.string_node",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 2],
        );
        let string_count = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.string_count",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[2],
        );
        let size_by_node = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.size_by_node",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[4, 0, 2, 0],
        );
        let offset_by_node = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.offset_by_node",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 4, 4, 6],
        );
        let rodata_len = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.len",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[RODATA_LEN as u32],
        );
        let rodata_status = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.rodata_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_RODATA_OK, 0, INVALID, RODATA_LEN as u32],
        );
        let elf_layout = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.layout",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[
                0x78,
                6,
                FILE_LEN as u32,
                0x400078,
                0x400000,
                0x1000,
                RODATA_OFFSET as u32,
                RODATA_LEN as u32,
            ],
        );
        let layout_status = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.layout_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_LAYOUT_OK, 0, INVALID, FILE_LEN as u32],
        );
        let out_words = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.out_words",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0; 40],
        );
        let status = x86_buffer_from_u32s(
            device,
            "x86_rodata_write.status",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[FILE_LEN as u32, 1, 0, INVALID],
        );

        let bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_rodata_write.bind_group"),
                &write_pass,
                0,
                &[
                    ("gParams", params.as_entire_binding()),
                    ("hir_status", hir_status.as_entire_binding()),
                    (
                        "hir_string_data_offset",
                        string_data_offset.as_entire_binding(),
                    ),
                    ("hir_string_decoded_len", decoded_len.as_entire_binding()),
                    (
                        "hir_string_data_words",
                        string_data_words.as_entire_binding(),
                    ),
                    ("hir_string_node", string_node.as_entire_binding()),
                    ("hir_string_count", string_count.as_entire_binding()),
                    ("x86_rodata_size_by_node", size_by_node.as_entire_binding()),
                    (
                        "x86_rodata_offset_by_node",
                        offset_by_node.as_entire_binding(),
                    ),
                    ("x86_rodata_len", rodata_len.as_entire_binding()),
                    ("x86_rodata_status", rodata_status.as_entire_binding()),
                    ("x86_elf_layout", elf_layout.as_entire_binding()),
                    ("layout_status", layout_status.as_entire_binding()),
                    ("out_words", out_words.as_entire_binding()),
                    ("status", status.as_entire_binding()),
                ],
            )
            .expect("create x86 rodata write bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.x86_rodata_write.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.x86_rodata_write"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&write_pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(2, 1, 1);
        }
        queue.submit(Some(encoder.finish()));

        let bytes = x86_read_bytes(
            device,
            queue,
            &out_words,
            "x86 rodata write bytes",
            FILE_LEN,
        );
        assert_eq!(&bytes[RODATA_OFFSET..FILE_LEN], b"abc\0\n\0");
        assert_eq!(
            x86_read_u32s(device, queue, &status, "x86 rodata write status", 4),
            vec![FILE_LEN as u32, 1, 0, INVALID],
        );
    });
}

fn assert_source_exit(name: &str, source: &str, expected: i32) {
    let bytes = compile_source(&format!("x86 source {name}"), source);

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        &format!("x86 source {name}"),
        &format!("x86_source_{name}"),
        &bytes,
        expected,
    );
}

#[test]
fn x86_elf_layout_accounts_for_rodata_after_text() {
    common::run_gpu_codegen_with_timeout("x86 ELF rodata layout", || {
        const INVALID: u32 = 0xffff_ffff;
        const X86_ENCODE_OK: u32 = 1;
        const X86_LAYOUT_OK: u32 = 1;
        const ELF_TEXT_OFFSET: u32 = 0x78;
        const TEXT_LEN: u32 = 16;
        const RODATA_LEN: u32 = 7;

        let gpu = laniusc_compiler::gpu::device::GpuDevice::new();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_x86_test_pass(device, "test.x86_elf_layout", "codegen/x86/elf/layout");

        let params = x86_buffer_from_u32s(
            device,
            "x86_elf_layout.params",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[0, 0, 512, 0],
        );
        let text_len = x86_buffer_from_u32s(
            device,
            "x86_elf_layout.text_len",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[TEXT_LEN],
        );
        let rodata_len = x86_buffer_from_u32s(
            device,
            "x86_elf_layout.rodata_len",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[RODATA_LEN],
        );
        let encode_status = x86_buffer_from_u32s(
            device,
            "x86_elf_layout.encode_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_ENCODE_OK, 0, INVALID, TEXT_LEN],
        );
        let layout = x86_buffer_from_u32s(
            device,
            "x86_elf_layout.layout",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0; 8],
        );
        let layout_status = x86_buffer_from_u32s(
            device,
            "x86_elf_layout.status",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0; 4],
        );

        let bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_elf_layout.bind_group"),
                &pass,
                0,
                &[
                    ("gParams", params.as_entire_binding()),
                    ("x86_text_len", text_len.as_entire_binding()),
                    ("x86_rodata_len", rodata_len.as_entire_binding()),
                    ("encode_status", encode_status.as_entire_binding()),
                    ("x86_elf_layout", layout.as_entire_binding()),
                    ("layout_status", layout_status.as_entire_binding()),
                ],
            )
            .expect("create x86 ELF layout bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.x86_elf_layout.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.x86_elf_layout"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        queue.submit(Some(encoder.finish()));

        let layout_words = x86_read_u32s(device, queue, &layout, "x86 ELF layout", 8);
        let status_words = x86_read_u32s(device, queue, &layout_status, "x86 layout status", 4);
        let rodata_offset = ELF_TEXT_OFFSET + TEXT_LEN;
        let file_len = rodata_offset + RODATA_LEN;

        assert_eq!(layout_words[0], ELF_TEXT_OFFSET, "text file offset");
        assert_eq!(layout_words[1], TEXT_LEN, "text byte length");
        assert_eq!(layout_words[2], file_len, "file byte length");
        assert_eq!(layout_words[6], rodata_offset, "rodata file offset");
        assert_eq!(layout_words[7], RODATA_LEN, "rodata byte length");
        assert_eq!(
            status_words,
            vec![X86_LAYOUT_OK, 0, INVALID, file_len],
            "layout status should publish the final file length"
        );
    });
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn assert_x86_stdout(context: &str, artifact_stem: &str, bytes: &[u8], expected: &str) {
    let output = common::run_x86_64_elf_output(context, artifact_stem, bytes);
    common::assert_command_success(format!("{context}: native ELF execution"), &output);
    assert_eq!(
        common::stdout_utf8(format!("{context}: native stdout"), output.stdout),
        expected
    );
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn run_x86_64_elf_output_in_dir(
    context: &str,
    artifact_stem: &str,
    bytes: &[u8],
    dir: &std::path::Path,
) -> std::process::Output {
    use std::os::unix::fs::PermissionsExt;

    let exe_path = dir.join(artifact_stem);
    std::fs::write(&exe_path, bytes)
        .unwrap_or_else(|err| panic!("{context}: write native ELF {}: {err}", exe_path.display()));
    let mut permissions = std::fs::metadata(&exe_path)
        .unwrap_or_else(|err| panic!("{context}: stat native ELF {}: {err}", exe_path.display()))
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(&exe_path, permissions)
        .unwrap_or_else(|err| panic!("{context}: chmod native ELF {}: {err}", exe_path.display()));

    let mut command = std::process::Command::new(&exe_path);
    command.current_dir(dir);
    common::short_process_output_with_timeout(
        format!("{context}: run native ELF {}", exe_path.display()),
        &mut command,
    )
}

#[cfg(all(unix, target_arch = "x86_64"))]
fn run_x86_64_elf_output_in_dir_with_args(
    context: &str,
    artifact_stem: &str,
    bytes: &[u8],
    dir: &std::path::Path,
    args: &[&str],
) -> std::process::Output {
    use std::os::unix::fs::PermissionsExt;

    let exe_path = dir.join(artifact_stem);
    std::fs::write(&exe_path, bytes)
        .unwrap_or_else(|err| panic!("{context}: write native ELF {}: {err}", exe_path.display()));
    let mut permissions = std::fs::metadata(&exe_path)
        .unwrap_or_else(|err| panic!("{context}: stat native ELF {}: {err}", exe_path.display()))
        .permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(&exe_path, permissions)
        .unwrap_or_else(|err| panic!("{context}: chmod native ELF {}: {err}", exe_path.display()));

    let mut command = std::process::Command::new(&exe_path);
    command.current_dir(dir).args(args);
    common::short_process_output_with_timeout(
        format!("{context}: run native ELF {}", exe_path.display()),
        &mut command,
    )
}

#[test]
fn x86_func_discover_projects_parser_function_owners_to_executable_functions() {
    common::run_gpu_codegen_with_timeout("x86 executable function owner projection", || {
        const HIR_FN: u32 = 3;
        const HIR_ITEM_KIND_FN: u32 = 4;
        const INVALID: u32 = u32::MAX;

        let gpu = laniusc_compiler::gpu::device::GpuDevice::new();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_x86_test_pass(
            device,
            "test.x86_func_discover",
            "codegen/x86/func/discover",
        );

        let storage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
        let storage_rw = storage | wgpu::BufferUsages::COPY_DST;
        let params = x86_buffer_from_u32s(
            device,
            "x86_func_discover.params",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[8, 1, 0, 8, 1, 0, 0, 0, 8],
        );
        let hir_status = x86_buffer_from_u32s(
            device,
            "x86_func_discover.hir_status",
            storage,
            &[0, 0, 0, 0, 0, 8],
        );
        let hir_kind = x86_buffer_from_u32s(
            device,
            "x86_func_discover.hir_kind",
            storage,
            &[HIR_FN, 0, 0, HIR_FN, 0, HIR_FN, 0, 0],
        );
        let hir_item_kind = x86_buffer_from_u32s(
            device,
            "x86_func_discover.hir_item_kind",
            storage,
            &[HIR_ITEM_KIND_FN, 0, 0, 0, 0, 0, 0, 0],
        );
        let hir_token_pos = x86_buffer_from_u32s(
            device,
            "x86_func_discover.hir_token_pos",
            storage,
            &[0, 1, 2, 3, 4, 5, 6, 7],
        );
        let method_decl_param_offset = x86_buffer_from_u32s(
            device,
            "x86_func_discover.method_decl_param_offset",
            storage,
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, 0, INVALID, INVALID,
            ],
        );
        let nearest_fn_node = x86_buffer_from_u32s(
            device,
            "x86_func_discover.nearest_fn_node",
            storage,
            &[0, 0, 0, 3, 3, 5, 5, INVALID],
        );
        let node_func =
            x86_buffer_from_u32s(device, "x86_func_discover.node_func", storage_rw, &[99; 8]);
        let node_tree_status = x86_buffer_from_u32s(
            device,
            "x86_func_discover.node_tree_status",
            storage,
            &[1, 0, INVALID, 0],
        );
        let node_decl_token = x86_buffer_from_u32s(
            device,
            "x86_func_discover.node_decl_token",
            storage,
            &[INVALID; 8],
        );
        let item_name_token = x86_buffer_from_u32s(
            device,
            "x86_func_discover.item_name_token",
            storage,
            &[INVALID; 8],
        );
        let entrypoint_tag =
            x86_buffer_from_u32s(device, "x86_func_discover.entrypoint_tag", storage, &[0; 8]);
        let func_meta = x86_buffer_from_u32s(
            device,
            "x86_func_discover.func_meta",
            storage_rw,
            &[0, 0, 0, 0, INVALID, 0, 0, 0],
        );
        let decl_node_by_token = x86_buffer_from_u32s(
            device,
            "x86_func_discover.decl_node_by_token",
            storage_rw,
            &[INVALID; 8],
        );

        let bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_func_discover.bind_group"),
                &pass,
                0,
                &[
                    ("gParams", params.as_entire_binding()),
                    ("hir_status", hir_status.as_entire_binding()),
                    ("hir_kind", hir_kind.as_entire_binding()),
                    ("hir_item_kind", hir_item_kind.as_entire_binding()),
                    ("x86_node_tree_status", node_tree_status.as_entire_binding()),
                    ("hir_token_pos", hir_token_pos.as_entire_binding()),
                    (
                        "method_decl_param_offset",
                        method_decl_param_offset.as_entire_binding(),
                    ),
                    ("hir_node_decl_token", node_decl_token.as_entire_binding()),
                    ("hir_item_name_token", item_name_token.as_entire_binding()),
                    ("fn_entrypoint_tag", entrypoint_tag.as_entire_binding()),
                    ("hir_nearest_fn_node", nearest_fn_node.as_entire_binding()),
                    ("x86_func_meta", func_meta.as_entire_binding()),
                    ("x86_node_func", node_func.as_entire_binding()),
                    (
                        "x86_decl_node_by_token",
                        decl_node_by_token.as_entire_binding(),
                    ),
                ],
            )
            .expect("create x86_func_discover bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.x86_func_discover.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.x86_func_discover"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        queue.submit(Some(encoder.finish()));

        let owner_words = x86_read_u32s(
            device,
            queue,
            &node_func,
            "x86 executable function owners",
            8,
        );

        assert_eq!(
            owner_words,
            vec![0, 0, 0, INVALID, INVALID, 5, 5, INVALID],
            "parser function ownership must retain free functions and impl methods while rejecting non-executable signatures"
        );
    });
}

#[test]
fn x86_node_tree_info_rejects_malformed_preorder_records() {
    common::run_gpu_codegen_with_timeout("x86 node tree shape status", || {
        const INVALID: u32 = 0xffff_ffff;
        const X86_NODE_TREE_OK: u32 = 1;
        const X86_ERR_TREE_SHAPE: u32 = 57;

        let gpu = laniusc_compiler::gpu::device::GpuDevice::new();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_x86_test_pass(
            device,
            "test.x86_node_tree_info",
            "codegen/x86/node/tree_info",
        );

        let assert_rejected = |case_name: &str,
                               parent_words: &[u32],
                               subtree_end_words: &[u32],
                               detail: u32| {
            let active_nodes = u32::try_from(parent_words.len()).expect("test HIR rows fit u32");
            assert_eq!(
                parent_words.len(),
                subtree_end_words.len(),
                "{case_name} parent/subtree fixtures should have matching row counts"
            );

            let storage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
            let storage_rw = storage | wgpu::BufferUsages::COPY_DST;
            let params = x86_buffer_from_u32s(
                device,
                "x86_node_tree_info.params",
                wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                &[0, 0, 0, active_nodes],
            );
            let hir_status = x86_buffer_from_u32s(
                device,
                "x86_node_tree_info.hir_status",
                storage,
                &[0, 0, 0, 0, 0, active_nodes],
            );
            let parent =
                x86_buffer_from_u32s(device, "x86_node_tree_info.parent", storage, parent_words);
            let subtree_end = x86_buffer_from_u32s(
                device,
                "x86_node_tree_info.subtree_end",
                storage,
                subtree_end_words,
            );
            let node_tree_status = x86_buffer_from_u32s(
                device,
                "x86_node_tree_info.status",
                storage_rw,
                &[X86_NODE_TREE_OK, 0, INVALID, 0],
            );

            let bind_group =
                laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                    device,
                    Some("test.x86_node_tree_info.bind_group"),
                    &pass,
                    0,
                    &[
                        ("gParams", params.as_entire_binding()),
                        ("hir_status", hir_status.as_entire_binding()),
                        ("parent", parent.as_entire_binding()),
                        ("subtree_end", subtree_end.as_entire_binding()),
                        ("x86_node_tree_status", node_tree_status.as_entire_binding()),
                    ],
                )
                .expect("create x86_node_tree_info bind group");

            let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.x86_node_tree_info.encoder"),
            });
            {
                let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("test.x86_node_tree_info"),
                    timestamp_writes: None,
                });
                compute.set_pipeline(&pass.pipeline);
                compute.set_bind_group(0, &bind_group, &[]);
                compute.dispatch_workgroups(1, 1, 1);
            }
            queue.submit(Some(encoder.finish()));

            let status_words =
                x86_read_u32s(device, queue, &node_tree_status, "node tree status", 4);
            assert_eq!(status_words[0], 0, "{case_name} should fail closed");
            assert_eq!(
                status_words[1], X86_ERR_TREE_SHAPE,
                "{case_name} should publish the HIR tree-shape boundary"
            );
            assert_eq!(
                status_words[2], detail,
                "{case_name} should identify the first malformed HIR row"
            );
        };

        assert_rejected("parent after child", &[INVALID, 0, 3, 0], &[4, 2, 3, 4], 2);
        assert_rejected("empty subtree range", &[INVALID, 0, 0], &[3, 1, 3], 1);
        assert_rejected(
            "child outside parent range",
            &[INVALID, 0, 1, 0],
            &[4, 2, 4, 4],
            2,
        );
    });
}

#[test]
fn x86_call_abi_clears_stale_rows_for_unsupported_arg_count() {
    fn words_as_bytes(words: &[u32]) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(words.len() * 4);
        for word in words {
            bytes.extend_from_slice(&word.to_le_bytes());
        }
        bytes
    }

    fn buffer_from_u32s(
        device: &wgpu::Device,
        label: &str,
        usage: wgpu::BufferUsages,
        words: &[u32],
    ) -> wgpu::Buffer {
        use wgpu::util::DeviceExt;

        device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some(label),
            contents: &words_as_bytes(words),
            usage,
        })
    }

    fn read_u32s(
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        buffer: &wgpu::Buffer,
        label: &str,
        count: usize,
    ) -> Vec<u32> {
        let byte_len = (count * 4) as wgpu::BufferAddress;
        let readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: byte_len,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut encoder =
            device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) });
        encoder.copy_buffer_to_buffer(buffer, 0, &readback, 0, byte_len);
        queue.submit(Some(encoder.finish()));

        let slice = readback.slice(..byte_len);
        let (tx, rx) = std::sync::mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |result| {
            tx.send(result).expect("send readback map result");
        });
        device
            .poll(wgpu::PollType::wait_indefinitely())
            .expect("poll readback");
        rx.recv()
            .expect("receive readback map result")
            .expect("map readback");

        let mapped = slice.get_mapped_range();
        let words = mapped
            .chunks_exact(4)
            .map(|chunk| u32::from_le_bytes(chunk.try_into().expect("u32 readback chunk")))
            .collect::<Vec<_>>();
        drop(mapped);
        readback.unmap();
        words
    }

    common::run_gpu_codegen_with_timeout("x86 call ABI stale-row clearing", || {
        const INVALID: u32 = 0xffff_ffff;
        const X86_CALL_RECORDS_OK: u32 = 1;
        const X86_CALL_ABI_OK: u32 = 1;
        const X86_ENUM_RECORDS_OK: u32 = 1;
        const X86_STRUCT_RECORDS_OK: u32 = 1;
        const X86_ERR_CALL_ABI: u32 = 9;
        const X86_ERR_CALL_ARG_COUNT: u32 = 56;

        let gpu = laniusc_compiler::gpu::device::GpuDevice::new();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_x86_test_pass(device, "test.x86_call_abi", "codegen/x86/call/abi");

        let params = buffer_from_u32s(
            device,
            "x86_call_abi.params",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[2, 0, 0, 1],
        );
        let feature_params = buffer_from_u32s(
            device,
            "x86_call_abi.features",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[0, 0, 0, 0],
        );
        let hir_status = buffer_from_u32s(
            device,
            "x86_call_abi.hir_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 0, 0, 0, 0, 1],
        );
        let one_word_invalid = buffer_from_u32s(
            device,
            "x86_call_abi.one_word_invalid",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[INVALID],
        );
        let hir_fn_kind = buffer_from_u32s(
            device,
            "x86_call_abi.hir_fn_kind",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[3],
        );
        let hir_fn_item_kind = buffer_from_u32s(
            device,
            "x86_call_abi.hir_fn_item_kind",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[1],
        );
        let two_word_invalid = buffer_from_u32s(
            device,
            "x86_call_abi.two_word_invalid",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[INVALID, INVALID],
        );
        let decl_node_by_token = buffer_from_u32s(
            device,
            "x86_call_abi.decl_node_by_token",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, INVALID],
        );
        let token_words_zero = buffer_from_u32s(
            device,
            "x86_call_abi.token_words_zero",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 0],
        );
        let zero_words = buffer_from_u32s(
            device,
            "x86_call_abi.zero_words",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0; 64],
        );
        let decl_layout_record = buffer_from_u32s(
            device,
            "x86_call_abi.decl_layout_record",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[INVALID, 0, INVALID, 0, INVALID, 0, INVALID, 0],
        );
        let call_record = buffer_from_u32s(
            device,
            "x86_call_abi.call_record",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 0, 0, 7],
        );
        let call_type_record = buffer_from_u32s(
            device,
            "x86_call_abi.call_type_record",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[1, INVALID, 0],
        );
        let call_record_status = buffer_from_u32s(
            device,
            "x86_call_abi.call_record_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_CALL_RECORDS_OK, 0, INVALID, 1],
        );
        let call_intrinsic_tag = buffer_from_u32s(
            device,
            "x86_call_abi.call_intrinsic_tag",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 0],
        );
        let enum_value_record = buffer_from_u32s(
            device,
            "x86_call_abi.enum_value_record",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[INVALID, INVALID],
        );
        let enum_record_status = buffer_from_u32s(
            device,
            "x86_call_abi.enum_record_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_ENUM_RECORDS_OK, 0, INVALID, 0],
        );
        let struct_record_status = buffer_from_u32s(
            device,
            "x86_call_abi.struct_record_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_STRUCT_RECORDS_OK, 0, INVALID, 0],
        );
        let call_abi_record = buffer_from_u32s(
            device,
            "x86_call_abi.record",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0, 1 << 8, INVALID, INVALID],
        );
        let call_abi_status = buffer_from_u32s(
            device,
            "x86_call_abi.status",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[X86_CALL_ABI_OK, 0, INVALID, 0],
        );

        let bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_call_abi.bind_group"),
                &pass,
                0,
                &[
                    ("gParams", params.as_entire_binding()),
                    ("gX86Features", feature_params.as_entire_binding()),
                    ("hir_status", hir_status.as_entire_binding()),
                    ("hir_kind", hir_fn_kind.as_entire_binding()),
                    ("hir_item_kind", hir_fn_item_kind.as_entire_binding()),
                    ("hir_stmt_record", zero_words.as_entire_binding()),
                    (
                        "hir_fn_return_type_node",
                        one_word_invalid.as_entire_binding(),
                    ),
                    ("hir_type_form", one_word_invalid.as_entire_binding()),
                    ("hir_type_len_value", one_word_invalid.as_entire_binding()),
                    (
                        "x86_decl_node_by_token",
                        decl_node_by_token.as_entire_binding(),
                    ),
                    (
                        "x86_enclosing_let_node",
                        one_word_invalid.as_entire_binding(),
                    ),
                    (
                        "x86_decl_layout_record",
                        decl_layout_record.as_entire_binding(),
                    ),
                    ("x86_call_record", call_record.as_entire_binding()),
                    ("x86_call_type_record", call_type_record.as_entire_binding()),
                    ("call_record_status", call_record_status.as_entire_binding()),
                    ("call_intrinsic_tag", call_intrinsic_tag.as_entire_binding()),
                    ("call_param_type", zero_words.as_entire_binding()),
                    ("name_id_by_token", token_words_zero.as_entire_binding()),
                    ("language_name_id", zero_words.as_entire_binding()),
                    ("type_instance_kind", token_words_zero.as_entire_binding()),
                    (
                        "type_instance_decl_token",
                        two_word_invalid.as_entire_binding(),
                    ),
                    (
                        "type_instance_elem_ref_tag",
                        token_words_zero.as_entire_binding(),
                    ),
                    (
                        "type_instance_elem_ref_payload",
                        token_words_zero.as_entire_binding(),
                    ),
                    (
                        "type_instance_len_kind",
                        token_words_zero.as_entire_binding(),
                    ),
                    (
                        "type_instance_len_payload",
                        token_words_zero.as_entire_binding(),
                    ),
                    (
                        "x86_struct_type_record",
                        token_words_zero.as_entire_binding(),
                    ),
                    (
                        "x86_struct_record_status",
                        struct_record_status.as_entire_binding(),
                    ),
                    ("x86_enum_type_record", token_words_zero.as_entire_binding()),
                    (
                        "x86_enum_value_record",
                        enum_value_record.as_entire_binding(),
                    ),
                    (
                        "x86_enum_record_status",
                        enum_record_status.as_entire_binding(),
                    ),
                    ("x86_call_abi_record", call_abi_record.as_entire_binding()),
                    ("call_abi_status", call_abi_status.as_entire_binding()),
                ],
            )
            .expect("create x86_call_abi bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.x86_call_abi.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.x86_call_abi"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        queue.submit(Some(encoder.finish()));

        let abi_words = read_u32s(device, queue, &call_abi_record, "call ABI readback", 4);
        let status_words = read_u32s(device, queue, &call_abi_status, "call ABI status", 4);

        assert_eq!(
            &abi_words[0..2],
            &[INVALID, INVALID],
            "unsupported call ABI projection must clear any stale row before failing"
        );
        assert_eq!(status_words[0], 0, "call ABI should fail closed");
        assert_eq!(
            status_words[1], X86_ERR_CALL_ARG_COUNT,
            "unsupported packed argument count should publish the specific ABI boundary"
        );
        assert_eq!(
            status_words[2], 0,
            "status detail should point at the call token slot"
        );

        let invalid_owner_call_record = buffer_from_u32s(
            device,
            "x86_call_abi.invalid_owner_call_record",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[INVALID, 0, 0, 0],
        );
        let invalid_owner_call_abi_record = buffer_from_u32s(
            device,
            "x86_call_abi.invalid_owner_record",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0, 1 << 8, INVALID, INVALID],
        );
        let invalid_owner_call_abi_status = buffer_from_u32s(
            device,
            "x86_call_abi.invalid_owner_status",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[X86_CALL_ABI_OK, 0, INVALID, 0],
        );
        let invalid_owner_bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_call_abi.invalid_owner_bind_group"),
                &pass,
                0,
                &[
                    ("gParams", params.as_entire_binding()),
                    ("gX86Features", feature_params.as_entire_binding()),
                    ("hir_status", hir_status.as_entire_binding()),
                    ("hir_kind", hir_fn_kind.as_entire_binding()),
                    ("hir_item_kind", hir_fn_item_kind.as_entire_binding()),
                    ("hir_stmt_record", zero_words.as_entire_binding()),
                    (
                        "hir_fn_return_type_node",
                        one_word_invalid.as_entire_binding(),
                    ),
                    ("hir_type_form", one_word_invalid.as_entire_binding()),
                    ("hir_type_len_value", one_word_invalid.as_entire_binding()),
                    (
                        "x86_decl_node_by_token",
                        decl_node_by_token.as_entire_binding(),
                    ),
                    (
                        "x86_enclosing_let_node",
                        one_word_invalid.as_entire_binding(),
                    ),
                    (
                        "x86_decl_layout_record",
                        decl_layout_record.as_entire_binding(),
                    ),
                    (
                        "x86_call_record",
                        invalid_owner_call_record.as_entire_binding(),
                    ),
                    ("x86_call_type_record", call_type_record.as_entire_binding()),
                    ("call_record_status", call_record_status.as_entire_binding()),
                    ("call_intrinsic_tag", call_intrinsic_tag.as_entire_binding()),
                    ("call_param_type", zero_words.as_entire_binding()),
                    ("name_id_by_token", token_words_zero.as_entire_binding()),
                    ("language_name_id", zero_words.as_entire_binding()),
                    ("type_instance_kind", token_words_zero.as_entire_binding()),
                    (
                        "type_instance_decl_token",
                        two_word_invalid.as_entire_binding(),
                    ),
                    (
                        "type_instance_elem_ref_tag",
                        token_words_zero.as_entire_binding(),
                    ),
                    (
                        "type_instance_elem_ref_payload",
                        token_words_zero.as_entire_binding(),
                    ),
                    (
                        "type_instance_len_kind",
                        token_words_zero.as_entire_binding(),
                    ),
                    (
                        "type_instance_len_payload",
                        token_words_zero.as_entire_binding(),
                    ),
                    (
                        "x86_struct_type_record",
                        token_words_zero.as_entire_binding(),
                    ),
                    (
                        "x86_struct_record_status",
                        struct_record_status.as_entire_binding(),
                    ),
                    ("x86_enum_type_record", token_words_zero.as_entire_binding()),
                    (
                        "x86_enum_value_record",
                        enum_value_record.as_entire_binding(),
                    ),
                    (
                        "x86_enum_record_status",
                        enum_record_status.as_entire_binding(),
                    ),
                    (
                        "x86_call_abi_record",
                        invalid_owner_call_abi_record.as_entire_binding(),
                    ),
                    (
                        "call_abi_status",
                        invalid_owner_call_abi_status.as_entire_binding(),
                    ),
                ],
            )
            .expect("create x86_call_abi invalid-owner bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.x86_call_abi.invalid_owner_encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.x86_call_abi.invalid_owner"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &invalid_owner_bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        queue.submit(Some(encoder.finish()));

        let abi_words = read_u32s(
            device,
            queue,
            &invalid_owner_call_abi_record,
            "invalid owner call ABI readback",
            4,
        );
        let status_words = read_u32s(
            device,
            queue,
            &invalid_owner_call_abi_status,
            "invalid owner call ABI status",
            4,
        );

        assert_eq!(
            &abi_words[0..2],
            &[INVALID, INVALID],
            "malformed call ABI projection must clear any stale row before failing"
        );
        assert_eq!(
            status_words[0], 0,
            "invalid call owner should fail the ABI projection"
        );
        assert_eq!(
            status_words[1], X86_ERR_CALL_ABI,
            "invalid call owner should publish the call ABI boundary"
        );
        assert_eq!(
            status_words[2], 0,
            "invalid call owner detail should stay source-addressable through the call token"
        );
    });
}

#[test]
fn x86_select_clears_stale_selected_rows_for_unsupported_virtual_ops() {
    common::run_gpu_codegen_with_timeout("x86 select stale-row clearing", || {
        const INVALID: u32 = 0xffff_ffff;
        const X86_SELECT_OK: u32 = 1;
        const X86_VIRTUAL_INST_OK: u32 = 1;
        const X86_VIRTUAL_REGALLOC_OK: u32 = 1;
        const X86_FUNC_FIRST_VIRTUAL_ROW_OK: u32 = 1;
        const X86_ERR_SELECT: u32 = 17;
        const X86_VINST_UNSUPPORTED: u32 = 99;
        const X86_INST_V_MOV_R32_IMM32: u32 = 50;

        let gpu = laniusc_compiler::gpu::device::GpuDevice::new();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_x86_test_pass(device, "test.x86_select", "codegen/x86/select");

        let storage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC;
        let storage_rw = storage | wgpu::BufferUsages::COPY_DST;
        let params = x86_buffer_from_u32s(
            device,
            "x86_select.params",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[0, 0, 0, 1, 3, 0, 0, 0, 1],
        );
        let virtual_inst_record = x86_buffer_from_u32s(
            device,
            "x86_select.virtual_inst_record",
            storage,
            &[0, 0, X86_VINST_UNSUPPORTED, 0],
        );
        let virtual_inst_args = x86_buffer_from_u32s(
            device,
            "x86_select.virtual_inst_args",
            storage,
            &[0, 0, 0, 0],
        );
        let virtual_inst_status = x86_buffer_from_u32s(
            device,
            "x86_select.virtual_inst_status",
            storage,
            &[X86_VIRTUAL_INST_OK, 0, INVALID, 1],
        );
        let virtual_phys_reg =
            x86_buffer_from_u32s(device, "x86_select.virtual_phys_reg", storage, &[0]);
        let virtual_call_live_reg_mask = x86_buffer_from_u32s(
            device,
            "x86_select.virtual_call_live_reg_mask",
            storage,
            &[0],
        );
        let virtual_regalloc_status = x86_buffer_from_u32s(
            device,
            "x86_select.virtual_regalloc_status",
            storage,
            &[X86_VIRTUAL_REGALLOC_OK, 0, INVALID, 1],
        );
        let func_first_virtual_row =
            x86_buffer_from_u32s(device, "x86_select.func_first_virtual_row", storage, &[0]);
        let func_first_virtual_row_status = x86_buffer_from_u32s(
            device,
            "x86_select.func_first_virtual_row_status",
            storage,
            &[X86_FUNC_FIRST_VIRTUAL_ROW_OK, 0, INVALID, 1],
        );
        let decl_layout_status = x86_buffer_from_u32s(
            device,
            "x86_select.decl_layout_status",
            storage,
            &[0, 0, 0, 0],
        );
        let func_meta =
            x86_buffer_from_u32s(device, "x86_select.func_meta", storage, &[1, 0, 0, 0, 0]);
        let virtual_func_slot =
            x86_buffer_from_u32s(device, "x86_select.virtual_func_slot", storage, &[0]);
        let virtual_value_def_flag =
            x86_buffer_from_u32s(device, "x86_select.virtual_value_def_flag", storage, &[1]);
        let inst_kind = x86_buffer_from_u32s(
            device,
            "x86_select.inst_kind",
            storage_rw,
            &[0, X86_INST_V_MOV_R32_IMM32, 0],
        );
        let inst_arg0 =
            x86_buffer_from_u32s(device, "x86_select.inst_arg0", storage_rw, &[0, 7, 0]);
        let inst_arg1 =
            x86_buffer_from_u32s(device, "x86_select.inst_arg1", storage_rw, &[0, 123, 0]);
        let inst_arg2 =
            x86_buffer_from_u32s(device, "x86_select.inst_arg2", storage_rw, &[0, 45, 0]);
        let select_status = x86_buffer_from_u32s(
            device,
            "x86_select.status",
            storage_rw,
            &[X86_SELECT_OK, 0, INVALID, 3],
        );

        let bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_select.bind_group"),
                &pass,
                0,
                &[
                    ("gParams", params.as_entire_binding()),
                    (
                        "x86_virtual_inst_record",
                        virtual_inst_record.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_inst_args",
                        virtual_inst_args.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_inst_status",
                        virtual_inst_status.as_entire_binding(),
                    ),
                    ("x86_virtual_phys_reg", virtual_phys_reg.as_entire_binding()),
                    (
                        "x86_virtual_call_live_reg_mask",
                        virtual_call_live_reg_mask.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_regalloc_status",
                        virtual_regalloc_status.as_entire_binding(),
                    ),
                    (
                        "x86_func_first_virtual_row",
                        func_first_virtual_row.as_entire_binding(),
                    ),
                    (
                        "x86_func_first_virtual_row_status",
                        func_first_virtual_row_status.as_entire_binding(),
                    ),
                    (
                        "x86_decl_layout_status",
                        decl_layout_status.as_entire_binding(),
                    ),
                    ("x86_func_meta", func_meta.as_entire_binding()),
                    (
                        "x86_virtual_func_slot",
                        virtual_func_slot.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_value_def_flag",
                        virtual_value_def_flag.as_entire_binding(),
                    ),
                    ("x86_inst_kind", inst_kind.as_entire_binding()),
                    ("x86_inst_arg0", inst_arg0.as_entire_binding()),
                    ("x86_inst_arg1", inst_arg1.as_entire_binding()),
                    ("x86_inst_arg2", inst_arg2.as_entire_binding()),
                    ("select_status", select_status.as_entire_binding()),
                ],
            )
            .expect("create x86_select bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.x86_select.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.x86_select"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        queue.submit(Some(encoder.finish()));

        let status_words = x86_read_u32s(device, queue, &select_status, "select status", 4);
        let kind_words = x86_read_u32s(device, queue, &inst_kind, "select kind rows", 3);
        let arg0_words = x86_read_u32s(device, queue, &inst_arg0, "select arg0 rows", 3);
        let arg1_words = x86_read_u32s(device, queue, &inst_arg1, "select arg1 rows", 3);
        let arg2_words = x86_read_u32s(device, queue, &inst_arg2, "select arg2 rows", 3);

        assert_eq!(status_words[0], 0, "selection should fail closed");
        assert_eq!(
            status_words[1], X86_ERR_SELECT,
            "unsupported virtual op should publish the select boundary"
        );
        assert_eq!(
            status_words[2], 0,
            "diagnostic detail should identify the rejected virtual row's HIR node"
        );
        assert_eq!(
            status_words[3], 0,
            "diagnostic extra should identify the rejected virtual row"
        );
        assert_eq!(
            (kind_words[1], arg0_words[1], arg1_words[1], arg2_words[1]),
            (0, 0, 0, 0),
            "unsupported virtual rows must clear any stale selected instruction payload"
        );
    });
}

#[test]
fn x86_reloc_patch_rejects_non_compact_reloc_rows() {
    fn words_as_bytes(words: &[u32]) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(words.len() * 4);
        for word in words {
            bytes.extend_from_slice(&word.to_le_bytes());
        }
        bytes
    }

    fn buffer_from_u32s(
        device: &wgpu::Device,
        label: &str,
        usage: wgpu::BufferUsages,
        words: &[u32],
    ) -> wgpu::Buffer {
        use wgpu::util::DeviceExt;

        device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some(label),
            contents: &words_as_bytes(words),
            usage,
        })
    }

    fn read_u32s(
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        buffer: &wgpu::Buffer,
        label: &str,
        count: usize,
    ) -> Vec<u32> {
        let byte_len = (count * 4) as wgpu::BufferAddress;
        let readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: byte_len,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut encoder =
            device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) });
        encoder.copy_buffer_to_buffer(buffer, 0, &readback, 0, byte_len);
        queue.submit(Some(encoder.finish()));

        let slice = readback.slice(..byte_len);
        let (tx, rx) = std::sync::mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |result| {
            tx.send(result).expect("send readback map result");
        });
        device
            .poll(wgpu::PollType::wait_indefinitely())
            .expect("poll readback");
        rx.recv()
            .expect("receive readback map result")
            .expect("map readback");

        let mapped = slice.get_mapped_range();
        let words = mapped
            .chunks_exact(4)
            .map(|chunk| u32::from_le_bytes(chunk.try_into().expect("u32 readback chunk")))
            .collect::<Vec<_>>();
        drop(mapped);
        readback.unmap();
        words
    }

    common::run_gpu_codegen_with_timeout("x86 reloc patch non-compact rows", || {
        const X86_ENCODE_OK: u32 = 1;
        const X86_RELOC_OK: u32 = 1;
        const X86_ERR_RELOC: u32 = 8;
        const X86_INST_JMP_REL32: u32 = 10;
        const X86_RELOC_REL32: u32 = 1;
        const INVALID: u32 = 0xffff_ffff;
        const ELF_TEXT_OFFSET: u32 = 0x78;

        let gpu = laniusc_compiler::gpu::device::GpuDevice::new();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_x86_test_pass(device, "test.x86_reloc_patch", "codegen/x86/reloc/patch");

        let text_len = 10;
        let out_word_count = ((ELF_TEXT_OFFSET + text_len + 3) / 4) as usize;
        let params = buffer_from_u32s(
            device,
            "x86_reloc_patch.params",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[0, 0, (out_word_count * 4) as u32, 2],
        );
        let inst_kind = buffer_from_u32s(
            device,
            "x86_reloc_patch.inst_kind",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_INST_JMP_REL32, X86_INST_JMP_REL32],
        );
        let inst_arg0 = buffer_from_u32s(
            device,
            "x86_reloc_patch.inst_arg0",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[2, 0],
        );
        let inst_arg1 = buffer_from_u32s(
            device,
            "x86_reloc_patch.inst_arg1",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 0],
        );
        let inst_arg2 = buffer_from_u32s(
            device,
            "x86_reloc_patch.inst_arg2",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 0],
        );
        let inst_size = buffer_from_u32s(
            device,
            "x86_reloc_patch.inst_size",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[5, 5],
        );
        let inst_byte_offset = buffer_from_u32s(
            device,
            "x86_reloc_patch.inst_byte_offset",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 5],
        );
        let decl_layout_status = buffer_from_u32s(
            device,
            "x86_reloc_patch.decl_layout_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 0, 0, 0],
        );
        let x86_text_len = buffer_from_u32s(
            device,
            "x86_reloc_patch.text_len",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[text_len],
        );
        let text_status = buffer_from_u32s(
            device,
            "x86_reloc_patch.text_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[1, 0, INVALID, 2],
        );
        let encode_status = buffer_from_u32s(
            device,
            "x86_reloc_patch.encode_status",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[X86_ENCODE_OK, 0, INVALID, text_len],
        );
        let reloc_count = buffer_from_u32s(
            device,
            "x86_reloc_patch.reloc_count",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[2],
        );
        let reloc_kind = buffer_from_u32s(
            device,
            "x86_reloc_patch.reloc_kind",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_RELOC_REL32, X86_RELOC_REL32],
        );
        let reloc_site_inst = buffer_from_u32s(
            device,
            "x86_reloc_patch.reloc_site_inst",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[1, 0],
        );
        let reloc_target_inst = buffer_from_u32s(
            device,
            "x86_reloc_patch.reloc_target_inst",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 2],
        );
        let out_words = buffer_from_u32s(
            device,
            "x86_reloc_patch.out_words",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &vec![0; out_word_count],
        );
        let reloc_status = buffer_from_u32s(
            device,
            "x86_reloc_patch.reloc_status",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[X86_RELOC_OK, 0, INVALID, 2],
        );

        let bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_reloc_patch.bind_group"),
                &pass,
                0,
                &[
                    ("gParams", params.as_entire_binding()),
                    ("x86_inst_kind", inst_kind.as_entire_binding()),
                    ("x86_inst_arg0", inst_arg0.as_entire_binding()),
                    ("x86_inst_arg1", inst_arg1.as_entire_binding()),
                    ("x86_inst_arg2", inst_arg2.as_entire_binding()),
                    ("x86_inst_size", inst_size.as_entire_binding()),
                    ("x86_inst_byte_offset", inst_byte_offset.as_entire_binding()),
                    (
                        "x86_decl_layout_status",
                        decl_layout_status.as_entire_binding(),
                    ),
                    ("x86_text_len", x86_text_len.as_entire_binding()),
                    ("text_status", text_status.as_entire_binding()),
                    ("encode_status", encode_status.as_entire_binding()),
                    ("x86_reloc_count", reloc_count.as_entire_binding()),
                    ("x86_reloc_kind", reloc_kind.as_entire_binding()),
                    ("x86_reloc_site_inst", reloc_site_inst.as_entire_binding()),
                    (
                        "x86_reloc_target_inst",
                        reloc_target_inst.as_entire_binding(),
                    ),
                    ("out_words", out_words.as_entire_binding()),
                    ("reloc_status", reloc_status.as_entire_binding()),
                ],
            )
            .expect("create x86_reloc_patch bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.x86_reloc_patch.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.x86_reloc_patch"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        queue.submit(Some(encoder.finish()));

        let encode_words = read_u32s(device, queue, &encode_status, "encode status readback", 4);
        let reloc_words = read_u32s(device, queue, &reloc_status, "reloc status readback", 4);
        let patched_words = read_u32s(
            device,
            queue,
            &out_words,
            "reloc patch output readback",
            out_word_count,
        );

        assert_eq!(
            encode_words[0], 0,
            "patch validation should poison encode ok"
        );
        assert_eq!(
            encode_words[1], X86_ERR_RELOC,
            "patch validation should publish an encode relocation error"
        );
        assert!(
            encode_words[2] <= 1,
            "non-compact row rejection should report one corrupt compact row: {encode_words:?}"
        );
        assert_eq!(
            encode_words[3], 0,
            "failed patch validation must clear encoded text length"
        );
        assert_eq!(reloc_words[0], 0, "relocation status should fail closed");
        assert_eq!(reloc_words[1], X86_ERR_RELOC);
        assert!(
            reloc_words[2] <= 1,
            "relocation detail should point at one corrupt compact row: {reloc_words:?}"
        );
        assert!(
            patched_words.iter().all(|word| *word == 0),
            "non-compact relocation rows must be rejected before patching bytes: {patched_words:?}"
        );
    });
}

#[test]
fn x86_virtual_liveness_rejects_cross_function_operands() {
    common::run_gpu_codegen_with_timeout("x86 liveness function-local operands", || {
        const INVALID: u32 = 0xffff_ffff;
        const X86_VIRTUAL_INST_OK: u32 = 1;
        const X86_FUNC_FIRST_VIRTUAL_ROW_OK: u32 = 1;
        const X86_ERR_VIRTUAL_LIVENESS: u32 = 14;
        const X86_VINST_IMM_I32: u32 = 1;
        const X86_VINST_RETURN: u32 = 9;

        let gpu = laniusc_compiler::gpu::device::GpuDevice::new();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_x86_test_pass(
            device,
            "test.x86_virtual_liveness",
            "codegen/x86/virtual/liveness",
        );

        let storage = wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST;
        let params = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.params",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[0, 0, 0, 16, 2, 0, 0, 0, 2],
        );
        let virtual_inst_record = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.inst_record",
            storage,
            &[7, 0, X86_VINST_RETURN, 0, 8, 0, X86_VINST_IMM_I32, 1],
        );
        let virtual_inst_args = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.inst_args",
            storage,
            &[1, 0, 0, 0, 0, 0, 0, 0],
        );
        let virtual_inst_status = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.inst_status",
            storage,
            &[X86_VIRTUAL_INST_OK, 0, INVALID, 2],
        );
        let virtual_func_slot =
            x86_buffer_from_u32s(device, "x86_virtual_liveness.func_slot", storage, &[0, 1]);
        let func_first_virtual_row_status = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.func_first_row_status",
            storage,
            &[X86_FUNC_FIRST_VIRTUAL_ROW_OK, 0, INVALID, 2],
        );
        let virtual_live_end = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.live_end",
            storage,
            &[INVALID; 2],
        );
        let virtual_liveness_status = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.status",
            storage,
            &[X86_VIRTUAL_INST_OK, 0, INVALID, 2],
        );

        let bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_virtual_liveness.bind_group"),
                &pass,
                0,
                &[
                    ("gParams", params.as_entire_binding()),
                    (
                        "x86_virtual_inst_record",
                        virtual_inst_record.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_inst_args",
                        virtual_inst_args.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_inst_status",
                        virtual_inst_status.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_func_slot",
                        virtual_func_slot.as_entire_binding(),
                    ),
                    (
                        "x86_func_first_virtual_row_status",
                        func_first_virtual_row_status.as_entire_binding(),
                    ),
                    ("x86_virtual_live_end", virtual_live_end.as_entire_binding()),
                    (
                        "x86_virtual_liveness_status",
                        virtual_liveness_status.as_entire_binding(),
                    ),
                ],
            )
            .expect("create x86_virtual_liveness bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.x86_virtual_liveness.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.x86_virtual_liveness"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        queue.submit(Some(encoder.finish()));

        let status_words = x86_read_u32s(
            device,
            queue,
            &virtual_liveness_status,
            "x86 liveness status readback",
            4,
        );
        let live_end_words = x86_read_u32s(
            device,
            queue,
            &virtual_live_end,
            "x86 liveness live-end readback",
            2,
        );

        assert_eq!(status_words[0], 0, "liveness should fail closed");
        assert_eq!(
            status_words[1], X86_ERR_VIRTUAL_LIVENESS,
            "cross-function operands should be rejected at the liveness boundary"
        );
        assert_eq!(
            status_words[2], 7,
            "diagnostic detail should point at the user HIR node, not the virtual row"
        );
        assert_eq!(
            live_end_words,
            vec![INVALID, INVALID],
            "cross-function operands must not extend live ranges"
        );
    });
}

#[test]
fn x86_virtual_liveness_preserves_row_local_error_status() {
    common::run_gpu_codegen_with_timeout("x86 liveness row-local status", || {
        const INVALID: u32 = 0xffff_ffff;
        const X86_VIRTUAL_INST_OK: u32 = 1;
        const X86_FUNC_FIRST_VIRTUAL_ROW_OK: u32 = 1;
        const X86_ERR_VIRTUAL_LIVENESS: u32 = 14;
        const X86_VINST_IMM_I32: u32 = 1;
        const X86_VINST_RETURN: u32 = 9;
        const ROW_LOCAL_EXTRA: u32 = 0x1234_5678;

        let gpu = laniusc_compiler::gpu::device::GpuDevice::new();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_x86_test_pass(
            device,
            "test.x86_virtual_liveness",
            "codegen/x86/virtual/liveness",
        );

        let storage = wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST;
        let params = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.params",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[0, 0, 0, 2, 2, 0, 0, 0, 1],
        );
        let virtual_inst_record = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.inst_record",
            storage,
            &[0, 0, X86_VINST_IMM_I32, 0, 1, 0, X86_VINST_RETURN, INVALID],
        );
        let virtual_inst_args = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.inst_args",
            storage,
            &[0, 0, 0, 0, 0, 0, 0, 0],
        );
        let virtual_inst_status = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.inst_status",
            storage,
            &[X86_VIRTUAL_INST_OK, 0, INVALID, 2],
        );
        let virtual_func_slot =
            x86_buffer_from_u32s(device, "x86_virtual_liveness.func_slot", storage, &[0, 0]);
        let func_first_virtual_row_status = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.func_first_row_status",
            storage,
            &[X86_FUNC_FIRST_VIRTUAL_ROW_OK, 0, INVALID, 2],
        );
        let virtual_live_end = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.live_end",
            storage,
            &[0, INVALID],
        );
        let virtual_liveness_status = x86_buffer_from_u32s(
            device,
            "x86_virtual_liveness.status",
            storage,
            &[0, X86_ERR_VIRTUAL_LIVENESS, 1, ROW_LOCAL_EXTRA],
        );

        let bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_virtual_liveness.bind_group"),
                &pass,
                0,
                &[
                    ("gParams", params.as_entire_binding()),
                    (
                        "x86_virtual_inst_record",
                        virtual_inst_record.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_inst_args",
                        virtual_inst_args.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_inst_status",
                        virtual_inst_status.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_func_slot",
                        virtual_func_slot.as_entire_binding(),
                    ),
                    (
                        "x86_func_first_virtual_row_status",
                        func_first_virtual_row_status.as_entire_binding(),
                    ),
                    ("x86_virtual_live_end", virtual_live_end.as_entire_binding()),
                    (
                        "x86_virtual_liveness_status",
                        virtual_liveness_status.as_entire_binding(),
                    ),
                ],
            )
            .expect("create x86_virtual_liveness bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.x86_virtual_liveness.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.x86_virtual_liveness"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        queue.submit(Some(encoder.finish()));

        let status_words = x86_read_u32s(
            device,
            queue,
            &virtual_liveness_status,
            "x86 liveness status readback",
            4,
        );
        let live_end_words = x86_read_u32s(
            device,
            queue,
            &virtual_live_end,
            "x86 liveness live-end readback",
            2,
        );

        assert_eq!(
            status_words,
            vec![0, X86_ERR_VIRTUAL_LIVENESS, 1, ROW_LOCAL_EXTRA],
            "successful row-0 publication must not erase a row-local liveness failure"
        );
        assert_eq!(
            live_end_words,
            vec![1, INVALID],
            "valid same-function operands should still extend liveness"
        );
    });
}

#[test]
fn x86_virtual_regalloc_uses_function_intervals_not_global_compact_order() {
    fn words_as_bytes(words: &[u32]) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(words.len() * 4);
        for word in words {
            bytes.extend_from_slice(&word.to_le_bytes());
        }
        bytes
    }

    fn buffer_from_u32s(
        device: &wgpu::Device,
        label: &str,
        usage: wgpu::BufferUsages,
        words: &[u32],
    ) -> wgpu::Buffer {
        use wgpu::util::DeviceExt;

        device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some(label),
            contents: &words_as_bytes(words),
            usage,
        })
    }

    fn read_u32s(
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        buffer: &wgpu::Buffer,
        label: &str,
        count: usize,
    ) -> Vec<u32> {
        let byte_len = (count * 4) as wgpu::BufferAddress;
        let readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: byte_len,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut encoder =
            device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) });
        encoder.copy_buffer_to_buffer(buffer, 0, &readback, 0, byte_len);
        queue.submit(Some(encoder.finish()));

        let slice = readback.slice(..byte_len);
        let (tx, rx) = std::sync::mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |result| {
            tx.send(result).expect("send readback map result");
        });
        device
            .poll(wgpu::PollType::wait_indefinitely())
            .expect("poll readback");
        rx.recv()
            .expect("receive readback map result")
            .expect("map readback");

        let mapped = slice.get_mapped_range();
        let words = mapped
            .chunks_exact(4)
            .map(|chunk| u32::from_le_bytes(chunk.try_into().expect("u32 readback chunk")))
            .collect::<Vec<_>>();
        drop(mapped);
        readback.unmap();
        words
    }

    common::run_gpu_codegen_with_timeout("x86 regalloc compact value-def rows", || {
        const INVALID: u32 = 0xffff_ffff;
        const X86_VIRTUAL_LIVENESS_OK: u32 = 1;
        const X86_VIRTUAL_NEXT_CALLS_OK: u32 = 1;
        const X86_FUNC_PARAM_REG_MASK_OK: u32 = 1;
        const X86_FUNC_FIRST_VIRTUAL_ROW_OK: u32 = 1;
        const X86_VIRTUAL_VALUE_DEFS_OK: u32 = 1;
        const X86_VIRTUAL_REGALLOC_OK: u32 = 1;
        const X86_VINST_IMM_I32: u32 = 1;

        let gpu = laniusc_compiler::gpu::device::GpuDevice::new();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_x86_test_pass(
            device,
            "test.x86_virtual_regalloc",
            "codegen/x86/virtual/regalloc",
        );

        let params = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.params",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[0, 0, 0, 3, 3, 0, 2, 2, 1],
        );
        let regalloc_params = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.regalloc_params",
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            &[2, 2, 0, 0],
        );
        let func_meta = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.func_meta",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[1, 0, 0, 0, 0, 0, 2, 2],
        );
        let func_slot_by_index = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.func_slot_by_index",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0],
        );
        let virtual_inst_record = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.inst_record",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[
                0,
                0,
                X86_VINST_IMM_I32,
                0,
                1,
                0,
                X86_VINST_IMM_I32,
                1,
                2,
                0,
                X86_VINST_IMM_I32,
                2,
            ],
        );
        let virtual_inst_args = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.inst_args",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0; 12],
        );
        let virtual_live_start = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.live_start",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 1, 2],
        );
        let virtual_live_end = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.live_end",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[1, 2, 2],
        );
        let virtual_liveness_status = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.liveness_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_VIRTUAL_LIVENESS_OK, 0, INVALID, 3],
        );
        let virtual_next_call_status = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.next_call_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_VIRTUAL_NEXT_CALLS_OK, 0, INVALID, 3],
        );
        let func_param_reg_mask = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.param_reg_mask",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0],
        );
        let func_param_reg_mask_status = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.param_reg_mask_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_FUNC_PARAM_REG_MASK_OK, 0, INVALID, 3],
        );
        let func_first_virtual_row = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.func_first_row",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0],
        );
        let func_last_virtual_row = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.func_last_row",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[2],
        );
        let func_first_virtual_row_status = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.func_first_row_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_FUNC_FIRST_VIRTUAL_ROW_OK, 0, INVALID, 3],
        );
        let virtual_value_def_row = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.value_def_row",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 2, 1],
        );
        let virtual_value_def_status = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.value_def_status",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[X86_VIRTUAL_VALUE_DEFS_OK, 0, INVALID, 3],
        );
        let virtual_func_slot = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.virtual_func_slot",
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
            &[0, 0, 0],
        );
        let virtual_regalloc_active_end = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.active_end",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[INVALID; 14],
        );
        let virtual_regalloc_param_rank_mask = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.param_rank_mask",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0],
        );
        let virtual_phys_reg = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.phys_reg",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[INVALID; 3],
        );
        let virtual_call_live_reg_mask = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.call_live_reg_mask",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[0; 3],
        );
        let virtual_regalloc_status = buffer_from_u32s(
            device,
            "x86_virtual_regalloc.status",
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            &[X86_VIRTUAL_REGALLOC_OK, 0, INVALID, 3],
        );

        let bind_group =
            laniusc_compiler::gpu::passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some("test.x86_virtual_regalloc.bind_group"),
                &pass,
                0,
                &[
                    ("gParams", params.as_entire_binding()),
                    ("gRegalloc", regalloc_params.as_entire_binding()),
                    ("x86_func_meta", func_meta.as_entire_binding()),
                    (
                        "x86_func_slot_by_index",
                        func_slot_by_index.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_inst_record",
                        virtual_inst_record.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_inst_args",
                        virtual_inst_args.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_live_start",
                        virtual_live_start.as_entire_binding(),
                    ),
                    ("x86_virtual_live_end", virtual_live_end.as_entire_binding()),
                    (
                        "x86_virtual_liveness_status",
                        virtual_liveness_status.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_next_call_status",
                        virtual_next_call_status.as_entire_binding(),
                    ),
                    (
                        "x86_func_param_reg_mask",
                        func_param_reg_mask.as_entire_binding(),
                    ),
                    (
                        "x86_func_param_reg_mask_status",
                        func_param_reg_mask_status.as_entire_binding(),
                    ),
                    (
                        "x86_func_first_virtual_row",
                        func_first_virtual_row.as_entire_binding(),
                    ),
                    (
                        "x86_func_last_virtual_row",
                        func_last_virtual_row.as_entire_binding(),
                    ),
                    (
                        "x86_func_first_virtual_row_status",
                        func_first_virtual_row_status.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_value_def_row",
                        virtual_value_def_row.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_value_def_status",
                        virtual_value_def_status.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_func_slot",
                        virtual_func_slot.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_regalloc_active_end",
                        virtual_regalloc_active_end.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_regalloc_param_rank_mask",
                        virtual_regalloc_param_rank_mask.as_entire_binding(),
                    ),
                    ("x86_virtual_phys_reg", virtual_phys_reg.as_entire_binding()),
                    (
                        "x86_virtual_call_live_reg_mask",
                        virtual_call_live_reg_mask.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_regalloc_status",
                        virtual_regalloc_status.as_entire_binding(),
                    ),
                ],
            )
            .expect("create x86_virtual_regalloc bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.x86_virtual_regalloc.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.x86_virtual_regalloc"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[0]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        queue.submit(Some(encoder.finish()));

        let status_words = read_u32s(
            device,
            queue,
            &virtual_regalloc_status,
            "regalloc status readback",
            4,
        );
        let phys_regs = read_u32s(
            device,
            queue,
            &virtual_phys_reg,
            "regalloc phys reg readback",
            3,
        );

        assert_eq!(
            status_words,
            vec![X86_VIRTUAL_REGALLOC_OK, 0, INVALID, 3],
            "function-interval allocation should not depend on the obsolete global compact-row order"
        );
        assert_eq!(
            phys_regs,
            vec![0, 10, 0],
            "function-local liveness should deterministically reuse EAX after the first interval ends"
        );
    });
}

#[test]
fn x86_path_reports_missing_input() {
    let missing = common::temp_artifact_path("laniusc_missing_x86", "input", Some("lani"));
    let _ = std::fs::remove_file(&missing);

    let err = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(
        &missing,
    ))
    .expect_err("missing source path should fail before codegen");
    let message = err.to_string();

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0040");
            assert_eq!(diagnostic.message, "input read failed");
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("missing input diagnostic should label the source path");
            assert_eq!(label.path, missing);
            assert_eq!(label.message, "could not read this source file");
            assert!(
                diagnostic
                    .notes
                    .iter()
                    .any(|note| note.contains("source input path:")),
                "missing input diagnostic should include the source path note: {message}"
            );
        }
        other => panic!("expected source read error, got {other:?}: {message}"),
    }
    assert!(
        message.contains("input read failed") && message.contains(&missing.display().to_string()),
        "missing input error should name the unreadable path: {message}"
    );
}

#[test]
fn x86_executes_representative_scalar_programs() {
    let cases = [
        (
            "integer_arithmetic",
            "fn main() {\n    return 1 + 2 + 3;\n}\n",
            6,
        ),
        (
            "bool_branch",
            "fn main() -> bool {\n    let value: i32 = 4;\n    return value > 3;\n}\n",
            1,
        ),
        (
            "function_call",
            "fn add(x: i32, y: i32) -> i32 {\n    return x + y;\n}\nfn main() {\n    return add(7, 5);\n}\n",
            12,
        ),
        (
            "live_local_after_call",
            "fn id(x: i32) -> i32 {\n    return x;\n}\nfn main() {\n    let left: i32 = 7 + 5;\n    let right: i32 = id(3);\n    return left + right;\n}\n",
            15,
        ),
        (
            "unsigned_compare",
            "fn main() -> bool {\n    let left: u32 = 4294967295;\n    let right: u32 = 1;\n    return left > right;\n}\n",
            1,
        ),
    ];

    for (name, source, expected) in cases {
        assert_source_exit(name, source, expected);
    }
}

#[test]
fn x86_executes_void_main_return_as_zero_exit() {
    assert_source_exit(
        "void_main_return",
        r#"
fn main() {
    return;
}
"#,
        0,
    );
}

#[test]
fn x86_rejects_parameterized_main_with_source_spanned_diagnostic() {
    let source = r#"
fn main(value: i32) {
    return value;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 parameterized main", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("parameterized main should fail until the native entrypoint ABI is defined");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "entrypoint parameter rejection should use the stable x86 diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "entrypoint parameter rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 entrypoint parameters")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the native entrypoint ABI boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the entrypoint source line");
            assert_eq!(
                source_line, "fn main(value: i32) {",
                "diagnostic should point at the parameterized entrypoint: {message}"
            );
            let param_start = source_line
                .find("value")
                .map(|column| column + 1)
                .expect("fixture should contain the entrypoint parameter");
            let param_end = param_start + "value".len();
            assert!(
                (param_start..=param_end).contains(&label.column),
                "diagnostic column should fall inside the entrypoint parameter: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_aggregate_returning_main_with_source_spanned_diagnostic() {
    let source = r#"
fn main() -> [i32; 2] {
    return [1, 2];
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 aggregate-returning main", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("aggregate-returning main should fail until the native entrypoint ABI is defined");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "entrypoint aggregate-return rejection should use the stable x86 diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "entrypoint aggregate-return rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 entrypoint aggregate return")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the native entrypoint return ABI boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the entrypoint source line");
            assert_eq!(
                source_line, "fn main() -> [i32; 2] {",
                "diagnostic should point at the aggregate-returning entrypoint: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_struct_returning_main_with_source_spanned_diagnostic() {
    let source = r#"
struct Pair {
    left: i32,
    right: i32,
}

fn main() -> Pair {
    return Pair { left: 1, right: 2 };
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 struct-returning main", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("struct-returning main should fail until the native entrypoint ABI is defined");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "entrypoint struct-return rejection should use the stable x86 diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "entrypoint struct-return rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 entrypoint aggregate return")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the native entrypoint return ABI boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the entrypoint source line");
            assert_eq!(
                source_line, "fn main() -> Pair {",
                "diagnostic should point at the struct-returning entrypoint: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_helper_parameter_beyond_sysv_registers_with_diagnostic() {
    let source = r#"
fn too_many_params(
    a: i32,
    b: i32,
    c: i32,
    d: i32,
    e: i32,
    f: i32,
    g: i32,
) -> i32 {
    return g;
}

fn main() {
    return 0;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 helper parameter count", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("helper parameter lists beyond SysV register coverage should fail closed");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "parameter-count rejection should use the stable x86 diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "parameter-count rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 parameter register count")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the native parameter-register boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert!(
                label
                    .source_line
                    .as_deref()
                    .is_some_and(|line| line.contains("g: i32")),
                "diagnostic should point at the first unsupported helper parameter: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 parameter-count diagnostic, got {other:?}"),
    }
}

#[test]
fn x86_source_pack_rejects_imported_helper_parameter_beyond_sysv_registers_with_diagnostic() {
    let sources = [
        r#"
module helpers::wide;

pub fn too_many_params(
    a: i32,
    b: i32,
    c: i32,
    d: i32,
    e: i32,
    f: i32,
    g: i32,
) -> i32 {
    return g;
}
"#,
        r#"
module app::main;

import helpers::wide;

fn main() {
    return 0;
}
"#,
    ];

    let err =
        common::run_gpu_codegen_with_timeout("x86 source-pack helper parameter count", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect_err(
            "source-pack helper parameter lists beyond SysV register coverage should fail closed",
        );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "source-pack parameter-count rejection should use the stable x86 diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "source-pack parameter-count rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 parameter register count")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the native parameter-register boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("source-pack x86 diagnostic should include a primary source label");
            assert_eq!(label.path.display().to_string(), "<source pack file 0>");
            assert!(
                label
                    .source_line
                    .as_deref()
                    .is_some_and(|line| line.contains("g: i32")),
                "diagnostic should point at the first unsupported imported helper parameter: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected source-pack x86 parameter-count diagnostic, got {other:?}"),
    }
}

#[test]
fn x86_executes_direct_scalar_calls_with_five_and_six_args() {
    assert_source_exit(
        "direct_scalar_calls_with_five_and_six_args",
        r#"
fn weighted5(a: i32, b: i32, c: i32, d: i32, e: i32) -> i32 {
    return a + b * 2 + c * 3 + d * 4 + e * 5;
}

fn weighted6(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32) -> i32 {
    return a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6;
}

fn main() {
    return weighted5(1, 2, 3, 4, 5) + weighted6(1, 2, 3, 4, 5, 6);
}
"#,
        146,
    );
}

#[test]
fn x86_rejects_aggregate_return_call_that_exceeds_sysv_register_slots() {
    let source = r#"
fn pair6(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32) -> [i32; 2] {
    return [a + e, b + f];
}

fn main() {
    let pair: [i32; 2] = pair6(1, 2, 3, 4, 5, 6);
    return pair[0] + pair[1];
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout(
        "x86 aggregate return call register slots",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .expect_err("aggregate-return calls must reserve a hidden SysV return-pointer slot");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "aggregate-return ABI rejection should use the stable backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "aggregate-return ABI rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic.message.contains("unsupported x86 call ABI")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the total SysV register-slot boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the aggregate-return call source line");
            assert!(
                source_line.contains("pair6(1, 2, 3, 4, 5, 6)"),
                "diagnostic should point at the call that needs six explicit args plus a hidden return pointer: {message}"
            );
            let call_start = source_line
                .find("pair6")
                .map(|offset| offset + 1)
                .expect("fixture should contain the aggregate-return call");
            let call_end = source_line
                .find(");")
                .map(|offset| offset + 2)
                .expect("fixture should contain the aggregate-return call terminator");
            assert!(
                (call_start..=call_end).contains(&label.column),
                "diagnostic column should fall inside the capacity-exceeding call expression: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 aggregate-return ABI diagnostic, got {other:?}"),
    }
}

#[test]
fn x86_direct_call_with_seven_parameters_reaches_native_parameter_boundary() {
    let source = r#"
fn sum7(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32) -> i32 {
    return a + b + c + d + e + f + g;
}

fn main() {
    return sum7(1, 2, 3, 4, 5, 6, 7);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 direct call parameter count", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("seven-parameter direct callees should fail before native x86 bytes are returned");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "wide direct calls should now reach the native x86 diagnostic boundary: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "wide direct calls should no longer fail in frontend call resolution: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 parameter register count")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the remaining native parameter-register boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the unsupported parameter source line");
            assert!(
                source_line.contains("g: i32"),
                "diagnostic should point at the first unsupported direct-callee parameter: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        CompileError::GpuTypeCheck(message) => {
            panic!("expected native x86 diagnostic, got raw GPU type-check error: {message}")
        }
        other => panic!("expected x86 parameter-count diagnostic, got {other:?}"),
    }
}

#[test]
fn x86_executes_lanius_std_write_i32_stdout() {
    let bytes = compile_source(
        "x86 lanius_std write_i32 stdout",
        r#"
extern "lanius_std" fn write_i32(handle: i32, value: i32) -> i32;

fn main() {
    let result: i32 = write_i32(1, 42);
    if (result < 0) {
        return 1;
    }
    return result;
}
"#,
    );

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_stdout(
        "x86 lanius_std write_i32 stdout",
        "x86_lanius_std_write_i32_stdout",
        &bytes,
        "42",
    );
}

#[test]
fn x86_executes_lanius_std_write_i32_nested_status_check() {
    let bytes = compile_source(
        "x86 lanius_std write_i32 nested status",
        r#"
extern "lanius_std" fn write_i32(handle: i32, value: i32) -> i32;

fn operation_failed(result: i32) -> bool {
    return result < 0;
}

fn main() {
    if (operation_failed(write_i32(1, 7))) {
        return 1;
    }
    return 0;
}
"#,
    );

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_stdout(
        "x86 lanius_std write_i32 nested status",
        "x86_lanius_std_write_i32_nested_status",
        &bytes,
        "7",
    );
}

#[test]
fn x86_executes_multi_argument_method_call() {
    assert_source_exit(
        "multi_argument_method_call",
        r#"
struct Counter {
    value: i32,
    scale: i32,
}

impl Counter {
    fn mix(self, first: i32, second: i32) -> i32 {
        return self.value * self.scale + first * 3 + second;
    }
}

fn main() {
    let counter: Counter = Counter { value: 5, scale: 10 };
    return counter.mix(4, 7);
}
"#,
        69,
    );
}

#[test]
fn x86_executes_while_loop_with_scalar_local_mutation() {
    assert_source_exit(
        "while_loop_scalar_mutation",
        r#"
fn main() {
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 4) {
        total += i;
        i += 1;
    }
    return total;
}
"#,
        6,
    );
}

#[test]
fn x86_executes_nested_while_loop_with_scalar_local_mutation() {
    assert_source_exit(
        "nested_while_loop_scalar_mutation",
        r#"
fn main() {
    let i: i32 = 0;
    let j: i32 = 0;
    let total: i32 = 0;
    while (i < 3) {
        j = 0;
        while (j < i) {
            total += j;
            j += 1;
        }
        i += 1;
    }
    return total;
}
"#,
        1,
    );
}

#[test]
fn x86_executes_nested_branch_with_scalar_local_mutation() {
    assert_source_exit(
        "nested_branch_scalar_mutation",
        r#"
fn main() {
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 5) {
        if (i < 2) {
            total += 10;
        } else {
            total += i;
        }
        i += 1;
    }
    return total;
}
"#,
        29,
    );
}

#[test]
fn x86_executes_nested_arithmetic_in_branch_conditions_and_bodies() {
    assert_source_exit(
        "nested_arithmetic_in_branches",
        r#"
fn main() {
    let base: i32 = 4;
    let total: i32 = 0;
    if ((base * 3 + 2) > 10) {
        total += (base + 1) * 2;
    } else {
        total += 40;
    }
    if ((total - base) == 6) {
        total += 3 * (base - 1);
    } else {
        total += 70;
    }
    return total;
}
"#,
        19,
    );
}

#[test]
fn x86_executes_scalar_boolean_operators_in_branches() {
    assert_source_exit(
        "scalar_boolean_operators",
        r#"
fn main() {
    let left: bool = true;
    let right: bool = false;
    let total: i32 = 0;
    if (left && !right) {
        total += 4;
    } else {
        total += 40;
    }
    if (right || (total == 4)) {
        total += 3;
    }
    if ((left && right) || false) {
        total += 100;
    } else {
        total += 5;
    }
    return total;
}
"#,
        12,
    );
}

#[test]
fn x86_executes_block_scoped_shadowed_locals() {
    assert_source_exit(
        "block_scoped_shadowed_locals",
        r#"
fn main() {
    let value: i32 = 3;
    let total: i32 = value;
    let keep_inner: bool = value < 10;
    if (keep_inner) {
        let value: i32 = 9;
        total += value;
    }
    return total * 10 + value;
}
"#,
        123,
    );
}

#[test]
fn x86_executes_signed_comparison_operators_in_branches() {
    assert_source_exit(
        "signed_comparison_operators",
        r#"
fn main() {
    let low: i32 = -2;
    let high: i32 = 3;
    let total: i32 = 0;
    if (low <= -2) {
        total += 1;
    }
    if (high >= 3) {
        total += 2;
    }
    if (low != high) {
        total += 4;
    }
    if (low > high) {
        total += 64;
    }
    return total;
}
"#,
        7,
    );
}

#[test]
fn x86_executes_return_match_on_single_payload_enum() {
    assert_source_exit(
        "return_match_single_payload_enum",
        r#"
enum Maybe {
    Some(i32),
    None,
}

fn score(value: Maybe) -> i32 {
    return match (value) {
        Some(inner) -> inner + 2,
        None -> 5,
    };
}

fn main() {
    let hit: Maybe = Some(4);
    let miss: Maybe = None;
    return score(hit) * 10 + score(miss);
}
"#,
        65,
    );
}

#[test]
fn x86_executes_source_pack_imported_enum_return_match_helper() {
    let sources = [
        r#"
module helpers::maybe;

pub enum Maybe {
    Some(i32),
    None,
}

pub fn choose(flag: bool, value: i32) -> Maybe {
    if (flag) {
        return Some(value);
    }
    return None;
}

pub fn score(value: Maybe) -> i32 {
    return match (value) {
        Some(inner) -> inner + 2,
        None -> 5,
    };
}
"#,
        r#"
module app::main;

import helpers::maybe;

fn main() {
    let hit: helpers::maybe::Maybe = helpers::maybe::choose(true, 4);
    let miss: helpers::maybe::Maybe = helpers::maybe::choose(false, 9);
    return helpers::maybe::score(hit) * 10 + helpers::maybe::score(miss);
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack imported enum return match helper",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack imported enum return-match helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack imported enum return match helper",
        "x86_source_pack_imported_enum_return_match_helper",
        &bytes,
        65,
    );
}

#[test]
fn x86_rejects_non_return_match_expression_with_diagnostic() {
    let source = r#"
fn main() {
    let observed: i32 = match (0) {
        _ -> 7,
    };
    return observed;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 non-return match expression", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err(
        "non-return match expressions should fail closed until x86 match lowering broadens",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "match-expression rejection should use the stable x86 diagnostic: {rendered}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "match-expression rejection should stay in the native-codegen category: {rendered}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 match expression")
                    && rendered.contains("native x86 backend"),
                "diagnostic should name the unsupported x86 match boundary: {rendered}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the match source line");
            assert_eq!(
                source_line, "    let observed: i32 = match (0) {",
                "diagnostic should point at the unsupported match expression: {rendered}"
            );
            let match_start_column = source_line
                .find("match")
                .map(|column| column + 1)
                .expect("fixture should contain the match expression");
            let match_end_column = match_start_column + "match".len();
            assert!(
                (match_start_column..=match_end_column).contains(&label.column),
                "diagnostic column should fall inside the match token: {rendered}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_multi_payload_enum_constructor_with_diagnostic() {
    let source = r#"
enum Pairish {
    Pair(i32, bool),
    Empty,
}

fn main() {
    let value: Pairish = Pair(7, true);
    return 0;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout(
        "x86 multi-payload enum constructor",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .expect_err(
        "multi-payload enum constructors should fail closed until x86 payload lowering broadens",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "enum-constructor rejection should use the stable x86 diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "enum-constructor rejection should stay in the native-codegen category: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 multi-payload enum constructor")
                    && message.contains("native x86 backend"),
                "diagnostic should name the unsupported enum-constructor boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the enum-constructor source line");
            assert_eq!(
                source_line, "    let value: Pairish = Pair(7, true);",
                "diagnostic should point at the unsupported enum constructor: {message}"
            );
            let ctor_start_column = source_line
                .find("Pair(7")
                .map(|column| column + 1)
                .expect("fixture should contain the enum constructor call");
            let ctor_end_column = ctor_start_column + "Pair".len();
            assert!(
                (ctor_start_column..=ctor_end_column).contains(&label.column),
                "diagnostic column should fall inside the enum constructor name: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_char_literal_until_native_literal_layout_exists() {
    let source = r#"
fn main() {
    let digit: char = '7';
    return 0;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 char literal", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("char literals should fail closed until native x86 literal layout exists");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "char literal rejection should use the stable x86 backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "char literal rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 literal expression")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the native literal boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the literal source line");
            assert_eq!(
                source_line, "    let digit: char = '7';",
                "diagnostic should point at the unsupported char literal: {message}"
            );
            let literal_start = source_line
                .find("'7'")
                .map(|column| column + 1)
                .expect("fixture should contain the char literal");
            let literal_end = literal_start + "'7'".len();
            assert!(
                (literal_start..=literal_end).contains(&label.column),
                "diagnostic column should fall inside the char literal: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 char literal diagnostic, got {other:?}"),
    }
}

#[test]
fn x86_rejects_short_circuit_rhs_call_before_eager_lowering() {
    let cases = [
        (
            "and",
            r#"
fn rhs() -> bool {
    return true;
}

fn main() -> bool {
    let left: bool = false;
    return left && rhs();
}
"#,
            "    return left && rhs();",
        ),
        (
            "or",
            r#"
fn rhs() -> bool {
    return false;
}

fn main() -> bool {
    let left: bool = true;
    return left || rhs();
}
"#,
            "    return left || rhs();",
        ),
    ];

    for (name, source, expected_line) in cases {
        let source = source.to_owned();
        let err = common::run_gpu_codegen_with_timeout(
            &format!("x86 short-circuit RHS call {name}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .expect_err("RHS calls in short-circuit expressions should fail until conditional call lowering exists");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                let rendered = diagnostic.render();
                assert_eq!(
                    diagnostic.code, "LNC0017",
                    "short-circuit call rejection should use the stable backend diagnostic: {rendered}"
                );
                assert_eq!(
                    diagnostic.category, "native codegen",
                    "short-circuit call rejection should stay in the native-codegen category: {rendered}"
                );
                assert!(
                    diagnostic
                        .message
                        .contains("unsupported x86 short-circuit call operand")
                        && rendered.contains("native x86 backend"),
                    "diagnostic should name the short-circuit call boundary: {rendered}"
                );
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 diagnostic should include a primary source label");
                let source_line = label
                    .source_line
                    .as_deref()
                    .expect("x86 diagnostic should include the short-circuit source line");
                assert_eq!(
                    source_line, expected_line,
                    "diagnostic should point at the short-circuit expression: {rendered}"
                );
                let call_start_column = source_line
                    .find("rhs")
                    .map(|column| column + 1)
                    .expect("fixture should contain the RHS call token");
                let call_end_column = source_line
                    .find("();")
                    .map(|column| column + 3)
                    .expect("fixture should contain the RHS call expression");
                assert!(
                    (call_start_column..=call_end_column).contains(&label.column),
                    "diagnostic column should fall inside the RHS call: {rendered}"
                );
            }
            CompileError::GpuCodegen(message) => {
                panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
            }
            other => panic!("expected x86 diagnostic rejection, got {other:?}"),
        }
    }
}

#[test]
fn x86_rejects_nested_short_circuit_rhs_call_before_eager_lowering() {
    let source = r#"
fn rhs() -> bool {
    return true;
}

fn main() -> bool {
    let left: bool = false;
    return left && (rhs() == true);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout(
        "x86 nested short-circuit RHS call",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .expect_err(
        "nested RHS calls in short-circuit expressions should fail until conditional call lowering exists",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "nested short-circuit call rejection should use the stable backend diagnostic: {rendered}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "nested short-circuit call rejection should stay in the native-codegen category: {rendered}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 short-circuit call operand")
                    && rendered.contains("native x86 backend"),
                "diagnostic should name the short-circuit call boundary: {rendered}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the short-circuit source line");
            assert_eq!(
                source_line, "    return left && (rhs() == true);",
                "diagnostic should point at the short-circuit expression: {rendered}"
            );
            let call_start_column = source_line
                .find("rhs")
                .map(|column| column + 1)
                .expect("fixture should contain the RHS call token");
            let call_end_column = source_line
                .find("()")
                .map(|column| column + 2)
                .expect("fixture should contain the RHS call expression");
            assert!(
                (call_start_column..=call_end_column).contains(&label.column),
                "diagnostic column should fall inside the nested RHS call: {rendered}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_deeply_nested_short_circuit_rhs_call_without_depth_limit() {
    let source = r#"
fn rhs() -> bool {
    return true;
}

fn main() -> bool {
    let left: bool = false;
    return left && ((((((((rhs() == true) == true) == true) == true) == true) == true) == true) == true);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout(
        "x86 deeply nested short-circuit RHS call",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .expect_err("short-circuit RHS call rejection should not depend on a fixed parent depth");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "deep short-circuit call rejection should use the stable backend diagnostic: {rendered}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 short-circuit call operand")
                    && rendered.contains("native x86 backend"),
                "diagnostic should name the short-circuit call boundary: {rendered}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the short-circuit source line");
            let call_start_column = source_line
                .find("rhs")
                .map(|column| column + 1)
                .expect("fixture should contain the RHS call token");
            let call_end_column = source_line
                .find("()")
                .map(|column| column + 2)
                .expect("fixture should contain the RHS call expression");
            assert!(
                (call_start_column..=call_end_column).contains(&label.column),
                "diagnostic column should fall inside the deeply nested RHS call: {rendered}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_short_circuit_rhs_trapping_arithmetic_before_eager_lowering() {
    let source = r#"
fn main() -> bool {
    let left: bool = false;
    return left && ((12 / 0) == 0);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout(
        "x86 short-circuit RHS trapping arithmetic",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .expect_err(
        "RHS arithmetic that needs trap-aware lowering should fail until conditional lowering exists",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "short-circuit arithmetic rejection should use the stable backend diagnostic: {rendered}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "short-circuit arithmetic rejection should stay in native codegen: {rendered}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 short-circuit trapping operand")
                    && rendered.contains("native x86 backend"),
                "diagnostic should identify the conditional trap-lowering boundary: {rendered}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the short-circuit source line");
            let operand_start = source_line
                .find("12 / 0")
                .map(|column| column + 1)
                .expect("fixture should contain the trapping RHS operand");
            let operand_end = operand_start + "12 / 0".len();
            assert!(
                (operand_start..=operand_end).contains(&label.column),
                "diagnostic column should fall inside the RHS trapping operand: {rendered}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_short_circuit_rhs_dynamic_index_before_eager_lowering() {
    let source = r#"
fn check(index: i32) -> bool {
    let values: [i32; 2] = [1, 2];
    return true || (values[index] == 2);
}

fn main() -> bool {
    return check(1);
}
"#
    .to_owned();

    let err =
        common::run_gpu_codegen_with_timeout("x86 short-circuit RHS dynamic index", move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err(
            "RHS dynamic indexing should fail until short-circuit lowering can avoid eager loads",
        );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let rendered = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "short-circuit index rejection should use the stable backend diagnostic: {rendered}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "short-circuit index rejection should stay in native codegen: {rendered}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 short-circuit trapping operand")
                    && rendered.contains("native x86 backend"),
                "diagnostic should identify the conditional trap-lowering boundary: {rendered}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the short-circuit source line");
            assert_eq!(
                source_line, "    return true || (values[index] == 2);",
                "diagnostic should point at the short-circuit RHS index expression: {rendered}"
            );
            let index_start = source_line
                .find("index")
                .map(|column| column + 1)
                .expect("fixture should contain the dynamic index operand");
            let index_end = index_start + "index".len();
            assert!(
                (index_start..=index_end).contains(&label.column),
                "diagnostic column should fall inside the dynamic index operand: {rendered}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_executes_scalar_div_mod_bitwise_and_shift_ops() {
    assert_source_exit(
        "scalar_div_mod_bitwise_shift_ops",
        r#"
fn main() {
    let value: i32 = 27;
    let quotient: i32 = value / 3;
    let remainder: i32 = value % 4;
    let flags: i32 = (6 & 3) | (8 >> 1);
    let shifted: i32 = (1 << -(1 - 4)) ^ 2;
    return quotient * 10 + remainder + flags + shifted;
}
"#,
        109,
    );
}

#[test]
fn x86_executes_runtime_unary_not_and_negation() {
    assert_source_exit(
        "runtime_unary_not_and_negation",
        r#"
fn main() {
    let value: i32 = 7;
    let negative: i32 = -value;
    if (!(negative > 0)) {
        return -negative;
    }
    return 1;
}
"#,
        7,
    );
}

#[test]
fn x86_executes_unsigned_div_mod_without_signed_reinterpretation() {
    assert_source_exit(
        "unsigned_div_mod_without_signed_reinterpretation",
        r#"
fn main() -> u32 {
    let value: u32 = 4000000000;
    let divisor: u32 = 1000000000;
    let quotient: u32 = value / divisor;
    let remainder: u32 = value % divisor;
    return quotient * 10 + remainder;
}
"#,
        40,
    );
}

#[test]
fn x86_executes_unsigned_right_shift_without_signed_reinterpretation() {
    assert_source_exit(
        "unsigned_right_shift_without_signed_reinterpretation",
        r#"
fn main() -> u32 {
    let value: u32 = 2147483648;
    let shifted: u32 = value >> 28;
    let assigned: u32 = 2147483648;
    assigned >>= 29;
    return shifted * 10 + assigned;
}
"#,
        84,
    );
}

#[test]
fn x86_executes_unsigned_compound_div_mod_without_signed_reinterpretation() {
    assert_source_exit(
        "unsigned_compound_div_mod_without_signed_reinterpretation",
        r#"
fn main() -> bool {
    let quotient: u32 = 4294967294;
    quotient /= 2;
    let remainder: u32 = 4294967295;
    remainder %= 2;
    return quotient == 2147483647 && remainder == 1;
}
"#,
        1,
    );
}

#[test]
fn x86_preserves_live_local_across_call_and_division_barriers() {
    assert_source_exit(
        "live_local_across_call_and_division_barriers",
        r#"
fn id(value: i32) -> i32 {
    return value;
}

fn main() {
    let keep: i32 = 17;
    let observed: i32 = id(4);
    let quotient: i32 = 27 / 3;
    return keep + observed + quotient;
}
"#,
        30,
    );
}

#[test]
fn x86_preserves_live_local_across_call_and_shift_barriers() {
    assert_source_exit(
        "live_local_across_call_and_shift_barriers",
        r#"
fn id(value: i32) -> i32 {
    return value;
}

fn main() {
    let keep: i32 = 19;
    let amount: i32 = id(3);
    let shifted: i32 = 1 << amount;
    return keep + amount + shifted;
}
"#,
        30,
    );
}

#[test]
fn x86_traps_out_of_range_dynamic_shift_count() {
    let source = r#"
fn shift_by(amount: i32) -> i32 {
    return 1 << amount;
}

fn main() {
    let amount: i32 = 32;
    return shift_by(amount);
}
"#
    .to_owned();

    let bytes = common::run_gpu_codegen_with_timeout("x86 dynamic shift count", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect("dynamic shift counts should compile with a generated runtime range check");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 dynamic shift count",
        "x86_dynamic_shift_count",
        &bytes,
        102,
    );
}

#[test]
fn x86_executes_shaped_compile_time_safe_divisor() {
    assert_source_exit(
        "shaped_compile_time_safe_divisor",
        r#"
fn main() {
    return 12 / (1 + 2);
}
        "#,
        4,
    );
}

#[test]
fn x86_executes_dynamic_divisor_with_runtime_trap_checks() {
    assert_source_exit(
        "dynamic_divisor_runtime_trap_checks",
        r#"
fn divide(value: i32, divisor: i32) -> i32 {
    return value / divisor;
}

fn remainder(value: i32, divisor: i32) -> i32 {
    return value % divisor;
}

fn main() {
    return divide(12, 3) + remainder(17, 5);
}
"#,
        6,
    );
}

#[test]
fn x86_traps_mutated_local_zero_divisor_at_runtime() {
    assert_source_exit(
        "mutated_local_zero_divisor_runtime_trap",
        r#"
fn main() {
    let divisor: i32 = 3;
    divisor = 0;
    return 12 / divisor;
}
"#,
        103,
    );
}

#[test]
fn x86_executes_negative_one_divisor_with_runtime_overflow_check() {
    assert_source_exit(
        "negative_one_divisor_runtime_overflow_check",
        r#"
fn divide(value: i32) -> i32 {
    return value / -1;
}

fn main() {
    return divide(-7);
}
"#,
        7,
    );
}

#[test]
fn x86_executes_scalar_compound_assignment_ops() {
    assert_source_exit(
        "scalar_compound_assignment_ops",
        r#"
fn main() {
    let value: i32 = 48;
    value /= 3;
    value %= 5;
    value |= 8;
    value &= 11;
    value ^= 2;
    value <<= 1;
    value >>= 2;
    value -= 1;
    value *= 3;
    return value;
}
"#,
        12,
    );
}

#[test]
fn x86_executes_four_argument_call_with_mixed_argument_sources() {
    assert_source_exit(
        "four_argument_call_mixed_sources",
        r#"
fn mix(first: i32, second: i32, third: i32, fourth: i32) -> i32 {
    return first * 10 + second * 3 + third - fourth;
}

fn main() {
    let local: i32 = 4;
    let other: i32 = 6;
    return mix(local, 2 + 1, other, 5);
}
"#,
        50,
    );
}

#[test]
fn x86_executes_nested_call_results_as_call_arguments() {
    assert_source_exit(
        "nested_call_results_as_call_arguments",
        r#"
fn inc(value: i32) -> i32 {
    return value + 1;
}

fn mix(left: i32, right: i32) -> i32 {
    return left * 10 + right;
}

fn main() {
    return mix(inc(3), inc(4));
}
"#,
        45,
    );
}

#[test]
fn x86_executes_six_argument_call_with_nested_call_values() {
    assert_source_exit(
        "six_argument_call_nested_values",
        r#"
fn inc(value: i32) -> i32 {
    return value + 1;
}

fn weighted(
    first: i32,
    second: i32,
    third: i32,
    fourth: i32,
    fifth: i32,
    sixth: i32,
) -> i32 {
    return first + second * 2 + third * 3 + fourth * 4 + fifth * 5 + sixth * 6;
}

fn main() {
    let local: i32 = 7;
    return weighted(inc(1), inc(2), inc(local), inc(3), inc(4), inc(5));
}
"#,
        109,
    );
}

#[test]
fn x86_executes_bool_returning_helper_call_in_branch_condition() {
    assert_source_exit(
        "bool_returning_helper_call_branch_condition",
        r#"
fn between(value: i32, low: i32, high: i32) -> bool {
    return value > low && value < high;
}

fn main() {
    if (between(7, 3, 10)) {
        return 9;
    } else {
        return 1;
    }
}
"#,
        9,
    );
}

#[test]
fn x86_executes_helper_branch_early_return_and_fallthrough_return() {
    assert_source_exit(
        "helper_branch_early_return_fallthrough",
        r#"
fn adjusted(value: i32) -> i32 {
    if (value < 0) {
        return -value;
    }
    return value + 1;
}

fn main() {
    return adjusted(-6) + adjusted(4);
}
"#,
        11,
    );
}

#[test]
fn x86_executes_while_break_and_continue() {
    assert_source_exit(
        "while_break_continue",
        r#"
fn main() {
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 8) {
        i += 1;
        if (i == 3) {
            continue;
        }
        if (i > 5) {
            break;
        }
        total += i;
    }
    return total;
}
"#,
        12,
    );
}

#[test]
fn x86_rejects_break_continue_outside_repetition_with_diagnostic() {
    let cases = [
        (
            "break",
            r#"
fn main() {
    break;
    return 0;
}
"#,
            "    break;",
        ),
        (
            "continue",
            r#"
fn main() {
    continue;
    return 0;
}
"#,
            "    continue;",
        ),
    ];

    for (name, source, expected_line) in cases {
        let source = source.to_owned();
        let err = common::run_gpu_codegen_with_timeout(
            &format!("x86 break continue outside repetition {name}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .expect_err(
            "break/continue outside repetition should fail before native branches are emitted",
        );

        match err {
            CompileError::Diagnostic(diagnostic) => {
                let message = diagnostic.render();
                assert_eq!(
                    diagnostic.code, "LNC0041",
                    "break/continue rejection should use the stable frontend diagnostic: {message}"
                );
                assert_eq!(
                    diagnostic.category, "type checking",
                    "break/continue rejection should fail before native codegen: {message}"
                );
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 diagnostic should include a primary source label");
                assert_eq!(
                    label.source_line.as_deref(),
                    Some(expected_line),
                    "diagnostic should point at the unsupported break/continue statement: {message}"
                );
            }
            CompileError::GpuCodegen(message) => {
                panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
            }
            other => panic!("expected x86 diagnostic rejection, got {other:?}"),
        }
    }
}

#[test]
fn x86_executes_early_return_from_loop_body() {
    assert_source_exit(
        "early_return_from_loop_body",
        r#"
fn main() {
    let i: i32 = 0;
    while (i < 5) {
        if (i == 3) {
            return i + 4;
        }
        i += 1;
    }
    return 99;
}
"#,
        7,
    );
}

#[test]
fn x86_executes_for_array_with_break_and_continue() {
    assert_source_exit(
        "for_array_break_continue",
        r#"
fn main() {
    let values: [i32; 6] = [1, 2, 3, 4, 5, 6];
    let total: i32 = 0;
    for value in values {
        if (value == 2) {
            continue;
        }
        if (value == 5) {
            break;
        }
        total += value;
    }
    return total;
}
"#,
        8,
    );
}

#[test]
fn x86_executes_early_return_from_for_array_body() {
    assert_source_exit(
        "early_return_from_for_array_body",
        r#"
fn main() {
    let values: [i32; 4] = [1, 2, 3, 4];
    for value in values {
        if (value == 3) {
            return value + 4;
        }
    }
    return 99;
}
"#,
        7,
    );
}

#[test]
fn x86_executes_for_array_with_helper_call_and_branch() {
    assert_source_exit(
        "for_array_helper_call_branch",
        r#"
fn adjust(value: i32) -> i32 {
    return value * 2;
}

fn main() {
    let values: [i32; 4] = [1, 2, 3, 4];
    let total: i32 = 0;
    for value in values {
        if (value == 3) {
            total += adjust(value);
        } else {
            total += value;
        }
    }
    return total;
}
"#,
        13,
    );
}

#[test]
fn x86_executes_numeric_range_for_loop_with_dynamic_end() {
    assert_source_exit(
        "numeric_range_for_loop_dynamic_end",
        r#"
fn sum_range(end: i32) -> i32 {
    let total: i32 = 0;
    for value in 2..end {
        if (value == 3) {
            continue;
        }
        if (value == 6) {
            break;
        }
        total += value;
    }
    return total;
}

fn main() -> i32 {
    return sum_range(8);
}
"#,
        11,
    );
}

#[test]
fn x86_executes_numeric_range_for_loop_with_struct_field_end() {
    assert_source_exit(
        "numeric_range_for_loop_struct_field_end",
        r#"
struct Settings {
    samples: i32,
}

fn count_samples(settings: Settings) -> i32 {
    let samples: i32 = settings.samples;
    let total: i32 = 0;
    for sample_y in 0..samples {
        for sample_x in 0..samples {
            total += 1;
        }
    }
    return total;
}

fn main() -> i32 {
    let settings: Settings = Settings { samples: 3 };
    return count_samples(settings);
}
"#,
        9,
    );
}

#[test]
fn x86_executes_nested_range_f32_accumulation() {
    assert_source_exit(
        "nested_range_f32_accumulation",
        r#"
struct Settings {
    samples: i32,
}

fn accumulate(settings: Settings) -> f32 {
    let samples: i32 = settings.samples;
    let total: f32 = 0.0;
    for sample_y in 0..samples {
        for sample_x in 0..samples {
            total = total + 0.25;
        }
    }
    return total;
}

fn main() -> i32 {
    let settings: Settings = Settings { samples: 2 };
    let value: f32 = accumulate(settings);
    if (value > 0.99 && value < 1.01) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_rejects_struct_for_iterable_without_record_with_diagnostic() {
    let source = r#"
struct Range {
    start: i32,
    end: i32,
}

fn main() {
    let range: Range = Range { start: 1, end: 5 };
    let total: i32 = 0;
    for value in range {
        total += value;
    }
    return total;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 struct for iterable", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err(
        "struct for iterables should fail until x86 lowering consumes an explicit iterable record",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "struct for-iterable rejection should use the stable x86 diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "struct for-iterable rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic.message.contains("unsupported x86 for iterable"),
                "diagnostic should identify the native iterable boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    for value in range {"),
                "diagnostic should point at the unsupported for statement: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_scalar_for_iterable_with_diagnostic() {
    let source = r#"
fn main() {
    let limit: i32 = 3;
    let total: i32 = 0;
    for value in limit {
        total += value;
    }
    return total;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 scalar for iterable", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err(
        "scalar for iterables should fail closed until x86 iteration lowering supports them",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "scalar for-iterable rejection should use the stable x86 diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("x86") && diagnostic.message.contains("iterable"),
                "diagnostic should identify the native iterable boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    for value in limit {"),
                "diagnostic should point at the unsupported for statement: {message}"
            );
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the source line");
            assert!(
                (1..=source_line.len()).contains(&label.column),
                "diagnostic column should fall inside the for statement: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_stage_status_pairs_error_code_with_min_detail() {
    let source = r#"
fn main() {
    let limit: i32 = 3;
    let total: i32 = 0;
    for value in limit {
        total += value;
    }
    let later: str = "not yet";
    return total;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 min-detail status pairing", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("the earliest unsupported x86 node should determine both code and label");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert!(
                diagnostic.message.contains("unsupported x86 for iterable"),
                "diagnostic code/message should follow the earliest unsupported node, not a later literal: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    for value in limit {"),
                "diagnostic label should stay paired with the reported x86 error: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_source_pack_rejects_scalar_for_iterable_with_diagnostic() {
    let sources = [
        r#"
module helpers::limits;

pub const LIMIT: i32 = 3;
"#,
        r#"
module app::main;

import helpers::limits;

fn main() {
    let limit: i32 = helpers::limits::LIMIT;
    let total: i32 = 0;
    for value in limit {
        total += value;
    }
    return total;
}
"#,
    ];

    let err = common::run_gpu_codegen_with_timeout("x86 source-pack scalar for iterable", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect_err(
        "source-pack scalar for iterables should fail closed until x86 iteration lowering supports them",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "source-pack scalar for-iterable rejection should use the stable x86 diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "source-pack scalar for-iterable rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic.message.contains("unsupported x86 for iterable")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the native iterable boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(label.path.display().to_string(), "<source pack file 1>");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the source line");
            assert_eq!(
                source_line, "    for value in limit {",
                "diagnostic should point at the unsupported source-pack for statement: {message}"
            );
            let for_start_column = source_line
                .find("for")
                .map(|column| column + 1)
                .expect("fixture should contain the for statement");
            assert!(
                (for_start_column..=source_line.len()).contains(&label.column),
                "diagnostic column should fall inside the source-pack for statement: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected source-pack x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_executes_array_literal_index_sum() {
    assert_source_exit(
        "array_literal_index_sum",
        r#"
fn main() {
    let values: [i32; 3] = [1, 2, 3];
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 3) {
        total += values[i];
        i += 1;
    }
    return total;
}
"#,
        6,
    );
}

#[test]
fn x86_executes_array_literal_with_local_element_expressions() {
    assert_source_exit(
        "array_literal_local_element_expressions",
        r#"
fn main() {
    let seed: i32 = 4;
    let values: [i32; 3] = [seed, seed + 1, seed * 2];
    return values[0] * 10 + values[1] + values[2];
}
"#,
        53,
    );
}

#[test]
fn x86_executes_for_loop_over_struct_array() {
    assert_source_exit(
        "for_loop_struct_array",
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn sum(values: [Pair; 3]) -> i32 {
    let total: i32 = 0;
    for pair in values {
        total += pair.left * 10 + pair.right;
    }
    return total;
}

fn main() {
    let values: [Pair; 3] = [
        Pair { left: 1, right: 2 },
        Pair { left: 3, right: 4 },
        Pair { left: 5, right: 6 },
    ];
    return sum(values);
}
"#,
        102,
    );
}

#[test]
fn x86_executes_bounded_aggregate_copy_as_value() {
    assert_source_exit(
        "bounded_aggregate_copy_value",
        r#"
fn main() {
    let original: [i32; 3] = [4, 5, 6];
    let copied: [i32; 3] = original;
    copied[1] += 10;
    return original[1] * 10 + copied[1];
}
"#,
        65,
    );
}

#[test]
fn x86_executes_struct_literal_field_mutation_and_copy() {
    assert_source_exit(
        "struct_literal_field_mutation_copy",
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn main() {
    let pair: Pair = Pair { left: 7, right: 5 };
    pair.right += 10;
    let copied: Pair = pair;
    return copied.left * 10 + copied.right;
}
"#,
        85,
    );
}

#[test]
fn x86_executes_struct_parameter_member_reads() {
    assert_source_exit(
        "struct_parameter_member_reads",
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn score(pair: Pair) -> i32 {
    return pair.left * 10 + pair.right;
}

fn main() {
    let pair: Pair = Pair { left: 4, right: 7 };
    return score(pair);
}
"#,
        47,
    );
}

#[test]
fn x86_executes_single_field_struct_parameter_member_reads() {
    assert_source_exit(
        "single_field_struct_parameter_member_reads",
        r#"
struct Boxed {
    value: i32,
}

fn read(value: Boxed) -> i32 {
    return value.value;
}

fn main() {
    let value: Boxed = Boxed { value: 9 };
    return read(value);
}
"#,
        9,
    );
}

#[test]
fn x86_executes_generic_struct_parameter_member_reads() {
    assert_source_exit(
        "generic_struct_parameter_member_reads",
        r#"
struct Boxed<T> {
    value: i32,
}

fn read<T>(value: Boxed<T>) -> i32 {
    return value.value;
}

fn main() {
    let value: Boxed<i32> = Boxed { value: 9 };
    return read(value);
}
"#,
        9,
    );
}

#[test]
fn x86_executes_source_pack_struct_literal_return_from_helper() {
    let sources = [
        r#"
module core::i32;

pub struct WrappingMul {
    value: i32,
    rhs: i32,
}

pub fn wrapping_mul(value: i32, rhs: i32) -> WrappingMul {
    return WrappingMul { value: value, rhs: rhs };
}
"#,
        r#"
module app::main;

import core::i32;

fn main() {
    let computed: core::i32::WrappingMul = core::i32::wrapping_mul(7, 5);
    return computed.value + computed.rhs;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack struct literal return helper",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack struct literal return helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack struct literal return helper",
        "x86_source_pack_struct_literal_return_helper",
        &bytes,
        12,
    );
}

#[test]
fn x86_executes_parameter_aggregate_member_assignment() {
    assert_source_exit(
        "parameter_aggregate_member_assignment",
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn rewrite(pair: Pair) -> i32 {
    pair.left = 5;
    pair.right += pair.left;
    return pair.left * 10 + pair.right;
}

fn main() {
    let pair: Pair = Pair { left: 1, right: 2 };
    return rewrite(pair);
}
"#,
        57,
    );
}

#[test]
fn x86_executes_unsigned_parameter_member_compound_ops() {
    assert_source_exit(
        "unsigned_parameter_member_compound_ops",
        r#"
struct Pair {
    left: u32,
    right: u32,
}

fn rewrite(pair: Pair) -> bool {
    pair.left /= 2;
    pair.right >>= 31;
    return pair.left == 2147483647 && pair.right == 1;
}

fn main() -> bool {
    let zero: u32 = 0;
    let pair: Pair = Pair { left: zero, right: zero };
    pair.left = 4294967294;
    pair.right = 2147483648;
    return rewrite(pair);
}
"#,
        1,
    );
}

#[test]
fn x86_executes_parameter_aggregate_indexed_assignment() {
    assert_source_exit(
        "parameter_aggregate_indexed_assignment",
        r#"
fn rewrite(values: [i32; 3]) -> i32 {
    let index: i32 = 1;
    values[index] = values[0] + 7;
    values[2] += values[index];
    return values[1] * 10 + values[2];
}

fn main() {
    let values: [i32; 3] = [2, 4, 5];
    return rewrite(values);
}
"#,
        104,
    );
}

#[test]
fn x86_executes_source_pack_parameter_aggregate_indexed_assignment() {
    let sources = [
        r#"
module helpers::arrays;

pub fn rewrite(values: [i32; 3], bump: i32) -> i32 {
    let index: i32 = 1;
    values[index] = values[0] + bump;
    values[2] += values[index];
    return values[1] * 10 + values[2];
}
"#,
        r#"
module app::main;

import helpers::arrays;

fn main() {
    let values: [i32; 3] = [3, 4, 6];
    return helpers::arrays::rewrite(values, 5);
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack parameter aggregate indexed assignment",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack parameter aggregate indexed assignment should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack parameter aggregate indexed assignment",
        "x86_source_pack_parameter_aggregate_indexed_assignment",
        &bytes,
        94,
    );
}

#[test]
fn x86_executes_indexed_assignment_with_dynamic_index() {
    assert_source_exit(
        "indexed_assignment_dynamic_index",
        r#"
fn main() {
    let values: [i32; 4] = [1, 2, 3, 4];
    let index: i32 = 1;
    values[index] = values[2] + 5;
    values[3] += values[index];
    return values[0] + values[1] + values[2] + values[3];
}
"#,
        24,
    );
}

#[test]
fn x86_executes_unsigned_indexed_compound_div_mod_without_signed_reinterpretation() {
    assert_source_exit(
        "unsigned_indexed_compound_div_mod",
        r#"
fn main() -> bool {
    let zero: u32 = 0;
    let values: [u32; 2] = [zero, zero];
    values[0] = 4294967294;
    values[1] = 4294967295;
    let index: i32 = 0;
    values[index] /= 2;
    values[1] %= 2;
    return values[0] == 2147483647 && values[1] == 1;
}
"#,
        1,
    );
}

#[test]
fn x86_executes_indexed_assignment_inside_loop_branch() {
    assert_source_exit(
        "indexed_assignment_loop_branch",
        r#"
fn main() {
    let values: [i32; 4] = [0, 10, 20, 30];
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 4) {
        if (i == 1) {
            values[i] += 5;
        } else {
            values[i] = values[i] + i;
        }
        total += values[i];
        i += 1;
    }
    return total;
}
"#,
        70,
    );
}

#[test]
fn x86_rejects_static_out_of_bounds_array_index_before_native_memory_access() {
    let cases = [
        (
            "literal_read",
            r#"
fn main() {
    let values: [i32; 3] = [1, 2, 3];
    return values[3];
}
"#,
            "    return values[3];",
        ),
        (
            "const_expression_read",
            r#"
fn main() {
    let values: [i32; 3] = [1, 2, 3];
    return values[1 + 2];
}
"#,
            "    return values[1 + 2];",
        ),
    ];

    for (name, source, expected_line) in cases {
        let source = source.to_owned();
        let err = common::run_gpu_codegen_with_timeout(
            &format!("x86 static out-of-bounds array index {name}"),
            move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
        )
        .expect_err("known out-of-bounds array indexes should fail before native memory access");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                let message = diagnostic.render();
                assert_eq!(
                    diagnostic.code, "LNC0017",
                    "array-index rejection should use the stable backend diagnostic: {message}"
                );
                assert!(
                    diagnostic
                        .message
                        .contains("unsupported x86 array index bounds")
                        && message.contains("native x86 backend"),
                    "diagnostic should identify the static array-index boundary: {message}"
                );
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 diagnostic should include a primary source label");
                assert_eq!(
                    label.source_line.as_deref(),
                    Some(expected_line),
                    "diagnostic should point at the out-of-bounds index expression: {message}"
                );
            }
            CompileError::GpuCodegen(message) => {
                panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
            }
            other => panic!("expected x86 diagnostic rejection, got {other:?}"),
        }
    }
}

#[test]
fn x86_traps_local_literal_array_index_through_runtime_bounds_check() {
    assert_source_exit(
        "local_literal_array_index_runtime_bounds_check",
        r#"
fn main() {
    let values: [i32; 2] = [7, 8];
    let index: i32 = 3;
    return values[index];
}
"#,
        101,
    );
}

#[test]
fn x86_executes_parameter_array_index_with_runtime_bounds_check() {
    assert_source_exit(
        "parameter_array_index_runtime_bounds_check",
        r#"
fn pick(values: [i32; 2], index: i32) -> i32 {
    return values[index];
}

fn main() {
    let values: [i32; 2] = [7, 8];
    return pick(values, 1);
}
"#,
        8,
    );
}

#[test]
fn x86_traps_mutated_local_array_index_out_of_bounds() {
    assert_source_exit(
        "mutated_local_array_index_out_of_bounds",
        r#"
fn main() {
    let values: [i32; 2] = [7, 8];
    let index: i32 = 0;
    index = 3;
    return values[index];
}
"#,
        101,
    );
}

#[test]
fn x86_rejects_unsized_slice_parameter_index_with_diagnostic() {
    let source = r#"
fn first(values: [i32], index: i32) -> i32 {
    return values[index];
}

fn main() {
    return 0;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 unsized slice index", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("unsized slice parameter indexes should fail before native memory access");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "slice-index rejection should use the stable x86 backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "slice-index rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 dynamic array index")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the dynamic index boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the indexed slice source line");
            assert_eq!(
                source_line, "    return values[index];",
                "diagnostic should point at the unsupported slice index: {message}"
            );
            let index_start = source_line
                .find("index")
                .map(|column| column + 1)
                .expect("fixture should contain the index operand");
            let index_end = index_start + "index".len();
            assert!(
                (index_start..=index_end).contains(&label.column),
                "diagnostic column should fall inside the index operand: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_aggregate_return_call_without_destination_with_diagnostic() {
    let sources = [
        "module core::i32;\npub struct Pair {\n    left: i32,\n    right: i32,\n}\npub fn make_pair(left: i32, right: i32) -> Pair {\n    return Pair { left: left, right: right };\n}\n",
        "module app::main;\nimport core::i32;\nfn main() {\n    core::i32::make_pair(7, 5);\n    return 0;\n}\n",
    ];

    let err = common::run_gpu_codegen_with_timeout(
        "x86 aggregate return call without destination",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect_err(
        "aggregate-return calls should fail closed unless a destination aggregate row exists",
    );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "aggregate-return call rejection should use the stable backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "aggregate-return call rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 aggregate return call")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the aggregate-return call boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(label.path.display().to_string(), "<source pack file 1>");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the aggregate-return call source line");
            assert_eq!(
                source_line, "    core::i32::make_pair(7, 5);",
                "diagnostic should point at the unsupported aggregate-return call: {message}"
            );
            let call_start = source_line
                .find("core::i32::make_pair")
                .map(|column| column + 1)
                .expect("fixture should contain the aggregate-return call");
            let call_end = source_line
                .find(";")
                .map(|column| column + 1)
                .expect("fixture should contain the end of the aggregate-return call");
            assert!(
                (call_start..=call_end).contains(&label.column),
                "diagnostic column should fall inside the aggregate-return call: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_aggregate_temporary_index_with_diagnostic() {
    let source = r#"
fn values() -> [i32; 2] {
    return [4, 5];
}

fn main() {
    return values()[1];
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 aggregate temporary index", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("aggregate temporaries should fail closed until indexed temporary lowering exists");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "aggregate temporary index rejection should use the stable backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "aggregate temporary index rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 aggregate temporary index")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the aggregate temporary index boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the indexed temporary source line");
            let index_start = source_line
                .find("[1]")
                .map(|column| column + 1)
                .expect("fixture should contain the index expression");
            assert!(
                (1..index_start).contains(&label.column),
                "diagnostic column should point at the aggregate source before the index: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_aggregate_return_temporary_member_with_diagnostic() {
    let source = r#"
struct Pair {
    left: i32,
    right: i32,
}

fn pair() -> Pair {
    return Pair { left: 4, right: 5 };
}

fn main() {
    return pair().left;
}
"#
    .to_owned();

    let err =
        common::run_gpu_codegen_with_timeout("x86 aggregate return temporary member", move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err(
            "aggregate temporaries should fail closed until member temporary lowering exists",
        );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "aggregate temporary member rejection should use the stable backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "aggregate temporary member rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 aggregate temporary member")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the aggregate temporary member boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the member temporary source line");
            assert_eq!(
                source_line, "    return pair().left;",
                "diagnostic should point at the aggregate temporary member expression: {message}"
            );
            let member_start = source_line
                .find(".left")
                .map(|column| column + 1)
                .expect("fixture should contain the member access");
            assert!(
                (1..member_start).contains(&label.column),
                "diagnostic column should point at the aggregate source before the member: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_nested_aggregate_member_receiver_with_diagnostic() {
    let source = r#"
struct Inner {
    left: i32,
    right: i32,
}

struct Outer {
    inner: Inner,
    extra: i32,
}

fn read(outer: Outer) -> i32 {
    return outer.inner.left;
}

fn main() {
    return 0;
}
"#
    .to_owned();

    let err =
        common::run_gpu_codegen_with_timeout("x86 nested aggregate member receiver", move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect_err(
            "nested aggregate member receivers should fail until aggregate path rows exist",
        );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "nested aggregate member rejection should use the stable backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "nested aggregate member rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 nested aggregate member")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the nested aggregate-member boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            let source_line = label
                .source_line
                .as_deref()
                .expect("x86 diagnostic should include the nested member source line");
            assert_eq!(
                source_line, "    return outer.inner.left;",
                "diagnostic should point at the nested aggregate member expression: {message}"
            );
            let receiver_start = source_line
                .find("outer.inner")
                .map(|column| column + 1)
                .expect("fixture should contain the nested receiver");
            let receiver_end = receiver_start + "outer.inner".len();
            assert!(
                (receiver_start..=receiver_end).contains(&label.column),
                "diagnostic column should point at the unsupported aggregate receiver: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_aggregate_copy_above_bounded_gpu_row_width() {
    let elements = (0..33)
        .map(|value| value.to_string())
        .collect::<Vec<_>>()
        .join(", ");
    let source = format!(
        r#"
fn main() {{
    let a: [i32; 33] = [{elements}];
    let b: [i32; 33] = a;
    return b[0];
}}
"#
    );

    let err = common::run_gpu_codegen_with_timeout("x86 oversized aggregate copy", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("oversized aggregate copies should fail before virtual row generation");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic
                    .message
                    .contains("unsupported x86 aggregate copy width")
                    && message.contains("native x86 backend"),
                "diagnostic should name the aggregate row-width boundary: {message}"
            );
            assert!(
                message.contains("let b: [i32; 33] = a;"),
                "diagnostic should point at the oversized aggregate copy: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_accepts_float_literals_as_scalar_immediates() {
    assert_source_exit(
        "float_literal_immediates",
        r#"
const HALF: f32 = 0.5;

fn main() {
    let one: f32 = 1.0;
    let two: f32 = 2.0e0;
    let small: f32 = .25;
    let copy: f32 = HALF;
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_arithmetic_and_comparison() {
    assert_source_exit(
        "f32_arithmetic_and_comparison",
        r#"
fn main() {
    let value: f32 = (1.5 + 2.5) * 3.0 / 2.0 - 1.0;
    if (value > 4.9) {
        if (value < 5.1) {
            return 0;
        }
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_addition() {
    assert_source_exit(
        "f32_addition",
        r#"
fn main() {
    let value: f32 = 1.5 + 2.5;
    if (value > 3.9) {
        if (value < 4.1) {
            return 0;
        }
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_sum_of_products() {
    assert_source_exit(
        "f32_sum_of_products",
        r#"
fn main() {
    let value: f32 = 1.5 * 2.0 + 3.0 * 4.0;
    if (value > 14.9) {
        if (value < 15.1) {
            return 0;
        }
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_negation() {
    assert_source_exit(
        "f32_negation",
        r#"
fn main() {
    let value: f32 = -2.5;
    if (value < 0.0) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_negative_literal_comparison_bounds() {
    assert_source_exit(
        "f32_negative_literal_comparison_bounds",
        r#"
fn main() {
    let value: f32 = -1.0;
    if (value > -1.01 && value < -0.99) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_lanius_std_i32_to_f32_conversion() {
    assert_source_exit(
        "lanius_std_i32_to_f32",
        r#"
extern "lanius_std" fn i32_to_f32(value: i32) -> f32;

fn main() {
    let value: f32 = i32_to_f32(7) / 2.0;
    if (value > 3.4) {
        if (value < 3.6) {
            return 0;
        }
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_mutable_f32_threshold_loop() {
    assert_source_exit(
        "mutable_f32_threshold_loop",
        r#"
fn count_to_scaled(value: f32) -> i32 {
    let byte: i32 = 0;
    let threshold: f32 = 1.0;
    while (threshold <= value && byte < 255) {
        byte += 1;
        threshold += 1.0;
    }
    return byte;
}

fn main() {
    return count_to_scaled(4.0);
}
"#,
        4,
    );
}

#[test]
fn x86_executes_raytracer_color_to_byte_shape() {
    assert_source_exit(
        "raytracer_color_to_byte_shape",
        r#"
fn sqrt_approx(value: f32) -> f32 {
    if (value <= 0.0) {
        return 0.0;
    }
    let guess: f32 = value;
    if (guess < 1.0) {
        guess = 1.0;
    }
    let iteration: i32 = 0;
    while (iteration < 8) {
        guess = 0.5 * (guess + value / guess);
        iteration += 1;
    }
    return guess;
}

fn clamp01(value: f32) -> f32 {
    if (value < 0.0) {
        return 0.0;
    }
    if (value > 0.999) {
        return 0.999;
    }
    return value;
}

fn color_to_byte(value: f32) -> i32 {
    let scaled: f32 = sqrt_approx(clamp01(value)) * 256.0;
    let byte: i32 = 0;
    let threshold: f32 = 1.0;
    while (threshold <= scaled && byte < 255) {
        byte += 1;
        threshold += 1.0;
    }
    return byte;
}

fn main() {
    let r: i32 = color_to_byte(0.625);
    let g: i32 = color_to_byte(0.781);
    let b: i32 = color_to_byte(1.0);
    if (!(r > 200 && r < 204)) {
        return 10;
    }
    if (!(g > 225 && g < 228)) {
        return 11;
    }
    if (!(b == 255)) {
        return 12;
    }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_member_argument_to_scalar_call() {
    assert_source_exit(
        "f32_member_argument_to_scalar_call",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

fn sqrt_approx(value: f32) -> f32 {
    if (value <= 0.0) {
        return 0.0;
    }
    let guess: f32 = value;
    if (guess < 1.0) {
        guess = 1.0;
    }
    let iteration: i32 = 0;
    while (iteration < 8) {
        guess = 0.5 * (guess + value / guess);
        iteration += 1;
    }
    return guess;
}

fn clamp01(value: f32) -> f32 {
    if (value < 0.0) {
        return 0.0;
    }
    if (value > 0.999) {
        return 0.999;
    }
    return value;
}

fn color_to_byte(value: f32) -> i32 {
    let scaled: f32 = sqrt_approx(clamp01(value)) * 256.0;
    let byte: i32 = 0;
    let threshold: f32 = 1.0;
    while (threshold <= scaled && byte < 255) {
        byte += 1;
        threshold += 1.0;
    }
    return byte;
}

fn main() {
    let color: Vec3 = Vec3 { x: 0.625, y: 0.781, z: 1.0 };
    let r: i32 = color_to_byte(color.x);
    if (r > 200 && r < 204) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_struct_method_return_and_member_reads() {
    let sources = [
        r#"
module helpers::vec3;

pub struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    pub fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    pub fn mul_scalar(self, scale: f32) -> Vec3 {
        return Vec3::new(self.x * scale, self.y * scale, self.z * scale);
    }
}
"#,
        r#"
module app::main;

import helpers::vec3;

fn main() {
    let base: helpers::vec3::Vec3 = helpers::vec3::Vec3::new(0.5, 0.7, 1.0);
    let value: helpers::vec3::Vec3 = base.mul_scalar(0.5);
    if (value.x > 0.24 && value.x < 0.26) {
        if (value.y > 0.34 && value.y < 0.36) {
            if (value.z > 0.49 && value.z < 0.51) {
                return 0;
            }
        }
    }
    return 1;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack f32 struct method return member reads",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack f32 struct method return should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack f32 struct method return member reads",
        "x86_source_pack_f32_struct_method_return_member_reads",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_f32_struct_constructor_return_and_member_reads() {
    let sources = [
        r#"
module helpers::vec3;

pub struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    pub fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }
}
"#,
        r#"
module app::main;

import helpers::vec3;

fn main() {
    let value: helpers::vec3::Vec3 = helpers::vec3::Vec3::new(0.5, 0.7, 1.0);
    let byte: i32 = 0;
    let threshold: f32 = 0.0;
    while (threshold < value.x && byte < 20) {
        byte += 1;
        threshold += 0.1;
    }
    return byte;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack f32 struct constructor return member reads",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack f32 struct constructor return should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack f32 struct constructor return member reads",
        "x86_source_pack_f32_struct_constructor_return_member_reads",
        &bytes,
        5,
    );
}

#[test]
fn x86_executes_f32_free_struct_constructor_return_and_member_reads() {
    let sources = [
        r#"
module helpers::vec3;

pub struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

pub fn new_vec3(x: f32, y: f32, z: f32) -> Vec3 {
    return Vec3 { x: x, y: y, z: z };
}
"#,
        r#"
module app::main;

import helpers::vec3;

fn main() {
    let value: helpers::vec3::Vec3 = helpers::vec3::new_vec3(0.5, 0.7, 1.0);
    let byte: i32 = 0;
    let threshold: f32 = 0.0;
    while (threshold < value.x && byte < 20) {
        byte += 1;
        threshold += 0.1;
    }
    return byte;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack f32 free struct constructor return member reads",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack f32 free struct constructor return should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack f32 free struct constructor return member reads",
        "x86_source_pack_f32_free_struct_constructor_return_member_reads",
        &bytes,
        5,
    );
}

#[test]
fn x86_executes_f32_struct_constant_return_and_member_reads() {
    let sources = [
        r#"
module helpers::vec3;

pub struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

pub fn constant() -> Vec3 {
    return Vec3 { x: 0.5, y: 0.7, z: 1.0 };
}
"#,
        r#"
module app::main;

import helpers::vec3;

fn main() {
    let value: helpers::vec3::Vec3 = helpers::vec3::constant();
    if (!(value.x > 0.49 && value.x < 0.51)) {
        return 2;
    }
    if (!(value.y > 0.69 && value.y < 0.71)) {
        return 3;
    }
    if (!(value.z > 0.99 && value.z < 1.01)) {
        return 4;
    }
    return 0;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack f32 struct constant return member reads",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack f32 struct constant return should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack f32 struct constant return member reads",
        "x86_source_pack_f32_struct_constant_return_member_reads",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_f32_local_struct_literal_member_reads() {
    assert_source_exit(
        "f32_local_struct_literal_member_reads",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

fn main() {
    let value: Vec3 = Vec3 { x: 0.5, y: 0.7, z: 1.0 };
    if (!(value.x > 0.49 && value.x < 0.51)) {
        return 2;
    }
    if (!(value.y > 0.69 && value.y < 0.71)) {
        return 3;
    }
    if (!(value.z > 0.99 && value.z < 1.01)) {
        return 4;
    }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_local_struct_literal_negative_member_reads() {
    assert_source_exit(
        "f32_local_struct_literal_negative_member_reads",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

fn main() {
    let value: Vec3 = Vec3 { x: 0.5, y: 0.7, z: -1.0 };
    if (!(value.x > 0.49 && value.x < 0.51)) {
        return 2;
    }
    if (!(value.y > 0.69 && value.y < 0.71)) {
        return 3;
    }
    if (!(value.z > -1.01 && value.z < -0.99)) {
        return 4;
    }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_width3_struct_constructor_return_and_member_reads() {
    let sources = [
        r#"
module helpers::triple;

pub struct Triple {
    x: i32,
    y: i32,
    z: i32,
}

pub fn new(x: i32, y: i32, z: i32) -> Triple {
    return Triple { x: x, y: y, z: z };
}
"#,
        r#"
module app::main;

import helpers::triple;

fn main() {
    let value: helpers::triple::Triple = helpers::triple::new(5, 7, 11);
    return value.x * 16 + value.y * 4 + value.z;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack width3 struct constructor return member reads",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack width3 struct constructor return should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack width3 struct constructor return member reads",
        "x86_source_pack_width3_struct_constructor_return_member_reads",
        &bytes,
        119,
    );
}

#[test]
fn x86_executes_width3_assoc_struct_constructor_return_and_member_reads() {
    let sources = [
        r#"
module helpers::triple;

pub struct Triple {
    x: i32,
    y: i32,
    z: i32,
}

impl Triple {
    pub fn new(x: i32, y: i32, z: i32) -> Triple {
        return Triple { x: x, y: y, z: z };
    }
}
"#,
        r#"
module app::main;

import helpers::triple;

fn main() {
    let value: helpers::triple::Triple = helpers::triple::Triple::new(5, 7, 11);
    return value.x * 16 + value.y * 4 + value.z;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack width3 associated struct constructor return member reads",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack width3 associated struct constructor return should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack width3 associated struct constructor return member reads",
        "x86_source_pack_width3_assoc_struct_constructor_return_member_reads",
        &bytes,
        119,
    );
}

#[test]
fn x86_executes_camera_like_explicit_receiver_aggregate_return() {
    assert_source_exit(
        "camera_like_explicit_receiver_aggregate_return",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn add(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x + right.x, self.y + right.y, self.z + right.z);
    }

    fn sub(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x - right.x, self.y - right.y, self.z - right.z);
    }

    fn mul_scalar(self, scale: f32) -> Vec3 {
        return Vec3::new(self.x * scale, self.y * scale, self.z * scale);
    }
}

struct Ray {
    origin: Vec3,
    direction: Vec3,
}

impl Ray {
    fn at(self, t: f32) -> Vec3 {
        let scale: f32 = t;
        let direction: Vec3 = self.direction;
        let offset: Vec3 = direction.mul_scalar(scale);
        let origin: Vec3 = self.origin;
        return origin.add(offset);
    }
}

struct Camera {
    origin: Vec3,
    lower_left_corner: Vec3,
    horizontal: Vec3,
    vertical: Vec3,
}

impl Camera {
    fn ray(self, u: f32, v: f32) -> Ray {
        let horizontal: Vec3 = self.horizontal;
        let vertical: Vec3 = self.vertical;
        let lower_left_corner: Vec3 = self.lower_left_corner;
        let origin: Vec3 = self.origin;
        let across: Vec3 = horizontal.mul_scalar(u);
        let up: Vec3 = vertical.mul_scalar(v);
        let corner_across: Vec3 = lower_left_corner.add(across);
        let target: Vec3 = corner_across.add(up);
        let direction: Vec3 = target.sub(origin);
        let result: Ray = Ray { origin: origin, direction: direction };
        return result;
    }
}

fn main() {
    let origin: Vec3 = Vec3::new(0.0, 0.0, 0.0);
    let lower_left_corner: Vec3 = Vec3::new(-2.0, -1.0, -1.0);
    let horizontal: Vec3 = Vec3::new(4.0, 0.0, 0.0);
    let vertical: Vec3 = Vec3::new(0.0, 2.0, 0.0);
    let camera: Camera = Camera {
        origin: origin,
        lower_left_corner: lower_left_corner,
        horizontal: horizontal,
        vertical: vertical,
    };
    let ray: Ray = camera.ray(0.5, 0.5);
    let direction: Vec3 = ray.direction;
    if (!(direction.x > -0.01 && direction.x < 0.01)) {
        return 1;
    }
    if (!(direction.y > -0.01 && direction.y < 0.01)) {
        return 2;
    }
    if (!(direction.z > -1.01 && direction.z < -0.99)) {
        return 3;
    }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_camera_sky_pixel_color_byte() {
    assert_source_exit(
        "camera_sky_pixel_color_byte",
        r#"
extern "lanius_std" fn i32_to_f32(value: i32) -> f32;

struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn add(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x + right.x, self.y + right.y, self.z + right.z);
    }

    fn sub(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x - right.x, self.y - right.y, self.z - right.z);
    }

    fn mul_scalar(self, scale: f32) -> Vec3 {
        return Vec3::new(self.x * scale, self.y * scale, self.z * scale);
    }

    fn add(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x + right.x, self.y + right.y, self.z + right.z);
    }

    fn sub(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x - right.x, self.y - right.y, self.z - right.z);
    }

    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y + self.z * right.z;
    }

    fn length(self) -> f32 {
        return sqrt_approx(self.dot(self));
    }

    fn unit(self) -> Vec3 {
        let len: f32 = self.length();
        if (len == 0.0) {
            return self;
        }
        return self.mul_scalar(1.0 / len);
    }

    fn lerp(self, right: Vec3, t: f32) -> Vec3 {
        let left_part: Vec3 = self.mul_scalar(1.0 - t);
        let right_part: Vec3 = right.mul_scalar(t);
        return left_part.add(right_part);
    }
}

struct Ray {
    origin: Vec3,
    direction: Vec3,
}

struct Camera {
    origin: Vec3,
    lower_left_corner: Vec3,
    horizontal: Vec3,
    vertical: Vec3,
}

impl Camera {
    fn ray(self, u: f32, v: f32) -> Ray {
        let horizontal: Vec3 = self.horizontal;
        let vertical: Vec3 = self.vertical;
        let lower_left_corner: Vec3 = self.lower_left_corner;
        let origin: Vec3 = self.origin;
        let across: Vec3 = horizontal.mul_scalar(u);
        let up: Vec3 = vertical.mul_scalar(v);
        let corner_across: Vec3 = lower_left_corner.add(across);
        let target: Vec3 = corner_across.add(up);
        let direction: Vec3 = target.sub(origin);
        let result: Ray = Ray {
            origin: origin,
            direction: direction,
        };
        return result;
    }
}

struct RenderSettings {
    width: i32,
    height: i32,
    samples_per_pixel: i32,
}

fn sqrt_approx(value: f32) -> f32 {
    if (value <= 0.0) {
        return 0.0;
    }
    let guess: f32 = value;
    if (guess < 1.0) {
        guess = 1.0;
    }
    let iteration: i32 = 0;
    while (iteration < 8) {
        guess = 0.5 * (guess + value / guess);
        iteration += 1;
    }
    return guess;
}

fn sky_color(ray: Ray) -> Vec3 {
    let direction: Vec3 = ray.direction;
    let dir: Vec3 = direction.unit();
    let t: f32 = 0.5 * (dir.y + 1.0);
    let white: Vec3 = Vec3::new(1.0, 1.0, 1.0);
    let blue: Vec3 = Vec3::new(0.5, 0.7, 1.0);
    return white.lerp(blue, t);
}

fn make_camera(settings: RenderSettings) -> Camera {
    let aspect_ratio: f32 = i32_to_f32(settings.width) / i32_to_f32(settings.height);
    let viewport_height: f32 = 2.0;
    let viewport_width: f32 = aspect_ratio * viewport_height;
    let focal_length: f32 = 1.0;
    let origin: Vec3 = Vec3::new(0.0, 0.0, 0.0);
    let horizontal: Vec3 = Vec3::new(viewport_width, 0.0, 0.0);
    let vertical: Vec3 = Vec3::new(0.0, viewport_height, 0.0);
    let half_horizontal: Vec3 = horizontal.mul_scalar(0.5);
    let half_vertical: Vec3 = vertical.mul_scalar(0.5);
    let focal: Vec3 = Vec3::new(0.0, 0.0, focal_length);
    let lower_step0: Vec3 = origin.sub(half_horizontal);
    let lower_step1: Vec3 = lower_step0.sub(half_vertical);
    let lower_left_corner: Vec3 = lower_step1.sub(focal);
    let result: Camera = Camera {
        origin: origin,
        lower_left_corner: lower_left_corner,
        horizontal: horizontal,
        vertical: vertical,
    };
    return result;
}

fn clamp01(value: f32) -> f32 {
    if (value < 0.0) {
        return 0.0;
    }
    if (value > 0.999) {
        return 0.999;
    }
    return value;
}

fn color_to_byte(value: f32) -> i32 {
    let scaled: f32 = sqrt_approx(clamp01(value)) * 256.0;
    let byte: i32 = 0;
    let threshold: f32 = 1.0;
    while (threshold <= scaled && byte < 255) {
        byte += 1;
        threshold += 1.0;
    }
    return byte;
}

fn pixel_color(camera: Camera, settings: RenderSettings, x: i32, y: i32) -> Vec3 {
    let samples: i32 = settings.samples_per_pixel;
    let samples_f: f32 = i32_to_f32(samples);
    let color_x: f32 = 0.0;
    let color_y: f32 = 0.0;
    let color_z: f32 = 0.0;
    for sample_y in 0..samples {
        for sample_x in 0..samples {
            let x_offset: f32 = (i32_to_f32(sample_x) + 0.5) / samples_f;
            let y_offset: f32 = (i32_to_f32(sample_y) + 0.5) / samples_f;
            let u: f32 = (i32_to_f32(x) + x_offset) / i32_to_f32(settings.width - 1);
            let row_from_top: i32 = settings.height - 1 - y;
            let v: f32 =
                (i32_to_f32(row_from_top) + y_offset) / i32_to_f32(settings.height - 1);
            let ray: Ray = camera.ray(u, v);
            let sample_color: Vec3 = sky_color(ray);
            color_x = color_x + sample_color.x;
            color_y = color_y + sample_color.y;
            color_z = color_z + sample_color.z;
        }
    }
    let sample_scale: f32 = 1.0 / (samples_f * samples_f);
    return Vec3::new(color_x * sample_scale, color_y * sample_scale, color_z * sample_scale);
}

fn main() {
    let settings: RenderSettings = RenderSettings {
        width: 16,
        height: 9,
        samples_per_pixel: 1,
    };
    let camera: Camera = make_camera(settings);
    let color: Vec3 = pixel_color(camera, settings, 0, 0);
    if (!(color.x > 0.60 && color.x < 0.65)) {
        return 20;
    }
    if (!(color.y > 0.75 && color.y < 0.80)) {
        return 21;
    }
    if (!(color.z > 0.99 && color.z < 1.01)) {
        return 22;
    }
    let r: i32 = color_to_byte(color.x);
    let g: i32 = color_to_byte(color.y);
    let b: i32 = color_to_byte(color.z);
    if (!(r > 200 && r < 205)) {
        return 10;
    }
    if (!(g > 223 && g < 228)) {
        return 11;
    }
    if (!(b == 255)) {
        return 12;
    }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_hit_like_bool_and_f32_aggregate_return() {
    assert_source_exit(
        "hit_like_bool_f32_aggregate_return",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn mul_scalar(self, scale: f32) -> Vec3 {
        return Vec3::new(self.x * scale, self.y * scale, self.z * scale);
    }
}

struct Hit {
    ok: bool,
    t: f32,
    point: Vec3,
    normal: Vec3,
    albedo: Vec3,
}

fn make_hit() -> Hit {
    let point: Vec3 = Vec3::new(0.0, 0.0, 0.0);
    let normal: Vec3 = Vec3::new(0.0, 1.0, 0.0);
    let albedo: Vec3 = Vec3::new(0.7, 0.3, 0.3);
    let result: Hit = Hit {
        ok: true,
        t: 1.0,
        point: point,
        normal: normal,
        albedo: albedo,
    };
    return result;
}

fn color_to_digit(value: f32) -> i32 {
    let digit: i32 = 0;
    let threshold: f32 = 0.1;
    while (threshold <= value && digit < 9) {
        digit += 1;
        threshold += 0.1;
    }
    return digit;
}

fn main() {
    let hit: Hit = make_hit();
    if (hit.ok) {
        let color: Vec3 = hit.albedo.mul_scalar(1.0);
        if (color.x > 0.69 && color.x < 0.71) {
            return 0;
        }
        if (color.x > 0.99 && color.x < 1.01) {
            return 1;
        }
        if (color.x > -0.01 && color.x < 0.01) {
            return 2;
        }
        return color_to_digit(color.x);
    }
    return 3;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_false_bool_local_in_aggregate_return() {
    assert_source_exit(
        "false_bool_local_in_aggregate_return",
        r#"
struct Hit {
    ok: bool,
    t: f32,
}

fn make_miss() -> Hit {
    let result_ok: bool = false;
    let result_t: f32 = 0.0;
    let result: Hit = Hit {
        ok: result_ok,
        t: result_t,
    };
    return result;
}

fn main() {
    let hit: Hit = make_miss();
    if (hit.ok) {
        return 1;
    }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_bool_accumulator_survives_aggregate_return_temp() {
    assert_source_exit(
        "bool_accumulator_survives_aggregate_return_temp",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

struct Hit {
    ok: bool,
    t: f32,
    point: Vec3,
    normal: Vec3,
    albedo: Vec3,
}

fn vec3(x: f32, y: f32, z: f32) -> Vec3 {
    return Vec3 { x: x, y: y, z: z };
}

fn miss() -> Hit {
    let point: Vec3 = vec3(0.0, 0.0, 0.0);
    let normal: Vec3 = vec3(0.0, 0.0, 0.0);
    let albedo: Vec3 = vec3(0.0, 0.0, 0.0);
    let result: Hit = Hit {
        ok: false,
        t: 0.0,
        point: point,
        normal: normal,
        albedo: albedo,
    };
    return result;
}

fn combine() -> Hit {
    let result_ok: bool = false;
    let result_t: f32 = 0.0;
    let result_point_x: f32 = 0.0;
    let result_point_y: f32 = 0.0;
    let result_point_z: f32 = 0.0;
    let result_normal_x: f32 = 0.0;
    let result_normal_y: f32 = 0.0;
    let result_normal_z: f32 = 0.0;
    let result_albedo_x: f32 = 0.0;
    let result_albedo_y: f32 = 0.0;
    let result_albedo_z: f32 = 0.0;
    let hit_ground: Hit = miss();
    if (hit_ground.ok) {
        result_ok = true;
        result_t = hit_ground.t;
    }
    let hit_center: Hit = miss();
    if (hit_center.ok) {
        result_ok = true;
        result_t = hit_center.t;
    }
    let result_point: Vec3 = vec3(result_point_x, result_point_y, result_point_z);
    let result_normal: Vec3 = vec3(result_normal_x, result_normal_y, result_normal_z);
    let result_albedo: Vec3 = vec3(result_albedo_x, result_albedo_y, result_albedo_z);
    let result: Hit = Hit {
        ok: result_ok,
        t: result_t,
        point: result_point,
        normal: result_normal,
        albedo: result_albedo,
    };
    return result;
}

fn main() {
    let hit: Hit = combine();
    if (hit.ok) {
        return 1;
    }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_aggregate_parameter_reused_after_aggregate_call() {
    assert_source_exit(
        "aggregate_parameter_reused_after_aggregate_call",
        r#"
struct Ray {
    x: f32,
    y: f32,
    z: f32,
}

struct Hit {
    ok: bool,
    t: f32,
}

fn miss_if_direction_x_negative(ray: Ray) -> Hit {
    let ok: bool = false;
    if (ray.x > 0.0) {
        ok = true;
    }
    return Hit { ok: ok, t: 0.0 };
}

fn reuse(ray: Ray) -> Hit {
    let first: Hit = miss_if_direction_x_negative(ray);
    if (first.ok) {
        return first;
    }
    let second: Hit = miss_if_direction_x_negative(ray);
    return second;
}

fn main() {
    let ray: Ray = Ray { x: -1.0, y: 0.0, z: -1.0 };
    let hit: Hit = reuse(ray);
    if (hit.ok) {
        return 1;
    }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_second_aggregate_parameter_reused_after_call() {
    assert_source_exit(
        "second_aggregate_parameter_reused_after_call",
        r#"
struct Sphere {
    x: f32,
    radius: f32,
}

struct Ray {
    x: f32,
    y: f32,
    z: f32,
}

struct Hit {
    ok: bool,
    t: f32,
}

fn miss_if_sum_positive(sphere: Sphere, ray: Ray) -> Hit {
    let ok: bool = false;
    let sum: f32 = sphere.x + ray.x;
    if (sum > 0.0) {
        ok = true;
    }
    return Hit { ok: ok, t: 0.0 };
}

fn reuse(ray: Ray) -> Hit {
    let left: Sphere = Sphere { x: 0.25, radius: 1.0 };
    let first: Hit = miss_if_sum_positive(left, ray);
    if (first.ok) {
        return Hit { ok: true, t: 2.0 };
    }
    let right: Sphere = Sphere { x: 0.5, radius: 1.0 };
    let second: Hit = miss_if_sum_positive(right, ray);
    return second;
}

fn main() {
    let ray: Ray = Ray { x: -1.0, y: 0.0, z: -1.0 };
    let hit: Hit = reuse(ray);
    if (hit.ok) {
        if (hit.t > 1.9 && hit.t < 2.1) {
            return 2;
        }
        return 1;
    }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_aggregate_parameter_identity_return() {
    assert_source_exit(
        "aggregate_parameter_identity_return",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

fn keep(value: Vec3) -> Vec3 {
    return value;
}

fn main() {
    let input: Vec3 = Vec3 { x: 0.5, y: 0.7, z: 1.0 };
    let output: Vec3 = keep(input);
    if (!(output.x > 0.49 && output.x < 0.51)) {
        return 1;
    }
    if (!(output.y > 0.69 && output.y < 0.71)) {
        return 2;
    }
    if (!(output.z > 0.99 && output.z < 1.01)) {
        return 3;
    }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_parameter_aggregate_member_copy_after_disp8_range() {
    let fields = (0..33)
        .map(|i| format!("    p{i}: i32,"))
        .collect::<Vec<_>>()
        .join("\n");
    let init_fields = (0..33)
        .map(|i| format!("        p{i}: {i},"))
        .collect::<Vec<_>>()
        .join("\n");
    let source = format!(
        r#"
struct Vec3 {{
    x: i32,
    y: i32,
    z: i32,
}}

struct Wide {{
{fields}
    tail: Vec3,
}}

impl Wide {{
    fn tail_vec(self) -> Vec3 {{
        let value: Vec3 = self.tail;
        return value;
    }}
}}

fn main() {{
    let tail: Vec3 = Vec3 {{ x: 7, y: 8, z: 9 }};
    let wide: Wide = Wide {{
{init_fields}
        tail: tail,
    }};
    let read: Vec3 = wide.tail_vec();
    return read.z;
}}
"#
    );
    assert_source_exit(
        "parameter_aggregate_member_copy_after_disp8_range",
        &source,
        9,
    );
}

#[test]
fn x86_executes_first_scalar_member_returns_without_aggregate_copy() {
    assert_source_exit(
        "first_scalar_member_returns",
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn first(pair: Pair) -> i32 {
    return pair.left;
}

impl Pair {
    fn first(self) -> i32 {
        return self.left;
    }
}

fn main() -> i32 {
    let pair: Pair = Pair { left: 7, right: 9 };
    return first(pair) + pair.first();
}
"#,
        14,
    );
}

#[test]
fn x86_executes_wide_parameter_member_as_direct_call_receiver() {
    let fields = (0..33)
        .map(|i| format!("    p{i}: i32,"))
        .collect::<Vec<_>>()
        .join("\n");
    let init_fields = (0..33)
        .map(|i| format!("        p{i}: {i},"))
        .collect::<Vec<_>>()
        .join("\n");
    let source = format!(
        r#"
struct Vec3 {{
    x: i32,
    y: i32,
    z: i32,
}}

impl Vec3 {{
    fn z_value(self) -> i32 {{
        return self.z;
    }}
}}

struct Wide {{
{fields}
    tail: Vec3,
}}

impl Wide {{
    fn tail_z(self) -> i32 {{
        return self.tail.z_value();
    }}
}}

fn main() {{
    let tail: Vec3 = Vec3 {{ x: 7, y: 8, z: 9 }};
    let wide: Wide = Wide {{
{init_fields}
        tail: tail,
    }};
    return wide.tail_z();
}}
"#
    );
    assert_source_exit("wide_parameter_member_as_direct_call_receiver", &source, 9);
}

#[test]
fn x86_executes_nested_struct_literal_member_reads() {
    assert_source_exit(
        "nested_struct_literal_member_reads",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

struct Ray {
    origin: Vec3,
    direction: Vec3,
}

fn main() {
    let origin: Vec3 = Vec3 { x: 0.0, y: 0.0, z: 0.0 };
    let direction: Vec3 = Vec3 { x: 0.0, y: 0.0, z: -1.0 };
    let ray: Ray = Ray { origin: origin, direction: direction };
    let read_direction: Vec3 = ray.direction;
    if (!(read_direction.z > -1.01 && read_direction.z < -0.99)) {
        return 1;
    }
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_aggregate_parameter_member_copy() {
    assert_source_exit(
        "aggregate_parameter_member_copy",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

struct Ray {
    origin: Vec3,
    direction: Vec3,
}

fn direction(ray: Ray) -> Vec3 {
    return ray.direction;
}

fn main() {
    let origin: Vec3 = Vec3 { x: 0.0, y: 0.0, z: 0.0 };
    let dir: Vec3 = Vec3 { x: -1.86, y: 1.125, z: -1.0 };
    let ray: Ray = Ray { origin: origin, direction: dir };
    let read: Vec3 = direction(ray);
    if (read.x > -1.87 && read.x < -1.85 &&
        read.y > 1.12 && read.y < 1.13 &&
        read.z > -1.01 && read.z < -0.99) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_two_aggregate_parameters_return_first() {
    assert_source_exit(
        "two_aggregate_parameters_return_first",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

fn first(left: Vec3, right: Vec3, t: f32) -> Vec3 {
    return left;
}

fn main() {
    let left: Vec3 = Vec3 { x: 1.0, y: 2.0, z: 3.0 };
    let right: Vec3 = Vec3 { x: 4.0, y: 5.0, z: 6.0 };
    let value: Vec3 = first(left, right, 0.5);
    if (value.x > 0.99 && value.x < 1.01 &&
        value.y > 1.99 && value.y < 2.01 &&
        value.z > 2.99 && value.z < 3.01) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_scalar_parameter_after_two_aggregates() {
    assert_source_exit(
        "scalar_parameter_after_two_aggregates",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

fn scale(left: Vec3, right: Vec3, t: f32) -> f32 {
    return 1.0 - t;
}

fn main() {
    let left: Vec3 = Vec3 { x: 1.0, y: 2.0, z: 3.0 };
    let right: Vec3 = Vec3 { x: 4.0, y: 5.0, z: 6.0 };
    let value: f32 = scale(left, right, 0.735);
    if (value > 0.26 && value < 0.27) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_aggregate_method_call_on_aggregate_parameter() {
    assert_source_exit(
        "aggregate_method_call_on_aggregate_parameter",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn mul_scalar(self, scale: f32) -> Vec3 {
        return Vec3::new(self.x * scale, self.y * scale, self.z * scale);
    }
}

fn scale(value: Vec3, factor: f32) -> Vec3 {
    return value.mul_scalar(1.0 - factor);
}

fn main() {
    let value: Vec3 = Vec3 { x: 1.0, y: 2.0, z: 3.0 };
    let scaled: Vec3 = scale(value, 0.5);
    if (scaled.x > 0.49 && scaled.x < 0.51 &&
        scaled.y > 0.99 && scaled.y < 1.01 &&
        scaled.z > 1.49 && scaled.z < 1.51) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_sum_of_three_products() {
    assert_source_exit(
        "f32_sum_of_three_products",
        r#"
fn main() {
    let value: f32 = 1.5 * 2.0 + 3.0 * 4.0 + 5.0 * 6.0;
    if (value > 44.9) {
        if (value < 45.1) {
            return 0;
        }
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_member_sum_of_three_products() {
    assert_source_exit(
        "f32_member_sum_of_three_products",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y + self.z * right.z;
    }
}

fn main() {
    let value: Vec3 = Vec3 { x: -1.86, y: 1.125, z: -1.0 };
    let dot: f32 = value.dot(value);
    if (dot > 5.70) {
        if (dot < 5.75) {
            return 0;
        }
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_vec3_lerp_method_chain() {
    assert_source_exit(
        "f32_vec3_lerp_method_chain",
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn add(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x + right.x, self.y + right.y, self.z + right.z);
    }

    fn mul_scalar(self, scale: f32) -> Vec3 {
        return Vec3::new(self.x * scale, self.y * scale, self.z * scale);
    }

    fn lerp(self, right: Vec3, t: f32) -> Vec3 {
        let left_part: Vec3 = self.mul_scalar(1.0 - t);
        let right_part: Vec3 = right.mul_scalar(t);
        return left_part.add(right_part);
    }
}

fn main() {
    let white: Vec3 = Vec3::new(1.0, 1.0, 1.0);
    let blue: Vec3 = Vec3::new(0.5, 0.7, 1.0);
    let color: Vec3 = white.lerp(blue, 0.735);
    if (color.x > 0.62 && color.x < 0.64 &&
        color.y > 0.77 && color.y < 0.79 &&
        color.z > 0.99 && color.z < 1.01) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_helper_parameters() {
    assert_source_exit(
        "f32_helper_parameters",
        r#"
fn scaled(value: f32, factor: f32) -> f32 {
    return value * factor;
}

fn main() {
    let value: f32 = scaled(0.7, 0.5);
    if (value > 0.34 && value < 0.36) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_single_helper_parameter() {
    assert_source_exit(
        "f32_single_helper_parameter",
        r#"
fn id(value: f32) -> f32 {
    return value;
}

fn main() {
    let value: f32 = id(0.7);
    if (value > 0.69 && value < 0.71) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_second_helper_parameter() {
    assert_source_exit(
        "f32_second_helper_parameter",
        r#"
fn second(left: f32, right: f32) -> f32 {
    return right;
}

fn main() {
    let value: f32 = second(0.7, 0.5);
    if (value > 0.49 && value < 0.51) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_f32_first_of_three_helper_parameters() {
    assert_source_exit(
        "f32_first_of_three_helper_parameters",
        r#"
fn first(x: f32, y: f32, z: f32) -> f32 {
    return x;
}

fn main() {
    let value: f32 = first(0.5, 0.7, 1.0);
    if (value > 0.49 && value < 0.51) {
        return 0;
    }
    return 1;
}
"#,
        0,
    );
}

#[test]
fn x86_rejects_same_signature_extern_as_i32_to_f32_host_binding() {
    let source = r#"
extern "lanius_std" fn convert(value: i32) -> f32;

fn main() {
    let value: f32 = convert(7);
    if (value > 0.0) {
        return 0;
    }
    return 1;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout(
        "x86 same-signature i32_to_f32 host binding",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .expect_err("same-signature externs should not be treated as i32_to_f32 host bindings");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(diagnostic.code, "LNC0017", "{message}");
            assert!(
                diagnostic.message.contains("unsupported x86 call ABI"),
                "diagnostic should keep same-signature externs at the explicit host-binding boundary: {message}"
            );
            assert!(
                message.contains("convert(7)"),
                "diagnostic should point at the unbound extern call: {message}"
            );
        }
        other => panic!("expected x86 host-binding diagnostic, got {other:?}"),
    }
}

#[test]
fn x86_accepts_string_literal_locals_as_rodata_pairs() {
    assert_source_exit(
        "string_literal_rodata_pairs",
        r#"
fn main() {
    let first: str = "ready";
    let second: str = "go";
    return 0;
}
"#,
        0,
    );
}

#[test]
fn x86_executes_lanius_std_text_write_direct_string_result() {
    let bytes = compile_source(
        "x86 lanius_std direct text write stdout",
        r#"
extern "lanius_std" fn write_text(handle: i32, text: str) -> i32;

fn main() {
    let result: i32 = write_text(1, "ready");
    if (result < 0) {
        return 1;
    }
    return 0;
}
"#,
    );

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_stdout(
        "x86 lanius_std direct text write stdout",
        "x86_lanius_std_direct_text_write_stdout",
        &bytes,
        "ready",
    );
}

#[test]
fn x86_executes_parser_decoded_string_escapes() {
    let bytes = compile_source(
        "x86 parser decoded string escapes",
        r#"
extern "lanius_std" fn write_text(handle: i32, text: str) -> i32;

fn main() {
    let result: i32 = write_text(1, "line1\nquote:\" slash:\\ unknown:\q");
    if (result < 0) {
        return 1;
    }
    return 0;
}
"#,
    );

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_stdout(
        "x86 parser decoded string escapes",
        "x86_parser_decoded_string_escapes",
        &bytes,
        "line1\nquote:\" slash:\\ unknown:q",
    );
}

#[test]
fn x86_executes_long_parser_decoded_string_across_dfa_chunks() {
    let left = "a".repeat(130);
    let right = "b".repeat(130);
    let source = format!(
        r#"
extern "lanius_std" fn write_text(handle: i32, text: str) -> i32;

fn main() {{
    let result: i32 = write_text(1, "{left}\n{right}");
    if (result < 0) {{
        return 1;
    }}
    return 0;
}}
"#
    );
    let bytes = compile_source("x86 long parser decoded string", &source);

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_stdout(
        "x86 long parser decoded string",
        "x86_long_parser_decoded_string",
        &bytes,
        &format!("{left}\n{right}"),
    );
}

#[test]
fn x86_executes_lanius_std_open_read_path_stub_as_negative() {
    let bytes = compile_source(
        "x86 lanius_std open_read_path negative stub",
        r#"
extern "lanius_std" fn open_read_path(path: str) -> i32;

fn main() {
    let file: i32 = open_read_path("missing.txt");
    if (file < 0) {
        return 7;
    }
    return 1;
}
"#,
    );

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 lanius_std open_read_path negative stub",
        "x86_lanius_std_open_read_path_negative_stub",
        &bytes,
        7,
    );
}

#[test]
fn x86_executes_source_pack_open_read_path_stub_as_negative() {
    let sources = [r#"
module app::main;

extern "lanius_std" fn open_read_path(path: str) -> i32;

fn main() {
    let file: i32 = open_read_path("missing.txt");
    if (file < 0) {
        return 7;
    }
    return 1;
}
"#];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack open_read_path negative stub",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack open_read_path negative stub",
        "x86_source_pack_open_read_path_negative_stub",
        &bytes,
        7,
    );
}

#[test]
fn x86_rejects_same_signature_extern_as_write_text_host_binding() {
    let source = r#"
extern "lanius_std" fn write_bytes(handle: i32, text: str) -> i32;

fn main() {
    let result: i32 = write_bytes(1, "ready");
    return result;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout(
        "x86 same-signature write_text host binding",
        move || pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source)),
    )
    .expect_err("same-signature externs should not be treated as write_text host bindings");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(diagnostic.code, "LNC0017", "{message}");
            assert!(
                diagnostic.message.contains("unsupported x86 call ABI"),
                "diagnostic should keep same-signature externs at the explicit host-binding boundary: {message}"
            );
            assert!(
                message.contains("write_bytes(1, \"ready\")"),
                "diagnostic should point at the unbound extern call: {message}"
            );
        }
        other => panic!("expected x86 host-binding diagnostic, got {other:?}"),
    }
}

#[test]
fn x86_rejects_compile_time_zero_divisor_before_native_fault() {
    let source = r#"
fn main() {
    return 12 / 0;
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 compile-time zero divisor", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("statically known zero divisors should fail before native idiv can fault");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("unsupported x86 zero divisor")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the zero-divisor boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    return 12 / 0;"),
                "diagnostic should point at the division expression: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_folded_compile_time_zero_divisor_before_native_fault() {
    let source = r#"
fn main() {
    return 12 / (4 % 2);
}
"#
    .to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 folded zero divisor", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("folded zero divisors should fail before native idiv can fault");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "x86 rejection should use the stable backend diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("unsupported x86 zero divisor")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the folded zero-divisor boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    return 12 / (4 % 2);"),
                "diagnostic should point at the folded zero divisor: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_traps_local_zero_modulo_at_runtime() {
    assert_source_exit(
        "local_zero_modulo_runtime_trap",
        r#"
fn main() {
    let scale: i32 = 0;
    return 12 % scale;
}
"#,
        103,
    );
}

#[test]
fn x86_traps_unsigned_local_zero_divisor_at_runtime() {
    assert_source_exit(
        "unsigned_local_zero_divisor_runtime_trap",
        r#"
fn main() -> u32 {
    let value: u32 = 4000000000;
    let scale: u32 = 0;
    return value / scale;
}
"#,
        103,
    );
}

#[test]
fn x86_traps_signed_division_overflow_at_runtime() {
    assert_source_exit(
        "signed_division_overflow_runtime_trap",
        r#"
fn main() {
    let value: i32 = -2147483647 - 1;
    let scale: i32 = -1;
    return value / scale;
}
"#,
        104,
    );
}

#[test]
fn x86_source_pack_assignment_mismatch_reports_lnc0006_diagnostic() {
    let sources = [
        "module core::math;\npub fn identity(value: i32) -> i32 {\n    return value;\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    let value: i32 = false;\n    return core::math::identity(value);\n}\n",
    ];

    let err = common::run_gpu_codegen_with_timeout(
        "x86 source pack assignment mismatch diagnostic",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect_err("source-pack assignment mismatch should fail GPU type checking");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0006",
                "source-pack x86 type-check rejection should use the stable mismatch diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("type mismatch"),
                "source-pack x86 diagnostic should identify the type mismatch: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("source-pack x86 diagnostic should include a primary label");
            assert_eq!(label.path.display().to_string(), "<source pack file 1>");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    let value: i32 = false;"),
                "diagnostic should point at the mismatched source-pack file line: {message}"
            );
            assert!(
                message.contains("value type is bool")
                    && message.contains("expects i32")
                    && message.contains("= note:")
                    && message.contains("change the expression or the annotation")
                    && !message.contains("type code")
                    && !message.contains("GPU type check rejected"),
                "diagnostic should match the single-source type mismatch style: {message}"
            );
        }
        CompileError::GpuTypeCheck(message) => {
            panic!("expected source-pack x86 diagnostic, got GPU type-check error: {message}")
        }
        other => panic!("expected source-pack x86 type mismatch diagnostic, got {other:?}"),
    }
}

#[test]
fn x86_source_pack_unresolved_identifier_reports_lnc0005_diagnostic() {
    let sources = [
        "module core::math;\npub fn identity(value: i32) -> i32 {\n    return value;\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    return missing_value;\n}\n",
    ];

    let err = common::run_gpu_codegen_with_timeout(
        "x86 source pack unresolved identifier diagnostic",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect_err("source-pack unresolved identifier should fail GPU type checking");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0005",
                "source-pack x86 type-check rejection should use the stable unresolved identifier diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("unresolved identifier"),
                "source-pack x86 diagnostic should identify the unresolved identifier: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("source-pack x86 diagnostic should include a primary label");
            assert_eq!(label.path.display().to_string(), "<source pack file 1>");
            assert_eq!(
                label.source_line.as_deref(),
                Some("    return missing_value;"),
                "diagnostic should point at the unresolved identifier source-pack file line: {message}"
            );
            assert!(
                message.contains("not found in this scope")
                    && message.contains(
                        "declare the value before using it or import its defining module"
                    )
                    && !message.contains("GPU type check rejected"),
                "diagnostic should match the single-source unresolved identifier style: {message}"
            );
        }
        CompileError::GpuTypeCheck(message) => {
            panic!("expected source-pack x86 diagnostic, got GPU type-check error: {message}")
        }
        other => panic!("expected source-pack x86 unresolved identifier diagnostic, got {other:?}"),
    }
}

#[test]
fn x86_executes_direct_recursive_scalar_call() {
    let source = r#"
fn sum_to(n: i32) -> i32 {
    if (n <= 0) {
        return 0;
    }
    return n + sum_to(n - 1);
}

fn main() {
    return sum_to(4);
}
"#;

    assert_source_exit("direct_recursive_scalar_call", source, 10);
}

#[test]
fn x86_rejects_missing_main_entrypoint_with_diagnostic() {
    let source = "fn helper() -> i32 {\n    return 1;\n}\n".to_owned();

    let err = common::run_gpu_codegen_with_timeout("x86 missing main entrypoint", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("missing main should fail closed before entry selection");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "missing-main rejection should use the stable x86 backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "missing-main rejection should stay in the native-codegen category: {message}"
            );
            assert!(
                diagnostic.message.contains("missing main entrypoint")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the native entrypoint boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("x86 diagnostic should include a primary source label");
            assert_eq!(
                label.source_line.as_deref(),
                Some("fn helper() -> i32 {"),
                "diagnostic should anchor to the source when no main token exists: {message}"
            );
            assert!(
                label.line > 0 && label.column > 0,
                "diagnostic should include a concrete source span: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_rejects_empty_non_void_entrypoint_before_native_codegen() {
    let source = "fn main() -> i32 {\n}\n".to_owned();
    let err = common::run_gpu_codegen_with_timeout("x86 empty non-void entrypoint", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect_err("non-void entrypoints without a return should fail in GPU type checking");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0006");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0006]: type mismatch"));
            assert!(rendered.contains("fn main() -> i32 {"));
            assert!(rendered.contains("expected i32, found void"));
        }
        other => panic!("expected missing-return diagnostic before x86 codegen, got {other:?}"),
    }
}

#[test]
fn x86_source_pack_rejects_empty_non_void_entrypoint_before_native_codegen() {
    let sources = [
        "module helpers::math;\npub fn identity(value: i32) -> i32 {\n    return value;\n}\n",
        "module app::main;\nimport helpers::math;\nfn main() -> i32 {\n}\n",
    ];

    let err =
        common::run_gpu_codegen_with_timeout("x86 source pack empty entrypoint body", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect_err(
            "source-pack non-void entrypoints without a return should fail in type checking",
        );

    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0006");
            let rendered = diagnostic.render();
            assert!(rendered.contains("error[LNC0006]: type mismatch"));
            assert!(rendered.contains("fn main() -> i32 {"));
            assert!(rendered.contains("expected i32, found void"));
        }
        other => panic!("expected missing-return diagnostic before x86 codegen, got {other:?}"),
    }
}

#[test]
fn x86_source_pack_rejects_empty_pack_with_diagnostic() {
    let sources: [&str; 0] = [];

    let err = common::run_gpu_codegen_with_timeout("x86 empty source pack", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect_err("empty source packs should fail closed before x86 entry selection succeeds");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "empty source-pack rejection should use the stable backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "empty source-pack rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic.message.contains("missing main entrypoint")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the missing native entrypoint: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("empty source-pack x86 diagnostic should include a primary label");
            assert_eq!(label.path.display().to_string(), "<source pack>");
            assert_eq!(label.line, 1);
            assert_eq!(label.column, 1);
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected source-pack x86 diagnostic rejection, got {other:?}"),
    }
}

#[test]
fn x86_source_pack_rejects_multiple_main_entrypoints_with_diagnostic() {
    let sources = [
        "module app::first;\nfn main() {\n    return 1;\n}\n",
        "module app::second;\nfn main() {\n    return 2;\n}\n",
    ];

    let err = common::run_gpu_codegen_with_timeout("x86 source pack multiple main", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect_err("multiple native entrypoints should fail closed before entry selection");

    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0017",
                "multiple-main rejection should use the stable backend diagnostic: {message}"
            );
            assert_eq!(
                diagnostic.category, "native codegen",
                "multiple-main rejection should stay in native codegen: {message}"
            );
            assert!(
                diagnostic.message.contains("multiple main entrypoints")
                    && message.contains("native x86 backend"),
                "diagnostic should identify the ambiguous native entrypoint boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("multiple-main x86 diagnostic should include a primary label");
            assert_eq!(label.path.display().to_string(), "<source pack file 1>");
            assert_eq!(
                label.source_line.as_deref(),
                Some("fn main() {"),
                "diagnostic should point at a duplicate source-pack entrypoint: {message}"
            );
        }
        CompileError::GpuCodegen(message) => {
            panic!("expected source-spanned x86 diagnostic, got GPU codegen error: {message}")
        }
        other => panic!("expected source-pack x86 multiple-main diagnostic, got {other:?}"),
    }
}

#[test]
fn x86_executes_direct_self_method_call() {
    assert_source_exit(
        "direct_self_method_call",
        r#"
struct Range {
    start: i32,
    end: i32,
}

impl Range {
    fn span(self) -> i32 {
        return self.end - self.start;
    }
}

fn main() -> i32 {
    let range: Range = Range { start: 1, end: 4 };
    return range.span();
}
"#,
        3,
    );
}

#[test]
fn x86_executes_direct_self_method_call_with_explicit_arg() {
    assert_source_exit(
        "direct_self_method_call_with_explicit_arg",
        r#"
struct Range {
    start: i32,
    end: i32,
}

impl Range {
    fn mix(self, amount: i32) -> i32 {
        return amount + 40;
    }
}

fn main() -> i32 {
    let range: Range = Range { start: 1, end: 4 };
    let offset: i32 = 3;
    return range.mix(offset + 2);
}
"#,
        45,
    );
}

#[test]
fn x86_source_pack_executes_imported_self_method_call() {
    let sources = [
        r#"
module helpers::range;

pub struct Range {
    start: i32,
    end: i32,
}

pub fn make(start: i32, end: i32) -> Range {
    return Range { start: start, end: end };
}

pub impl Range {
    pub fn span(self) -> i32 {
        return self.end - self.start;
    }

    pub fn contains(self, value: i32) -> bool {
        return value >= self.start && value < self.end;
    }
}
"#,
        r#"
module app::main;

import helpers::range;

fn main() -> i32 {
    let range: helpers::range::Range = helpers::range::make(2, 8);
    if (range.contains(5)) {
        return range.span();
    }
    return 99;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack imported self method call",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack imported self method calls should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack imported self method call",
        "x86_source_pack_imported_self_method_call",
        &bytes,
        6,
    );
}

#[test]
fn x86_source_pack_executes_imported_multi_argument_self_method_call() {
    let sources = [
        r#"
module helpers::window;

pub struct Window {
    start: i32,
    end: i32,
}

pub fn make(start: i32, end: i32) -> Window {
    return Window { start: start, end: end };
}

pub impl Window {
    pub fn score(self, candidate: i32, bias: i32, scale: i32) -> i32 {
        if ((candidate + bias) >= self.start && candidate < self.end) {
            return candidate * scale + self.end;
        }
        return 0;
    }
}
"#,
        r#"
module app::main;

import helpers::window;

fn main() -> i32 {
    let window: helpers::window::Window = helpers::window::make(1, 6);
    let value: i32 = 0;
    let total: i32 = 0;
    while (value < 7) {
        total += window.score(value, 1, 3);
        value += 2;
    }
    return total;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack imported multi-argument self method call",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack imported self methods with multiple arguments should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack imported multi-argument self method call",
        "x86_source_pack_imported_multi_arg_self_method_call",
        &bytes,
        36,
    );
}

#[test]
fn x86_executes_source_pack_method_call_in_loop_condition() {
    let sources = [
        r#"
module helpers::range;

pub struct Range {
    start: i32,
    end: i32,
}

pub fn make(start: i32, end: i32) -> Range {
    return Range { start: start, end: end };
}

pub impl Range {
    pub fn contains(self, value: i32) -> bool {
        return value >= self.start && value < self.end;
    }
}
"#,
        r#"
module app::main;

import helpers::range;

fn main() -> i32 {
    let range: helpers::range::Range = helpers::range::make(0, 4);
    let value: i32 = 0;
    let total: i32 = 0;
    while (range.contains(value)) {
        total += value;
        value += 1;
    }
    return total;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack method call loop condition",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack method calls in loop conditions should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack method call loop condition",
        "x86_source_pack_method_loop_condition",
        &bytes,
        6,
    );
}

#[test]
fn x86_executes_mutually_recursive_scalar_calls() {
    assert_source_exit(
        "mutually_recursive_scalar_calls",
        r#"
fn even(value: i32) -> i32 {
    if (value == 0) {
        return 1;
    }
    return odd(value - 1);
}

fn odd(value: i32) -> i32 {
    if (value == 0) {
        return 0;
    }
    return even(value - 1);
}

fn main() {
    return even(5) * 10 + odd(5);
}
"#,
        1,
    );
}

#[test]
fn x86_executes_zero_argument_scalar_helper_call() {
    assert_source_exit(
        "zero_argument_scalar_helper_call",
        r#"
fn answer() -> i32 {
    return 37;
}

fn main() -> i32 {
    return answer();
}
"#,
        37,
    );
}

#[test]
fn x86_executes_loop_condition_call() {
    assert_source_exit(
        "loop_condition_call",
        r#"
fn keep_going(value: i32) -> i32 {
    return 2 - value;
}

fn main() {
    let i: i32 = 0;
    while (keep_going(i) > 0) {
        i += 1;
    }
    return i;
}
"#,
        2,
    );
}

#[test]
fn x86_executes_loop_body_assignment_call() {
    assert_source_exit(
        "loop_body_assignment_call",
        r#"
fn inc(value: i32) -> i32 {
    return value + 1;
}

fn main() {
    let i: i32 = 0;
    while (i < 2) {
        i = inc(i);
    }
    return i;
}
"#,
        2,
    );
}

#[test]
fn x86_executes_loop_branch_condition_call() {
    assert_source_exit(
        "loop_branch_condition_call",
        r#"
fn is_even(value: i32) -> bool {
    return (value & 1) == 0;
}

fn main() {
    let index: i32 = 0;
    let total: i32 = 0;
    while (index < 5) {
        if (is_even(index)) {
            total += index;
        }
        index += 1;
    }
    return total;
}
"#,
        6,
    );
}

#[test]
fn x86_executes_loop_branch_body_call_with_nested_argument_call() {
    assert_source_exit(
        "loop_branch_body_call_nested_argument_call",
        r#"
fn add(left: i32, right: i32) -> i32 {
    return left + right;
}

fn adjusted(value: i32) -> i32 {
    if (value == 1) {
        return 10;
    }
    return value;
}

fn main() {
    let index: i32 = 0;
    let total: i32 = 0;
    while (index < 4) {
        if ((index & 1) == 0) {
            total = add(total, adjusted(index));
        } else {
            total = add(total, index * 2);
        }
        index += 1;
    }
    return total;
}
"#,
        10,
    );
}

#[test]
fn x86_executes_builtin_print_stdout() {
    let bytes = compile_source(
        "x86 builtin print stdout",
        r#"
fn main() {
    print(0);
    print(40);
    print(-7);
    return 0;
}
"#,
    );

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_stdout(
        "x86 builtin print stdout",
        "x86_builtin_print_stdout",
        &bytes,
        "0\n40\n-7\n",
    );
}

#[test]
fn x86_executes_lanius_std_text_write_stdout() {
    let bytes = compile_source(
        "x86 lanius_std text write stdout",
        r#"
extern "lanius_std" fn write_text(handle: i32, text: str) -> i32;

fn main() {
    let text: str = "host text";
    write_text(1, text);
    return 0;
}
"#,
    );

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_stdout(
        "x86 lanius_std text write stdout",
        "x86_lanius_std_text_write_stdout",
        &bytes,
        "host text",
    );
}

#[test]
fn x86_executes_void_helper_fallthrough_return() {
    let bytes = compile_source(
        "x86 void helper fallthrough return",
        r#"
fn print_once(value: i32) {
    print(value);
}

fn main() {
    print_once(7);
    print(9);
    return 0;
}
"#,
    );

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_stdout(
        "x86 void helper fallthrough return",
        "x86_void_helper_fallthrough_return",
        &bytes,
        "7\n9\n",
    );
}

#[test]
fn x86_executes_std_io_print_i32_stdout() {
    let sources = [
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::io;

fn main() {
    let a: i32 = 1 + 2 * 3;
    let b: i32 = (1 + 2) * 3;
    if (a < b) {
        std::io::print_i32(a);
    }
    std::io::print_i32(b);
    return 0;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout("x86 std::io print_i32 stdout", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("std::io::print_i32 should compile through the native print primitive");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_stdout(
        "x86 std::io print_i32 stdout",
        "x86_std_io_print_i32_stdout",
        &bytes,
        "7\n9\n",
    );
}

#[test]
fn x86_executes_source_pack_qualified_scalar_const_return() {
    let sources = [
        "module core::numbers;\npub const LIMIT: i32 = 21;\npub const STEP: i32 = 6;\npub const DIVISOR: i32 = 3;\n",
        "module app::main;\nimport core::numbers;\nfn main() {\n    return (12 / core::numbers::DIVISOR) + core::numbers::LIMIT + core::numbers::STEP;\n}\n",
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack qualified scalar const", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source-pack qualified scalar const should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack qualified scalar const",
        "x86_source_pack_qualified_scalar_const",
        &bytes,
        31,
    );
}

#[test]
fn x86_executes_source_pack_qualified_scalar_const_expression_return() {
    let sources = [
        "module core::numbers;\npub const BASE: i32 = 40 + 2;\npub const DELTA: i32 = 9 - 5;\npub const SCALE: i32 = 2 * 3;\npub const QUOTIENT: i32 = 84 / 7;\npub const REMAINDER: i32 = 17 % 5;\npub const SHIFTED: i32 = 5 << 2;\npub const SHRUNK: i32 = 64 >> 3;\npub const NESTED: i32 = (40 + 2) + (9 - 5);\npub const READY: bool = true && !false;\npub const DISABLED: bool = false || false;\npub const MATCHED: bool = 42 == 42;\npub const DIFFERENT: bool = 42 != 7;\npub const BELOW: bool = 3 < 5;\npub const ABOVE: bool = 9 > 4;\npub const AT_MOST: bool = 6 <= 6;\npub const AT_LEAST: bool = 8 >= 7;\n",
        "module app::main;\nimport core::numbers;\nfn main() {\n    if (core::numbers::READY && !core::numbers::DISABLED && core::numbers::MATCHED && core::numbers::DIFFERENT && core::numbers::BELOW && core::numbers::ABOVE && core::numbers::AT_MOST && core::numbers::AT_LEAST) {\n        return core::numbers::BASE + core::numbers::DELTA + core::numbers::SCALE + core::numbers::QUOTIENT + core::numbers::REMAINDER + core::numbers::SHIFTED + core::numbers::SHRUNK + core::numbers::NESTED;\n    }\n    return 1;\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack qualified scalar const expression",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack qualified scalar const expressions should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack qualified scalar const expression",
        "x86_source_pack_qualified_scalar_const_expression",
        &bytes,
        140,
    );
}

#[test]
fn x86_executes_source_pack_qualified_const_local_initializer_and_alias() {
    let sources = [
        "module core::bytes;\npub type Byte = u8;\npub const SLASH: Byte = 47;\npub const LETTER: Byte = 65;\npub fn is_slash(value: Byte) -> bool {\n    return value == SLASH;\n}\n",
        "module app::main;\nimport core::bytes;\nfn main() {\n    let slash: core::bytes::Byte = core::bytes::SLASH;\n    let letter: core::bytes::Byte = core::bytes::LETTER;\n    if (core::bytes::is_slash(slash)) {\n        if (!core::bytes::is_slash(letter)) {\n            return 0;\n        }\n    }\n    return 1;\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack qualified const local initializer and alias",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack qualified const locals and type aliases should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack qualified const local initializer and alias",
        "x86_source_pack_qualified_const_local_initializer_alias",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_qualified_const_indexed_assignment() {
    let sources = [
        "module helpers::offsets;\npub const SECOND: i32 = 1;\npub const LAST: i32 = 3;\npub const BUMP: i32 = 2;\n",
        "module app::main;\nimport helpers::offsets;\nfn main() {\n    let values: [i32; 4] = [4, 6, 8, 10];\n    values[helpers::offsets::SECOND] += helpers::offsets::BUMP;\n    return values[helpers::offsets::SECOND] + values[helpers::offsets::LAST];\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack qualified const indexed assignment",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack qualified const indexes should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack qualified const indexed assignment",
        "x86_source_pack_qualified_const_indexed_assignment",
        &bytes,
        18,
    );
}

#[test]
fn x86_executes_source_pack_for_array_with_imported_break_continue_limits() {
    let sources = [
        "module helpers::limits;\npub const SKIP: i32 = 2;\npub const STOP: i32 = 5;\n",
        "module app::main;\nimport helpers::limits;\nfn main() {\n    let values: [i32; 6] = [1, 2, 3, 4, 5, 6];\n    let total: i32 = 0;\n    for value in values {\n        if (value == helpers::limits::SKIP) {\n            continue;\n        }\n        if (value == helpers::limits::STOP) {\n            break;\n        }\n        total += value;\n    }\n    return total;\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack array imported branch limits",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack array with imported branch limits should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack array imported branch limits",
        "x86_source_pack_for_array_imported_break_continue",
        &bytes,
        8,
    );
}

#[test]
fn x86_executes_source_pack_for_array_branch_body_nested_imported_call() {
    let sources = [
        r#"
module helpers::score;

pub fn double(value: i32) -> i32 {
    return value * 2;
}

pub fn adjust(value: i32) -> i32 {
    return value + 3;
}
"#,
        r#"
module app::main;

import helpers::score;

fn main() {
    let values: [i32; 4] = [1, 2, 3, 4];
    let total: i32 = 0;
    for value in values {
        if (value == 2 || value == 4) {
            total += helpers::score::adjust(helpers::score::double(value));
        } else {
            total += value;
        }
    }
    return total;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack for array branch body nested imported call",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack for-array branch-body nested imported call should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack for array branch body nested imported call",
        "x86_source_pack_for_array_branch_nested_call",
        &bytes,
        22,
    );
}

#[test]
fn x86_executes_source_pack_function_call() {
    let sources = [
        "module core::math;\npub fn abs(value: i32) -> i32 {\n    if (value < 0) {\n        return -value;\n    } else {\n        return value;\n    }\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    return core::math::abs(-7);\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout("x86 source pack function call", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack function call",
        "x86_source_pack_call",
        &bytes,
        7,
    );
}

#[test]
fn x86_executes_source_pack_text_write_direct_string_result() {
    let sources = [r#"
module app::main;

extern "lanius_std" fn write_text(handle: i32, text: str) -> i32;

fn main() {
    let result: i32 = write_text(1, "ready");
    if (result < 0) {
        return 1;
    }
    return 0;
}
"#];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack lanius_std direct text write stdout",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_stdout(
        "x86 source pack lanius_std direct text write stdout",
        "x86_source_pack_lanius_std_direct_text_write_stdout",
        &bytes,
        "ready",
    );
}

#[test]
fn x86_executes_source_pack_namespaced_text_write() {
    let sources = [
        r#"
module runtime::io;

pub extern "lanius_std" fn write_text(handle: i32, text: str) -> i32;
"#,
        r#"
module app::main;

import runtime::io;

fn main() {
    let result: i32 = runtime::io::write_text(1, "ready");
    if (result < 0) {
        return 1;
    }
    return 0;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack namespaced lanius_std text write stdout",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_stdout(
        "x86 source pack namespaced lanius_std text write stdout",
        "x86_source_pack_namespaced_lanius_std_text_write_stdout",
        &bytes,
        "ready",
    );
}

#[test]
fn x86_executes_source_pack_std_io_text_write() {
    let sources = [
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::io;

fn main() {
    let result: i32 = std::io::write_text(1, "ready");
    if (result < 0) {
        return 1;
    }
    return 0;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack std::io text write stdout",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_stdout(
        "x86 source pack std::io text write stdout",
        "x86_source_pack_std_io_text_write_stdout",
        &bytes,
        "ready",
    );
}

#[test]
fn x86_executes_source_pack_std_io_flush_operations() {
    let sources = [
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::io;

fn main() -> i32 {
    if (!std::io::stdio_is_available()) {
        return 3;
    }
    if (std::io::stdio_requires_runtime_binding()) {
        return 4;
    }
    if (!std::io::flush_stdout_is_executable()) {
        return 5;
    }
    if (!std::io::flush_stderr_is_executable()) {
        return 6;
    }
    let stdout_result: i32 = std::io::flush_stdout();
    let stderr_result: i32 = std::io::flush_stderr();
    if (stdout_result != std::io::STDIO_OPERATION_OK) {
        return 1;
    }
    if (stderr_result != std::io::STDIO_OPERATION_OK) {
        return 2;
    }
    return 0;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack std::io flush operations",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("std::io flush operations should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack std::io flush operations",
        "x86_source_pack_std_io_flush",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_std_io_raw_stdout_and_stderr() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/io.lani"),
        include_str!("../stdlib/std/process.lani"),
        r#"
module app::main;

import alloc::allocator;
import std::io;
import std::process;

fn main() -> i32 {
    let capacity: usize = 64;
    let align: usize = 4;
    let out_ptr: u32 = alloc::allocator::alloc(capacity, align);
    if (out_ptr == 0) {
        return 1;
    }
    let err_ptr: u32 = alloc::allocator::alloc(capacity, align);
    if (err_ptr == 0) {
        alloc::allocator::dealloc(out_ptr, capacity, align);
        return 2;
    }
    let one: i32 = 1;
    let two: i32 = 2;
    let out_len_i32: i32 = std::process::arg_read(one, out_ptr, capacity);
    let err_len_i32: i32 = std::process::arg_read(two, err_ptr, capacity);
    if (out_len_i32 <= 0 || err_len_i32 <= 0) {
        alloc::allocator::dealloc(err_ptr, capacity, align);
        alloc::allocator::dealloc(out_ptr, capacity, align);
        return 3;
    }
    let out_len: usize = out_len_i32;
    let err_len: usize = err_len_i32;
    let out_written: i32 = std::io::write_stdout(out_ptr, out_len);
    let err_written: i32 = std::io::write_stderr(err_ptr, err_len);
    alloc::allocator::dealloc(err_ptr, capacity, align);
    alloc::allocator::dealloc(out_ptr, capacity, align);
    if (out_written != out_len_i32 || err_written != err_len_i32) {
        return 4;
    }
    return 0;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack std::io raw stdout stderr",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_io_raw", "run_dir", None);
        std::fs::create_dir(run_dir.path()).unwrap_or_else(|err| {
            panic!(
                "create std::io raw run directory {}: {err}",
                run_dir.path().display()
            )
        });
        let output = run_x86_64_elf_output_in_dir_with_args(
            "x86 source pack std::io raw stdout stderr",
            "x86_source_pack_std_io_raw_stdout_stderr",
            &bytes,
            run_dir.path(),
            &["stdout-bytes", "stderr-bytes"],
        );
        common::assert_command_success("x86 source pack std::io raw stdout stderr", &output);
        assert_eq!(
            common::stdout_utf8("x86 std::io raw stdout", output.stdout),
            "stdout-bytes"
        );
        assert_eq!(
            String::from_utf8(output.stderr).expect("x86 std::io raw stderr should be valid UTF-8"),
            "stderr-bytes"
        );
        std::fs::remove_dir_all(run_dir.path()).unwrap_or_else(|err| {
            panic!(
                "remove std::io raw run directory {}: {err}",
                run_dir.path().display()
            )
        });
    }
}

#[test]
fn x86_executes_source_pack_std_io_read_stdin() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import alloc::allocator;
import std::io;

fn main() -> i32 {
    let capacity: usize = 32;
    let align: usize = 4;
    let ptr: u32 = alloc::allocator::alloc(capacity, align);
    if (ptr == 0) {
        return 1;
    }
    let count: i32 = std::io::read_stdin(ptr, capacity);
    if (count <= 0) {
        alloc::allocator::dealloc(ptr, capacity, align);
        return 2;
    }
    let count_len: usize = count;
    let written: i32 = std::io::write_stdout(ptr, count_len);
    alloc::allocator::dealloc(ptr, capacity, align);
    if (written != count) {
        return 3;
    }
    return 0;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout("x86 source pack std::io stdin", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_io_stdin", "run_dir", None);
        std::fs::create_dir(run_dir.path()).unwrap_or_else(|err| {
            panic!(
                "create std::io stdin run directory {}: {err}",
                run_dir.path().display()
            )
        });
        let exe_path = run_dir.path().join("x86_source_pack_std_io_read_stdin");
        std::fs::write(&exe_path, &bytes)
            .unwrap_or_else(|err| panic!("write std::io stdin ELF {}: {err}", exe_path.display()));
        {
            use std::os::unix::fs::PermissionsExt;
            let mut permissions = std::fs::metadata(&exe_path)
                .unwrap_or_else(|err| {
                    panic!("stat std::io stdin ELF {}: {err}", exe_path.display())
                })
                .permissions();
            permissions.set_mode(0o700);
            std::fs::set_permissions(&exe_path, permissions).unwrap_or_else(|err| {
                panic!("chmod std::io stdin ELF {}: {err}", exe_path.display())
            });
        }
        let mut command = std::process::Command::new("bash");
        command
            .current_dir(run_dir.path())
            .arg("-c")
            .arg("printf stdin-bytes | \"$1\"")
            .arg("stdio-stdin")
            .arg(&exe_path);
        let output = common::short_process_output_with_timeout(
            "x86 source pack std::io read stdin",
            &mut command,
        );
        common::assert_command_success("x86 source pack std::io read stdin", &output);
        assert_eq!(
            common::stdout_utf8("x86 std::io stdin stdout", output.stdout),
            "stdin-bytes"
        );
        std::fs::remove_dir_all(run_dir.path()).unwrap_or_else(|err| {
            panic!(
                "remove std::io stdin run directory {}: {err}",
                run_dir.path().display()
            )
        });
    }
}

#[test]
fn x86_executes_source_pack_std_fs_text_write() {
    let sources = [
        include_str!("../stdlib/std/io.lani"),
        include_str!("../stdlib/std/fs.lani"),
        r#"
module app::main;

import std::fs;
import std::io;

fn main() {
    let file: std::fs::FileHandle = std::fs::open_write_path("std_output.txt");
    if (file < 0) {
        return 1;
    }
    let result: i32 = std::io::write_text(file, "saved");
    let close_result: i32 = std::fs::close_file(file);
    if (result < 0 || close_result < 0) {
        return 1;
    }
    return 0;
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack std::fs text write", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_fs", "run_dir", None);
        std::fs::create_dir(run_dir.path()).unwrap_or_else(|err| {
            panic!(
                "create std::fs run directory {}: {err}",
                run_dir.path().display()
            )
        });
        let output = run_x86_64_elf_output_in_dir(
            "x86 source pack std::fs text write",
            "x86_source_pack_std_fs_text_write",
            &bytes,
            run_dir.path(),
        );
        common::assert_command_success("x86 source pack std::fs text write", &output);
        let output_path = run_dir.path().join("std_output.txt");
        let text = std::fs::read_to_string(&output_path)
            .unwrap_or_else(|err| panic!("read std::fs output {}: {err}", output_path.display()));
        assert_eq!(text, "saved");
        std::fs::remove_dir_all(run_dir.path()).unwrap_or_else(|err| {
            panic!(
                "remove std::fs run directory {}: {err}",
                run_dir.path().display()
            )
        });
    }
}

#[test]
fn x86_executes_source_pack_std_fs_buffer_copy() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/fs.lani"),
        r#"
module app::main;

import alloc::allocator;
import std::fs;

fn main() -> i32 {
    let capacity: usize = 64;
    let align: usize = 4;
    let ptr: u32 = alloc::allocator::alloc(capacity, align);
    if (ptr == 0) {
        return 1;
    }

    let input: std::fs::FileHandle = std::fs::open_read_path("fs_raw_input.bin");
    if (input < 0) {
        alloc::allocator::dealloc(ptr, capacity, align);
        return 2;
    }
    let count: i32 = std::fs::read(input, ptr, capacity);
    let input_close: i32 = std::fs::close(input);
    if (count <= 0 || input_close < 0) {
        alloc::allocator::dealloc(ptr, capacity, align);
        return 3;
    }

    let output: std::fs::FileHandle = std::fs::open_write_path("fs_raw_output.bin");
    if (output < 0) {
        alloc::allocator::dealloc(ptr, capacity, align);
        return 4;
    }
    let count_len: usize = count;
    let written: i32 = std::fs::write(output, ptr, count_len);
    let output_close: i32 = std::fs::close(output);
    alloc::allocator::dealloc(ptr, capacity, align);
    if (written != count || output_close < 0) {
        return 5;
    }
    return 0;
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack std::fs buffer copy", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_fs_buffer", "run_dir", None);
        std::fs::create_dir(run_dir.path()).unwrap_or_else(|err| {
            panic!(
                "create std::fs buffer run directory {}: {err}",
                run_dir.path().display()
            )
        });
        let input = b"raw\x00bytes\nsecond line\n";
        let input_path = run_dir.path().join("fs_raw_input.bin");
        std::fs::write(&input_path, input).unwrap_or_else(|err| {
            panic!("write std::fs buffer input {}: {err}", input_path.display())
        });
        let output = run_x86_64_elf_output_in_dir(
            "x86 source pack std::fs buffer copy",
            "x86_source_pack_std_fs_buffer_copy",
            &bytes,
            run_dir.path(),
        );
        common::assert_command_success("x86 source pack std::fs buffer copy", &output);
        let output_path = run_dir.path().join("fs_raw_output.bin");
        let copied = std::fs::read(&output_path).unwrap_or_else(|err| {
            panic!(
                "read std::fs buffer output {}: {err}",
                output_path.display()
            )
        });
        assert_eq!(copied, input);
        std::fs::remove_dir_all(run_dir.path()).unwrap_or_else(|err| {
            panic!(
                "remove std::fs buffer run directory {}: {err}",
                run_dir.path().display()
            )
        });
    }
}

#[test]
fn x86_executes_source_pack_std_fs_pointer_path_open() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/fs.lani"),
        include_str!("../stdlib/std/process.lani"),
        r#"
module app::main;

import alloc::allocator;
import std::fs;
import std::process;

fn main() -> i32 {
    let path_capacity: usize = 4096;
    let data_capacity: usize = 4;
    let align: usize = 4;
    let input_path: u32 = alloc::allocator::alloc(path_capacity, align);
    if (input_path == 0) {
        return 1;
    }
    let output_path: u32 = alloc::allocator::alloc(path_capacity, align);
    if (output_path == 0) {
        alloc::allocator::dealloc(input_path, path_capacity, align);
        return 2;
    }
    let data: u32 = alloc::allocator::alloc(data_capacity, align);
    if (data == 0) {
        alloc::allocator::dealloc(output_path, path_capacity, align);
        alloc::allocator::dealloc(input_path, path_capacity, align);
        return 3;
    }

    let zero: i32 = 0;
    let one: i32 = 1;
    let input_len_i32: i32 = std::process::arg_read(zero, input_path, path_capacity);
    let output_len_i32: i32 = std::process::arg_read(one, output_path, path_capacity);
    if (input_len_i32 <= 0 || output_len_i32 <= 0) {
        alloc::allocator::dealloc(data, data_capacity, align);
        alloc::allocator::dealloc(output_path, path_capacity, align);
        alloc::allocator::dealloc(input_path, path_capacity, align);
        return 4;
    }

    let input_len: usize = input_len_i32;
    let input: std::fs::FileHandle = std::fs::open_read(input_path, input_len);
    if (input < 0) {
        alloc::allocator::dealloc(data, data_capacity, align);
        alloc::allocator::dealloc(output_path, path_capacity, align);
        alloc::allocator::dealloc(input_path, path_capacity, align);
        return 5;
    }
    let read_count: i32 = std::fs::read(input, data, data_capacity);
    let input_close: i32 = std::fs::close(input);
    if (read_count != 4 || input_close < 0) {
        alloc::allocator::dealloc(data, data_capacity, align);
        alloc::allocator::dealloc(output_path, path_capacity, align);
        alloc::allocator::dealloc(input_path, path_capacity, align);
        return 6;
    }

    let output_len: usize = output_len_i32;
    let output: std::fs::FileHandle = std::fs::open_write(output_path, output_len);
    if (output < 0) {
        alloc::allocator::dealloc(data, data_capacity, align);
        alloc::allocator::dealloc(output_path, path_capacity, align);
        alloc::allocator::dealloc(input_path, path_capacity, align);
        return 7;
    }
    let first_write: i32 = std::fs::write(output, data, data_capacity);
    let output_close: i32 = std::fs::close(output);
    if (first_write != 4 || output_close < 0) {
        alloc::allocator::dealloc(data, data_capacity, align);
        alloc::allocator::dealloc(output_path, path_capacity, align);
        alloc::allocator::dealloc(input_path, path_capacity, align);
        return 8;
    }

    let appended: std::fs::FileHandle = std::fs::open_append(output_path, output_len);
    if (appended < 0) {
        alloc::allocator::dealloc(data, data_capacity, align);
        alloc::allocator::dealloc(output_path, path_capacity, align);
        alloc::allocator::dealloc(input_path, path_capacity, align);
        return 9;
    }
    let second_write: i32 = std::fs::write(appended, data, data_capacity);
    let appended_close: i32 = std::fs::close(appended);
    alloc::allocator::dealloc(data, data_capacity, align);
    alloc::allocator::dealloc(output_path, path_capacity, align);
    alloc::allocator::dealloc(input_path, path_capacity, align);
    if (second_write != 4 || appended_close < 0) {
        return 10;
    }
    return 0;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack std::fs pointer path open",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_std_fs_pointer", "run_dir", None);
        std::fs::create_dir(run_dir.path()).unwrap_or_else(|err| {
            panic!(
                "create std::fs pointer run directory {}: {err}",
                run_dir.path().display()
            )
        });
        let output_name = "fs_pointer_output.bin";
        let output = run_x86_64_elf_output_in_dir_with_args(
            "x86 source pack std::fs pointer path open",
            "x86_source_pack_std_fs_pointer_path_open",
            &bytes,
            run_dir.path(),
            &[output_name],
        );
        common::assert_command_success("x86 source pack std::fs pointer path open", &output);
        let output_path = run_dir.path().join(output_name);
        let copied = std::fs::read(&output_path).unwrap_or_else(|err| {
            panic!(
                "read std::fs pointer output {}: {err}",
                output_path.display()
            )
        });
        assert_eq!(copied, b"\x7fELF\x7fELF");
        std::fs::remove_dir_all(run_dir.path()).unwrap_or_else(|err| {
            panic!(
                "remove std::fs pointer run directory {}: {err}",
                run_dir.path().display()
            )
        });
    }
}

#[test]
fn x86_executes_source_pack_std_process_exit() {
    let sources = [
        include_str!("../stdlib/std/process.lani"),
        r#"
module app::main;

import std::process;

fn finish(code: i32) {
    std::process::exit(code);
}

fn main() {
    finish(7);
    return 0;
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack std::process exit", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack std::process exit",
        "x86_source_pack_std_process_exit",
        &bytes,
        7,
    );
}

#[test]
fn x86_executes_source_pack_std_process_argc_from_helper() {
    let sources = [
        include_str!("../stdlib/std/process.lani"),
        r#"
module app::main;

import std::process;

fn observed_argc() -> i32 {
    return std::process::argc();
}

fn main() {
    return observed_argc() - 1;
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack std::process argc", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack std::process argc",
        "x86_source_pack_std_process_argc",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_std_process_args_from_helper() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/process.lani"),
        r#"
module app::main;

import alloc::allocator;
import std::process;

fn first_arg_len(index: i32) -> i32 {
    return std::process::arg_len(index);
}

fn first_arg_read(index: i32, ptr: u32, len: usize) -> i32 {
    return std::process::arg_read(index, ptr, len);
}

fn main() -> i32 {
    let zero: i32 = 0;
    let arg_count: i32 = std::process::argc();
    if (arg_count < 1) {
        return 10;
    }
    let len: i32 = first_arg_len(zero);
    if (len <= 0) {
        return 11;
    }
    if (std::process::arg_len(arg_count) != -1) {
        return 12;
    }
    let capacity: usize = 16;
    let align: usize = 4;
    let ptr: u32 = alloc::allocator::alloc(capacity, align);
    if (ptr == 0) {
        return 13;
    }
    let read: i32 = first_arg_read(zero, ptr, capacity);
    let negative: i32 = zero - 1;
    if (std::process::arg_read(negative, ptr, capacity) != -1) {
        alloc::allocator::dealloc(ptr, capacity, align);
        return 14;
    }
    alloc::allocator::dealloc(ptr, capacity, align);
    if (read <= 0) {
        return 15;
    }
    if (read > 16) {
        return 16;
    }
    return 0;
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack std::process args", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source pack std::process args should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack std::process args",
        "x86_source_pack_std_process_args",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_std_process_arg_len_from_helper() {
    let sources = [
        include_str!("../stdlib/std/process.lani"),
        r#"
module app::main;

import std::process;

fn first_arg_len(index: i32) -> i32 {
    return std::process::arg_len(index);
}

fn main() -> i32 {
    let zero: i32 = 0;
    let arg_count: i32 = std::process::argc();
    if (arg_count < 1) {
        return 10;
    }
    let len: i32 = first_arg_len(zero);
    if (len <= 0) {
        return 11;
    }
    if (std::process::arg_len(arg_count) != -1) {
        return 12;
    }
    return 0;
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack std::process arg_len", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source pack std::process arg_len should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack std::process arg_len",
        "x86_source_pack_std_process_arg_len",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_std_random_secure_u32() {
    let sources = [
        include_str!("../stdlib/std/random.lani"),
        r#"
module app::main;

import std::random;

fn main() {
    let a: u32 = std::random::secure_u32();
    let b: u32 = std::random::secure_u32();
    let c: u32 = std::random::secure_u32();
    let d: u32 = std::random::secure_u32();
    if (a != b) {
        return 0;
    }
    if (b != c) {
        return 0;
    }
    if (c != d) {
        return 0;
    }
    return 1;
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack std::random secure_u32", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack std::random secure_u32",
        "x86_source_pack_std_random_secure_u32",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_std_random_fill_secure_bytes() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/io.lani"),
        include_str!("../stdlib/std/random.lani"),
        r#"
module app::main;

import alloc::allocator;
import std::io;
import std::random;

fn main() -> i32 {
    if (!std::random::random_is_available()) {
        return 4;
    }
    if (!std::random::fill_secure_bytes_is_executable()) {
        return 5;
    }
    let len: usize = 16;
    let align: usize = 4;
    let ptr: u32 = alloc::allocator::alloc(len, align);
    if (ptr == 0) {
        return 1;
    }
    let filled: i32 = std::random::fill_secure_bytes(ptr, len);
    if (filled != 16) {
        alloc::allocator::dealloc(ptr, len, align);
        return 2;
    }
    let written: i32 = std::io::write_stdout(ptr, len);
    alloc::allocator::dealloc(ptr, len, align);
    if (written != filled) {
        return 3;
    }
    return 0;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack std::random fill_secure_bytes",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source pack std::random fill_secure_bytes should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    let output = common::run_x86_64_elf_output(
        "x86 source pack std::random fill_secure_bytes",
        "x86_source_pack_std_random_fill_secure_bytes",
        &bytes,
    );
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(output.stdout.len(), 16);
    assert!(output.stdout.iter().any(|byte| *byte != 0));
}

#[test]
fn x86_executes_source_pack_std_fs_path_mutations() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/process.lani"),
        include_str!("../stdlib/std/fs.lani"),
        r#"
module app::main;
import alloc::allocator;
import std::process;
import std::fs;
fn main() -> i32 {
    let capacity: usize = 64;
    let path_len: usize = 20;
    let from_ptr: u32 = alloc::allocator::alloc(capacity, 4);
    let to_ptr: u32 = alloc::allocator::alloc(capacity, 4);
    let from_read_result: i32 = std::process::arg_read(1, from_ptr, capacity);
    let to_read_result: i32 = std::process::arg_read(2, to_ptr, capacity);
    if (from_read_result != 20) {
        return 1;
    }
    if (to_read_result != 20) {
        return 1;
    }
    let create_result: i32 = std::fs::create_dir(from_ptr, path_len);
    if (create_result != 0) {
        return 2;
    }
    let rename_dir_result: i32 = std::fs::rename(from_ptr, path_len, to_ptr, path_len);
    if (rename_dir_result != 0) {
        return 3;
    }
    let remove_dir_result: i32 = std::fs::remove_dir(to_ptr, path_len);
    if (remove_dir_result != 0) {
        return 4;
    }
    let handle: i32 = std::fs::open_write(from_ptr, path_len);
    if (handle < 0) {
        return 5;
    }
    let close_result: i32 = std::fs::close(handle);
    if (close_result != 0) {
        return 6;
    }
    let rename_file_result: i32 = std::fs::rename(from_ptr, path_len, to_ptr, path_len);
    if (rename_file_result != 0) {
        return 7;
    }
    let remove_file_result: i32 = std::fs::remove_file(to_ptr, path_len);
    if (remove_file_result != 0) {
        return 8;
    }
    alloc::allocator::dealloc(from_ptr, capacity, 4);
    alloc::allocator::dealloc(to_ptr, capacity, 4);
    return 0;
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack std::fs path mutations", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source pack std::fs path mutations should compile to x86_64");
    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output_with_args(
            "x86 source pack std::fs path mutations",
            "x86_source_pack_std_fs_path_mutations",
            &bytes,
            &["lanius_fs_mutation_x", "lanius_fs_mutation_y"],
        );
        assert_eq!(output.status.code(), Some(0));
    }
}

#[test]
fn x86_executes_source_pack_std_time_unix_seconds() {
    let sources = [
        include_str!("../stdlib/std/time.lani"),
        r#"
module app::main;

import std::time;

fn main() -> i32 {
    let seconds: i32 = std::time::unix_seconds();
    if (seconds > 0) {
        return 0;
    }
    return 1;
}

"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack std::time unix_seconds", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source pack std::time unix_seconds should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack std::time unix_seconds",
        "x86_source_pack_std_time_unix_seconds",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_exact_clock_buffer_api() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/time.lani"),
        r#"
module app::main;
import alloc::allocator;
import std::time;
fn main() -> i32 {
    let ptr: u32 = alloc::allocator::alloc(16, 8);
    let monotonic_status: i32 = std::time::monotonic_read(ptr, 16);
    if (monotonic_status != 0) {
        return 1;
    }
    let system_status: i32 = std::time::system_read(ptr, 16);
    if (system_status != 0) {
        return 2;
    }
    let short_status: i32 = std::time::monotonic_read(ptr, 15);
    if (short_status != -1) {
        return 3;
    }
    let sleep_status: i32 = std::time::sleep_ms_i32(0);
    if (sleep_status != 0) {
        return 4;
    }
    let negative_status: i32 = std::time::sleep_ms_i32(-1);
    if (negative_status != -1) {
        return 5;
    }
    alloc::allocator::dealloc(ptr, 16, 8);
    return 0;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout("x86 exact clock buffer API", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("exact clock buffer API should compile to x86_64");
    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 exact clock buffer API",
        "exact_clock_buffer",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_std_env_current_dir_read() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/env.lani"),
        r#"
module app::main;

import alloc::allocator;
import std::env;

fn read_current_dir(ptr: u32, capacity: usize) -> i32 {
    return std::env::current_dir_read(ptr, capacity);
}

fn main() -> i32 {
    let reported_len: i32 = std::env::current_dir_len();
    if (reported_len <= 0) {
        return 9;
    }
    let capacity: usize = 256;
    let capacity_i32: i32 = 256;
    let align: usize = 4;
    let ptr: u32 = alloc::allocator::alloc(capacity, align);
    if (ptr == 0) {
        return 10;
    }
    let read: i32 = read_current_dir(ptr, capacity);
    alloc::allocator::dealloc(ptr, capacity, align);
    if (read <= 0) {
        return 11;
    }
    if (read > capacity_i32) {
        return 12;
    }
    if (read != reported_len) {
        return 13;
    }
    return 0;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack std::env current_dir_read",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source pack std::env current_dir_read should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack std::env current_dir_read",
        "x86_source_pack_std_env_current_dir_read",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_std_env_var_key_enumeration() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/env.lani"),
        r#"
module app::main;

import alloc::allocator;
import std::env;

fn first_key_len(index: i32) -> i32 {
    return std::env::var_key_len(index);
}

fn first_key_read(index: i32, ptr: u32, capacity: usize) -> i32 {
    return std::env::var_key_read(index, ptr, capacity);
}

fn main() -> i32 {
    let count: i32 = std::env::var_count();
    if (count < 0) {
        return 10;
    }
    if (count == 0) {
        return 0;
    }
    let zero: i32 = 0;
    let len: i32 = first_key_len(zero);
    if (len <= 0) {
        return 11;
    }
    if (std::env::var_key_len(count) != -1) {
        return 12;
    }
    let capacity: usize = 4096;
    let capacity_i32: i32 = 4096;
    let align: usize = 4;
    let ptr: u32 = alloc::allocator::alloc(capacity, align);
    if (ptr == 0) {
        return 13;
    }
    let read: i32 = first_key_read(zero, ptr, capacity);
    let invalid_read: i32 = std::env::var_key_read(count, ptr, capacity);
    alloc::allocator::dealloc(ptr, capacity, align);
    if (invalid_read != -1) {
        return 14;
    }
    if (read <= 0) {
        return 15;
    }
    if (read > capacity_i32) {
        return 16;
    }
    if (len <= capacity_i32 && read != len) {
        return 17;
    }
    return 0;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack std::env var key enumeration",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source pack std::env var key enumeration should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack std::env var key enumeration",
        "x86_source_pack_std_env_var_key_enumeration",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_std_env_var_lookup() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/env.lani"),
        r#"
module app::main;

import alloc::allocator;
import std::env;

fn value_len_for_key(ptr: u32, len: usize) -> i32 {
    return std::env::var_len(ptr, len);
}

fn value_read_for_key(key_ptr: u32, key_len: usize, value_ptr: u32, value_capacity: usize) -> i32 {
    return std::env::var_read(key_ptr, key_len, value_ptr, value_capacity);
}

fn main() -> i32 {
    let count: i32 = std::env::var_count();
    if (count < 0) {
        return 10;
    }
    if (count == 0) {
        return 0;
    }
    let capacity: usize = 4096;
    let capacity_i32: i32 = 4096;
    let align: usize = 4;
    let key_ptr: u32 = alloc::allocator::alloc(capacity, align);
    if (key_ptr == 0) {
        return 11;
    }
    let value_ptr: u32 = alloc::allocator::alloc(capacity, align);
    if (value_ptr == 0) {
        alloc::allocator::dealloc(key_ptr, capacity, align);
        return 12;
    }
    let zero: i32 = 0;
    let key_len_i32: i32 = std::env::var_key_read(zero, key_ptr, capacity);
    if (key_len_i32 <= 0) {
        alloc::allocator::dealloc(value_ptr, capacity, align);
        alloc::allocator::dealloc(key_ptr, capacity, align);
        return 13;
    }
    let key_len: usize = key_len_i32;
    let value_len: i32 = value_len_for_key(key_ptr, key_len);
    if (value_len < 0) {
        alloc::allocator::dealloc(value_ptr, capacity, align);
        alloc::allocator::dealloc(key_ptr, capacity, align);
        return 14;
    }
    let value_read: i32 = value_read_for_key(key_ptr, key_len, value_ptr, capacity);
    alloc::allocator::dealloc(value_ptr, capacity, align);
    alloc::allocator::dealloc(key_ptr, capacity, align);
    if (value_read < 0) {
        return 15;
    }
    if (value_read > capacity_i32) {
        return 16;
    }
    if (value_len <= capacity_i32 && value_read != value_len) {
        return 17;
    }
    return 0;
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack std::env var lookup", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source pack std::env var lookup should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack std::env var lookup",
        "x86_source_pack_std_env_var_lookup",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_alloc_allocator_alloc_dealloc() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        r#"
module app::main;

import alloc::allocator;

fn main() {
    let ptr: u32 = alloc::allocator::alloc(64, 8);
    if (ptr == 0) {
        return 1;
    }
    alloc::allocator::dealloc(ptr, 64, 8);
    return 0;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack alloc::allocator alloc/dealloc",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack alloc::allocator alloc/dealloc",
        "x86_source_pack_alloc_allocator_alloc_dealloc",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_recursive_scalar_call() {
    let sources = [
        r#"
module helpers::recur;

pub fn sum_down(value: i32) -> i32 {
    if (value <= 0) {
        return 0;
    }
    return value + sum_down(value - 1);
}
"#,
        r#"
module app::main;

import helpers::recur;

fn main() {
    return helpers::recur::sum_down(4);
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack recursive scalar call", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source-pack recursive scalar helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack recursive scalar call",
        "x86_source_pack_recursive_scalar_call",
        &bytes,
        10,
    );
}

#[test]
fn x86_executes_source_pack_bool_helper_call_in_branch_condition() {
    let sources = [
        "module helpers::predicates;\npub fn between(value: i32, low: i32, high: i32) -> bool {\n    return value > low && value < high;\n}\n",
        "module app::main;\nimport helpers::predicates;\nfn main() {\n    if (helpers::predicates::between(7, 3, 10)) {\n        return 9;\n    } else {\n        return 1;\n    }\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack bool helper branch condition",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack bool helper branch condition should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack bool helper branch condition",
        "x86_source_pack_bool_helper_branch_condition",
        &bytes,
        9,
    );
}

#[test]
fn x86_executes_source_pack_std_path_separator_helper() {
    let sources = [
        include_str!("../stdlib/std/path.lani"),
        r#"
module app::main;

import std::path;

fn main() {
    let slash: std::path::PathByte = std::path::PATH_SEPARATOR_UNIX;
    let letter: std::path::PathByte = 65;
    if (std::path::path_byte_is_separator(slash)) {
        if (!std::path::path_byte_is_separator(letter)) {
            return 0;
        }
    }
    return 1;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack std::path separator helper",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack std::path separator helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack std::path separator helper",
        "x86_source_pack_std_path_separator_helper",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_helper_call_in_loop_condition() {
    let sources = [
        "module helpers::loops;\npub fn remaining(value: i32) -> i32 {\n    return 2 - value;\n}\n",
        "module app::main;\nimport helpers::loops;\nfn main() {\n    let i: i32 = 0;\n    while (helpers::loops::remaining(i) > 0) {\n        i += 1;\n    }\n    return i;\n}\n",
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack helper loop condition", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source-pack helper loop condition should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack helper loop condition",
        "x86_source_pack_helper_loop_condition",
        &bytes,
        2,
    );
}

#[test]
fn x86_executes_source_pack_helper_call_in_loop_body_assignment() {
    let sources = [
        "module helpers::loops;\npub fn advance(value: i32) -> i32 {\n    return value + 1;\n}\n",
        "module app::main;\nimport helpers::loops;\nfn main() {\n    let i: i32 = 0;\n    while (i < 2) {\n        i = helpers::loops::advance(i);\n    }\n    return i;\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack helper loop body assignment",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack helper loop body assignment should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack helper loop body assignment",
        "x86_source_pack_helper_loop_body_assignment",
        &bytes,
        2,
    );
}

#[test]
fn x86_executes_source_pack_helper_call_in_loop_let_initializer() {
    let sources = [
        "module helpers::loops;\npub fn advance(value: i32) -> i32 {\n    return value + 1;\n}\n",
        "module app::main;\nimport helpers::loops;\nfn main() {\n    let i: i32 = 0;\n    while (i < 3) {\n        let next: i32 = helpers::loops::advance(i);\n        i = next;\n    }\n    return i;\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack helper loop let initializer",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack helper loop let initializer should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack helper loop let initializer",
        "x86_source_pack_helper_loop_let_initializer",
        &bytes,
        3,
    );
}

#[test]
fn x86_executes_source_pack_branch_body_call_with_nested_argument_call() {
    let sources = [
        r#"
module helpers::math;

pub fn add(left: i32, right: i32) -> i32 {
    return left + right;
}

pub fn adjusted(value: i32) -> i32 {
    if (value == 1) {
        return 10;
    }
    return value;
}
"#,
        r#"
module app::main;

import helpers::math;

fn main() {
    let index: i32 = 0;
    let total: i32 = 0;
    while (index < 4) {
        if (index < 2) {
            total = helpers::math::add(total, helpers::math::adjusted(index));
        } else {
            total = helpers::math::add(total, index * 2);
        }
        index += 1;
    }
    return total;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack branch body nested call argument",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack branch-body nested helper call should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack branch body nested call argument",
        "x86_source_pack_branch_body_nested_call_argument",
        &bytes,
        20,
    );
}

#[test]
fn x86_executes_source_pack_helper_branch_early_return_and_fallthrough_return() {
    let sources = [
        "module helpers::adjust;\npub fn adjusted(value: i32) -> i32 {\n    if (value < 0) {\n        return -value;\n    }\n    return value + 1;\n}\n",
        "module app::main;\nimport helpers::adjust;\nfn main() {\n    return helpers::adjust::adjusted(-6) + helpers::adjust::adjusted(4);\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack helper branch early return",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack helper early return and fallthrough should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack helper branch early return",
        "x86_source_pack_helper_early_return",
        &bytes,
        11,
    );
}

#[test]
fn x86_executes_source_pack_nested_call_results_as_call_arguments() {
    let sources = [
        "module helpers::math;\npub fn inc(value: i32) -> i32 {\n    return value + 1;\n}\npub fn mix(left: i32, right: i32) -> i32 {\n    return left * 10 + right;\n}\n",
        "module app::main;\nimport helpers::math;\nfn main() {\n    return helpers::math::mix(helpers::math::inc(3), helpers::math::inc(4));\n}\n",
    ];

    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack nested call arguments", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect(
            "source-pack nested helper call arguments should compile through GPU x86 call records",
        );

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack nested call arguments",
        "x86_source_pack_nested_call_arguments",
        &bytes,
        45,
    );
}

#[test]
fn x86_executes_source_pack_struct_parameter_helper_call() {
    let sources = [
        r#"
module helpers::ranges;

pub struct Range {
    start: i32,
    end: i32,
}

pub fn make(start: i32, end: i32) -> Range {
    return Range { start: start, end: end };
}

pub fn span(range: Range) -> i32 {
    return range.end - range.start;
}

pub fn shifted_span(range: Range, amount: i32) -> i32 {
    return span(range) + amount;
}
"#,
        r#"
module app::main;

import helpers::ranges;

fn main() {
    let range: helpers::ranges::Range = helpers::ranges::make(2, 8);
    return helpers::ranges::shifted_span(range, 4);
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack struct parameter helper call",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack struct-parameter helper calls should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack struct parameter helper call",
        "x86_source_pack_struct_parameter_helper_call",
        &bytes,
        10,
    );
}

#[test]
fn x86_executes_source_pack_aggregate_return_passed_to_helper_in_loop() {
    let sources = [
        r#"
module helpers::pairs;

pub struct Pair {
    left: i32,
    right: i32,
}

pub fn make_pair(left: i32, right: i32) -> Pair {
    return Pair { left: left, right: right };
}

pub fn score(pair: Pair) -> i32 {
    return pair.left * 10 + pair.right;
}
"#,
        r#"
module app::main;

import helpers::pairs;

fn main() {
    let row: i32 = 0;
    let total: i32 = 0;
    while (row < 3) {
        let pair: helpers::pairs::Pair = helpers::pairs::make_pair(2 + row, 5 - row);
        total += helpers::pairs::score(pair);
        row += 1;
    }
    return total;
}
"#,
    ];

    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack aggregate return passed to helper in loop",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack aggregate return should pass through imported helper calls in loops");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack aggregate return passed to helper in loop",
        "x86_source_pack_aggregate_return_helper_loop",
        &bytes,
        102,
    );
}

#[test]
fn x86_executes_source_pack_four_argument_helper_call() {
    let sources = [
        "module core::math;\npub fn mix(first: i32, second: i32, third: i32, fourth: i32) -> i32 {\n    return first * 10 + second * 3 + third - fourth;\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    let local: i32 = 4;\n    let other: i32 = 6;\n    return core::math::mix(local, 2 + 1, other, 5);\n}\n",
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack four argument call", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source-pack four-argument helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack four argument call",
        "x86_source_pack_four_arg_call",
        &bytes,
        50,
    );
}

#[test]
fn x86_executes_source_pack_six_argument_helper_call() {
    let sources = [
        r#"
module core::weights;

pub fn weighted(
    first: i32,
    second: i32,
    third: i32,
    fourth: i32,
    fifth: i32,
    sixth: i32,
) -> i32 {
    return first + second * 2 + third * 3 + fourth * 4 + fifth * 5 + sixth * 6;
}
"#,
        r#"
module app::main;

import core::weights;

fn main() {
    let local: i32 = 2;
    let other: i32 = 5;
    return core::weights::weighted(local, 1 + 2, other, 4, 2 + 3, 6);
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack six argument call", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source-pack six-argument helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack six argument call",
        "x86_source_pack_six_arg_call",
        &bytes,
        100,
    );
}

#[test]
fn x86_executes_source_pack_locals_live_across_consecutive_calls() {
    let sources = [
        "module helpers::calls;\npub fn mix(first: i32, second: i32, third: i32, fourth: i32) -> i32 {\n    return first * 7 + second * 5 + third * 3 + fourth;\n}\npub fn bump(value: i32) -> i32 {\n    return value + 2;\n}\n",
        "module app::main;\nimport helpers::calls;\nfn main() {\n    let anchor: i32 = 11;\n    let left: i32 = helpers::calls::mix(1, 2, 3, 4);\n    let right: i32 = helpers::calls::bump(anchor);\n    return left + right + anchor;\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack locals live across consecutive calls",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack consecutive helper calls should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack locals live across consecutive calls",
        "x86_source_pack_call_liveness",
        &bytes,
        54,
    );
}

#[test]
fn x86_executes_source_pack_array_param_helper_with_loop_and_branch() {
    let sources = [
        r#"
module helpers::fold;
pub fn weighted_sum(values: [i32; 4], bias: i32) -> i32 {
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 4) {
        let term: i32 = values[i] * (i + 1);
        if ((term + bias) > 10) {
            total += term - bias;
        } else {
            total += term + bias;
        }
        i += 1;
    }
    return total;
}
"#,
        r#"
module app::main;
import helpers::fold;
fn main() {
    let numbers: [i32; 4] = [2, 3, 4, 5];
    return helpers::fold::weighted_sum(numbers, 2);
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack array parameter loop helper",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack array-parameter helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack array parameter loop helper",
        "x86_source_pack_array_param_loop_helper",
        &bytes,
        40,
    );
}

#[test]
fn x86_executes_source_pack_for_array_parameter_helper() {
    let sources = [
        r#"
module helpers::fold;
pub fn sum_until(values: [i32; 4], stop: i32) -> i32 {
    let total: i32 = 0;
    for value in values {
        if (value == stop) {
            break;
        }
        if (value == 3) {
            continue;
        }
        total += value;
    }
    return total;
}
"#,
        r#"
module app::main;
import helpers::fold;
fn main() {
    let numbers: [i32; 4] = [2, 3, 4, 5];
    return helpers::fold::sum_until(numbers, 5);
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack for array parameter helper",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack for over a sized array parameter should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack for array parameter helper",
        "x86_source_pack_for_array_parameter_helper",
        &bytes,
        6,
    );
}

#[test]
fn x86_executes_source_pack_nested_loop_helper_with_inner_call() {
    let sources = [
        r#"
module helpers::nested;
pub fn add(left: i32, right: i32) -> i32 {
    return left + right;
}

pub fn triangular(limit: i32) -> i32 {
    let row: i32 = 0;
    let total: i32 = 0;
    while (row < limit) {
        let column: i32 = 0;
        while (column < row) {
            total = add(total, column);
            column += 1;
        }
        row += 1;
    }
    return total;
}
"#,
        r#"
module app::main;
import helpers::nested;
fn main() {
    return helpers::nested::triangular(4);
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout(
        "x86 source pack nested loop helper inner call",
        move || pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources)),
    )
    .expect("source-pack nested loop helper with an inner call should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack nested loop helper inner call",
        "x86_source_pack_nested_loop_inner_call",
        &bytes,
        4,
    );
}

#[test]
fn x86_executes_stdlib_helper_from_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_ascii_digit(53);\n}\n",
    ];
    let bytes = common::run_gpu_codegen_with_timeout("x86 source pack stdlib helper", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("stdlib helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack stdlib helper",
        "x86_stdlib_helper",
        &bytes,
        1,
    );
}

#[test]
fn x86_executes_stdlib_f32_sqrt_from_source_pack() {
    let sources = [
        include_str!("../stdlib/core/f32.lani"),
        r#"
module app::main;

import core::f32;
extern "lanius_std" fn i32_to_f32(value: i32) -> f32;

fn color_to_byte(value: f32) -> i32 {
    let scaled: f32 = core::f32::sqrt(value) * 256.0;
    let byte: i32 = 0;
    let threshold: f32 = 1.0;
    while (threshold <= scaled && byte < 255) {
        byte += 1;
        threshold += 1.0;
    }
    return byte;
}

fn main() {
    let r: i32 = color_to_byte(0.625);
    if (r > 200 && r < 204) {
        return 0;
    }
    return 1;
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack stdlib f32 sqrt", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("stdlib f32 sqrt helper should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack stdlib f32 sqrt",
        "x86_stdlib_f32_sqrt",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_source_pack_camera_sky_with_stdlib_sqrt() {
    let sources = [
        include_str!("../stdlib/core/f32.lani"),
        r#"
module app::main;

import core::f32;
extern "lanius_std" fn i32_to_f32(value: i32) -> f32;

struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn mul_scalar(self, scale: f32) -> Vec3 {
        return Vec3::new(self.x * scale, self.y * scale, self.z * scale);
    }

    fn add(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x + right.x, self.y + right.y, self.z + right.z);
    }

    fn sub(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x - right.x, self.y - right.y, self.z - right.z);
    }

    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y + self.z * right.z;
    }

    fn length(self) -> f32 {
        return core::f32::sqrt(self.dot(self));
    }

    fn unit(self) -> Vec3 {
        let len: f32 = self.length();
        if (len == 0.0) {
            return self;
        }
        return self.mul_scalar(1.0 / len);
    }
}

struct Ray {
    origin: Vec3,
    direction: Vec3,
}

struct Camera {
    origin: Vec3,
    lower_left_corner: Vec3,
    horizontal: Vec3,
    vertical: Vec3,
}

struct Sphere {
    center: Vec3,
    radius: f32,
    albedo: Vec3,
}

struct Hit {
    ok: bool,
    t: f32,
    point: Vec3,
    normal: Vec3,
    albedo: Vec3,
}

struct RenderSettings {
    width: i32,
    height: i32,
    samples_per_pixel: i32,
}

impl Camera {
    fn ray(self, u: f32, v: f32) -> Ray {
        let horizontal: Vec3 = self.horizontal;
        let vertical: Vec3 = self.vertical;
        let lower_left_corner: Vec3 = self.lower_left_corner;
        let origin: Vec3 = self.origin;
        let across: Vec3 = horizontal.mul_scalar(u);
        let up: Vec3 = vertical.mul_scalar(v);
        let corner_across: Vec3 = lower_left_corner.add(across);
        let target: Vec3 = corner_across.add(up);
        let direction: Vec3 = target.sub(origin);
        let result: Ray = Ray {
            origin: origin,
            direction: direction,
        };
        return result;
    }
}

fn make_camera(settings: RenderSettings) -> Camera {
    let aspect_ratio: f32 = i32_to_f32(settings.width) / i32_to_f32(settings.height);
    let viewport_width: f32 = aspect_ratio * 2.0;
    let origin: Vec3 = Vec3::new(0.0, 0.0, 0.0);
    let horizontal: Vec3 = Vec3::new(viewport_width, 0.0, 0.0);
    let vertical: Vec3 = Vec3::new(0.0, 2.0, 0.0);
    let half_horizontal: Vec3 = horizontal.mul_scalar(0.5);
    let half_vertical: Vec3 = vertical.mul_scalar(0.5);
    let focal: Vec3 = Vec3::new(0.0, 0.0, 1.0);
    let lower_step0: Vec3 = origin.sub(half_horizontal);
    let lower_step1: Vec3 = lower_step0.sub(half_vertical);
    let lower_left_corner: Vec3 = lower_step1.sub(focal);
    let result: Camera = Camera {
        origin: origin,
        lower_left_corner: lower_left_corner,
        horizontal: horizontal,
        vertical: vertical,
    };
    return result;
}

fn default_settings() -> RenderSettings {
    let result: RenderSettings = RenderSettings {
        width: 16,
        height: 9,
        samples_per_pixel: 1,
    };
    return result;
}

fn sky_color(ray: Ray) -> Vec3 {
    let direction: Vec3 = ray.direction;
    let dir: Vec3 = direction.unit();
    let t: f32 = 0.5 * (dir.y + 1.0);
    let white: Vec3 = Vec3::new(1.0, 1.0, 1.0);
    let blue: Vec3 = Vec3::new(0.5, 0.7, 1.0);
    let left_part: Vec3 = white.mul_scalar(1.0 - t);
    let right_part: Vec3 = blue.mul_scalar(t);
    return left_part.add(right_part);
}

fn color_to_byte(value: f32) -> i32 {
    let scaled: f32 = core::f32::sqrt(value) * 256.0;
    let byte: i32 = 0;
    let threshold: f32 = 1.0;
    while (threshold <= scaled && byte < 255) {
        byte += 1;
        threshold += 1.0;
    }
    return byte;
}

fn main() -> i32 {
    let settings: RenderSettings = default_settings();
    let camera: Camera = make_camera(settings);
    let camera_vertical: Vec3 = camera.vertical;
    if (!(camera_vertical.y > 1.9 && camera_vertical.y < 2.1)) {
        return 60;
    }
    let camera_lower_left: Vec3 = camera.lower_left_corner;
    if (!(camera_lower_left.y < -0.9 && camera_lower_left.y > -1.1)) {
        return 61;
    }
    let ray: Ray = camera.ray(0.033333, 0.9375);
    let sky: Vec3 = sky_color(ray);
    let byte: i32 = color_to_byte(sky.x);
    if (byte > 204 && byte < 209) {
        return 0;
    }
    return byte;
}
"#,
    ];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack camera sky stdlib sqrt", move || {
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
        })
        .expect("source pack camera sky stdlib sqrt should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack camera sky stdlib sqrt",
        "x86_source_pack_camera_sky_stdlib_sqrt",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_raytracer_first_pixel_from_source_pack() {
    let source = include_str!("fixtures/raytracer_ppm/raytracer.lani").replace(
        r#"fn main() -> i32 {
    let settings_path: str = "render_settings.txt";
    let settings: RenderSettings = load_settings(settings_path);
    let file: i32 = open_write_path("lanius_ray.ppm");
    if (file < 0) {
        print(-1);
        return 1;
    }

    let pixels_written: i32 = render(file, settings);
    let close_status: i32 = close_file(file);
    if (operation_failed(pixels_written)) {
        print(-2);
        return 1;
    }
    if (operation_failed(close_status)) {
        print(-2);
        return 1;
    }

    print(pixels_written);
    return 0;
}
"#,
        r#"fn main() -> i32 {
    let settings: RenderSettings = default_settings();
    let camera: Camera = make_camera(settings);
    let ray: Ray = camera.ray(0.033333, 0.9375);
    let ray_direction: Vec3 = ray.direction;
    if (!(ray_direction.y > 0.85 && ray_direction.y < 0.90)) {
        if (ray_direction.x < -1.6 && ray_direction.x > -1.8) {
            return 62;
        }
        if (ray_direction.z < -0.9 && ray_direction.z > -1.1) {
            return 63;
        }
        return color_to_byte(ray_direction.y);
    }
    let sky_before_hit_world: Vec3 = sky_color(ray);
    if (!(sky_before_hit_world.x > 0.60 && sky_before_hit_world.x < 0.65)) {
        return color_to_byte(sky_before_hit_world.x);
    }
    let ground_center: Vec3 = Vec3::new(0.0, -100.5, -1.0);
    let ground_albedo: Vec3 = Vec3::new(0.8, 0.8, 0.0);
    let ground: Sphere = Sphere {
        center: ground_center,
        radius: 100.0,
        albedo: ground_albedo,
    };
    let hit_ground: Hit = hit_sphere(ground, ray, 0.001, 1000000.0);
    if (hit_ground.ok) {
        return 40;
    }
    let center_center: Vec3 = Vec3::new(0.0, 0.0, -1.0);
    let center_albedo: Vec3 = Vec3::new(0.7, 0.3, 0.3);
    let center: Sphere = Sphere {
        center: center_center,
        radius: 0.5,
        albedo: center_albedo,
    };
    let hit_center: Hit = hit_sphere(center, ray, 0.001, 1000000.0);
    if (hit_center.ok) {
        return 41;
    }
    let side_center: Vec3 = Vec3::new(1.0, 0.0, -1.6);
    let side_albedo: Vec3 = Vec3::new(0.2, 0.4, 0.8);
    let side: Sphere = Sphere {
        center: side_center,
        radius: 0.5,
        albedo: side_albedo,
    };
    let hit_side: Hit = hit_sphere(side, ray, 0.001, 1000000.0);
    if (hit_side.ok) {
        return 42;
    }
    let hit: Hit = hit_world(ray);
    if (hit.ok) {
        return 30;
    }
    let sky: Vec3 = sky_color(ray);
    if (!(sky.x > 0.60 && sky.x < 0.65)) {
        return color_to_byte(sky.x);
    }
    let color: Vec3 = pixel_color(camera, settings, 0, 0);
    if (!(color.x > 0.60 && color.x < 0.65)) {
        return 20;
    }
    if (!(color.y > 0.75 && color.y < 0.80)) {
        return 21;
    }
    if (!(color.z > 0.99 && color.z < 1.01)) {
        return 22;
    }
    let r: i32 = color_to_byte(color.x);
    let g: i32 = color_to_byte(color.y);
    let b: i32 = color_to_byte(color.z);
    if (!(r > 200 && r < 205)) {
        return 10;
    }
    if (!(g > 223 && g < 228)) {
        return 11;
    }
    if (!(b == 255)) {
        return 12;
    }
    return 0;
}
"#,
    );
    let sources = vec![include_str!("../stdlib/core/f32.lani").to_string(), source];
    let bytes =
        common::run_gpu_codegen_with_timeout("x86 source pack raytracer first pixel", move || {
            let source_refs = sources.iter().map(String::as_str).collect::<Vec<_>>();
            pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&source_refs))
        })
        .expect("raytracer first pixel source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code(
        "x86 source pack raytracer first pixel",
        "x86_raytracer_first_pixel",
        &bytes,
        0,
    );
}

#[test]
fn x86_executes_raytracer_ppm_from_source_pack() {
    let sources = [
        include_str!("../stdlib/core/f32.lani"),
        include_str!("fixtures/raytracer_ppm/raytracer.lani"),
    ];
    let bytes = common::run_gpu_codegen_with_timeout("x86 source pack raytracer PPM", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("raytracer source pack should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let run_dir = common::TempArtifact::new("laniusc_raytracer_ppm", "run_dir", None);
        std::fs::create_dir(run_dir.path()).unwrap_or_else(|err| {
            panic!(
                "create raytracer run directory {}: {err}",
                run_dir.path().display()
            )
        });
        let output = run_x86_64_elf_output_in_dir(
            "x86 source pack raytracer PPM",
            "x86_raytracer_ppm",
            &bytes,
            run_dir.path(),
        );
        common::assert_command_success("x86 source pack raytracer PPM", &output);
        assert_eq!(
            common::stdout_utf8("x86 raytracer stdout", output.stdout),
            "144\n"
        );

        let ppm_path = run_dir.path().join("lanius_ray.ppm");
        let ppm = std::fs::read_to_string(&ppm_path)
            .unwrap_or_else(|err| panic!("read raytracer PPM {}: {err}", ppm_path.display()));
        assert!(
            ppm.starts_with("P3\n16 9\n255\n"),
            "raytracer PPM should start with the expected header, got {:?}",
            ppm.lines().take(3).collect::<Vec<_>>()
        );
        assert_eq!(
            ppm.lines().count(),
            147,
            "raytracer PPM should contain a three-line header and 144 pixel rows"
        );
        std::fs::remove_dir_all(run_dir.path()).unwrap_or_else(|err| {
            panic!(
                "remove raytracer run directory {}: {err}",
                run_dir.path().display()
            )
        });
    }
}

#[test]
fn x86_reads_source_from_path() {
    let src_path = common::TempArtifact::new("laniusc_gpu_x86", "input", Some("lani"));
    src_path.write_str("fn main() {\n    return 37;\n}\n");

    let path = src_path.path().to_path_buf();
    let bytes = common::run_gpu_codegen_with_timeout("x86 source path", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen_from_path(&path))
    })
    .expect("source path should compile to x86_64");

    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code("x86 source path", "x86_source_path", &bytes, 37);
}

#[test]
fn x86_realloc_preserves_existing_bytes() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/process.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;
import alloc::allocator;
import std::process;
import std::io;
fn main() -> i32 {
    let ptr: u32 = alloc::allocator::alloc(32, 4);
    let read: i32 = std::process::arg_read(1, ptr, 32);
    if (read != 15) {
        return 1;
    }
    let grown: u32 = alloc::allocator::realloc(ptr, 32, 64, 4);
    if (grown == 0) {
        return 2;
    }
    let written: i32 = std::io::write_stdout(grown, 15);
    if (written != 15) {
        return 3;
    }
    alloc::allocator::dealloc(grown, 64, 4);
    return 0;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout("x86 realloc preservation", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("realloc preservation should compile to x86_64");
    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output_with_args(
            "x86 realloc preservation",
            "realloc_preservation",
            &bytes,
            &["LANIUS_TEST_ENV"],
        );
        assert_eq!(output.status.code(), Some(0));
        assert_eq!(output.stdout, b"LANIUS_TEST_ENV");
    }
}

#[test]
fn x86_alloc_failed_is_non_returning() {
    let sources = [
        include_str!("../stdlib/alloc/allocator.lani"),
        r#"
module app::main;
import alloc::allocator;
fn main() -> i32 {
    alloc::allocator::alloc_failed(64, 8);
    return 99;
}
"#,
    ];
    let bytes = common::run_gpu_codegen_with_timeout("x86 alloc_failed", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("alloc_failed should compile to x86_64");
    assert_x86_64_elf_header(&bytes);
    #[cfg(all(unix, target_arch = "x86_64"))]
    assert_x86_exit_code("x86 alloc_failed", "alloc_failed", &bytes, 1);
}
