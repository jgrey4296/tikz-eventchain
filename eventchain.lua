-- --  eventchain.lua -*- mode: lua -*-
local getlocal    = require("debug" ).getlocal
local texio       = require("texio")

-- Consts:
local DIRECTIONS     = {["left"]=1, ["right"]=1, ["above"]=1, ["below"]=1}
local OPPOSITE       = {["left"]="right", ["right"]="left", ["above"]="below", ["below"]="above"}
local BEGIN          = [[\begin]]
local END            = [[\end]]
local NODE           = [[\node]]
local OBRACE         = "{"
local CBRACE         = "}"
local LDOTS          = [[\ldots]]
local EMPTYSET       = [[\emptyset{}]]
local DRAW           = [[\draw]]
local EMPH           = [[\emph]]
local BOTTOM         = [[$\bot$]]
local TOP            = [[$\top$]]
local TURNSTILE      = [[$\vdash$]]
local ENDSTILE       = [[$\dashv$]]
local ON_CHAIN       = "on chain=trace"
local NODE_BASE      = "Trace"
local OCCUR_PREFIX   = "eventOccur"
local EVENT_PREFIX   = "eventBox"
local STATE_PREFIX   = "stateBox"

-- Base class and its data:
local EventChain  = {
  total           =  {},
  changes         =  {},
  fluents         =  {},
  count           = -1,
  dir             = "below",
  dist            = "1cm",
  side            = "left",
  WRITE_DEBUG     = false,
  catcode         = -1,
  last_prefix     = nil
}


-- --  --------------------------------------------------

local function debug(str, ...)
  -- Writes out debug information when the package is loaded with the debug option
  local val
  if EventChain.WRITE_DEBUG ~= true then return end
  if ... then
    val = string.format(str, ...)
  else
    val = str
  end
  texio.write_nl("term", "-- EventChain --: "  .. val .. "\n")
end

-- --  --------------------------------------------------

function EventChain:new (dir, dist)
  -- ctor for an eventchain. Takes a direction, a node distance
  debug("Creating Eventchain: (%s), (%s)", dir, dist)
  o = {}
  setmetatable(o, self)
  self.__index = self
  if dir  ~= nil and string.len(dir) > 0 then self.dir = dir end
  if dist ~= nil and string.len(dist) > 0 then self.dist = dist end

  if self.dir == "right" then self.side = "above" end

  return o
end

function EventChain:open (start)
  -- Starts the tikzpicture environment
  debug("Open: %s : %s", self.dir, self.dist)
  local chain_str = string.format("start chain=trace going %s", self.dir)
  local node_str = string.format("node distance=%s and %s", self.dist, self.dist)
  local style_str = "every node/.style=/eventchain/node"

  self:output(
    string.format("%s{tikzpicture}[%s, %s, %s]", BEGIN, chain_str, node_str, style_str)
    -- "% Chain Starts here: "
  )
end

function EventChain:close ()
  -- Ends the tikzpicture environment
  debug("Close")
  self:finish()
  self:output(
    -- "% Chain Ends here",
    [[\end{tikzpicture}]]
    )
  local final = table.concat(self.total, "\n")
  debug("Final: ")
  debug("\n" .. final)
  self.total = {}
  return nil
end

function EventChain:start (val)
  -- A Start node of the chain.
  debug("Start event: %s", val or -1)
  self:set_count(val or 0)
  local start_sym = TOP
  if self.dir == "right" then start_sym = TURNSTILE end

  self:output(
    -- "% start node",
    string.format("%s [join, %s, /eventchain/node] (%s) { %s };",
                  NODE, ON_CHAIN, self:node_id(), start_sym)
  )
  self:tick()
end

function EventChain:body (body)
  self:output(body or [[ \BODY ]])
end

function EventChain:node (val)
  -- A generic state node of the chain.
  debug("Basic Node: %s", val or 'nil')
  local curr_count = self.count
  self:set_count(val)
  if curr_count ~= self.count then
    debug("Jumping to")
    self:continue()
  end

  self:output(
    string.format("%s [join, %s, /eventchain/state/node] (%s) { %s };",
                  NODE, ON_CHAIN, self:node_id(), self:node_content(val))
  )
  self:tick()

end

function EventChain:continue (val)
  -- A Node that jumps to forward to a new index
  debug("Continue Node: %s", val)
  self:output(
    -- "% continuing",
    string.format("%s [join, %s, draw=none, /eventchain/skip/node] (%s) { %s };",
                  NODE, ON_CHAIN, self:node_id(), LDOTS)
    )
  self:set_count(val)
end

function EventChain:finish ()
  -- The final node of a chain
  debug("Finish Node")
  local end_sym = BOTTOM
  if self.dir == "right" then end_sym = ENDSTILE end

  self:output(
    -- "% end node",
    string.format("%s [join, %s, /eventchain/node] (%s) { %s };",
                  NODE, ON_CHAIN, self:node_id(-1), end_sym)
  )
end

function EventChain:event_block(name, dist, cols, fmt, body)
  -- The start of an event description of {name} at {dist} from the chain.
  name = name or "Ev:"
  debug("Opening Event Changes: %s, %s, %s", name, dist, body or "")
  local prev_node   = self:node_id(self:prev_tick())
  local event_box   = self:node_id(self:prev_tick(), EVENT_PREFIX)
  local event_node  = self:node_id(self:prev_tick(), OCCUR_PREFIX)

  -- Continue the Chain
  self:output(
    -- "% opening changes",
    string.format("%s [%s, /eventchain/event/node] (%s) {};", NODE, ON_CHAIN, event_node)
    , string.format("%s (%s) -- (%s);", DRAW, prev_node, event_node)
  )
  -- And add the changed fluents to the side
  opp = OPPOSITE[self.dir]
  options = string.format("/eventchain/event/box, %s=%s", self.side, dist)
  self:output(
    string.format("%s (%s) node[ %s ] (%s)", DRAW, event_node, options, event_box)
    , [[ { ]]
  )
  self:tab_block(name, cols, fmt, body)
  -- Finishes an event description environment
  self:output(
    [[ }; ]]
    , string.format("%s (%s) --  (%s);", DRAW, event_node, event_box)
    --, "% Closing changes"
  )
  self.side = OPPOSITE[self.side]
  debug("Changes closed")
end

function EventChain:fluents_block(name, dist, cols, fmt, body)
  -- Starts a state description environment of {name}, {dist} from the chain
  debug("Opening Fluents: %s, %s : fmt: %s Body: %s", name, dist, fmt, body or "")
  self:node()
  local options = string.format("/eventchain/state/box, %s=%s", self.side, dist)
  self:output(
    -- "% Open Fluents"
    string.format("%s (%s) node[%s] (%s) ",
                  DRAW, self:node_id(self:prev_tick()),
                  options,
                  self:node_id(self:prev_tick(), STATE_PREFIX))
    , [[ { ]]
    )
  self:tab_block(name, cols, fmt, body)
  -- Closes the state description environment
  self:output(
    [[ }; ]]
    , string.format("%s (%s) -- (%s);",
                    DRAW,
                    self:node_id(self:prev_tick()),
                    self:node_id(self:prev_tick(), STATE_PREFIX)
                   )
  )

  self.side = OPPOSITE[self.side]
end

function EventChain:tab_block(name, cols, fmt, body)
  self:output(
    string.format([[\begin{tabular}{ %s }]], fmt)
    , string.format([[\multicolumn{%s}{c}{%s} \\]], cols, name)
    , [[ \hline ]]
    )
  self:body(body)
  self:output([[\end{tabular}]])
end

function EventChain:node_id (val, prefix)
  -- Create a canonical node id
  local id = self.count
  if val ~= nil then
    id = val
  end
  if prefix ~= nil then
    self.last_prefix = prefix
  else
    self.last_prefix = nil
  end
  return string.format("%s%s%s", prefix or "", NODE_BASE, id)
end

function EventChain:node_content (val)
  -- Create the canonical content of a node
  local id = self.count
  if val ~= nil and val ~= "nil" and string.len(val) > 0 then id = val end
  return string.format("$ S_{%s} $", id)
end

function EventChain:set_count(val)
  -- Move the focus index of the chain
  if val == "nil" or val == nil or string.len(val) == 0 then
    debug("Set count early exit")
    return
  end

  self.count = tonumber(val)
  debug("Set count to: %s", self.count)
end

function EventChain:tick()
  -- Increment the focus index of the chain by 1
  self.count = math.floor(self.count + 1)
end

function EventChain:prev_tick ()
  -- Util function to get the previous tick, as an integer
  return math.floor(self.count - 1)
end

function EventChain:output (...)
  -- Util method to output strings to the tex file for expansion.
  local extra = table.pack(...)
  ::loop:: for i,v in ipairs(extra) do
    if v == nil then goto loop end
    table.insert(self.total, v)
    tex.print(v)
  end
end

function EventChain:output_parts (...)
  -- Util method to output strings to the tex file for expansion.
  local extra = table.pack(...)
  for i,v in ipairs(extra) do
    for m in string.gmatch(v, "[^\n]+") do
      table.insert(self.total, m)
      tex.print(m)
    end
  end
end

function EventChain:s_output (...)
  -- Util method to output strings to the tex file for expansion.
  local extra = table.pack(...)
  tex.sprint(extra)
end


-- --  --------------------------------------------------
return EventChain
