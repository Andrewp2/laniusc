use anyhow::{Result, anyhow};
use log::warn;

use super::GpuLexer;
use crate::lexer::{buffers, buffers::GpuBuffers};

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
            .map_err(|_| anyhow!("source file {file_i} is too large for GPU lexing"))?;
        starts.push(total_len);
        lens.push(len);
        bytes.extend_from_slice(source_bytes);
        total_len = total_len
            .checked_add(len)
            .ok_or_else(|| anyhow!("source pack byte length exceeds GPU lexer capacity"))?;
    }

    Ok((bytes, SourceFileMetadata { starts, lens }))
}

impl GpuLexer {
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

        let recreate = |cap_n: u32| -> buffers::GpuBuffers {
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
            )
        };

        if guard.is_none() {
            *guard = Some(recreate(aligned_len.max(1)));
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

            let needs_resize = desired_cap != cap_bytes || nb_dfa != cap_nb_dfa || n > cap_n;
            if needs_resize {
                let mut new_bufs = recreate(desired_cap);
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
        let (input_bytes, source_files) = build_source_pack(sources)?;
        let n = u32::try_from(input_bytes.len())
            .map_err(|_| anyhow!("source pack byte length exceeds GPU lexer capacity"))?;
        let aligned_len = align_to_word(n);
        let source_file_capacity = source_files.capacity();

        let mut guard = self
            .buffers
            .lock()
            .expect("GpuLexer.buffers mutex poisoned");

        let recreate = |cap_n: u32, cap_files: u32| -> buffers::GpuBuffers {
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
            )
        };

        if guard.is_none() {
            *guard = Some(recreate(aligned_len.max(1), source_file_capacity));
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

            let needs_resize = desired_cap != cap_bytes
                || nb_dfa != cap_nb_dfa
                || n > cap_n
                || source_file_capacity != cap_files;
            if needs_resize {
                let mut new_bufs = recreate(desired_cap, source_file_capacity.max(1));
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
