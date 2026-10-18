use anyhow::{Result, anyhow};
use log::warn;

use super::GpuLexer;
use crate::{
    gpu::buffers::grown_resident_capacity,
    lexer::{buffers, buffers::GpuBuffers},
};

const SOURCE_BYTE_CAPACITY_GRANULARITY: u32 = 4 * 1024;
const SOURCE_FILE_CAPACITY_GRANULARITY: u32 = 64;

fn capacity_bucket(value: u32, granularity: u32) -> u32 {
    value
        .max(1)
        .div_ceil(granularity)
        .saturating_mul(granularity)
}

/// Reports a lexer buffer replacement, which also replaces the identities the
/// resident type-check workspace is bound to.
fn trace_lexer_resize(old_bytes: u32, new_bytes: u32, old_files: u32, new_files: u32) {
    if crate::gpu::env::env_bool_truthy("LANIUS_TYPECHECK_RESIDENT_CACHE_TRACE", false)
        || crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false)
    {
        eprintln!(
            "[gpu_compile_host_timer] lexer.resident_cache: allocate=true bytes={old_bytes}->{new_bytes} files={old_files}->{new_files}"
        );
    }
}

#[derive(Debug, Clone)]
struct SourceFileMetadata {
    starts: Vec<u32>,
    lens: Vec<u32>,
}

impl SourceFileMetadata {
    fn count(&self) -> u32 {
        self.starts.len() as u32
    }

    fn capacity(&self) -> u32 {
        self.count().max(1)
    }
}

fn build_source_pack<S: AsRef<str>>(sources: &[S]) -> Result<(Vec<u8>, SourceFileMetadata)> {
    let file_count = u32::try_from(sources.len())
        .map_err(|_| anyhow!("source pack has too many source files"))?;
    let mut bytes = Vec::new();
    let mut starts = Vec::with_capacity(file_count as usize);
    let mut lens = Vec::with_capacity(file_count as usize);
    let mut total_len = 0u32;

    for (file_i, source) in sources.iter().enumerate() {
        let source_bytes = source.as_ref().as_bytes();
        let len = u32::try_from(source_bytes.len())
            .map_err(|_| anyhow!("source file {file_i} is too large to lex"))?;
        starts.push(total_len);
        lens.push(len);
        bytes.extend_from_slice(source_bytes);
        total_len = total_len
            .checked_add(len)
            .ok_or_else(|| anyhow!("source pack byte length exceeds lexer capacity"))?;
    }

    Ok((bytes, SourceFileMetadata { starts, lens }))
}

impl GpuLexer {
    /// Returns whether the resident source-pack allocation can accept the
    /// requested input without changing any buffer identity.
    pub(crate) fn current_resident_source_pack_capacity_covers(
        &self,
        source_bytes: u32,
        source_files: u32,
    ) -> bool {
        let guard = self
            .buffers
            .lock()
            .expect("GpuLexer.buffers mutex poisoned");
        guard.as_ref().is_some_and(|bufs| {
            source_bytes as usize <= bufs.in_bytes.byte_size
                && source_bytes as usize <= bufs.in_bytes.count
                && source_files as usize <= bufs.source_file_start.count
        })
    }

    fn source_pack_capacity_floor(&self) -> (u32, u32) {
        *self
            .source_pack_capacity_floor
            .lock()
            .expect("GpuLexer.source_pack_capacity_floor poisoned")
    }

    fn raise_source_pack_capacity_floor(&self, bytes: u32, files: u32) {
        let mut floor = self
            .source_pack_capacity_floor
            .lock()
            .expect("GpuLexer.source_pack_capacity_floor poisoned");
        *floor = (floor.0.max(bytes), floor.1.max(files));
    }

    /// Prepares resident buffers and metadata for one source string.
    pub(super) fn prepare_buffers_for_input<'a>(
        &'a self,
        input: &str,
        start_state: u32,
        skip_kinds: [u32; 4],
    ) -> Result<std::sync::MutexGuard<'a, Option<buffers::GpuBuffers>>> {
        let input_bytes = input.as_bytes();
        let n = input_bytes.len() as u32;
        let aligned_len = align_to_word(n);

        let mut guard = self
            .buffers
            .lock()
            .expect("GpuLexer.buffers mutex poisoned");

        let recreate = |cap_n: u32| -> Result<buffers::GpuBuffers> {
            GpuBuffers::new(
                &self.device,
                &self.queue,
                cap_n,
                1,
                start_state,
                &self.next_emit_words,
                &self.next_u8_packed,
                &self.token_map,
                skip_kinds,
                &self.passes,
            )
        };

        if guard.is_none() {
            *guard = Some(recreate(capacity_bucket(
                grown_resident_capacity(0, aligned_len),
                SOURCE_BYTE_CAPACITY_GRANULARITY,
            ))?);
        }

        {
            let bufs = guard
                .as_mut()
                .expect("GpuLexer buffers must exist after allocation");

            let nb_dfa = dfa_blocks(n);
            let nb_sum = sum_blocks(n);
            let desired_cap = aligned_len.max(n).max(1);
            let cap_n = bufs.in_bytes.count as u32;
            let cap_bytes = bufs.in_bytes.byte_size as u32;
            let cap_nb_dfa = (bufs.dfa_02_ping.count / crate::lexer::tables::dfa::N_STATES) as u32;

            let needs_resize = desired_cap > cap_bytes || nb_dfa > cap_nb_dfa || n > cap_n;
            if needs_resize {
                let new_bytes = capacity_bucket(
                    grown_resident_capacity(cap_bytes.max(cap_n), desired_cap),
                    SOURCE_BYTE_CAPACITY_GRANULARITY,
                );
                trace_lexer_resize(cap_bytes, new_bytes, 1, 1);
                let mut new_bufs = recreate(new_bytes)?;
                self.write_current_lex_inputs(
                    &mut new_bufs,
                    input_bytes,
                    n,
                    nb_dfa,
                    nb_sum,
                    start_state,
                    skip_kinds,
                );
                *bufs = new_bufs;
                self.clear_bind_group_cache("failed to clear lexer bind-group cache");
            } else {
                self.write_current_lex_inputs(
                    bufs,
                    input_bytes,
                    n,
                    nb_dfa,
                    nb_sum,
                    start_state,
                    skip_kinds,
                );
            }
        }

        Ok(guard)
    }

    /// Prepares resident buffers and source-file metadata for a source pack.
    pub(super) fn prepare_buffers_for_source_pack<'a, S: AsRef<str>>(
        &'a self,
        sources: &[S],
        start_state: u32,
        skip_kinds: [u32; 4],
    ) -> Result<std::sync::MutexGuard<'a, Option<buffers::GpuBuffers>>> {
        let _span = crate::gpu::trace::HostSpan::new("host.lexer", "lex.source-pack.prepare_buffers");
        let (input_bytes, source_files) = build_source_pack(sources)?;
        let n = u32::try_from(input_bytes.len())
            .map_err(|_| anyhow!("source pack byte length exceeds lexer capacity"))?;
        let aligned_len = align_to_word(n);
        let source_file_capacity = source_files.capacity();

        let mut guard = self
            .buffers
            .lock()
            .expect("GpuLexer.buffers mutex poisoned");

        let recreate = |cap_n: u32, cap_files: u32| -> Result<buffers::GpuBuffers> {
            GpuBuffers::new(
                &self.device,
                &self.queue,
                cap_n,
                cap_files,
                start_state,
                &self.next_emit_words,
                &self.next_u8_packed,
                &self.token_map,
                skip_kinds,
                &self.passes,
            )
        };

        if guard.is_none() {
            let (floor_bytes, floor_files) = self.source_pack_capacity_floor();
            let bytes = capacity_bucket(
                grown_resident_capacity(floor_bytes, aligned_len),
                SOURCE_BYTE_CAPACITY_GRANULARITY,
            );
            let files = capacity_bucket(
                source_file_capacity.max(floor_files),
                SOURCE_FILE_CAPACITY_GRANULARITY,
            );
            trace_lexer_resize(0, bytes, 0, files);
            *guard = Some(recreate(bytes, files)?);
            self.raise_source_pack_capacity_floor(bytes, files);
        }

        {
            let bufs = guard
                .as_mut()
                .expect("GpuLexer buffers must exist after allocation");

            let nb_dfa = dfa_blocks(n);
            let nb_sum = sum_blocks(n);
            let desired_cap = aligned_len.max(n).max(1);
            let cap_n = bufs.in_bytes.count as u32;
            let cap_bytes = bufs.in_bytes.byte_size as u32;
            let cap_files = bufs.source_file_start.count as u32;
            let cap_nb_dfa = (bufs.dfa_02_ping.count / crate::lexer::tables::dfa::N_STATES) as u32;

            let needs_resize = desired_cap > cap_bytes
                || nb_dfa > cap_nb_dfa
                || n > cap_n
                || source_file_capacity > cap_files;
            if needs_resize {
                // Grow every dimension and never shrink one: a pack with more
                // files but fewer bytes keeps the byte capacity. Each
                // replacement gives the buffers new identities, which rebuilds
                // the resident type-check workspace bound to them.
                let new_bytes = capacity_bucket(
                    grown_resident_capacity(cap_bytes.max(cap_n), desired_cap),
                    SOURCE_BYTE_CAPACITY_GRANULARITY,
                );
                let new_files = capacity_bucket(
                    source_file_capacity.max(cap_files),
                    SOURCE_FILE_CAPACITY_GRANULARITY,
                );
                trace_lexer_resize(cap_bytes, new_bytes, cap_files, new_files);
                let mut new_bufs = recreate(new_bytes, new_files)?;
                self.raise_source_pack_capacity_floor(new_bytes, new_files);
                self.write_source_pack_lex_inputs(
                    &mut new_bufs,
                    &input_bytes,
                    &source_files,
                    n,
                    nb_dfa,
                    nb_sum,
                    start_state,
                    skip_kinds,
                );
                *bufs = new_bufs;
                self.clear_bind_group_cache("failed to clear lexer bind-group cache");
            } else {
                self.write_source_pack_lex_inputs(
                    bufs,
                    &input_bytes,
                    &source_files,
                    n,
                    nb_dfa,
                    nb_sum,
                    start_state,
                    skip_kinds,
                );
            }
        }

        Ok(guard)
    }

    fn write_current_lex_inputs(
        &self,
        bufs: &mut buffers::GpuBuffers,
        input_bytes: &[u8],
        n: u32,
        nb_dfa: u32,
        nb_sum: u32,
        start_state: u32,
        skip_kinds: [u32; 4],
    ) {
        self.write_input_bytes(bufs, input_bytes, n);
        self.write_lex_params(bufs, n, start_state, skip_kinds);
        self.write_current_source_file_metadata(bufs, n);
        set_runtime_sizes(bufs, n, nb_dfa, nb_sum);
    }

    #[allow(clippy::too_many_arguments)]
    fn write_source_pack_lex_inputs(
        &self,
        bufs: &mut buffers::GpuBuffers,
        input_bytes: &[u8],
        source_files: &SourceFileMetadata,
        n: u32,
        nb_dfa: u32,
        nb_sum: u32,
        start_state: u32,
        skip_kinds: [u32; 4],
    ) {
        self.write_input_bytes(bufs, input_bytes, n);
        self.write_lex_params(bufs, n, start_state, skip_kinds);
        self.write_source_pack_metadata(bufs, source_files);
        set_runtime_sizes(bufs, n, nb_dfa, nb_sum);
    }

    fn write_input_bytes(&self, bufs: &buffers::GpuBuffers, input_bytes: &[u8], n: u32) {
        if n == 0 {
            return;
        }

        let aligned_len = align_to_word(n) as usize;
        if aligned_len == input_bytes.len() {
            self.queue.write_buffer(&bufs.in_bytes, 0, input_bytes);
        } else {
            let mut tmp = Vec::with_capacity(aligned_len);
            tmp.extend_from_slice(input_bytes);
            tmp.resize(aligned_len, 0u8);
            self.queue.write_buffer(&bufs.in_bytes, 0, &tmp);
        }
    }

    fn write_lex_params(
        &self,
        bufs: &buffers::GpuBuffers,
        n: u32,
        start_state: u32,
        skip_kinds: [u32; 4],
    ) {
        let params = crate::lexer::types::LexParams {
            n,
            m: self.token_map.len() as u32,
            start_state,
            skip0: skip_kinds[0],
            skip1: skip_kinds[1],
            skip2: skip_kinds[2],
            skip3: skip_kinds[3],
        };
        let mut uniform = encase::UniformBuffer::new(Vec::<u8>::new());
        uniform.write(&params).expect("failed to encode LexParams");
        self.queue.write_buffer(&bufs.params, 0, uniform.as_ref());
        self.queue
            .write_buffer(&bufs.token_count, 0, &0u32.to_le_bytes());
        self.queue
            .write_buffer(&bufs.parser_feature_flags, 0, &0u32.to_le_bytes());
    }

    /// Writes single-file source metadata into resident buffers.
    pub(super) fn write_current_source_file_metadata(&self, bufs: &buffers::GpuBuffers, n: u32) {
        self.queue
            .write_buffer(&bufs.source_file_count, 0, &1u32.to_le_bytes());
        self.queue
            .write_buffer(&bufs.source_file_start, 0, &0u32.to_le_bytes());
        self.queue
            .write_buffer(&bufs.source_file_len, 0, &n.to_le_bytes());
    }

    fn write_source_pack_metadata(
        &self,
        bufs: &buffers::GpuBuffers,
        source_files: &SourceFileMetadata,
    ) {
        self.queue.write_buffer(
            &bufs.source_file_count,
            0,
            &source_files.count().to_le_bytes(),
        );
        self.write_u32_slice(&bufs.source_file_start, &source_files.starts);
        self.write_u32_slice(&bufs.source_file_len, &source_files.lens);
    }

    fn write_u32_slice(&self, buffer: &wgpu::Buffer, values: &[u32]) {
        if values.is_empty() {
            return;
        }
        let mut bytes = Vec::with_capacity(values.len() * 4);
        for value in values {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
        self.queue.write_buffer(buffer, 0, &bytes);
    }

    fn clear_bind_group_cache(&self, message: &str) {
        if let Ok(mut cache) = self.bg_cache.lock() {
            cache.clear();
        } else {
            warn!("{message} (poisoned mutex)");
        }
    }
}

fn align_to_word(n: u32) -> u32 {
    ((n as usize + 3) / 4 * 4) as u32
}

fn dfa_blocks(n: u32) -> u32 {
    n.div_ceil(256)
}

fn sum_blocks(n: u32) -> u32 {
    n.div_ceil(256)
}

fn set_runtime_sizes(bufs: &mut buffers::GpuBuffers, n: u32, nb_dfa: u32, nb_sum: u32) {
    bufs.n = n;
    bufs.nb_dfa = nb_dfa;
    bufs.nb_sum = nb_sum;
}

#[cfg(test)]
mod tests {
    use super::{
        SOURCE_BYTE_CAPACITY_GRANULARITY,
        SOURCE_FILE_CAPACITY_GRANULARITY,
        capacity_bucket,
        grown_resident_capacity,
    };

    #[test]
    fn source_capacity_buckets_cover_ordinary_edits() {
        assert_eq!(capacity_bucket(1, SOURCE_BYTE_CAPACITY_GRANULARITY), 4096);
        assert_eq!(
            capacity_bucket(4096, SOURCE_BYTE_CAPACITY_GRANULARITY),
            4096
        );
        assert_eq!(
            capacity_bucket(4097, SOURCE_BYTE_CAPACITY_GRANULARITY),
            8192
        );
        assert_eq!(capacity_bucket(1, SOURCE_FILE_CAPACITY_GRANULARITY), 64);
        assert_eq!(capacity_bucket(65, SOURCE_FILE_CAPACITY_GRANULARITY), 128);
    }

    #[test]
    fn source_capacity_headroom_covers_a_slightly_larger_next_pack() {
        // Two units of one stdlib build: the second is 4000 bytes larger and
        // crossed the exact bucket, which replaced every workspace bound to
        // the lexer buffers.
        let exact = capacity_bucket(1_400_000, SOURCE_BYTE_CAPACITY_GRANULARITY);
        assert!(exact < 1_404_000);
        let grown = capacity_bucket(
            grown_resident_capacity(0, 1_400_000),
            SOURCE_BYTE_CAPACITY_GRANULARITY,
        );
        assert!(grown >= 1_404_000);
        assert_eq!(grown_resident_capacity(grown, 1_404_000), grown);
    }
}
