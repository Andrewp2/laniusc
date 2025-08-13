// src/lexer/gpu/debug.rs
#![allow(dead_code)]

use wgpu::BufferUsages;

use super::buffers::GpuBuffers;

/// CPU-side holder for a staged GPU buffer.
#[derive(Clone, Default)]
pub struct DebugBuffer {
    pub label: &'static str,
    pub buffer: Option<wgpu::Buffer>,
    pub byte_len: usize,
}

impl DebugBuffer {
    pub fn is_some(&self) -> bool {
        self.buffer.is_some()
    }

    pub fn read_bytes(&self) -> Option<Vec<u8>> {
        let buf = self.buffer.as_ref()?;
        let view = buf.slice(..).get_mapped_range();
        Some(view.to_vec())
    }

    pub fn read_u32s(&self) -> Option<Vec<u32>> {
        self.read_bytes().map(|v| {
            let mut out = Vec::with_capacity(v.len() / 4);
            for chunk in v.chunks_exact(4) {
                out.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            out
        })
    }
}

#[derive(Default)]
pub struct DebugGpuBuffers {
    pub in_bytes: DebugBuffer,

    pub f_ping: DebugBuffer,
    pub block_summaries: DebugBuffer,
    pub block_ping: DebugBuffer,
    pub block_pong: DebugBuffer,
    pub block_prefix: DebugBuffer,
    pub f_final: DebugBuffer,

    pub end_flags: DebugBuffer,
    pub tok_types: DebugBuffer,
    pub filtered_flags: DebugBuffer,
    pub end_excl_by_i: DebugBuffer,
    pub s_all_seed: DebugBuffer,
    pub s_keep_seed: DebugBuffer,

    pub s_all_final: DebugBuffer,
    pub s_keep_final: DebugBuffer,

    pub end_positions_all: DebugBuffer,
    pub token_count_all: DebugBuffer,
    pub end_positions: DebugBuffer,
    pub types_compact: DebugBuffer,
    pub all_index_compact: DebugBuffer,
    pub token_count: DebugBuffer,
    pub tokens_out: DebugBuffer,
}

#[derive(Default)]
pub struct DebugOutput {
    pub gpu: DebugGpuBuffers,
}

impl DebugOutput {
    pub fn map_all_blocking(&mut self, device: &wgpu::Device) {
        fn map(buf: &mut DebugBuffer, device: &wgpu::Device) {
            if let Some(b) = buf.buffer.as_ref() {
                b.slice(..).map_async(wgpu::MapMode::Read, |_| {});
            }
            let _ = device.poll(wgpu::PollType::Wait);
        }
        let g = &mut self.gpu;
        map(&mut g.in_bytes, device);

        map(&mut g.f_ping, device);
        map(&mut g.block_summaries, device);
        map(&mut g.block_ping, device);
        map(&mut g.block_pong, device);
        map(&mut g.block_prefix, device);
        map(&mut g.f_final, device);

        map(&mut g.end_flags, device);
        map(&mut g.tok_types, device);
        map(&mut g.filtered_flags, device);
        map(&mut g.end_excl_by_i, device);
        map(&mut g.s_all_seed, device);
        map(&mut g.s_keep_seed, device);

        map(&mut g.s_all_final, device);
        map(&mut g.s_keep_final, device);

        map(&mut g.end_positions_all, device);
        map(&mut g.token_count_all, device);
        map(&mut g.end_positions, device);
        map(&mut g.types_compact, device);
        map(&mut g.all_index_compact, device);
        map(&mut g.token_count, device);
        map(&mut g.tokens_out, device);
    }
}

fn make_staging(device: &wgpu::Device, label: &'static str, byte_len: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_len as u64,
        usage: BufferUsages::COPY_DST | BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}

/// Copy after a dispatch, using exact source sizes from LaniusBuffer.
pub fn record_after_pass(
    label: &str,
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    bufs: &GpuBuffers,
    dbg: &mut DebugOutput,
) {
    let g = &mut dbg.gpu;

    match label {
        "map" => {
            let b0 = make_staging(device, "dbg.in_bytes", bufs.in_bytes.byte_size);
            encoder.copy_buffer_to_buffer(
                &bufs.in_bytes,
                0,
                &b0,
                0,
                bufs.in_bytes.byte_size as u64,
            );
            g.in_bytes = DebugBuffer {
                label: "in_bytes",
                buffer: Some(b0),
                byte_len: bufs.in_bytes.byte_size,
            };

            let b1 = make_staging(device, "dbg.f_ping", bufs.f_ping.byte_size);
            encoder.copy_buffer_to_buffer(&bufs.f_ping, 0, &b1, 0, bufs.f_ping.byte_size as u64);
            g.f_ping = DebugBuffer {
                label: "f_ping",
                buffer: Some(b1),
                byte_len: bufs.f_ping.byte_size,
            };
        }

        "block_scan" => {
            let size = bufs.block_summaries.byte_size;
            let b = make_staging(device, "dbg.block_summaries", size);
            encoder.copy_buffer_to_buffer(&bufs.block_summaries, 0, &b, 0, size as u64);
            g.block_summaries = DebugBuffer {
                label: "block_summaries",
                buffer: Some(b),
                byte_len: size,
            };
        }

        "scan_blocks" => {
            for (src, dst_label, slot) in [
                (&bufs.block_ping, "dbg.block_ping", &mut g.block_ping),
                (&bufs.block_pong, "dbg.block_pong", &mut g.block_pong),
            ] {
                let b = make_staging(device, dst_label, src.byte_size);
                encoder.copy_buffer_to_buffer(src, 0, &b, 0, src.byte_size as u64);
                *slot = DebugBuffer {
                    label: if dst_label.ends_with("ping") {
                        "block_ping"
                    } else {
                        "block_pong"
                    },
                    buffer: Some(b),
                    byte_len: src.byte_size,
                };
            }
        }

        "blocks_prefix" => {
            let size = bufs.block_prefix.byte_size;
            let b = make_staging(device, "dbg.block_prefix", size);
            encoder.copy_buffer_to_buffer(&bufs.block_prefix, 0, &b, 0, size as u64);
            g.block_prefix = DebugBuffer {
                label: "block_prefix",
                buffer: Some(b),
                byte_len: size,
            };
        }

        "fixup" => {
            let size = bufs.f_final.byte_size;
            let b = make_staging(device, "dbg.f_final", size);
            encoder.copy_buffer_to_buffer(&bufs.f_final, 0, &b, 0, size as u64);
            g.f_final = DebugBuffer {
                label: "f_final",
                buffer: Some(b),
                byte_len: size,
            };
        }

        "finalize" => {
            for (src, dst, lab) in [
                (&bufs.end_flags, "dbg.end_flags", "end_flags"),
                (&bufs.tok_types, "dbg.tok_types", "tok_types"),
                (&bufs.filtered_flags, "dbg.filtered_flags", "filtered_flags"),
                (&bufs.end_excl_by_i, "dbg.end_excl_by_i", "end_excl_by_i"),
                (&bufs.s_all_seed, "dbg.s_all_seed", "s_all_seed"),
                (&bufs.s_keep_seed, "dbg.s_keep_seed", "s_keep_seed"),
            ] {
                let b = make_staging(device, dst, src.byte_size);
                encoder.copy_buffer_to_buffer(src, 0, &b, 0, src.byte_size as u64);
                let db = DebugBuffer {
                    label: lab,
                    buffer: Some(b),
                    byte_len: src.byte_size,
                };
                match lab {
                    "end_flags" => g.end_flags = db,
                    "tok_types" => g.tok_types = db,
                    "filtered_flags" => g.filtered_flags = db,
                    "end_excl_by_i" => g.end_excl_by_i = db,
                    "s_all_seed" => g.s_all_seed = db,
                    "s_keep_seed" => g.s_keep_seed = db,
                    _ => {}
                }
            }
        }

        "scan_sum[ALL]" => {
            let size = bufs.s_all_final.byte_size;
            let b = make_staging(device, "dbg.s_all_final", size);
            encoder.copy_buffer_to_buffer(&bufs.s_all_final, 0, &b, 0, size as u64);
            g.s_all_final = DebugBuffer {
                label: "s_all_final",
                buffer: Some(b),
                byte_len: size,
            };
        }

        "scan_sum[KEPT]" => {
            let size = bufs.s_keep_final.byte_size;
            let b = make_staging(device, "dbg.s_keep_final", size);
            encoder.copy_buffer_to_buffer(&bufs.s_keep_final, 0, &b, 0, size as u64);
            g.s_keep_final = DebugBuffer {
                label: "s_keep_final",
                buffer: Some(b),
                byte_len: size,
            };
        }

        "scatter[ALL]" => {
            for (src, dst, slot) in [
                (
                    &bufs.end_positions_all,
                    "dbg.end_positions_all",
                    &mut g.end_positions_all,
                ),
                (
                    &bufs.token_count_all,
                    "dbg.token_count_all",
                    &mut g.token_count_all,
                ),
            ] {
                let b = make_staging(device, dst, src.byte_size);
                encoder.copy_buffer_to_buffer(src, 0, &b, 0, src.byte_size as u64);
                *slot = DebugBuffer {
                    label: if dst.ends_with("positions_all") {
                        "end_positions_all"
                    } else {
                        "token_count_all"
                    },
                    buffer: Some(b),
                    byte_len: src.byte_size,
                };
            }
        }

        "scatter[KEPT]" => {
            for (src, dst, lab) in [
                (&bufs.end_positions, "dbg.end_positions", "end_positions"),
                (&bufs.types_compact, "dbg.types_compact", "types_compact"),
                (
                    &bufs.all_index_compact,
                    "dbg.all_index_compact",
                    "all_index_compact",
                ),
            ] {
                let b = make_staging(device, dst, src.byte_size);
                encoder.copy_buffer_to_buffer(src, 0, &b, 0, src.byte_size as u64);
                let db = DebugBuffer {
                    label: lab,
                    buffer: Some(b),
                    byte_len: src.byte_size,
                };
                match lab {
                    "end_positions" => g.end_positions = db,
                    "types_compact" => g.types_compact = db,
                    "all_index_compact" => g.all_index_compact = db,
                    _ => {}
                }
            }
            let b_tc = make_staging(device, "dbg.token_count", bufs.token_count.byte_size);
            encoder.copy_buffer_to_buffer(
                &bufs.token_count,
                0,
                &b_tc,
                0,
                bufs.token_count.byte_size as u64,
            );
            g.token_count = DebugBuffer {
                label: "token_count",
                buffer: Some(b_tc),
                byte_len: bufs.token_count.byte_size,
            };
        }

        "build_tokens" => {
            let size = bufs.tokens_out.byte_size;
            let b = make_staging(device, "dbg.tokens_out", size);
            encoder.copy_buffer_to_buffer(&bufs.tokens_out, 0, &b, 0, size as u64);
            g.tokens_out = DebugBuffer {
                label: "tokens_out",
                buffer: Some(b),
                byte_len: size,
            };
        }

        _ => {}
    }
}
