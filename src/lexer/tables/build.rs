// src/lexer/tables/build.rs
use hashbrown::{HashMap, HashSet};
use rayon::prelude::*;
use std::time::Instant;

use super::Tables;
use super::dfa::{N_STATES, Next, StreamingDfa};

// Q -> (Q, emit)
#[derive(Clone)]
struct UFunc {
    trans: Vec<Next>, // len = #states
}

#[inline]
fn compose_trans(a: &[Next], b: &[Next]) -> Vec<Next> {
    let n = a.len();
    let mut out = Vec::with_capacity(n);
    for s in 0..n {
        let Next { state: mid, .. } = a[s];
        let Next { state, emit } = b[mid as usize];
        out.push(Next { state, emit }); // keep LAST edge emit flag
    }
    out
}

fn closure_fixpoint_parallel(funcs: &mut Vec<UFunc>, map: &mut HashMap<Vec<Next>, u32>) {
    let mut round = 0usize;
    let mut new_start = 0usize; // treat current set as "new" in first round

    loop {
        let cur_len = funcs.len();
        let new_idxs: Vec<usize> = (new_start..cur_len).collect();
        if new_idxs.is_empty() {
            break;
        }
        let all_idxs: Vec<usize> = (0..cur_len).collect();

        // new × all
        let set1: HashSet<Vec<Next>> = new_idxs
            .par_iter()
            .fold(HashSet::new, |mut local, &i| {
                let ai = &funcs[i].trans;
                for &j in &all_idxs {
                    let bj = &funcs[j].trans;
                    let trans = compose_trans(ai, bj);
                    if !map.contains_key(&trans) {
                        local.insert(trans);
                    }
                }
                local
            })
            .reduce(HashSet::new, |mut a, b| {
                a.extend(b);
                a
            });

        // all × new
        let set2: HashSet<Vec<Next>> = all_idxs
            .par_iter()
            .fold(HashSet::new, |mut local, &i| {
                let ai = &funcs[i].trans;
                for &j in &new_idxs {
                    let bj = &funcs[j].trans;
                    let trans = compose_trans(ai, bj);
                    if !map.contains_key(&trans) {
                        local.insert(trans);
                    }
                }
                local
            })
            .reduce(HashSet::new, |mut a, b| {
                a.extend(b);
                a
            });

        // Insert sequentially to assign stable IDs
        let mut added = 0usize;
        for trans in set1.into_iter().chain(set2.into_iter()) {
            if !map.contains_key(&trans) {
                let id = funcs.len() as u32;
                map.insert(trans.clone(), id);
                funcs.push(UFunc { trans });
                added += 1;
            }
        }

        round += 1;
        println!("[tables] closure round {round}: size now {}", funcs.len());

        if added == 0 {
            break;
        }
        new_start = cur_len;
    }
}

fn build_merge_and_maps_parallel(
    funcs: &Vec<UFunc>,
    map: &HashMap<Vec<Next>, u32>,
    start_state_idx: usize,
    token_map: &[u32; N_STATES],
) -> (Vec<u32>, Vec<u32>, Vec<u32>) {
    let m = funcs.len();
    let mut merge = vec![0u32; m * m];

    // Fill rows in parallel.
    let m_us = m as usize;
    merge.par_chunks_mut(m_us).enumerate().for_each(|(a, row)| {
        let at = &funcs[a].trans;
        for b in 0..m_us {
            let bt = &funcs[b].trans;
            let trans = compose_trans(at, bt);
            let id = *map
                .get(&trans)
                .expect("closure should intern all compositions");
            row[b] = id;
        }
    });

    let mut token_of = vec![super::tokens::INVALID_TOKEN; m];
    let mut emit_on_start = vec![0u32; m];
    for (id, f) in funcs.iter().enumerate() {
        let Next { state, emit } = f.trans[start_state_idx];
        token_of[id] = token_map[state as usize];
        emit_on_start[id] = if emit { 1 } else { 0 };
    }

    (merge, token_of, emit_on_start)
}

pub fn build_tables() -> Tables {
    let t0 = Instant::now();
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

    // Interner (transitions -> id)
    let mut funcs: Vec<UFunc> = vec![identity.clone()];
    let mut map: HashMap<Vec<Next>, u32> = HashMap::new();
    map.insert(identity.trans.clone(), 0);

    let mut char_to_func = [0u32; 256];

    // δ_c for each byte
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

    println!("[tables] base generators (distinct δ_c) = {}", funcs.len());
    println!("[tables] took {} ms", t0.elapsed().as_millis());

    // Parallel closure
    let t1 = Instant::now();
    closure_fixpoint_parallel(&mut funcs, &mut map);
    println!("[tables] closure took {} ms", t1.elapsed().as_millis());

    let t2 = Instant::now();
    // Merge + maps
    let (merge, token_of, emit_on_start) =
        build_merge_and_maps_parallel(&funcs, &map, dfa.start as usize, &dfa.token_map);
    println!("[tables] merge took {} ms", t2.elapsed().as_millis());

    Tables {
        char_to_func,
        merge,
        token_of,
        emit_on_start,
        m: funcs.len() as u32,
        identity: 0,
    }
}

pub fn build_tables_for_bytes(bytes: &[u8]) -> Tables {
    let t0 = Instant::now();

    // Mark which bytes occur
    let mut present = [false; 256];
    let mut distinct = 0usize;
    for &b in bytes {
        if !present[b as usize] {
            present[b as usize] = true;
            distinct += 1;
        }
    }

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

    let mut funcs: Vec<UFunc> = vec![identity.clone()];
    let mut map: HashMap<Vec<Next>, u32> = HashMap::new();
    map.insert(identity.trans.clone(), 0);

    let mut char_to_func = [0u32; 256];

    // δ_c only for present bytes
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

    // Parallel closure
    closure_fixpoint_parallel(&mut funcs, &mut map);

    // Merge + maps
    let (merge, token_of, emit_on_start) =
        build_merge_and_maps_parallel(&funcs, &map, dfa.start as usize, &dfa.token_map);

    let t2 = Instant::now();
    let m = funcs.len() as u64;
    let bytes_merge = m * m * 4;
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
        m: funcs.len() as u32,
        identity: 0,
    }
}
