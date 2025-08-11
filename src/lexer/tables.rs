// src/lexer/tables.rs
use hashbrown::HashMap;
use serde::{Deserialize, Serialize};
use serde_with::serde_as;

/// Token kinds for the MVP grammar.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum TokenKind {
    Ident = 1,
    Int = 2,
    White = 3, // you can choose to filter later
    LParen = 4,
    RParen = 5,
    Plus = 6,
    Star = 7,
    Assign = 8,
    Slash = 9,         // when not starting comments
    LineComment = 10,  // //... (does not include the trailing '\n')
    BlockComment = 11, // /*...*/ (includes */)
}

// make this public so GPU side can use it
pub const INVALID_TOKEN: u32 = u32::MAX;

/// DFA states (small hand-built DFA).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum S {
    Start,
    Ident,
    Int,
    White,

    MaybeSlash,  // accepting: SLASH; but on '/' or '*' we continue into comments (no emit)
    LineComment, // continues until '\n' then emits
    BlockComment, // inside /* ... */
    BlockStar,   // saw '*' inside a block comment, may end if next is '/'
    BlockDone,   // accepting: BlockComment (emits on next char)

    AfterLParen, // accepting single-char tokens
    AfterRParen,
    AfterPlus,
    AfterStar,
    AfterAssign,

    Reject, // sink
}

impl S {
    fn idx(self) -> usize {
        self as usize
    }
}

const ALL_STATES: &[S] = &[
    S::Start,
    S::Ident,
    S::Int,
    S::White,
    S::MaybeSlash,
    S::LineComment,
    S::BlockComment,
    S::BlockStar,
    S::BlockDone,
    S::AfterLParen,
    S::AfterRParen,
    S::AfterPlus,
    S::AfterStar,
    S::AfterAssign,
    S::Reject,
];

const START: S = S::Start;
const REJECT: S = S::Reject;

/// Token mapping for accepting states (None => non-accepting).
fn token_of_state(s: S) -> Option<TokenKind> {
    use S::*;
    match s {
        Ident => Some(TokenKind::Ident),
        Int => Some(TokenKind::Int),
        White => Some(TokenKind::White),
        MaybeSlash => Some(TokenKind::Slash),
        BlockDone => Some(TokenKind::BlockComment),
        AfterLParen => Some(TokenKind::LParen),
        AfterRParen => Some(TokenKind::RParen),
        AfterPlus => Some(TokenKind::Plus),
        AfterStar => Some(TokenKind::Star),
        AfterAssign => Some(TokenKind::Assign),
        LineComment => Some(TokenKind::LineComment), // emits when we leave it via '\n'
        _ => None,
    }
}

fn is_alpha(b: u8) -> bool {
    matches!(b, b'a'..=b'z' | b'A'..=b'Z' | b'_')
}
fn is_digit(b: u8) -> bool {
    b.is_ascii_digit()
}
fn is_alnum(b: u8) -> bool {
    is_alpha(b) || is_digit(b)
}
fn is_white(b: u8) -> bool {
    matches!(b, b' ' | b'\t' | b'\r' | b'\n')
}

/// A transition with an 'emit' flag (meaning: the edge emits a token when taken).
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct Next {
    pub state: u16,
    pub emit: bool,
}

/// The fully materialized streaming DFA.
pub struct StreamingDfa {
    pub next: [[Next; 256]; 16], // [state][byte] -> (next, emit)
    pub token_map: [u32; 16],    // token kind per state (or INVALID_TOKEN)
    pub start: u16,
    pub reject: u16,
}

impl StreamingDfa {
    fn new() -> Self {
        // Base (non-streaming) edges default to reject, emit=false.
        let mut next = [[Next {
            state: S::Reject.idx() as u16,
            emit: false,
        }; 256]; 16];

        // Helper functions (no borrowing-through-closures issues)
        fn set(next: &mut [[Next; 256]; 16], from: S, bytes: &[u8], to: S) {
            for &b in bytes {
                next[from.idx()][b as usize] = Next {
                    state: to.idx() as u16,
                    emit: false,
                };
            }
        }
        fn set_range(next: &mut [[Next; 256]; 16], from: S, lo: u8, hi: u8, to: S) {
            for b in lo..=hi {
                next[from.idx()][b as usize] = Next {
                    state: to.idx() as u16,
                    emit: false,
                };
            }
        }
        fn set_all_except(next: &mut [[Next; 256]; 16], from: S, except: &[u8], to: S) {
            let mut skip = [false; 256];
            for &e in except {
                skip[e as usize] = true;
            }
            for b in 0u16..=255 {
                if !skip[b as usize] {
                    next[from.idx()][b as usize] = Next {
                        state: to.idx() as u16,
                        emit: false,
                    };
                }
            }
        }

        // ---------- Start state ----------
        for b in 0u8..=255 {
            let to = if is_alpha(b) {
                S::Ident
            } else if is_digit(b) {
                S::Int
            } else if is_white(b) {
                S::White
            } else {
                match b {
                    b'(' => S::AfterLParen,
                    b')' => S::AfterRParen,
                    b'+' => S::AfterPlus,
                    b'*' => S::AfterStar,
                    b'=' => S::AfterAssign,
                    b'/' => S::MaybeSlash, // may become comment or bare slash
                    _ => S::Reject,
                }
            };
            next[S::Start.idx()][b as usize] = Next {
                state: to.idx() as u16,
                emit: false,
            };
        }

        // ---------- Ident ----------
        // Stay on [A-Za-z0-9_], otherwise undefined (will be filled by streaming copy later)
        for b in 0u8..=255 {
            if is_alnum(b) {
                next[S::Ident.idx()][b as usize] = Next {
                    state: S::Ident.idx() as u16,
                    emit: false,
                };
            }
        }

        // ---------- Int ----------
        for b in b'0'..=b'9' {
            next[S::Int.idx()][b as usize] = Next {
                state: S::Int.idx() as u16,
                emit: false,
            };
        }

        // ---------- Whitespace ----------
        for &b in b" \t\r\n" {
            next[S::White.idx()][b as usize] = Next {
                state: S::White.idx() as u16,
                emit: false,
            };
        }

        // ---------- MaybeSlash ----------
        // On '/'  => line comment
        // On '*'  => block comment
        // Else    => (no explicit edge) -> streaming copy will create an emitting edge, giving bare SLASH
        set(&mut next, S::MaybeSlash, b"/", S::LineComment);
        set(&mut next, S::MaybeSlash, b"*", S::BlockComment);

        // ---------- LineComment ----------
        // Consume until '\n' (we don't include '\n' in the comment token)
        set_all_except(&mut next, S::LineComment, b"\n", S::LineComment);
        // No explicit edge on '\n' (streaming copy will create an emitting edge into Start's '\n' target)

        // ---------- BlockComment ----------
        // Consume everything; only watch for '*' to possibly end.
        set_all_except(&mut next, S::BlockComment, &[], S::BlockComment);
        set(&mut next, S::BlockComment, b"*", S::BlockStar);

        // ---------- BlockStar ----------
        // '*' can repeat; '/' ends the comment; otherwise back to BlockComment.
        set(&mut next, S::BlockStar, b"*", S::BlockStar);
        set(&mut next, S::BlockStar, b"/", S::BlockDone);
        set_all_except(&mut next, S::BlockStar, b"*/", S::BlockComment);

        // ---------- Single-char acceptors have no explicit edges (streaming copy handles them) ----------

        // ---------- Streaming transform: copy Start edges to accepting states as emitting edges ----------
        let mut token_map = [INVALID_TOKEN; 16];
        for s in ALL_STATES {
            if let Some(tk) = token_of_state(*s) {
                token_map[s.idx()] = tk as u32;
                // Copy Start's edges wherever 's' does not already define a transition.
                for b in 0u8..=255 {
                    let here = next[s.idx()][b as usize];
                    let has_explicit =
                        here.state != S::Reject.idx() as u16 || matches!(s, S::Reject);
                    if !has_explicit {
                        let start_edge = next[S::Start.idx()][b as usize];
                        next[s.idx()][b as usize] = Next {
                            state: start_edge.state,
                            emit: true,
                        };
                    }
                }
            }
        }
        // Reject self-loop (never emits)
        for b in 0u8..=255 {
            next[S::Reject.idx()][b as usize] = Next {
                state: S::Reject.idx() as u16,
                emit: false,
            };
        }

        Self {
            next,
            token_map,
            start: START.idx() as u16,
            reject: REJECT.idx() as u16,
        }
    }
}

/// Unary function ID registry; each function is Q -> (Q,emit).
#[derive(Clone)]
struct UFunc {
    trans: Vec<Next>, // length = #states
}

pub struct Tables {
    pub char_to_func: [u32; 256], // ids
    pub merge: Vec<u32>,          // m*m row-major
    pub token_of: Vec<u32>,       // m -> token kind (or INVALID_TOKEN)
    pub emit_on_start: Vec<u32>,  // m -> 0/1 (whether last edge of the prefix emits)
    pub m: u32,                   // number of functions (including id 0)
    pub identity: u32,            // identity id (0)
}

pub fn build_tables() -> Tables {
    let dfa = StreamingDfa::new();
    let n_states = dfa.next.len();

    // Identity function id 0
    let identity = UFunc {
        trans: (0..n_states)
            .map(|s| Next {
                state: s as u16,
                emit: false,
            })
            .collect(),
    };

    // Interner of functions: map trans-vectors -> id
    let mut funcs: Vec<UFunc> = vec![identity.clone()];
    let mut map: HashMap<Vec<Next>, u32> = HashMap::new();
    map.insert(identity.trans.clone(), 0);

    let mut char_to_func = [0u32; 256];

    // 1) Build δ_c for each byte and intern
    for b in 0u8..=255 {
        let mut trans = Vec::with_capacity(n_states);
        for s in 0..n_states {
            trans.push(dfa.next[s][b as usize]);
        }
        let id = *map.entry(trans.clone()).or_insert_with(|| {
            let id = funcs.len() as u32;
            funcs.push(UFunc {
                trans: trans.clone(),
            });
            id
        });
        char_to_func[b as usize] = id;
    }

    // 2) Closure of compositions to fill merge table (BFS over pairs)
    //    We repeatedly try to compose known ids until no growth.
    let mut changed = true;
    while changed {
        changed = false;
        let current_len = funcs.len();
        for a in 0..current_len {
            for b in 0..current_len {
                // compose: b ∘ a
                let trans = compose(&funcs[a], &funcs[b]).trans;
                if !map.contains_key(&trans) {
                    let id = funcs.len() as u32;
                    map.insert(trans.clone(), id);
                    funcs.push(UFunc { trans });
                    changed = true;
                }
            }
        }
    }

    // 3) Build merge[m*m], token_of[m], emit_on_start[m]
    let m = funcs.len() as u32;
    let mut merge = vec![0u32; (m * m) as usize];
    for a in 0..m {
        for b in 0..m {
            let trans = compose(&funcs[a as usize], &funcs[b as usize]).trans;
            let id = *map.get(&trans).unwrap();
            merge[(a * m + b) as usize] = id;
        }
    }

    let start = dfa.start as usize;
    let mut token_of = vec![INVALID_TOKEN; m as usize];
    let mut emit_on_start = vec![0u32; m as usize];
    for (id, f) in funcs.iter().enumerate() {
        let Next { state, emit } = f.trans[start];
        token_of[id] = dfa.token_map[state as usize];
        emit_on_start[id] = if emit { 1 } else { 0 };
    }

    Tables {
        char_to_func,
        merge,
        token_of,
        emit_on_start,
        m,
        identity: 0,
    }
}

fn compose(a: &UFunc, b: &UFunc) -> UFunc {
    // b ∘ a
    let n = a.trans.len();
    let mut out = Vec::with_capacity(n);
    for s in 0..n {
        let Next { state: mid, .. } = a.trans[s];
        let Next { state, emit } = b.trans[mid as usize];
        out.push(Next { state, emit }); // emit flag of the LAST transition (from b)
    }
    UFunc { trans: out }
}

// ---------------------------------------------
// Input-specialized tables to keep m manageable
// ---------------------------------------------
use std::time::Instant;

/// Build tables only for the bytes that actually appear in `bytes`.
/// All other bytes map to the identity function (they won't be used anyway).
pub fn build_tables_for_bytes(bytes: &[u8]) -> Tables {
    let t0 = Instant::now();

    // Mark which bytes occur
    let mut present = [false; 256];
    let mut distinct = 0usize;
    for &b in bytes {
        let was = present[b as usize];
        if !was {
            present[b as usize] = true;
            distinct += 1;
        }
    }

    // Construct the streaming DFA once
    let dfa = StreamingDfa::new();
    let n_states = dfa.next.len();

    // Identity function id 0
    let identity = UFunc {
        trans: (0..n_states)
            .map(|s| Next {
                state: s as u16,
                emit: false,
            })
            .collect(),
    };

    // Interner: transitions -> id
    let mut funcs: Vec<UFunc> = vec![identity.clone()];
    let mut map: HashMap<Vec<Next>, u32> = HashMap::new();
    map.insert(identity.trans.clone(), 0);

    let mut char_to_func = [0u32; 256];

    // 1) Build δ_c only for bytes that occur; others map to identity (0).
    for b in 0u8..=255 {
        if !present[b as usize] {
            char_to_func[b as usize] = 0;
            continue;
        }
        let mut trans = Vec::with_capacity(n_states);
        for s in 0..n_states {
            trans.push(dfa.next[s][b as usize]);
        }
        let id = *map.entry(trans.clone()).or_insert_with(|| {
            let id = funcs.len() as u32;
            funcs.push(UFunc {
                trans: trans.clone(),
            });
            id
        });
        char_to_func[b as usize] = id;
    }

    let t1 = Instant::now();
    println!(
        "[tables] generators: {} distinct bytes -> {} functions (took {:?})",
        distinct,
        funcs.len(),
        t1.duration_since(t0)
    );

    // 2) Closure of compositions (only over what we have)
    //    This can still grow, but usually stays small for real inputs.
    let mut changed = true;
    let mut round = 0usize;
    while changed {
        changed = false;
        round += 1;
        let current_len = funcs.len();
        for a in 0..current_len {
            for b in 0..current_len {
                let trans = compose(&funcs[a], &funcs[b]).trans;
                if !map.contains_key(&trans) {
                    let id = funcs.len() as u32;
                    map.insert(trans.clone(), id);
                    funcs.push(UFunc { trans });
                    changed = true;
                }
            }
        }
        println!("[tables] closure round {round}: size now {}", funcs.len());

        // Optional safety cap if you want to avoid pathologies:
        // if funcs.len() > 16384 { println!("[tables] cap hit; stopping growth"); break; }
    }

    // 3) Build merge[m*m], token_of[m], emit_on_start[m]
    let m = funcs.len() as u32;
    let mut merge = vec![0u32; (m * m) as usize];
    for a in 0..m {
        for b in 0..m {
            let trans = compose(&funcs[a as usize], &funcs[b as usize]).trans;
            let id = *map.get(&trans).unwrap();
            merge[(a * m + b) as usize] = id;
        }
    }

    let start = dfa.start as usize;
    let mut token_of = vec![INVALID_TOKEN; m as usize];
    let mut emit_on_start = vec![0u32; m as usize];
    for (id, f) in funcs.iter().enumerate() {
        let Next { state, emit } = f.trans[start];
        token_of[id] = dfa.token_map[state as usize];
        emit_on_start[id] = if emit { 1 } else { 0 };
    }

    let t2 = Instant::now();
    let bytes_merge = (m as u64) * (m as u64) * 4;
    println!(
        "[tables] finalized: m={}  merge={} bytes (~{} KiB)  total {:?}",
        m,
        bytes_merge,
        bytes_merge / 1024,
        t2.duration_since(t0)
    );

    Tables {
        char_to_func,
        merge,
        token_of,
        emit_on_start,
        m,
        identity: 0,
    }
}

// ---------------------------------------------
// JSON (de)serialization for prebuilt tables
// ---------------------------------------------
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
    let disk: TablesDisk = t.into();
    let s = serde_json::to_string(&disk).unwrap();
    std::fs::write(path, s)
}
pub fn load_tables_json_bytes(data: &[u8]) -> Result<Tables, String> {
    serde_json::from_slice::<TablesDisk>(data)
        .map(|d| d.into_tables())
        .map_err(|e| format!("Failed to parse tables JSON: {e}"))
}

// ---------------------------------------------
// Compact binary (de)serialization (u16 packing)
// ---------------------------------------------
use std::io::{Read, Write};

const BIN_MAGIC: &[u8; 8] = b"LXTBLE01";
const INVALID_TOKEN_U16: u16 = 0xFFFF;

pub fn save_tables_bin(path: &std::path::Path, t: &Tables) -> std::io::Result<()> {
    // Safety guard: we pack ids into u16
    if t.m > u16::MAX as u32 {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            format!("m={} exceeds u16::MAX; cannot pack to u16", t.m),
        ));
    }

    let mut f = std::fs::File::create(path)?;
    // Header: magic + m + identity
    f.write_all(BIN_MAGIC)?;
    f.write_all(&(t.m as u32).to_le_bytes())?;
    f.write_all(&(t.identity as u32).to_le_bytes())?;

    // char_to_func: 256 x u16
    for &id in &t.char_to_func {
        let v = u16::try_from(id).map_err(|_| {
            std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "char_to_func id > u16::MAX",
            )
        })?;
        f.write_all(&v.to_le_bytes())?;
    }

    // merge: m*m x u16
    for &id in &t.merge {
        let v = u16::try_from(id).map_err(|_| {
            std::io::Error::new(std::io::ErrorKind::InvalidData, "merge id > u16::MAX")
        })?;
        f.write_all(&v.to_le_bytes())?;
    }

    // token_of: m x u16 (INVALID_TOKEN -> 0xFFFF)
    for &tk in &t.token_of {
        let v = if tk == INVALID_TOKEN {
            INVALID_TOKEN_U16
        } else {
            u16::try_from(tk).map_err(|_| {
                std::io::Error::new(std::io::ErrorKind::InvalidData, "token_of value > u16::MAX")
            })?
        };
        f.write_all(&v.to_le_bytes())?;
    }

    // emit_on_start: m bits packed into bytes
    let m = t.m as usize;
    let mut bits = vec![0u8; (m + 7) / 8];
    for (i, &b) in t.emit_on_start.iter().enumerate() {
        if b != 0 {
            bits[i / 8] |= 1 << (i % 8);
        }
    }
    f.write_all(&bits)?;
    Ok(())
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

    let mut read_u32 = |buf: &mut &[u8]| -> Result<u32, String> {
        if buf.len() < 4 {
            return Err("truncated u32".into());
        }
        let mut le = [0u8; 4];
        le.copy_from_slice(&buf[..4]);
        *buf = &buf[4..];
        Ok(u32::from_le_bytes(le))
    };
    let mut read_u16 = |buf: &mut &[u8]| -> Result<u16, String> {
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
    let (bit_slice, rest) = data.split_at(bytes);
    data = rest;
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
