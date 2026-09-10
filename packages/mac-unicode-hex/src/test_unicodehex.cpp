// Deterministic unit tests for the Unicode hex input state machine.
// Plain asserts, no test framework.
#include <cstdint>
#include <cstdio>
#include <optional>
#include <string>
#include <vector>

#include "unicodehex.h"

using unicodehex::Action;
using unicodehex::State;
using unicodehex::step;
using unicodehex::SymAltR;
using unicodehex::SymMetaR;

namespace {

int failures = 0;

#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);        \
            failures++;                                                        \
        }                                                                      \
    } while (0)

constexpr uint32_t SymAltL = 0xffe9;
constexpr uint32_t SymMetaL = 0xffe7;
constexpr uint32_t SymShiftL = 0xffe1;
constexpr uint32_t SymF5 = 0xffbf;
constexpr uint32_t SymG = 'g';
constexpr uint32_t SymUpperG = 'G';
constexpr uint32_t SymKP1 = 0xffb1;

std::optional<uint32_t> typeHex(State &state, const std::string &digits) {
    step(state, false, SymAltR);
    for (char c : digits) {
        step(state, false, static_cast<uint8_t>(c));
    }
    const unicodehex::Step s = step(state, true, SymAltR);
    if (s.action == Action::Commit) {
        return s.codepoint;
    }
    return std::nullopt;
}

void testParserDirect() {
    CHECK(unicodehex::parse("2014") == std::optional<uint32_t>(0x2014));
    CHECK(unicodehex::parse("1F602") == std::optional<uint32_t>(0x1F602));
    CHECK(unicodehex::parse("0301") == std::optional<uint32_t>(0x301));
    CHECK(unicodehex::parse("10FFFF") == std::optional<uint32_t>(0x10FFFF));
    CHECK(unicodehex::parse("ff") == std::optional<uint32_t>(0xff));
    // Leading zeros and lowercase.
    CHECK(unicodehex::parse("002014") == std::optional<uint32_t>(0x2014));
    CHECK(unicodehex::parse("000041") == std::optional<uint32_t>(0x41));
    CHECK(unicodehex::parse("d83dde02") == std::optional<uint32_t>(0x1F602));
    CHECK(unicodehex::parse("D83DDE02") == std::optional<uint32_t>(0x1F602));
    CHECK(unicodehex::parse("10000") == std::optional<uint32_t>(0x10000));
    // Boundary surrogate pair.
    CHECK(unicodehex::parse("DBFFDFFF") ==
          std::optional<uint32_t>(0x10FFFF));

    // Rejects.
    CHECK(!unicodehex::parse("").has_value());
    CHECK(!unicodehex::parse("110000").has_value());  // above U+10FFFF
    CHECK(!unicodehex::parse("2000000").has_value()); // > 6 digits scalar
    CHECK(!unicodehex::parse("1234567").has_value()); // 7 digits
    CHECK(!unicodehex::parse("123456789").has_value());
    CHECK(!unicodehex::parse("0").has_value()); // U+0000
    CHECK(!unicodehex::parse("0000").has_value());
    // Standalone surrogate scalars.
    CHECK(!unicodehex::parse("D800").has_value());
    CHECK(!unicodehex::parse("D83D").has_value());
    CHECK(!unicodehex::parse("DE02").has_value());
    CHECK(!unicodehex::parse("0D83D").has_value());
    // Lone or malformed pairs.
    CHECK(!unicodehex::parse("D83DD800").has_value()); // bad low
    CHECK(!unicodehex::parse("D7FFDE02").has_value()); // bad high
    CHECK(!unicodehex::parse("DE02D83D").has_value()); // reversed
    CHECK(!unicodehex::parse("D83DXX02").has_value()); // non-hex
    CHECK(!unicodehex::parse("GG").has_value());
}

void testBasicSequence() {
    State state;
    // Right Alt press passes through and is not consumed.
    CHECK(step(state, false, SymAltR).action == Action::PassThrough);
    // Unrelated Left Alt press passes through while held.
    CHECK(step(state, false, SymAltL).action == Action::PassThrough);
    // Digits are consumed while Right Alt is held.
    CHECK(step(state, false, '2').action == Action::Consume);
    CHECK(step(state, false, '0').action == Action::Consume);
    CHECK(step(state, false, '1').action == Action::Consume);
    CHECK(step(state, false, '4').action == Action::Consume);
    // Digit releases of consumed presses are swallowed.
    CHECK(step(state, true, '2').action == Action::Consume);
    // Right Alt release commits.
    const unicodehex::Step s = step(state, true, SymAltR);
    CHECK(s.action == Action::Commit);
    CHECK(s.codepoint == 0x2014);
    // State is fully cleared after commit.
    CHECK(!state.rightAltHeld && state.buffer.empty());
}

void testEmacsMeta() {
    // Right Alt mapped to Meta_R behaves identically.
    State state;
    CHECK(step(state, false, SymMetaR).action == Action::PassThrough);
    CHECK(step(state, false, 'a').action == Action::Consume);
    const unicodehex::Step s = step(state, true, SymMetaR);
    CHECK(s.action == Action::Commit);
    CHECK(s.codepoint == 0xa);
}

void testRightAltNeverStuck() {
    // Plain Right Alt tap: nothing consumed, nothing committed.
    State state;
    CHECK(step(state, false, SymAltR).action == Action::PassThrough);
    CHECK(step(state, true, SymAltR).action == Action::PassThrough);
    CHECK(state.buffer.empty() && !state.rightAltHeld);

    // Tap with no digits in between two holds does not concatenate.
    CHECK(step(state, false, SymAltR).action == Action::PassThrough);
    CHECK(step(state, false, '1').action == Action::Consume);
    // A single buffered hex digit is already a complete 1-digit sequence.
    const unicodehex::Step one = step(state, true, SymAltR);
    CHECK(one.action == Action::Commit && one.codepoint == 0x1);
    CHECK(step(state, false, SymAltR).action == Action::PassThrough);
    CHECK(step(state, false, '2').action == Action::Consume);
    const unicodehex::Step s = step(state, true, SymAltR);
    CHECK(s.action == Action::Commit && s.codepoint == 0x2);
}

void testLeftAltPassthrough() {
    // Left Alt (plain or keyd-swapped Meta_L) never starts a sequence.
    for (uint32_t sym : {SymAltL, SymMetaL}) {
        State state;
        CHECK(step(state, false, sym).action == Action::PassThrough);
        CHECK(step(state, false, '2').action == Action::PassThrough);
        CHECK(step(state, false, 'a').action == Action::PassThrough);
        CHECK(step(state, true, sym).action == Action::PassThrough);
    }
}

void testInvalidSequences() {
    // Non-hex key aborts the sequence and passes through.
    State state;
    step(state, false, SymAltR);
    CHECK(step(state, false, 'd').action == Action::Consume);
    CHECK(step(state, false, SymG).action == Action::PassThrough);
    CHECK(step(state, false, '8').action == Action::PassThrough);
    CHECK(step(state, true, SymAltR).action == Action::PassThrough);

    // Even a hex-only sequence with a bad value does not commit.
    State state2;
    CHECK(!typeHex(state2, "110000").has_value());
    CHECK(!typeHex(state2, "DE02D83D").has_value());
    CHECK(!typeHex(state2, "123456789").has_value());
    CHECK(!typeHex(state2, "0").has_value());
}

void testOverlongInputPassesThrough() {
    // After 8 digits the buffer is full; further digits pass through.
    State state;
    step(state, false, SymAltR);
    for (int i = 0; i < 8; i++) {
        CHECK(step(state, false, 'd').action == Action::Consume);
    }
    CHECK(step(state, false, 'd').action == Action::PassThrough);
    // Releases of the eight swallowed presses are still swallowed; a
    // release for a key that was never swallowed passes through.
    CHECK(step(state, true, 'd').action == Action::Consume);
    CHECK(step(state, true, 'e').action == Action::PassThrough);
    CHECK(step(state, true, SymAltR).action == Action::PassThrough);
}

void testModifiersAndFunctionKeys() {
    // Modifiers and function keys do not abort the sequence.
    State state;
    step(state, false, SymAltR);
    CHECK(step(state, false, SymShiftL).action == Action::PassThrough);
    CHECK(step(state, false, SymF5).action == Action::PassThrough);
    CHECK(step(state, false, '2').action == Action::Consume);
    CHECK(step(state, false, '0').action == Action::Consume);
    CHECK(step(state, false, '1').action == Action::Consume);
    CHECK(step(state, false, '4').action == Action::Consume);
    const unicodehex::Step s = step(state, true, SymAltR);
    CHECK(s.action == Action::Commit && s.codepoint == 0x2014);
}

void testKeyPadDigitsIgnored() {
    // Keypad digits are not part of the sequence (passed through).
    State state;
    step(state, false, SymAltR);
    CHECK(step(state, false, SymKP1).action == Action::PassThrough);
    CHECK(step(state, false, '2').action == Action::Consume);
    CHECK(step(state, true, SymAltR).action == Action::Commit);
}

void testUppercaseHex() {
    State state;
    CHECK(typeHex(state, "D83DDE02") == std::optional<uint32_t>(0x1F602));
    State state2;
    CHECK(typeHex(state2, "1F602") == std::optional<uint32_t>(0x1F602));
    State state3;
    CHECK(typeHex(state3, "0301") == std::optional<uint32_t>(0x301));
    State state4;
    CHECK(typeHex(state4, "10FFFF") == std::optional<uint32_t>(0x10FFFF));
}

} // namespace

int main() {
    testParserDirect();
    testBasicSequence();
    testEmacsMeta();
    testRightAltNeverStuck();
    testLeftAltPassthrough();
    testInvalidSequences();
    testOverlongInputPassesThrough();
    testModifiersAndFunctionKeys();
    testKeyPadDigitsIgnored();
    testUppercaseHex();

    if (failures != 0) {
        std::printf("%d check(s) failed\n", failures);
        return 1;
    }
    std::printf("All tests passed\n");
    return 0;
}
