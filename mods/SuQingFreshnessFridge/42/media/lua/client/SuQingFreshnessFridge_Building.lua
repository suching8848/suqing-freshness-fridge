require "SuQingFreshnessFridge/Building"

local B = SuQingFreshnessFridge.Building
if not B.eventsInstalled then
    B.eventsInstalled = true
    Events.OnObjectAdded.Add(B.OnObjectAdded)
    Events.LoadGridsquare.Add(B.OnLoadSquare)
end
