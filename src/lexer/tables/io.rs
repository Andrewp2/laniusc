// src/lexer/tables/io.rs
use std::{
    io::{BufWriter, Write},
    time::Instant,
};

use serde::{Deserialize, Serialize};
use serde_with::serde_as;

use super::{Tables, tokens::INVALID_TOKEN};

// -------------------- JSON (de)serialization --------------------

#[serde_as]
#[derive(Serialize, Deserialize)]
struct TablesDisk {
    #[serde_as(as = "[_; 256]")]
    char_to_func: [u32; 256],
    merge: Vec<u32>,
    token_of: Vec<u32>,
    emit_on_start: Vec<u32>,
    m: u32,
    identity: u32,
}
impl From<&Tables> for TablesDisk {
    fn from(t: &Tables) -> Self {
        Self {
            char_to_func: t.char_to_func,
            merge: t.merge.clone(),
            token_of: t.token_of.clone(),
            emit_on_start: t.emit_on_start.clone(),
            m: t.m,
            identity: t.identity,
        }
    }
}
impl TablesDisk {
    fn into_tables(self) -> Tables {
        Tables {
            char_to_func: self.char_to_func,
            merge: self.merge,
            token_of: self.token_of,
            emit_on_start: self.emit_on_start,
            m: self.m,
            identity: self.identity,
        }
    }
}

pub fn save_tables_json(path: &std::path::Path, t: &Tables) -> std::io::Result<()> {
    // Stream to disk to avoid giant intermediate strings.
    let f = std::fs::File::create(path)?;
    let mut w = BufWriter::new(f);
    serde_json::to_writer(&mut w, &TablesDisk::from(t))?;
    w.flush()
}

pub fn load_tables_json_bytes(data: &[u8]) -> Result<Tables, String> {
    serde_json::from_slice::<TablesDisk>(data)
        .map(|d| d.into_tables())
        .map_err(|e| format!("Failed to parse tables JSON: {e}"))
}

// -------------------- Compact binary (u16 packing) --------------------

const BIN_MAGIC: &[u8; 8] = b"LXTBLE01";
const INVALID_TOKEN_U16: u16 = 0xFFFF;

pub fn save_tables_bin(path: &std::path::Path, t: &Tables) -> std::io::Result<()> {
    let instant = Instant::now();
    if t.m > u16::MAX as u32 {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            format!("m={} exceeds u16::MAX; cannot pack to u16", t.m),
        ));
    }

    // Pre-size file to reduce fragmentation and speed up contiguous writes.
    let f = std::fs::File::create(path)?;

    // Compute total size:
    // header (8 + 4 + 4) + char_to_func (256*2) + merge (m*m*2) + token_of (m*2) + emit bits ((m+7)/8)
    let m = t.m as usize;
    let header = 8 + 4 + 4;
    let size_char_to_func = 256 * 2;
    let size_merge = m
        .checked_mul(m)
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "m*m overflow"))?
        * 2;
    let size_token_of = m * 2;
    let size_emit = (m + 7) / 8;
    let total_len = header + size_char_to_func + size_merge + size_token_of + size_emit;

    // Pre-allocate (best effort).
    let _ = f.set_len(total_len as u64);

    let mut w = BufWriter::new(f);

    // Header
    w.write_all(BIN_MAGIC)?;
    w.write_all(&(t.m as u32).to_le_bytes())?;
    w.write_all(&(t.identity as u32).to_le_bytes())?;

    // char_to_func: 256 x u16 (chunk is tiny)
    {
        let mut buf = [0u8; 256 * 2];
        for (i, &id) in t.char_to_func.iter().enumerate() {
            let v = u16::try_from(id).map_err(|_| {
                std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    "char_to_func id > u16::MAX",
                )
            })?;
            let p = i * 2;
            buf[p..p + 2].copy_from_slice(&v.to_le_bytes());
        }
        w.write_all(&buf)?;
    }

    // merge: m*m x u16 — stream in reasonably large chunks to reduce syscalls
    const CHUNK: usize = 1 << 20; // entries per chunk (tune if needed)
    {
        let mut bytes = vec![0u8; CHUNK * 2];
        for chunk in t.merge.chunks(CHUNK) {
            // resize buffer if final chunk is smaller
            if chunk.len() * 2 != bytes.len() {
                bytes.resize(chunk.len() * 2, 0);
            }
            for (i, &id) in chunk.iter().enumerate() {
                let v = u16::try_from(id).map_err(|_| {
                    std::io::Error::new(std::io::ErrorKind::InvalidData, "merge id > u16::MAX")
                })?;
                let p = i * 2;
                bytes[p..p + 2].copy_from_slice(&v.to_le_bytes());
            }
            w.write_all(&bytes)?;
        }
    }

    // token_of: m x u16
    {
        let mut bytes = vec![0u8; m * 2];
        for (i, &tk) in t.token_of.iter().enumerate() {
            let v = if tk == INVALID_TOKEN {
                INVALID_TOKEN_U16
            } else {
                u16::try_from(tk).map_err(|_| {
                    std::io::Error::new(std::io::ErrorKind::InvalidData, "token_of > u16::MAX")
                })?
            };
            let p = i * 2;
            bytes[p..p + 2].copy_from_slice(&v.to_le_bytes());
        }
        w.write_all(&bytes)?;
    }

    // emit_on_start: m bits packed into bytes
    {
        let mut bits = vec![0u8; (m + 7) / 8];
        for (i, &b) in t.emit_on_start.iter().enumerate() {
            if b != 0 {
                bits[i / 8] |= 1 << (i % 8);
            }
        }
        w.write_all(&bits)?;
    }

    let flush = w.flush();
    println!(
        "Saved tables to {} in {} ms",
        path.display(),
        instant.elapsed().as_millis()
    );
    flush
}

pub fn load_tables_bin_bytes(mut data: &[u8]) -> Result<Tables, String> {
    // Header
    if data.len() < 8 + 4 + 4 {
        return Err("bin too short".into());
    }
    let mut magic = [0u8; 8];
    magic.copy_from_slice(&data[..8]);
    if &magic != BIN_MAGIC {
        return Err("bad magic in tables .bin".into());
    }
    data = &data[8..];

    let read_u32 = |buf: &mut &[u8]| -> Result<u32, String> {
        if buf.len() < 4 {
            return Err("truncated u32".into());
        }
        let mut le = [0u8; 4];
        le.copy_from_slice(&buf[..4]);
        *buf = &buf[4..];
        Ok(u32::from_le_bytes(le))
    };
    let read_u16 = |buf: &mut &[u8]| -> Result<u16, String> {
        if buf.len() < 2 {
            return Err("truncated u16".into());
        }
        let mut le = [0u8; 2];
        le.copy_from_slice(&buf[..2]);
        *buf = &buf[2..];
        Ok(u16::from_le_bytes(le))
    };

    let m = read_u32(&mut data)? as usize;
    let identity = read_u32(&mut data)?;

    // char_to_func
    let mut char_to_func = [0u32; 256];
    for i in 0..256 {
        char_to_func[i] = read_u16(&mut data)? as u32;
    }

    // merge m*m
    let mm = m.checked_mul(m).ok_or("m*m overflow")?;
    let mut merge = Vec::with_capacity(mm);
    for _ in 0..mm {
        merge.push(read_u16(&mut data)? as u32);
    }

    // token_of m
    let mut token_of = Vec::with_capacity(m);
    for _ in 0..m {
        let v = read_u16(&mut data)?;
        token_of.push(if v == INVALID_TOKEN_U16 {
            INVALID_TOKEN
        } else {
            v as u32
        });
    }

    // emit_on_start m bits
    let bytes = (m + 7) / 8;
    if data.len() < bytes {
        return Err("truncated emit_on_start bits".into());
    }
    let (bit_slice, _rest) = data.split_at(bytes);
    let mut emit_on_start = vec![0u32; m];
    for i in 0..m {
        let b = bit_slice[i / 8] >> (i % 8) & 1;
        emit_on_start[i] = b as u32;
    }

    Ok(Tables {
        char_to_func,
        merge,
        token_of,
        emit_on_start,
        m: m as u32,
        identity,
    })
}
