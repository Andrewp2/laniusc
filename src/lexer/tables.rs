// src/lexer/tables.rs
use hashbrown::HashMap;

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
