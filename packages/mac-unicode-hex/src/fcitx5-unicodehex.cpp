// Fcitx5 module implementing macOS-style Unicode hex input.
//
// While Right Alt is held, hex digits are buffered; when Right Alt is
// released, the buffered sequence is committed as a single Unicode scalar.
// Right Alt is a dedicated trigger whose down/up events are both consumed, so
// applications never observe a bare Alt sequence. As a Module-category addon
// it is loaded automatically and requires no input method selection.
#include <fcitx-utils/keysym.h>
#include <fcitx-utils/utf8.h>
#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>
#include <fcitx/event.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputcontextproperty.h>
#include <fcitx/instance.h>

#include <memory>
#include <vector>

#include "unicodehex.h"

namespace fcitx {

class UnicodeHexState : public InputContextProperty {
public:
    unicodehex::State state_;
};

class UnicodeHex : public AddonInstance {
public:
    UnicodeHex(Instance *instance)
        : instance_(instance),
          factory_([](InputContext &) { return new UnicodeHexState(); }) {
        instance_->inputContextManager().registerProperty("unicodehexState",
                                                          &factory_);

        eventHandlers_.emplace_back(instance_->watchEvent(
            EventType::InputContextKeyEvent,
            EventWatcherPhase::PreInputMethod,
            [this](Event &event) { handleKey(static_cast<KeyEvent &>(event)); }));

        auto reset = [this](Event &event) {
            auto *state = static_cast<InputContextEvent &>(event)
                              .inputContext()
                              ->propertyFor(&factory_);
            state->state_.clear();
        };
        eventHandlers_.emplace_back(instance_->watchEvent(
            EventType::InputContextFocusOut, EventWatcherPhase::Default, reset));
        eventHandlers_.emplace_back(instance_->watchEvent(
            EventType::InputContextReset, EventWatcherPhase::Default, reset));
    }

    void handleKey(KeyEvent &keyEvent) {
        auto *inputContext = keyEvent.inputContext();
        auto *state = inputContext->propertyFor(&factory_);

        const uint32_t sym = keyEvent.key().sym();
        const bool isRelease = keyEvent.isRelease();

        if (unicodehex::isRightAltSym(sym)) {
            // Right Alt is reserved for this protocol. Swallow matched edges
            // so applications such as Electron do not see a bare Alt tap.
            const unicodehex::Step step =
                unicodehex::step(state->state_, isRelease, sym);
            if (step.action != unicodehex::Action::PassThrough) {
                if (step.action == unicodehex::Action::Commit) {
                    inputContext->commitString(
                        utf8::UCS4ToUTF8(step.codepoint));
                }
                keyEvent.filterAndAccept();
            }
            return;
        }

        if (!state->state_.rightAltHeld) {
            return;
        }

        // While Right Alt is held, hide keys from the input method so the
        // sequence is not typed into the app.
        keyEvent.filter();
        const unicodehex::Step step =
            unicodehex::step(state->state_, isRelease, sym);
        if (step.action != unicodehex::Action::PassThrough) {
            keyEvent.accept();
        }
    }

private:
    Instance *instance_;
    FactoryFor<UnicodeHexState> factory_;
    std::vector<std::unique_ptr<HandlerTableEntry<EventHandler>>>
        eventHandlers_;
};

class UnicodeHexFactory : public AddonFactory {
    AddonInstance *create(AddonManager *manager) override {
        return new UnicodeHex(manager->instance());
    }
};

} // namespace fcitx

FCITX_ADDON_FACTORY_V2(unicodehex, fcitx::UnicodeHexFactory);
