--// SkylarkArenas.lua
-- The arenas of Skylark. Skylark is a world of arenas: anything the player sees about an arena
-- (its schedule, entry, terminals) is named for that arena, never "the arena".
-- Today one arena runs, Argonia; its schedule is ArenaSchedule and its entry state is the
-- Workspace ArenaReg* attributes (ArenaRegistration). A second arena adds an entry here with its
-- own schedule module and its own entry state; the player menu's SCHEDULE draws a section per
-- arena from this list.
--
--   SkylarkArenas.list()     -> { arena, ... } in display order
--   SkylarkArenas.get(id)    -> arena or nil
--   SkylarkArenas.current()  -> the arena this server runs (today: Argonia)
--   arena = { Id, Name, Short, Schedule (module), Live (this server runs it) }

local QuinCore = script.Parent

local SkylarkArenas = {}

local LIST = {
    {
        Id = "Argonia",
        Name = "Argonia Arena",
        Short = "Argonia",
        Schedule = require(QuinCore:WaitForChild("ArenaSchedule")),
        Live = true,
    },
}

function SkylarkArenas.list()
    return LIST
end

function SkylarkArenas.get(id)
    for _, arena in ipairs(LIST) do
        if arena.Id == id then
            return arena
        end
    end
    return nil
end

function SkylarkArenas.current()
    for _, arena in ipairs(LIST) do
        if arena.Live then
            return arena
        end
    end
    return LIST[1]
end

return SkylarkArenas
