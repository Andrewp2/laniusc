use anyhow::{Result, anyhow};

pub fn read_u32_words<const N: usize>(bytes: &[u8], context: &str) -> Result<[u32; N]> {
    let expected = N * 4;
    if bytes.len() < expected {
        return Err(anyhow!(
            "{context} readback was truncated: expected at least {expected} bytes, got {}",
            bytes.len()
        ));
    }

    let mut out = [0u32; N];
    for (i, word) in out.iter_mut().enumerate() {
        let start = i * 4;
        *word = u32::from_le_bytes(bytes[start..start + 4].try_into()?);
    }
    Ok(out)
}

pub fn read_i32_words<const N: usize>(bytes: &[u8], context: &str) -> Result<[i32; N]> {
    let expected = N * 4;
    if bytes.len() < expected {
        return Err(anyhow!(
            "{context} readback was truncated: expected at least {expected} bytes, got {}",
            bytes.len()
        ));
    }

    let mut out = [0i32; N];
    for (i, word) in out.iter_mut().enumerate() {
        let start = i * 4;
        *word = i32::from_le_bytes(bytes[start..start + 4].try_into()?);
    }
    Ok(out)
}
