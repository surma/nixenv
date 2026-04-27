---
name: homeassistant
description: Control Home Assistant devices and manage lists via the `hassio` CLI (unbraind/homeassistant-cli). Use when the user asks to control lights, switches, climate, fans, locks, covers, or other smart home devices, check sensor states, inspect automations, view calendars, or perform any Home Assistant operation. Also use when the user asks about shopping lists, to-do lists, or task lists — these are managed as Home Assistant `todo` entities (e.g. adding/removing items from a shopping list, checking what's on a to-do list).
compatibility: Requires `hassio` CLI to be installed and configured with a valid Home Assistant URL and long-lived access token.
---

# Home Assistant CLI (`hassio`)

Use this skill to interact with the user's Home Assistant instance via the `hassio` CLI.

The CLI is pre-configured with the HA URL and token via `~/.hassio-cli/settings.json` and the `HASSIO_URL` environment variable. No additional setup is needed.

## Verify the CLI

Before first use in a session, confirm the CLI is available and connected:

```bash
command -v hassio
hassio status
```

If `status` returns an error, check that the HA instance is reachable and the token is valid.

## Quick overview

Get a topology snapshot of the entire HA instance:

```bash
hassio summary
```

## Entity discovery

```bash
# List all entities in a domain
hassio entities -d light
hassio entities -d sensor
hassio entities -d todo

# Filter by state
hassio entities -d light -s on

# Filter by name pattern
hassio entities -p kitchen

# Count entities
hassio entities --count

# Search entities
hassio search "living room"

# Inspect a specific entity (detailed view)
hassio inspect light.living_room
hassio inspect sensor.temperature --history

# Find unavailable entities
hassio discover --unavailable
```

## Device control

### Lights

```bash
hassio call-service light turn_on -e light.living_room
hassio call-service light turn_off -e light.living_room
hassio call-service light turn_on -e light.living_room -d '{"brightness":200}'
hassio call-service light turn_on -e light.living_room -d '{"color_temp_kelvin":3000}'
```

### Switches

```bash
hassio call-service switch turn_on -e switch.kitchen
hassio call-service switch turn_off -e switch.kitchen
```

### Climate

```bash
hassio call-service climate set_temperature -e climate.living_room -d '{"temperature":22}'
hassio call-service climate set_hvac_mode -e climate.living_room -d '{"hvac_mode":"heat"}'
```

### Other domains

```bash
hassio call-service cover open_cover -e cover.garage
hassio call-service lock lock -e lock.front_door
hassio call-service fan turn_on -e fan.bedroom
```

### Batch operations

```bash
# Turn off multiple lights at once
hassio batch -d light -s turn_off -e light.living_room,light.kitchen,light.bedroom

# Set brightness on multiple lights
hassio batch -d light -s turn_on -e light.living_room,light.kitchen --data '{"brightness":200}'
```

## Shopping lists and to-do lists

Home Assistant exposes shopping lists and to-do lists as `todo` domain entities.

### List all to-do lists

```bash
hassio entities -d todo
```

### View items in a to-do list

To read items from a to-do list, use the `todo.get_items` service. The response includes item summaries and statuses:

```bash
hassio call-service todo get_items -e todo.shopping_list
hassio call-service todo get_items -e todo.todo_list
```

### Add an item

```bash
hassio call-service todo add_item -e todo.shopping_list -d '{"item":"Milk"}'
hassio call-service todo add_item -e todo.todo_list -d '{"item":"Fix the leaky faucet"}'
```

### Update an item (mark complete, rename)

```bash
hassio call-service todo update_item -e todo.shopping_list -d '{"item":"Milk","rename":"Oat Milk"}'
hassio call-service todo update_item -e todo.shopping_list -d '{"item":"Milk","status":"completed"}'
```

### Remove an item

```bash
hassio call-service todo remove_item -e todo.shopping_list -d '{"item":"Milk"}'
```

## Sensors and history

```bash
# Get current state
hassio states sensor.temperature

# Get history
hassio history -e sensor.temperature
hassio history -e sensor.temp1,sensor.temp2 -s "2024-01-01T00:00:00Z"

# View logbook
hassio logbook
```

## Automations

```bash
hassio entities -d automation
hassio call-service automation trigger -e automation.morning_routine
```

## Calendars

```bash
hassio entities -d calendar
hassio calendar-events calendar.home -s "2026-01-01T00:00:00Z" -e "2026-01-31T23:59:59Z"
```

## Scenes

```bash
hassio entities -d scene
hassio call-service scene turn_on -e scene.movie_night
```

## Advanced querying

```bash
# Query with expressions
hassio query "domain:light state:on"
hassio query "domain:sensor attributes:unit_of_measurement=°C"
hassio query "name:living" --summary

# Service schema (see what parameters a service accepts)
hassio services --domain light --flat
```

## Output formats

Default output is TOON (token-efficient). Other formats available:

```bash
hassio states --format json
hassio states --format yaml
hassio states --format table
hassio states --format markdown
```

## Read-only mode

To prevent accidental state changes, use read-only mode:

```bash
hassio --read-only states
```

## Tips

- **Always discover before acting**: Use `hassio entities -d <domain>` to find entity IDs before calling services.
- **Check state after commands**: After turning something on/off, the response includes the new state.
- **Use batch for multiple devices**: `hassio batch` is more efficient than multiple `call-service` calls.
- **Shopping list items are case-sensitive**: Use exact item names when updating or removing.
- **TOON format** is the most token-efficient output — prefer it for agent workflows unless the user asks for a specific format.
