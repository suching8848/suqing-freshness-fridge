-- Optional model-pack integration. Normal isometric play has no Viewpoint dependency.
local registered = false
local function registerModels()
    if registered or not Viewpoint or not Viewpoint.ModelPacks then return end
    local ok, result = pcall(Viewpoint.ModelPacks.register,
        "SuQingFreshnessFridge", "media/viewpoint/package.properties")
    if ok and result then
        registered = true
        print("[SuQingFreshnessFridge] independent Viewpoint model registered")
    else
        print("[SuQingFreshnessFridge] Viewpoint model registration failed: " .. tostring(result))
    end
end
registerModels()
Events.OnGameBoot.Add(registerModels)
Events.OnGameStart.Add(registerModels)
