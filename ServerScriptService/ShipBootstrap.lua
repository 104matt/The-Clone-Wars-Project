-- ShipBootstrap.lua
-- ServerScriptService/ShipBootstrap
--
-- All'avvio del server:
--   1. Garantisce che ReplicatedStorage.FlightEvents esista come Folder.
--   2. Garantisce che FlightEvents.ShipEvent esista come RemoteEvent.
-- Se "ShipEvent" si trova al primo livello di ReplicatedStorage (vecchia
-- posizione), viene riparentato dentro FlightEvents per migrare in modo
-- trasparente.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function ensureFolder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name   = name
		f.Parent = parent
	elseif not f:IsA("Folder") then
		warn(("[ShipBootstrap] %s.%s esiste ma non e' una Folder."):format(parent:GetFullName(), name))
	end
	return f
end

local flightEvents = ensureFolder(ReplicatedStorage, "FlightEvents")

-- Migrazione dalla vecchia posizione (ReplicatedStorage.ShipEvent)
local legacy = ReplicatedStorage:FindFirstChild("ShipEvent")
if legacy and legacy:IsA("RemoteEvent") and legacy.Parent == ReplicatedStorage then
	legacy.Parent = flightEvents
end

local shipEvent = flightEvents:FindFirstChild("ShipEvent")
if not shipEvent then
	shipEvent = Instance.new("RemoteEvent")
	shipEvent.Name   = "ShipEvent"
	shipEvent.Parent = flightEvents
elseif not shipEvent:IsA("RemoteEvent") then
	shipEvent:Destroy()
	shipEvent = Instance.new("RemoteEvent")
	shipEvent.Name   = "ShipEvent"
	shipEvent.Parent = flightEvents
end
