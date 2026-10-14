-- raop-discover creates a sink for each AirPlay receiver on the network. On
-- an office network, most of these receivers belong to other people.
-- WirePlumber must never select such a sink by itself. It uses an AirPlay
-- sink only in two cases:
--
-- * The user selects the sink as the default in this session. The selection
--   ends when the receiver disappears or when WirePlumber starts again. Then
--   the newest non-AirPlay node from the history becomes the selected node.
-- * A stream has its own target for that sink (per-app memory).
--
-- This script must load before state-default-nodes.lua.

lutils = require ("linking-utils")
log = Log.open_topic ("s-airplay")

function isAirplay (name)
  return name ~= nil and name:find ("^raop_sink%.") ~= nil
end

-- The history of selected nodes from state-default-nodes.lua, newest first.
-- The keys are KEY, KEY.0, KEY.1, and so on.
function historyKey (key, position)
  return position == 1 and key or key .. "." .. tostring (position - 2)
end

function loadHistory (state_table, key)
  local history = {}
  while state_table [historyKey (key, #history + 1)] do
    table.insert (history, state_table [historyKey (key, #history + 1)])
  end
  return history
end

function newestLocal (history)
  for _, name in ipairs (history) do
    if not isAirplay (name) then
      return name
    end
  end
  return nil
end

function configuredName (metadata, def_node_type)
  local value = metadata:find (0, "default.configured." .. def_node_type)
  return value and Json.Raw (value):parse ().name
end

-- A selection from the last session is not a selection in this session.
-- Before state-default-nodes.lua restores it, move the newest non-AirPlay
-- node to the top of the history.
do
  local state = State ("default-nodes")
  local state_table = state:load ()
  local changed = false

  for _, def_node_type in ipairs { "audio.sink", "audio.source" } do
    local key = "default.configured." .. def_node_type
    local history = loadHistory (state_table, key)
    if isAirplay (history [1]) then
      local reordered = {}
      local name = newestLocal (history)
      if name then
        table.insert (reordered, name)
        for _, other in ipairs (history) do
          if other ~= name then
            table.insert (reordered, other)
          end
        end
      end
      for position = 1, #history do
        state_table [historyKey (key, position)] = reordered [position]
      end
      log:notice ("drop AirPlay selection " .. history [1] .. " from the last session")
      changed = true
    end
  end

  if changed then
    state:save (state_table)
  end
end

SimpleEventHook {
  name = "airplay/filter-default-candidates",
  before = { "default-nodes/find-selected-default-node",
             "default-nodes/find-stored-default-node",
             "default-nodes/find-best-default-node" },
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-default-node" },
    },
  },
  execute = function (event)
    local available_nodes = event:get_data ("available-nodes")
    available_nodes = available_nodes and available_nodes:parse ()
    if not available_nodes then
      return
    end

    local source = event:get_source ()
    local def_node_type = event:get_properties () ["default-node.type"]
    local metadata_om = source:call ("get-object-manager", "metadata")
    local metadata = metadata_om:lookup {
      Constraint { "metadata.name", "=", "default" },
    }
    if not metadata then
      return
    end

    local configured = configuredName (metadata, def_node_type)
    local configured_available = false
    local kept = {}
    for _, node_props in ipairs (available_nodes) do
      local name = node_props ["node.name"]
      if name == configured then
        configured_available = true
      end
      if not isAirplay (name) or name == configured then
        table.insert (kept, Json.Object (node_props))
      end
    end

    -- The selected receiver disappeared. End the selection.
    if isAirplay (configured) and not configured_available then
      local key = "default.configured." .. def_node_type
      local name = newestLocal (loadHistory (State ("default-nodes"):load (), key))
      log:notice ("drop AirPlay selection " .. configured .. ", use " .. tostring (name))
      if name then
        metadata:set (0, key, "Spa:String:JSON",
            Json.Object { ["name"] = name }:to_string ())
      else
        metadata:set (0, key, nil, nil)
      end
    end

    event:set_data ("available-nodes", Json.Array (kept))
  end
}:register ()

-- find-best-target links a stream to the sink with the highest priority when
-- no default sink exists. Reject that choice for an AirPlay sink.
SimpleEventHook {
  name = "airplay/reject-best-target",
  after = "linking/find-best-target",
  before = { "linking/get-filter-from-target", "linking/prepare-link" },
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-target" },
    },
  },
  execute = function (event)
    local source, _, _, _, si_flags, target =
        lutils:unwrap_select_target_event (event)
    if not target then
      return
    end

    local name = target.properties ["node.name"]
    if not isAirplay (name) or si_flags.has_defined_target then
      return
    end

    local metadata_om = source:call ("get-object-manager", "metadata")
    local metadata = metadata_om:lookup {
      Constraint { "metadata.name", "=", "default" },
    }
    if metadata and (name == configuredName (metadata, "audio.sink") or
        name == configuredName (metadata, "audio.source")) then
      return
    end

    log:notice ("reject AirPlay sink " .. name .. " as best target")
    event:set_data ("target", nil)
  end
}:register ()
