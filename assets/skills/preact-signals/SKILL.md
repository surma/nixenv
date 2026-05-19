---
name: preact-signals
description: Use when writing, debugging, or testing Preact code that uses @preact/signals for state management — including signal/computed/effect primitives, models, utility components (Show, For), component integration patterns, and testing strategies.
---

# Preact Signals

## Core Reactivity Model

Signals are runtime-tracked value containers. A reactive scope (component render, computed, or effect) subscribes only to `.value` reads that actually execute during that run. Signals are **not** deep proxies — mutating a property inside the current value does not notify subscribers.

### Creation and reads

```ts
import { signal, computed, effect, batch, untracked } from "@preact/signals-core";

const count = signal(0);
const double = computed(() => count.value * 2);

effect(() => {
  console.log(double.value);
});

count.value = 1;
```

Use `.peek()` or `untracked()` only when a read must not become a dependency:

```ts
effect(() => {
  const next = count.value + untracked(() => offset.value);
  total.value = next;
});
```

### Runtime tracking pitfalls

Reads behind a conditional that doesn't execute are not tracked:

```ts
// Bad: states.value is not tracked until the guard passes.
effect(() => {
  const id = currentAction.peek().id;
  if (!id) return;
  console.log(states.value[id]);
});

// Good: read before the guard.
effect(() => {
  const allStates = states.value;
  const id = currentAction.peek().id;
  if (!id) return;
  console.log(allStates[id]);
});
```

### Updating objects and arrays

Always assign a new reference:

```ts
// Bad — no notification.
todos.value.push(todo);
profile.value.name = "Ada";

// Good.
todos.value = [...todos.value, todo];
profile.value = { ...profile.value, name: "Ada" };
```

Use `batch()` when several writes represent one logical update:

```ts
batch(() => {
  firstName.value = "Ada";
  lastName.value = "Lovelace";
});
```

### Computed and effect rules

- `computed()` must be pure — derive and return; never write to other signals.
- `effect()` is for side effects and cleanup.
- Avoid returning fresh signals from a computed.
- Use `action(fn)` when model methods should run batched and untracked.

## Component Integration (Preact)

### Component-local state

Create component-local signals with hooks, never bare `signal()` in render:

```tsx
import { useSignal, useComputed, useSignalEffect } from "@preact/signals";

function Counter() {
  const count = useSignal(0);
  const double = useComputed(() => count.value * 2);

  useSignalEffect(() => {
    console.log(count.value);
  });

  return <button onClick={() => count.value++}>{double}</button>;
}
```

### Rendering: `.value` vs direct signal

Reading `.value` subscribes the component (causes rerender on change):

```tsx
<p>Count: {count.value}</p>
```

Passing the signal directly enables direct DOM text-node updates (no component rerender):

```tsx
<p>Count: {count}</p>
```

Preact also supports signals as DOM attributes (React does NOT):

```tsx
const inputValue = signal("Ada");
<input value={inputValue} onInput={e => (inputValue.value = e.currentTarget.value)} />
```

### useLiveSignal

Use when a component receives a signal reference that may itself change, or when a model constructor needs a live reactive input:

```tsx
import { useLiveSignal } from "@preact/signals/utils";

function Detail({ selected }: { selected: Signal<string> }) {
  const liveSelected = useLiveSignal(selected);
  const model = useModel(() => new DetailModel(liveSelected));
  return <DetailView model={model} />;
}
```

## Models

Use models to encapsulate cohesive signal state plus actions. Model functions are wrapped as actions (batched and untracked).

### createModel pattern

```tsx
import { createModel, signal, computed } from "@preact/signals";

const CountModel = createModel((initialCount: number) => {
  const count = signal(initialCount);
  const double = computed(() => count.value * 2);

  return {
    count,
    double,
    increment() {
      this.count.value++;
    }
  };
});
```

### useModel pattern

```tsx
// No args — pass constructor directly:
const model = useModel(CountModelWithoutArgs);

// With args — wrap in factory:
const model = useModel(() => new CountModel(5));
```

`useModel()` ignores factory changes after initial render. If inputs can change, pass a signal (via `useLiveSignal`) into the model.

### State shape guidance

- Mutable UI state → signals
- Derived values → computed signals
- Writes → action methods or effects, never inside computed
- Arrays/objects → new references on update
- Async loading → co-locate loading/error signals with the data they update

```tsx
const ListModel = createModel(() => {
  const items = signal<Item[]>([]);
  const loading = signal(false);

  return {
    items,
    loading,
    async load() {
      loading.value = true;
      try {
        items.value = await fetchItems();
      } finally {
        loading.value = false;
      }
    },
    add(item: Item) {
      items.value = [...items.value, item];
    }
  };
});
```

## Utility Components

### Show and For

```tsx
import { For, Show } from "@preact/signals/utils";

<Show when={model.hasItems} fallback={<p>No items</p>}>
  <For each={model.items}>{item => <Item item={item} />}</For>
</Show>
```

**Important:** `For` caches children. They do not react to non-signal parent values changing. If children need to react to a parent value, pass it as a signal prop or lift the child into a component that reads the signal.

```tsx
const showDetails = useSignal(false);
const items = useSignal<Item[]>([]);

function App() {
  return (
    <For each={items}>
      {item => <Item item={item} showDetails={showDetails} />}
    </For>
  );
}

function Item({ item, showDetails }: { item: Item; showDetails: Signal<boolean> }) {
  return <li>{item.id}{showDetails.value && ` - ${item.createdAt}`}</li>;
}
```

## Testing

### Core principles

- Test behavior at the boundary that matters: component tests assert DOM output; unit tests verify signal graph behavior directly.
- Reset module-level signals between tests or use local factories for isolation.

### App test patterns

```ts
// Reset approach:
beforeEach(() => { count.value = 0; });

// Factory approach (preferred for isolation):
function createCounterState() {
  const count = signal(0);
  return { count, increment: () => count.value++ };
}
```

### Component tests

```tsx
render(<Counter />);
await user.click(screen.getByRole("button", { name: /increment/i }));
expect(screen.getByText("1")).toBeInTheDocument();
```

### Async and effects

- Read signals before `await` if the read should be tracked.
- Use `findBy*` or `waitFor` for UI that updates after effects/async actions.
- Dispose manual `effect()` calls in test cleanup.
- Unmount rendered components so effects don't leak between tests.

## Common Mistakes — Quick Reference

| Mistake | Why it's wrong | Fix |
|---------|---------------|-----|
| `signal()` in component body | Creates new signal every render | Use `useSignal()` |
| Mutating `.value` internals | No notification fires | Assign new reference |
| `.value` read after early return | Not tracked if guard short-circuits | Read before the guard |
| `if (signal)` instead of `if (signal.value)` | Signal object is always truthy | Read `.value` |
| Writing signals inside `computed()` | Side effects in pure derivation | Move to `effect` or action |
| Multiple writes without batch | Each triggers separate propagation | Wrap in `batch()` or use model action |
| `useModel(ModelWithArgs)` | Constructs without passing args | Use `useModel(() => new Model(args))` |
| Expecting `For` children to react to non-signal parent values | `For` caches children | Pass signals down |
| Signal DOM attributes in React | Only works in Preact | Use `.value` in React |
| `.value` read after `await` | Not tracked by reactive scope | Read before `await` |

## Debugging Quick Diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Value changes but UI stale | Property mutation without new reference | Assign new object/array |
| Effect never reruns | `.value` read didn't execute (behind guard) | Move read before guard |
| Computed loops or throws | Write inside `computed` | Move to effect or action |
| Component doesn't update | Duplicate Preact copy or missing adapter | Check singleton, add `preact/debug` |
| `For` children ignore parent changes | Non-signal value not tracked | Pass as signal prop |

## ESLint Rules (recommended)

Enable `@preact/eslint-plugin-signals` to catch static misuse:

| Rule | Catches |
|------|---------|
| `no-signal-write-in-computed` | Side effects inside `computed()` |
| `no-value-after-await` | `.value` reads after `await` (untracked) |
| `no-signal-truthiness` | `if (signal)` always-truthy checks |
| `no-signal-in-component-body` | `signal()`/`computed()`/`effect()` created every render |
| `no-conditional-value-read` | `.value` reads hidden behind non-reactive guards |

## References

- Signals core: https://github.com/preactjs/signals/blob/main/packages/core/README.md
- Preact integration: https://github.com/preactjs/signals/blob/main/packages/preact/README.md
- Utilities (Show, For, useLiveSignal): https://github.com/preactjs/signals/blob/main/packages/preact/utils/README.md
- Models: https://preactjs.com/guide/v10/signals/
- ESLint plugin: https://github.com/preactjs/signals/blob/main/packages/eslint-plugin-signals/README.md
- Debug package: https://github.com/preactjs/signals/blob/main/packages/debug/README.md
