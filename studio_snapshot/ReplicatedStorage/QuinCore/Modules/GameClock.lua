--// GameClock
-- The game's own clock (owner 2026-10-28, "literally pausing the time and play god"): everything
-- in QuinCore reads time through here instead of os.clock() / tick() / GetServerTimeNow(), and
-- waits through here instead of task.wait / task.delay, so a freeze stops time for the Quins -
-- cooldowns, state timers, memory, strike timings - and on resume each carries on from the same
-- moment instead of finding its timers run out.
--
-- While nothing is frozen every reading is the plain clock (paused total 0): no change at all.
--
-- The freeze is the server's: Workspace GameFrozen (true while frozen), GameFrozenAt (server time
-- it began) and GameFrozenTotal (server seconds frozen so far, finished freezes). The server
-- time reads take those, so a stamp written on one machine reads the same on another. The local
-- clocks (os.clock, tick) keep their own paused total on each machine, from when it saw the
-- freeze begin and end.
--   GameClock.now()        os.clock()
--   GameClock.tick()       tick()
--   GameClock.serverNow()  Workspace:GetServerTimeNow()
--   GameClock.wait(t)      task.wait(t): returns after t seconds of game time (none pass frozen)
--   GameClock.delay(t, f, ...)  task.delay; returns the thread (task.cancel works)
--   GameClock.frozen()     true while frozen
--   GameClock.changed      a BindableEvent fired with the new frozen state

local Workspace = game:GetService("Workspace")

local GameClock = {}

local frozen = Workspace:GetAttribute("GameFrozen") == true
local localPaused = 0 -- seconds this machine has spent frozen (finished freezes)
local localSince = frozen and os.clock() or nil
local changed = Instance.new("BindableEvent")
GameClock.changed = changed.Event

Workspace:GetAttributeChangedSignal("GameFrozen"):Connect(function()
	local now = Workspace:GetAttribute("GameFrozen") == true
	if now == frozen then return end
	frozen = now
	if frozen then
		localSince = os.clock()
	else
		localPaused += os.clock() - (localSince or os.clock())
		localSince = nil
	end
	changed:Fire(frozen)
end)

function GameClock.frozen()
	return frozen
end

-- seconds of real time this machine has been frozen, the current freeze included
local function pausedLocal()
	if localSince then return localPaused + (os.clock() - localSince) end
	return localPaused
end

function GameClock.now()
	return os.clock() - pausedLocal()
end

function GameClock.tick()
	return tick() - pausedLocal()
end

function GameClock.serverNow()
	local total = Workspace:GetAttribute("GameFrozenTotal") or 0
	if frozen then
		local at = Workspace:GetAttribute("GameFrozenAt")
		if at then return at - total end
	end
	return Workspace:GetServerTimeNow() - total
end

function GameClock.wait(seconds)
	local start = GameClock.now()
	task.wait(seconds)
	if not frozen and (seconds == nil or GameClock.now() - start >= seconds - 1e-4) then
		return GameClock.now() - start
	end
	-- frozen part way: wait out the freeze, then whatever game time is still owed
	while true do
		while frozen do changed.Event:Wait() end
		local left = (seconds or 0) - (GameClock.now() - start)
		if left <= 1e-4 then break end
		task.wait(left)
		if not frozen and GameClock.now() - start >= (seconds or 0) - 1e-4 then break end
	end
	return GameClock.now() - start
end

function GameClock.delay(seconds, callback, ...)
	local args = table.pack(...)
	return task.spawn(function()
		GameClock.wait(seconds)
		callback(table.unpack(args, 1, args.n))
	end)
end

return GameClock
