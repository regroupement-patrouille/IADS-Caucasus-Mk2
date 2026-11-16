-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- F10 map view of a Skynet IADS: draws the elements of a network and their relations on the F10 map, and keeps the drawing current.
--
--   iads:setMapView(true)   -- show it (for every coalition)
--   iads:setMapView(false)  -- erase it
--
-- Legend:
--   EW radar (or a SAM site acting as EW)   square          blue live, grey dark, purple silenced by a HARM
--   SAM site                                triangle        fill red live, grey dark, purple silenced by a HARM;
--                                                           outline orange when autonomous, else as the fill
--   point defence                           small triangle  as a SAM site
--   command center                          rectangle       green powered, orange unpowered, red destroyed
--   destroyed element                       dashed outline, at its last known position
--
-- A redraw removes every mark drawn last time and draws anew (DCS marks cannot be edited). It runs on a short timer, only for
-- networks that are shown and marked dirty.
--
-- Load order: after Skynet (skynet-iads-vendored.lua), before any script that builds an IADS. Uses nothing from VEAF.
-------------------------------------------------------------------------------------------------------------------------------------------------------------

-- guarded, so state (shown networks, the timer, mark ids) survives reloading this file
SkynetIADSMapView = SkynetIADSMapView or {}

SkynetIADSMapView.LogPrefix = "SKYNET MAP VIEW: "
SkynetIADSMapView.RefreshPeriod = 1 -- seconds between two checks for a dirty network
SkynetIADSMapView.FirstMarkId = 7300000
SkynetIADSMapView.FillAlpha = 0.35
SkynetIADSMapView.Colours = {
  red = { 1, 0, 0 },
  grey = { 0.5, 0.5, 0.5 },
  blue = { 0, 0.45, 1 },
  orange = { 1, 0.55, 0 },
  purple = { 0.65, 0.2, 0.85 },
  green = { 0, 0.75, 0 },
}
-- metres; a first guess, to tune in game
SkynetIADSMapView.Sizes = {
  ew = 1500, -- square half-side
  sam = 1500, -- triangle circumradius
  pointDefence = 800, -- triangle circumradius
  commandCenterHalfWidth = 3000,
  commandCenterHalfHeight = 1500,
}
SkynetIADSMapView.LineTypes = { solid = 1, dashed = 2 }

SkynetIADSMapView.shownIads = SkynetIADSMapView.shownIads or {}
SkynetIADSMapView.lastMarkId = SkynetIADSMapView.lastMarkId or (SkynetIADSMapView.FirstMarkId - 1)

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Tools
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function SkynetIADSMapView.warn(message)
  env.warning(SkynetIADSMapView.LogPrefix .. message)
end

function SkynetIADSMapView.colour(name, alpha)
  local rgb = SkynetIADSMapView.Colours[name] or SkynetIADSMapView.Colours.grey
  return { rgb[1], rgb[2], rgb[3], alpha or 1 }
end

function SkynetIADSMapView.newMarkId()
  SkynetIADSMapView.lastMarkId = SkynetIADSMapView.lastMarkId + 1
  return SkynetIADSMapView.lastMarkId
end

--- A new mark id, remembered by the IADS so the next redraw removes it.
function SkynetIADSMapView.newIadsMarkId(iads)
  local id = SkynetIADSMapView.newMarkId()
  table.insert(iads.mapViewMarkIds, id)
  return id
end

--- Where a Skynet element (or a DCS object) is; the last known position once it is gone.
function SkynetIADSMapView.positionOf(iads, object)
  iads.mapViewPositions = iads.mapViewPositions or {}
  local ok, position
  if object.getElementPosition then
    ok, position = pcall(object.getElementPosition, object)
  else
    ok, position = pcall(function()
      return object:isExist() and object:getPosition().p or nil
    end)
  end
  if ok and position then
    iads.mapViewPositions[object] = position
    return position
  end
  return iads.mapViewPositions[object]
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Styles: what an element looks like, from its state
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function SkynetIADSMapView.radarElementStyle(element, isEwRadar)
  local style = {}
  if isEwRadar or element:getActAsEW() then
    style.shape = "square"
    style.size = SkynetIADSMapView.Sizes.ew
  else
    style.shape = "triangle"
    style.size = element:getIsAPointDefence() and SkynetIADSMapView.Sizes.pointDefence or SkynetIADSMapView.Sizes.sam
  end
  if element:isDefendingHARM() then
    style.fill = "purple"
  elseif element:isActive() then
    style.fill = style.shape == "square" and "blue" or "red"
  else
    style.fill = "grey"
  end
  if style.shape == "triangle" and element:getAutonomousState() then
    style.outline = "orange"
  else
    style.outline = style.fill
  end
  style.dashed = element:isDestroyed() == true
  return style
end

function SkynetIADSMapView.commandCenterStyle(commandCenter)
  local style = { dashed = false }
  if commandCenter:isDestroyed() then
    style.fill, style.dashed = "red", true
  elseif not commandCenter:hasWorkingPowerSource() then
    style.fill = "orange"
  else
    style.fill = "green"
  end
  style.outline = style.fill
  return style
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Drawing primitives (all coalitions, read-only)
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function SkynetIADSMapView.lineTypeOf(style)
  return style.dashed and SkynetIADSMapView.LineTypes.dashed or SkynetIADSMapView.LineTypes.solid
end

--- Rectangle centred on `centre`, `halfHeight` north-south (x) and `halfWidth` east-west (z).
function SkynetIADSMapView.drawRectangle(iads, centre, halfWidth, halfHeight, style)
  local corner1 = { x = centre.x + halfHeight, y = centre.y, z = centre.z - halfWidth }
  local corner2 = { x = centre.x - halfHeight, y = centre.y, z = centre.z + halfWidth }
  trigger.action.rectToAll(
    -1,
    SkynetIADSMapView.newIadsMarkId(iads),
    corner1,
    corner2,
    SkynetIADSMapView.colour(style.outline),
    SkynetIADSMapView.colour(style.fill, SkynetIADSMapView.FillAlpha),
    SkynetIADSMapView.lineTypeOf(style),
    true
  )
end

--- Triangle on a circle of radius `radius` around `centre`, apex north.
function SkynetIADSMapView.drawTriangle(iads, centre, radius, style)
  local points = {}
  for i = 0, 2 do
    local angle = i * 2 * math.pi / 3
    points[i + 1] = { x = centre.x + radius * math.cos(angle), y = centre.y, z = centre.z + radius * math.sin(angle) }
  end
  trigger.action.markupToAll(
    7, -- freeform polygon
    -1,
    SkynetIADSMapView.newIadsMarkId(iads),
    points[1],
    points[2],
    points[3],
    SkynetIADSMapView.colour(style.outline),
    SkynetIADSMapView.colour(style.fill, SkynetIADSMapView.FillAlpha),
    SkynetIADSMapView.lineTypeOf(style),
    true
  )
end

function SkynetIADSMapView.drawShape(iads, centre, style)
  if style.shape == "triangle" then
    SkynetIADSMapView.drawTriangle(iads, centre, style.size, style)
  else
    SkynetIADSMapView.drawRectangle(iads, centre, style.size, style.size, style)
  end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Drawing a network
-------------------------------------------------------------------------------------------------------------------------------------------------------------
function SkynetIADSMapView.drawRadarElement(iads, element, isEwRadar)
  local position = SkynetIADSMapView.positionOf(iads, element)
  if position then
    SkynetIADSMapView.drawShape(iads, position, SkynetIADSMapView.radarElementStyle(element, isEwRadar))
  end
end

function SkynetIADSMapView.drawCommandCenter(iads, commandCenter)
  local position = SkynetIADSMapView.positionOf(iads, commandCenter)
  if position then
    local sizes = SkynetIADSMapView.Sizes
    SkynetIADSMapView.drawRectangle(iads, position, sizes.commandCenterHalfWidth, sizes.commandCenterHalfHeight, SkynetIADSMapView.commandCenterStyle(commandCenter))
  end
end

--- Run one drawing step; a failure is logged and the rest of the redraw goes on.
function SkynetIADSMapView.guardedDraw(what, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    SkynetIADSMapView.warn(string.format("drawing %s failed: %s", tostring(what), tostring(err)))
  end
end

function SkynetIADSMapView.erase(iads)
  for _, id in ipairs(iads.mapViewMarkIds or {}) do
    pcall(trigger.action.removeMark, id)
  end
  iads.mapViewMarkIds = {}
end

function SkynetIADSMapView.elementName(element)
  local ok, name = pcall(element.getDCSName, element)
  return ok and name or "?"
end

function SkynetIADSMapView.redraw(iads)
  SkynetIADSMapView.erase(iads)
  iads.mapViewDirty = false
  for _, ew in ipairs(iads:getEarlyWarningRadars() or {}) do
    SkynetIADSMapView.guardedDraw(SkynetIADSMapView.elementName(ew), SkynetIADSMapView.drawRadarElement, iads, ew, true)
  end
  -- point defences are SAM sites too
  for _, sam in ipairs(iads:getSAMSites() or {}) do
    SkynetIADSMapView.guardedDraw(SkynetIADSMapView.elementName(sam), SkynetIADSMapView.drawRadarElement, iads, sam, false)
  end
  for _, cc in ipairs(iads:getCommandCenters() or {}) do
    SkynetIADSMapView.guardedDraw(SkynetIADSMapView.elementName(cc), SkynetIADSMapView.drawCommandCenter, iads, cc)
  end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Refresh loop
-------------------------------------------------------------------------------------------------------------------------------------------------------------
--- Redraw every shown network marked dirty. Answers the time of the next check, so it can be the timer's function.
function SkynetIADSMapView.tick()
  for iads in pairs(SkynetIADSMapView.shownIads) do
    if iads.mapViewDirty then
      SkynetIADSMapView.guardedDraw(iads.name, SkynetIADSMapView.redraw, iads)
    end
  end
  return timer.getTime() + SkynetIADSMapView.RefreshPeriod
end

--- What the timer calls: looks tick() up at each call, so a reload of this file replaces it under the running timer.
function SkynetIADSMapView.timerTick()
  local ok, nextTime = pcall(SkynetIADSMapView.tick)
  if not ok then
    SkynetIADSMapView.warn("refresh failed: " .. tostring(nextTime))
    return timer.getTime() + SkynetIADSMapView.RefreshPeriod
  end
  return nextTime
end

function SkynetIADSMapView.startTimer()
  if not SkynetIADSMapView.timerId then
    SkynetIADSMapView.timerId = timer.scheduleFunction(SkynetIADSMapView.timerTick, nil, timer.getTime() + SkynetIADSMapView.RefreshPeriod)
  end
end

-------------------------------------------------------------------------------------------------------------------------------------------------------------
-- SkynetIADS API
-------------------------------------------------------------------------------------------------------------------------------------------------------------
--- Show (true) or erase (false) this network's drawing on the F10 map, for every coalition.
function SkynetIADS:setMapView(bEnabled)
  if bEnabled then
    SkynetIADSMapView.shownIads[self] = true
    self:markMapViewDirty()
    SkynetIADSMapView.startTimer()
  else
    SkynetIADSMapView.shownIads[self] = nil
    SkynetIADSMapView.erase(self)
  end
  return self
end

function SkynetIADS:getMapView()
  return SkynetIADSMapView.shownIads[self] == true
end

--- Ask for a redraw at the next refresh; costs nothing when the view is hidden.
function SkynetIADS:markMapViewDirty()
  self.mapViewDirty = true
end
