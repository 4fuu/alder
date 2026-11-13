module core.hash

// The Milestone 8.1 stable hashing contract (docs/api/core.hash-v1.md).
//
// `hash` and `hash_with` derive one SipHash-1-3 value from a structural
// value. The encoding is canonical and independent of padding, pointers, and
// object identity: fixed-width integers are little-endian, Bool is one byte,
// String and Bytes carry a u64 little-endian length and then their exact
// bytes, Option and Result carry a one-byte tag then their payload, records
// hash their fields in declaration order, and enums hash a u64 variant
// ordinal then the payload. Unit contributes no bytes. Floats stay outside
// the structural domain through the Eq+Hash constraints.
//
// `Hasher` exposes the same primitive for callers that build their own
// canonical stream. `RandomState` is the 128-bit key carrier: `seeded` gives
// deterministic tests and simulations, while `std.random.random_state` fills
// it from host entropy for attack-facing maps.


/// One process-independent SipHash key pair. The fields are private; create a
/// state with `seeded` or through the OS-backed `std.random.random_state`.
pub type RandomState {
    k0: U64
    k1: U64
}

impl RandomState {
    /// Deterministic key expansion from one seed. The same seed produces the
    /// same key pair on every target and in every process.
    fn seeded(seed: U64) -> RandomState {
        let first = splitmix64(seed)
        let second = splitmix64(first)
        return RandomState(k0: first, k1: second)
    }

    /// The low-level key constructor used by the OS-backed builder in
    /// `std.random`. Word order is the SipHash key order: `k0` is the first
    /// key word, `k1` the second.
    fn from_words(k0: U64, k1: U64) -> RandomState {
        return RandomState(k0: k0, k1: k1)
    }

    /// A fresh hasher initialized with this key.
    fn hasher(self) -> Hasher {
        return Hasher(
            v0: self.k0 ^ 8317987319222330741,
            v1: self.k1 ^ 7237128888997146477,
            v2: self.k0 ^ 7816392313619706465,
            v3: self.k1 ^ 8387220255154660723,
            total: 0,
            tail: 0
        )
    }

    /// The first key word.
    fn first_word(self) -> U64 {
        return self.k0
    }

    /// The second key word.
    fn second_word(self) -> U64 {
        return self.k1
    }
}

/// One SipHash-1-3 accumulator. The state is a small copyable value; every
/// write mutates the caller's `var` binding, and `finish` returns the digest
/// without changing it.
pub type Hasher {
    v0: U64
    v1: U64
    v2: U64
    v3: U64
    total: U64
    tail: U64
}

impl Hasher {
    /// A hasher seeded deterministically from `seed`.
    fn seeded(seed: U64) -> Hasher {
        return RandomState.seeded(seed).hasher()
    }

    /// Appends one byte.
    fn write_u8(mut self, one: U8) -> Unit {
        let next = self.push_byte(one.to_u64())
        self.store(next)
    }

    /// Appends one 16-bit value in little-endian byte order.
    fn write_u16(mut self, value: U16) -> Unit {
        let next = self.push_uint(value.to_u64(), 2)
        self.store(next)
    }

    /// Appends one 32-bit value in little-endian byte order.
    fn write_u32(mut self, value: U32) -> Unit {
        let next = self.push_uint(value.to_u64(), 4)
        self.store(next)
    }

    /// Appends one 64-bit value in little-endian byte order.
    fn write_u64(mut self, value: U64) -> Unit {
        let next = self.push_uint(value, 8)
        self.store(next)
    }

    /// Appends every byte of `data` in order.
    fn write_bytes(mut self, data: Bytes) -> Unit {
        var next = copy_hasher(self)
        let count = data.len()
        var at: U64 = 0
        while at < count {
            next = next.push_byte(data.byte(at).to_u64())
            at = at + 1
        }
        self.store(next)
    }

    /// Completes SipHash-1-3 and returns its 64-bit digest. The hasher value
    /// is unchanged, so a caller may finish more than once.
    fn finish(self) -> U64 {
        var state = Hasher(v0: self.v0, v1: self.v1, v2: self.v2, v3: self.v3, total: self.total, tail: self.tail)
        let final_word = (self.total << 56) | self.tail
        state = state.compress_word(final_word)
        state = Hasher(v0: state.v0, v1: state.v1, v2: state.v2 ^ 255, v3: state.v3, total: state.total, tail: state.tail)
        state = state.sip_round()
        state = state.sip_round()
        state = state.sip_round()
        return state.v0 ^ state.v1 ^ state.v2 ^ state.v3
    }

    // The functional core: every private step returns a new value, so a
    // public mut method performs one field copy back instead of recursive
    // borrows.
    fn store(mut self, next: Hasher) -> Unit {
        self.v0 = next.v0
        self.v1 = next.v1
        self.v2 = next.v2
        self.v3 = next.v3
        self.total = next.total
        self.tail = next.tail
    }

    fn push_uint(self, value: U64, width: U64) -> Hasher {
        var next = copy_hasher(self)
        var at: U64 = 0
        while at < width {
            next = next.push_byte((value >> (at * 8)) & 255)
            at = at + 1
        }
        return next
    }

    fn push_byte(self, one: U64) -> Hasher {
        let total = self.total.add_wrapping(1)
        let slot = self.total % 8
        let tail = self.tail | (one << (slot * 8))
        var next = Hasher(v0: self.v0, v1: self.v1, v2: self.v2, v3: self.v3, total: total, tail: tail)
        if total % 8 == 0 {
            next = next.compress_word(tail)
        }
        return next
    }

    // One compression block: v3 ^= word, one SipRound (SipHash-1-3's c=1),
    // then v0 ^= word.
    fn compress_word(self, word: U64) -> Hasher {
        let mixed = Hasher(v0: self.v0, v1: self.v1, v2: self.v2, v3: self.v3 ^ word, total: self.total, tail: 0)
        let rounds = mixed.sip_round()
        return Hasher(v0: rounds.v0 ^ word, v1: rounds.v1, v2: rounds.v2, v3: rounds.v3, total: rounds.total, tail: 0)
    }

    fn sip_round_pair(self) -> Hasher {
        let once = self.sip_round()
        return once.sip_round()
    }

    fn sip_round(self) -> Hasher {
        var v0 = self.v0.add_wrapping(self.v1)
        var v1 = rotl13(self.v1) ^ v0
        v0 = rotl32(v0)
        var v2 = self.v2.add_wrapping(self.v3)
        var v3 = rotl16(self.v3) ^ v2
        v0 = v0.add_wrapping(v3)
        v3 = rotl21(v3) ^ v0
        v2 = v2.add_wrapping(v1)
        v1 = rotl17(v1) ^ v2
        v2 = rotl32(v2)
        return Hasher(v0: v0, v1: v1, v2: v2, v3: v3, total: self.total, tail: self.tail)
    }
}

fn copy_hasher(value: Hasher) -> Hasher {
    return Hasher(v0: value.v0, v1: value.v1, v2: value.v2, v3: value.v3, total: value.total, tail: value.tail)
}

fn rotl13(value: U64) -> U64 { return (value << 13) | (value >> 51) }
fn rotl16(value: U64) -> U64 { return (value << 16) | (value >> 48) }
fn rotl17(value: U64) -> U64 { return (value << 17) | (value >> 47) }
fn rotl21(value: U64) -> U64 { return (value << 21) | (value >> 43) }
fn rotl32(value: U64) -> U64 { return (value << 32) | (value >> 32) }

// SplitMix64 finalizer: one stable mixing step used only to expand the
// deterministic seed into two key words.
fn splitmix64(state: U64) -> U64 {
    var z = state.add_wrapping(11400714819323198485)
    z = (z ^ (z >> 30)).mul_wrapping(13787848793156543929)
    z = (z ^ (z >> 27)).mul_wrapping(10723151780598845931)
    return z ^ (z >> 31)
}

/// The stable structural hash under the zero key.
pub fn hash(T: type(Eq, Hash), value: T) -> U64 {
    return hash_structural(0, 0, value)
}

/// The structural hash under one `RandomState` key.
pub fn hash_with(T: type(Eq, Hash), state: RandomState, value: T) -> U64 {
    return hash_structural(state.first_word(), state.second_word(), value)
}

// The compiler recognizes this private call and lowers it to one structural
// hash operation over the concrete value type. Its source body is never
// executed; it exists so ordinary checking and monomorphization own the
// Eq+Hash constraint and the concrete instance.
fn hash_structural(T: type(Eq, Hash), k0: U64, k1: U64, value: T) -> U64 {
    return 0
}
