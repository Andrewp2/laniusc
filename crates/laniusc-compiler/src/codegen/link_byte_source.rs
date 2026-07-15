use std::{
    io::{Read, Seek, SeekFrom},
    path::PathBuf,
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct GpuLinkFileSegment {
    path: PathBuf,
    file_offset: u64,
    byte_len: usize,
}

#[cfg_attr(not(test), allow(dead_code))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum GpuLinkByteSource {
    Resident {
        label: &'static str,
        bytes: Vec<u8>,
    },
    FileSegments {
        label: &'static str,
        segments: Vec<GpuLinkFileSegment>,
        byte_len: usize,
    },
}

impl GpuLinkByteSource {
    #[cfg_attr(not(test), allow(dead_code))]
    pub(crate) fn resident(label: &'static str, bytes: Vec<u8>) -> Self {
        Self::Resident { label, bytes }
    }

    pub(crate) fn file_segments(label: &'static str) -> Self {
        Self::FileSegments {
            label,
            segments: Vec::new(),
            byte_len: 0,
        }
    }

    pub(crate) fn len(&self) -> usize {
        match self {
            Self::Resident { bytes, .. } => bytes.len(),
            Self::FileSegments { byte_len, .. } => *byte_len,
        }
    }

    #[cfg_attr(not(test), allow(dead_code))]
    pub(crate) fn extend_resident(&mut self, new_bytes: &[u8]) {
        match self {
            Self::Resident { bytes, .. } => bytes.extend_from_slice(new_bytes),
            Self::FileSegments { label, .. } => {
                unreachable!("cannot append resident bytes to file-backed {label}")
            }
        }
    }

    pub(crate) fn push_file_segment(
        &mut self,
        path: PathBuf,
        range: std::ops::Range<u64>,
    ) -> Result<(), String> {
        let segment_len = usize::try_from(range.end.saturating_sub(range.start))
            .map_err(|_| "link file segment length exceeds usize".to_string())?;
        match self {
            Self::FileSegments {
                label,
                segments,
                byte_len,
            } => {
                *byte_len = byte_len
                    .checked_add(segment_len)
                    .ok_or_else(|| format!("{label} file-backed length overflows"))?;
                segments.push(GpuLinkFileSegment {
                    path,
                    file_offset: range.start,
                    byte_len: segment_len,
                });
                Ok(())
            }
            Self::Resident { label, .. } => {
                Err(format!("cannot append a file segment to resident {label}"))
            }
        }
    }

    pub(crate) fn read_range(&self, range: std::ops::Range<usize>) -> Result<Vec<u8>, String> {
        match self {
            Self::Resident { label, bytes } => {
                bytes.get(range.clone()).map(<[u8]>::to_vec).ok_or_else(|| {
                    format!(
                        "{label} range {}..{} exceeds source length {}",
                        range.start,
                        range.end,
                        bytes.len()
                    )
                })
            }
            Self::FileSegments {
                label,
                segments,
                byte_len,
            } => {
                if range.start > range.end || range.end > *byte_len {
                    return Err(format!(
                        "{label} range {}..{} exceeds file-backed source length {}",
                        range.start, range.end, byte_len
                    ));
                }
                let mut output = vec![0u8; range.len()];
                let mut logical_start = 0usize;
                for segment in segments {
                    let logical_end = logical_start
                        .checked_add(segment.byte_len)
                        .ok_or_else(|| format!("{label} segment position overflows"))?;
                    let overlap_start = range.start.max(logical_start);
                    let overlap_end = range.end.min(logical_end);
                    if overlap_start < overlap_end {
                        let within_segment = overlap_start - logical_start;
                        let output_start = overlap_start - range.start;
                        let copy_len = overlap_end - overlap_start;
                        let mut file = std::fs::File::open(&segment.path).map_err(|err| {
                            format!("open {label} {}: {err}", segment.path.display())
                        })?;
                        file.seek(SeekFrom::Start(segment.file_offset + within_segment as u64))
                            .map_err(|err| {
                                format!("seek {label} {}: {err}", segment.path.display())
                            })?;
                        file.read_exact(&mut output[output_start..output_start + copy_len])
                            .map_err(|err| {
                                format!("read {label} {}: {err}", segment.path.display())
                            })?;
                    }
                    logical_start = logical_end;
                    if logical_start >= range.end {
                        break;
                    }
                }
                Ok(output)
            }
        }
    }
}
