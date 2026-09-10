// macOS-style Unicode hex input logic.
//
// Pure, dependency-free state machine so it can be unit-tested without a
// running Fcitx5. `sym` is an XKB/Fcitx keysym value.
//
// Protocol: while Right Alt is held, hex digit presses are buffered; on
// Right Alt release, a valid buffer commits one Unicode scalar (either a
// 1-6 digit scalar value, or an 8-digit UTF-16 high+low surrogate pair).
#ifndef _MAC_UNICODE_HEX_H_
#define _MAC_UNICODE_HEX_H_

#include <array>
#include <cstdint>
#include <optional>
#include <string>

namespace unicodehex {

// XKB keysyms for the right-hand Alt/Meta keys.
constexpr uint32_t SymAltR = 0xffea;
constexpr uint32_t SymMetaR = 0xffe8;

inline bool isRightAltSym(uint32_t sym) {
    return sym == SymAltR || sym == SymMetaR;
}

// Modifiers, function keys, etc. use the 0xff00+ keysym range; those never
// become part of a hex sequence.
constexpr uint32_t kFunctionKeysymBase = 0xff00;

enum class Action {
    // Do not touch the event; it flows to the input method and app.
    PassThrough,
    // Swallow the event (it was part of the sequence).
    Consume,
    // Commit a character and swallow the current event.
    Commit,
};

struct Step {
    Action action = Action::PassThrough;
    // Valid only when action == Commit.
    uint32_t codepoint = 0;
};

struct State {
    bool rightAltHeld = false;
    bool aborted = false;
    std::string buffer;
    // Consumed presses without a consumed release, per hex digit (0-15).
    std::array<int, 16> pendingPresses{};

    void clear() {
        rightAltHeld = false;
        aborted = false;
        buffer.clear();
        pendingPresses.fill(0);
    }
};

// Maps a keysym to its hex digit value (0-15), or -1 if not a hex digit.
// Keysyms for ASCII letters and digits are their ASCII codes.
inline int hexDigitIndex(uint32_t sym) {
    if (sym >= '0' && sym <= '9') {
        return static_cast<int>(sym - '0');
    }
    if (sym >= 'a' && sym <= 'f') {
        return static_cast<int>(sym - 'a' + 10);
    }
    if (sym >= 'A' && sym <= 'F') {
        return static_cast<int>(sym - 'A' + 10);
    }
    return -1;
}

// Parses a buffered hex digit string.
// - 1-6 digits: a Unicode scalar value. Rejects values above U+10FFFF and
//   standalone surrogate scalars (U+D800-U+DFFF).
// - 8 digits: the UTF-16 surrogate pair form (e.g. D83DDE02 -> U+1F602).
//   Rejects lone, reversed, or otherwise malformed pairs.
// - Everything else (empty, 7 digits, non-hex, ...) is rejected.
// U+0000 is rejected as well: it cannot be meaningfully committed.
inline std::optional<uint32_t> parse(const std::string &digits) {
    const size_t len = digits.size();
    if (len == 0 || len == 7 || len > 8) {
        return std::nullopt;
    }
    uint32_t value = 0;
    for (char c : digits) {
        const int d = hexDigitIndex(static_cast<uint8_t>(c));
        if (d < 0) {
            return std::nullopt;
        }
        value = value * 16 + static_cast<uint32_t>(d);
    }
    if (len <= 6) {
        if (value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF) ||
            value == 0) {
            return std::nullopt;
        }
        return value;
    }
    // 8 digits: UTF-16 surrogate pair.
    const uint32_t high = value >> 16;
    const uint32_t low = value & 0xFFFF;
    if (high < 0xD800 || high > 0xDBFF || low < 0xDC00 || low > 0xDFFF) {
        return std::nullopt;
    }
    return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
}

// Advances the state machine by one key event. Right Alt is a dedicated
// delimiter: each matched press and release is swallowed, so applications
// never see a partial or bare Alt sequence.
inline Step step(State &state, bool isRelease, uint32_t sym) {
    if (isRightAltSym(sym)) {
        if (isRelease) {
            // Preserve pairing if focus changed or the addon started while
            // Right Alt was already held: only consume releases we matched.
            if (!state.rightAltHeld) {
                return {};
            }
            const bool committing = !state.aborted && !state.buffer.empty();
            const std::optional<uint32_t> codepoint =
                committing ? parse(state.buffer) : std::nullopt;
            state.clear();
            if (codepoint) {
                return {Action::Commit, *codepoint};
            }
            return {Action::Consume, 0};
        }
        // A fresh Right Alt press starts a new sequence.
        state.buffer.clear();
        state.aborted = false;
        state.rightAltHeld = true;
        return {Action::Consume, 0};
    }

    if (!state.rightAltHeld) {
        return {};
    }

    const int digit = hexDigitIndex(sym);
    if (isRelease) {
        // Only swallow releases of presses we swallowed ourselves, so a
        // release for a key pressed before the hold never gets lost.
        if (digit >= 0 && state.pendingPresses[digit] > 0) {
            state.pendingPresses[digit]--;
            return {Action::Consume, 0};
        }
        return {};
    }

    // Function keys and modifiers are ignored without aborting the
    // sequence; any other non-hex key aborts it and passes through.
    if (digit < 0) {
        if (sym < kFunctionKeysymBase) {
            state.aborted = true;
        }
        return {};
    }

    // Still buffering: swallow the digit and record it. Once the buffer is
    // full (or aborted), stop swallowing so nothing gets stuck.
    if (state.aborted || state.buffer.size() >= 8) {
        return {};
    }
    state.pendingPresses[digit]++;
    state.buffer.push_back("0123456789abcdef"[digit]);
    return {Action::Consume, 0};
}

} // namespace unicodehex

#endif // _MAC_UNICODE_HEX_H_
