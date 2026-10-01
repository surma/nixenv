---
name: philips-hue
description: Read and change the Philips Hue setup directly on the Hue bridge through the CLIP v2 REST API. Use when the user asks to change which lights a Hue scene uses, create or rename Hue scenes, inspect Hue rooms and zones, or change what a Hue switch (for example the living room Tap Dial) does. Home Assistant only mirrors Hue scenes and cannot edit them.
compatibility: Requires the Hue bridge application key at /var/lib/credentials/scout/hue-api-key and network access to the bridge.
---

# Philips Hue bridge (CLIP v2)

The Hue bridge "SurmBridge" stores all Hue rooms, zones, scenes, and switch setups.
Home Assistant gets them through its Hue integration.
Home Assistant can activate Hue scenes, but it cannot edit them.
To change them, use the bridge API directly.

The Hue app and Home Assistant read scenes from the bridge.
After a change on the bridge, they need no change of their own.

## Setup

```bash
HUE="https://10.0.255.16/clip/v2/resource"
HUE_KEY=$(cat /var/lib/credentials/scout/hue-api-key)
hue() { curl -sSk -H "hue-application-key: $HUE_KEY" "$@"; }

hue "$HUE/bridge" | jq '.data[0].bridge_id'   # "ecb5fafffe8fd23f"
```

- The bridge uses a self-signed certificate. For this reason, `curl` needs `-k`.
- Every response has the form `{"data": [...], "errors": [...]}`. Check `errors` after each write.
- Never print the key.

The bridge IP comes from the dynamic DHCP pool and can change.
If the bridge does not answer, get the current IP:

```bash
curl -s https://discovery.meethue.com/
```

Home Assistant uses the same key.
If the key file is missing or the bridge returns HTTP 403, read the current key from Home Assistant:

```bash
HUE_KEY=$(ssh root@10.0.0.5 "jq -r '.data.entries[] | select(.domain==\"hue\") | .data.api_key' /homeassistant/.storage/core.config_entries")
```

The same config entry also has the bridge IP in `.data.host`.

## Read the setup

```bash
# Lights: ID and name
hue "$HUE/light" | jq -r '.data[] | "\(.id)  \(.metadata.name)"'

# Rooms and zones
hue "$HUE/room" | jq -r '.data[] | "\(.id)  room  \(.metadata.name)"'
hue "$HUE/zone" | jq -r '.data[] | "\(.id)  zone  \(.metadata.name)"'

# Scenes: ID, name, and the room or zone of the scene
hue "$HUE/scene" | jq -r '.data[] | "\(.id)  \(.metadata.name)  (\(.group.rtype) \(.group.rid))"'
```

Show one scene with light names:

```bash
hue "$HUE/light" > /tmp/hue-lights.json
hue "$HUE/scene/$SCENE_ID" | jq --slurpfile l /tmp/hue-lights.json '
  ($l[0].data | map({(.id): .metadata.name}) | add) as $name
  | .data[0].actions[] | {light: $name[.target.rid], action}'
```

In Home Assistant, the `unique_id` of a Hue scene entity is the scene ID on the bridge:

```bash
hassio registries --entities -d scene --format json \
  | jq -r '.entity_registry[] | select(.platform=="hue") | "\(.entity_id)  \(.unique_id)"'
```

## Change a scene

A scene only controls the lights in its `actions` list.
To make the scene turn a light off, add the light with `{"on": {"on": false}}`.
`dimming.brightness` is a percentage from 0 to 100.

1. Save the current scene to a file in the working directory:

   ```bash
   hue "$HUE/scene/$SCENE_ID" > "scene-$SCENE_ID-$(date -u +%Y%m%dT%H%M%SZ).json"
   ```

2. Send the complete new `actions` list:

   ```bash
   hue -X PUT -H 'Content-Type: application/json' "$HUE/scene/$SCENE_ID" --data '{
     "actions": [
       {"target": {"rid": "<light-id>", "rtype": "light"},
        "action": {"on": {"on": true}, "dimming": {"brightness": 23.0}}},
       {"target": {"rid": "<other-light-id>", "rtype": "light"},
        "action": {"on": {"on": false}}}
     ]
   }'
   ```

3. Read the scene again. Compare it with the request of the user.

To restore a saved scene:

```bash
jq '{actions: .data[0].actions}' "scene-$SCENE_ID-<timestamp>.json" \
  | hue -X PUT -H 'Content-Type: application/json' "$HUE/scene/$SCENE_ID" --data @-
```

Other scene operations:

- Rename: `PUT` with `{"metadata": {"name": "New name"}}`.
- Create: `POST "$HUE/scene"` with `metadata.name`, `group` (the room or zone), and `actions`.
- Activate: `PUT` with `{"recall": {"action": "active"}}`. This switches the real lights.

## Switches (Tap Dial, dimmer switch)

A `behavior_instance` resource stores the setup of a Hue switch.
Its `configuration` connects each button to scenes and to a room or zone (`where`).

```bash
hue "$HUE/behavior_instance" | jq '.data[] | {id, name: .metadata.name, model: .state.model_id, configuration}'
```

- `buttonN.on_short_release` holds the short-press action: `recall_single`, `scene_cycle`, or `time_based`.
- `buttonN.on_long_press` holds the long-press action, for example `all_off`.
- `rotary` holds the setup of the dial.

A button points to a scene ID.
If only the lights of a scene change, the switch setup needs no change.

To change the switch setup itself, save the resource first.
Then send the complete `configuration` object with your change in it:

```bash
hue -X PUT -H 'Content-Type: application/json' "$HUE/behavior_instance/$ID" \
  --data @new-configuration.json   # {"configuration": {...complete configuration...}}
```

## Rules

- Save a resource to a file before you change it. Tell the user where the backup is.
- Do not switch lights or activate scenes unless the user asks for it. People can be in the room.
