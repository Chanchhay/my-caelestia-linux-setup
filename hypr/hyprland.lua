local home   = os.getenv("HOME")
local hypr   = home .. "/.config/hypr"
package.path = package.path .. ";" .. home .. "/.config/caelestia/?.lua"

-- Create a file if it doesn't exist, optionally with initial content
local function maybe_create(file, content)
    local f = io.open(file)

    if f then
        f:close()
        return
    end

    f = io.open(file, "w")
    if f then
        if content then f:write(content) end
        f:close()
    end
end

-- Copy src to dst, but only if dst doesn't already exist
local function maybe_copy(src, dst)
    local out = io.open(dst)
    if out then
        out:close()
        return
    end

    local input = io.open(src, "r")
    if not input then return end

    out = io.open(dst, "w")
    if out then
        out:write(input:read("*a"))
        out:close()
    end
    input:close()
end

-- Maybe set current colours to defaults
maybe_copy(hypr .. "/scheme/default.lua", hypr .. "/scheme/current.lua")

-- User variables
maybe_create(home .. "/.config/caelestia/hypr-vars.lua", "return {}\n")
local overrides = require("hypr-vars")
if type(overrides) == "table" then
    local vars = require("variables")
    for k, v in pairs(overrides) do
        vars[k] = v
    end
end


--------------------------------------------------------------------
---- MONITORS -------------------------------------------------------
--------------------------------------------------------------------
-- Hyprland does NOT re-render the desktop for a mirrored output: the
-- mirror just gets the source monitor's framebuffer stretched onto its
-- own panel. So if the external panel's aspect ratio differs from the
-- laptop's, the image is squished -- changing the external's `scale`
-- does nothing to fix it. The only lever that works is picking a *mode*
-- on the external whose aspect ratio matches the laptop's.
--
-- That's what this section does: the laptop is pinned to exactly what
-- it runs today, and every external monitor is inspected when it shows
-- up and given the best aspect-matched mode it supports.

local LAPTOP   = "eDP-1"
local LAPTOP_W = 1920
local LAPTOP_H = 1080

-- true  -> external mirrors the laptop (same picture on both)
-- false -> external extends the desktop (its own screen, placed to the right)
local MIRROR = true

local LAPTOP_AR = LAPTOP_W / LAPTOP_H

-- 1. The laptop panel: pinned, and never touched by the logic below.
hl.monitor({
    output   = LAPTOP,
    mode     = LAPTOP_W .. "x" .. LAPTOP_H .. "@144.42",
    position = "0x0",
    scale    = 1,
})

-- 2. Fallback for any external monitor, applied the instant it appears --
--    before we've had a chance to look at the modes it supports.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
    mirror   = MIRROR and LAPTOP or nil,
})

-- Normalise the monitor's mode list. Hyprland hands us a table of tables
-- ({width=, height=, refresh_rate=, preferred=}); the string form is kept
-- as a fallback in case that ever changes.
local function parse_modes(raw)
    local modes = {}
    if type(raw) ~= "table" then return modes end
    for _, m in ipairs(raw) do
        if type(m) == "table" and tonumber(m.width) and tonumber(m.height) then
            modes[#modes + 1] = {
                w  = tonumber(m.width),
                h  = tonumber(m.height),
                rr = tonumber(m.refresh_rate) or 60,
            }
        elseif type(m) == "string" then
            local w, h, rr = m:match("^(%d+)x(%d+)@([%d%.]+)")
            if w then
                modes[#modes + 1] = { w = tonumber(w), h = tonumber(h), rr = tonumber(rr) }
            end
        end
    end
    return modes
end

-- Pick the mode closest to the laptop's aspect ratio, breaking ties by
-- larger area first and then by higher refresh rate.
local function best_mode(modes)
    local best, best_err
    for _, m in ipairs(modes) do
        local err = math.abs((m.w / m.h) - LAPTOP_AR)
        local better
        if not best then
            better = true
        elseif err < best_err - 0.001 then
            better = true
        elseif math.abs(err - best_err) <= 0.001 then
            local area, best_area = m.w * m.h, best.w * best.h
            better = area > best_area or (area == best_area and m.rr > best.rr)
        end
        if better then best, best_err = m, err end
    end
    return best
end

local function configure_external(mon)
    if not mon or not mon.name or mon.name == LAPTOP then return end

    local m = best_mode(parse_modes(mon.available_modes))

    hl.monitor({
        output   = mon.name,
        mode     = m and string.format("%dx%d@%.2f", m.w, m.h, m.rr) or "preferred",
        position = "auto",
        scale    = 1,
        mirror   = MIRROR and LAPTOP or nil,
    })
end

local function resolve(mon)
    if type(mon) == "string" or type(mon) == "number" then return hl.get_monitor(mon) end
    return mon
end

-- Apply to whatever is already plugged in (e.g. on config reload)
for _, mon in ipairs(hl.get_monitors() or {}) do
    configure_external(mon)
end

-- ...and to anything hotplugged later. The mode list can still be settling
-- the moment the event fires, so re-apply shortly after as well; this also
-- clears the stale-framebuffer junk Hyprland leaves in the margins on hotplug.
hl.on("monitor.added", function(mon)
    mon = resolve(mon)
    configure_external(mon)

    local name = mon and mon.name
    if name then
        hl.timer(function()
            configure_external(hl.get_monitor(name))
        end, { timeout = 500, type = "oneshot" })
    end
end)

-- Configs
require("hyprland.env")
require("hyprland.general")
require("hyprland.input")
require("hyprland.misc")
require("hyprland.animations")
require("hyprland.decoration")
require("hyprland.group")
require("hyprland.execs")
require("hyprland.rules")
require("hyprland.gestures")
require("hyprland.keybinds")

-- User configs
maybe_create(home .. "/.config/caelestia/hypr-user.lua")
require("hypr-user")
