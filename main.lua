--[[
    HEAVYWEIGHT FISHING - CUSTOM SCRIPT v1.0
    Viết riêng dựa trên source StarCrow
    Tính năng:
      ✅ Auto Cast (đúc câu)
      ✅ Auto Reel (kéo qua UpdateFishProgression)
      ✅ Auto Skill (Z/X/C/V)
      ✅ Auto Sell KHI ĐẦY BALO (không spam)
      ✅ Lock Bar (giữ thanh giữa)
      ✅ Auto Hotbar
      ✅ Anti AFK
      ✅ Save/Load Config
      ✅ Debug Inventory
]]

-- ============ LOAD FLUENT UI ============
local Fluent
pcall(function()
    Fluent = loadstring(game:HttpGet("https://raw.githubusercontent.com/NoahTyrant/Fluent-Ui/refs/heads/main/main.lua"))()
    if Fluent and Fluent.GUI then
        Fluent.GUI.DisplayOrder = 5000
    end
end)
if not Fluent then
    warn("[CustomFish] Không load được Fluent UI! Script vẫn chạy nhưng không có menu.")
end

-- ============ SERVICES ============
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local Events = ReplicatedStorage:WaitForChild("Events")
local DataFolder = ReplicatedStorage:WaitForChild("Data")
local PlayerData = DataFolder:WaitForChild(tostring(LocalPlayer.UserId), 15)

-- ============ REMOTES (từ source StarCrow) ============
local FishingEvent = Events:WaitForChild("Fishing")
local UpdateFishProgression = Events:WaitForChild("UpdateFishProgression")
local UseSkill = Events:WaitForChild("UseSkill")
local SellFish = Events:WaitForChild("SellFish")
local ToggleHotbar = Events:WaitForChild("ToggleHotbar")
local AFKEvent = Events:FindFirstChild("AFK")

-- ============ CONFIG ============
local Config = {
    -- Farm
    AutoCast = true,
    CastDelay = 1.5,
    AutoReel = true,
    LockBar = true,
    AutoSkill = true,
    SkillOrder = {"Z", "X", "C", "V"},
    SkillDelay = 0.25,
    AutoHotbar = true,
    HotbarSlot = "1",

    -- Auto Sell (BÁN KHI ĐẦY)
    AutoSell = true,
    SellWhenFullPercent = 90,
    SellCooldown = 3,
    MaxInventory = 0,  -- 0 = tự dò

    -- Misc
    AntiAFK = true,
}

-- ============ SAVE / LOAD ============
local SAVE_FOLDER = "CustomFishScript"
local SAVE_FILE = SAVE_FOLDER .. "/config.json"

local function SaveConfig()
    pcall(function()
        if not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
        writefile(SAVE_FILE, HttpService:JSONEncode(Config))
    end)
end

local function LoadConfig()
    pcall(function()
        if isfile(SAVE_FILE) then
            local d = HttpService:JSONDecode(readfile(SAVE_FILE))
            for k, v in pairs(d) do
                if Config[k] ~= nil then Config[k] = v end
            end
        end
    end)
end
LoadConfig()

-- ============ CACHE CHARACTER ============
local cachedChar = LocalPlayer.Character
local cachedHum = cachedChar and cachedChar:FindFirstChildOfClass("Humanoid")
local cachedHrp = cachedChar and cachedChar:FindFirstChild("HumanoidRootPart")

LocalPlayer.CharacterAdded:Connect(function(c)
    cachedChar = c
    cachedHum = c:WaitForChild("Humanoid", 5)
    cachedHrp = c:WaitForChild("HumanoidRootPart", 5)
end)

-- ============ CACHE GUI ============
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local MainGui = PlayerGui:WaitForChild("MainGui", 15)
local FishingGui = MainGui and MainGui:WaitForChild("Fishing", 15)
local BarFrame = FishingGui and FishingGui:WaitForChild("BarFrame", 15)
local FishingBar = BarFrame and BarFrame:WaitForChild("Bar", 15)
local SkillBtnFrame = FishingGui and FishingGui:WaitForChild("SkillButton", 15)
SkillBtnFrame = SkillBtnFrame and SkillBtnFrame:WaitForChild("Frame", 15)

-- ============ INVENTORY HELPERS ============
local function GetInventoryCount()
    local inv = PlayerData and PlayerData:FindFirstChild("Inventory")
    if not inv then return 0 end
    return #inv:GetChildren()
end

local _cachedMax = 0
local function GetInventoryMax()
    if Config.MaxInventory and Config.MaxInventory > 0 then
        return Config.MaxInventory
    end
    if _cachedMax > 0 then return _cachedMax end

    local pData = PlayerData
    if not pData then return 100 end

    local names = {
        "MaxInventory", "InventoryMax", "MaxSlots", "MaxBag", "BagSize",
        "InventorySize", "MaxCapacity", "Capacity", "MaxFish", "FishCapacity", "SlotLimit"
    }
    for _, n in ipairs(names) do
        local v = pData:FindFirstChild(n)
        if v and (v:IsA("NumberValue") or v:IsA("IntValue")) then
            _cachedMax = v.Value
            return v.Value
        end
    end
    for _, n in ipairs(names) do
        local attr = pData:GetAttribute(n)
        if type(attr) == "number" and attr > 0 then
            _cachedMax = attr
            return attr
        end
    end
    _cachedMax = 100
    return 100
end

local function DebugInventory()
    print("=== INVENTORY DEBUG ===")
    print("Count hiện tại:", GetInventoryCount())
    print("Max (auto-detect):", GetInventoryMax())
    print("Ngưỡng bán:", Config.SellWhenFullPercent .. "%")
    if PlayerData then
        print("--- PlayerData children ---")
        for _, c in ipairs(PlayerData:GetChildren()) do
            local extra = ""
            if c:IsA("NumberValue") or c:IsA("IntValue") then
                extra = " = " .. tostring(c.Value)
            elseif c:IsA("StringValue") then
                extra = ' = "' .. tostring(c.Value) .. '"'
            elseif c:IsA("Folder") then
                extra = " (" .. #c:GetChildren() .. " items)"
            end
            print("  " .. c.Name .. " [" .. c.ClassName .. "]" .. extra)
        end
    else
        print("PlayerData chưa load!")
    end
end

-- ============ SKILL HELPERS ============
local function FindSkillButton(key)
    if not SkillBtnFrame then return nil end
    local direct = SkillBtnFrame:FindFirstChild(key)
    if direct then return direct end
    for _, c in ipairs(SkillBtnFrame:GetChildren()) do
        if c:IsA("GuiObject") and tostring(c:GetAttribute("Key") or "") == key then
            return c
        end
    end
    return nil
end

local function IsSkillReady(key)
    local btn = FindSkillButton(key)
    if btn then
        if not btn.Visible then return false end
        local cd = btn:FindFirstChild("CD")
        if cd and cd.Visible then
            local num = tonumber(string.match(cd.Text or "", "%d+%.?%d*"))
            if num and num > 0 then return false end
        end
        return true
    end
    return false
end

-- ============ LOCK BAR ============
local isLocking = false
local CENTER_POS = UDim2.new(0.5, 0, 0.5, 0)

local function LockBar()
    if isLocking or not Config.LockBar then return end
    if not FishingGui or not FishingGui.Visible then return end
    if not FishingBar then return end
    isLocking = true
    pcall(function()
        FishingBar:TweenPosition(CENTER_POS, Enum.EasingDirection.InOut, Enum.EasingStyle.Linear, 0, true)
        FishingBar.Position = CENTER_POS
    end)
    isLocking = false
end

if FishingBar then
    FishingBar:GetPropertyChangedSignal("Position"):Connect(function()
        if not isLocking and FishingBar.Position.X.Scale ~= 0.5 then
            LockBar()
        end
    end)
end

-- ============ ANTI AFK ============
LocalPlayer.Idled:Connect(function()
    if not Config.AntiAFK then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
    if AFKEvent then pcall(function() AFKEvent:FireServer() end) end
end)

-- ============ VÒNG LẶP CHÍNH ============
local lastCastTick = 0
local lastSkillTick = 0
local skillIdx = 1
local lastSellTick = 0
local lastHotbarTick = 0

task.spawn(function()
    while task.wait(0.08) do
        local now = os.clock()
        local char = cachedChar or LocalPlayer.Character
        if not char then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        local isMinigame = FishingGui and FishingGui.Visible or false

        -- ===== AUTO HOTBAR =====
        if Config.AutoHotbar and (now - lastHotbarTick >= 2) then
            local t = char:GetAttribute("Type")
            if t and t ~= "Fishing Rod" then
                lastHotbarTick = now
                pcall(function() ToggleHotbar:InvokeServer(Config.HotbarSlot) end)
            end
        end

        -- ===== AUTO CAST =====
        if Config.AutoCast and not isMinigame then
            local t = char:GetAttribute("Type")
            local fishing = char:GetAttribute("Fishing")
            if t == "Fishing Rod" and not fishing then
                if now - lastCastTick >= Config.CastDelay then
                    lastCastTick = now
                    pcall(function() FishingEvent:FireServer(hrp.CFrame) end)
                end
            elseif t ~= "Fishing Rod" then
                if now - lastHotbarTick >= 1 then
                    lastHotbarTick = now
                    pcall(function() ToggleHotbar:InvokeServer(Config.HotbarSlot) end)
                end
            end
        end

        -- ===== AUTO REEL =====
        if Config.AutoReel and isMinigame then
            pcall(function() UpdateFishProgression:FireServer() end)
            if Config.LockBar then LockBar() end
        end

        -- ===== AUTO SKILL =====
        if Config.AutoSkill and isMinigame then
            if now - lastSkillTick >= Config.SkillDelay then
                local order = Config.SkillOrder
                for i = 1, #order do
                    local idx = ((skillIdx - 1 + (i - 1)) % #order) + 1
                    local key = order[idx]
                    if IsSkillReady(key) then
                        lastSkillTick = now
                        skillIdx = (idx % #order) + 1
                        pcall(function() UseSkill:FireServer(key) end)
                        break
                    end
                end
            end
        end

        -- ===== AUTO SELL KHI ĐẦY =====
        if Config.AutoSell then
            local cur = GetInventoryCount()
            local max = GetInventoryMax()
            if max > 0 then
                local pct = (cur / max) * 100
                if pct >= Config.SellWhenFullPercent and (now - lastSellTick >= Config.SellCooldown) then
                    lastSellTick = now
                    pcall(function() SellFish:FireServer() end)
                    print(("[AutoSell] 🐟 Bán balo %d/%d (%d%%)"):format(cur, max, math.floor(pct)))
                    if Fluent and Fluent.Notify then
                        pcall(function()
                            Fluent:Notify({
                                Title = "Auto Sell",
                                Content = ("Đã bán %d cá (balo %d/%d)"):format(cur, cur, max),
                                Duration = 2,
                            })
                        end)
                    end
                end
            end
        end
    end
end)

-- ============ BUILD GUI ============
if Fluent then
    local Window = Fluent:CreateWindow({
        Title = "Custom Fish Script",
        SubTitle = "v1.0 - Based on StarCrow",
        TabWidth = 160,
        Size = UDim2.fromOffset(500, 400),
        Acrylic = true,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.RightControl,
    })

    local Tabs = {
        Main = Window:AddTab({ Title = "Main", Icon = "" }),
        Config = Window:AddTab({ Title = "Config", Icon = "" }),
        Debug = Window:AddTab({ Title = "Debug", Icon = "" }),
    }

    -- === Tab Main ===
    local farmGroup = Tabs.Main:AddSection("Farm")

    farmGroup:AddToggle("AutoCast", {
        Title = "Auto Cast (đúc câu)",
        Default = Config.AutoCast,
        Callback = function(v) Config.AutoCast = v; SaveConfig() end,
    })
    farmGroup:AddSlider("CastDelay", {
        Title = "Cast Delay (s)",
        Default = Config.CastDelay,
        Min = 0.1, Max = 5, Rounding = 1,
        Callback = function(v) Config.CastDelay = v; SaveConfig() end,
    })
    farmGroup:AddToggle("AutoReel", {
        Title = "Auto Reel (kéo cá)",
        Default = Config.AutoReel,
        Callback = function(v) Config.AutoReel = v; SaveConfig() end,
    })
    farmGroup:AddToggle("LockBar", {
        Title = "Lock Bar (giữa)",
        Default = Config.LockBar,
        Callback = function(v) Config.LockBar = v; SaveConfig() end,
    })
    farmGroup:AddToggle("AutoSkill", {
        Title = "Auto Skill (Z/X/C/V)",
        Default = Config.AutoSkill,
        Callback = function(v) Config.AutoSkill = v; SaveConfig() end,
    })
    farmGroup:AddToggle("AutoHotbar", {
        Title = "Auto Hotbar",
        Default = Config.AutoHotbar,
        Callback = function(v) Config.AutoHotbar = v; SaveConfig() end,
    })

    -- === Auto Sell ===
    local sellGroup = Tabs.Main:AddSection("Auto Sell (Khi Đầy)")

    sellGroup:AddToggle("AutoSell", {
        Title = "Auto Sell",
        Default = Config.AutoSell,
        Callback = function(v) Config.AutoSell = v; SaveConfig() end,
    })
    sellGroup:AddSlider("SellPercent", {
        Title = "Ngưỡng bán (%)",
        Default = Config.SellWhenFullPercent,
        Min = 10, Max = 100, Rounding = 0,
        Callback = function(v) Config.SellWhenFullPercent = v; SaveConfig() end,
    })
    sellGroup:AddSlider("SellCooldown", {
        Title = "Cooldown bán (s)",
        Default = Config.SellCooldown,
        Min = 1, Max = 30, Rounding = 0,
        Callback = function(v) Config.SellCooldown = v; SaveConfig() end,
    })

    -- === Misc ===
    local miscGroup = Tabs.Main:AddSection("Misc")

    miscGroup:AddToggle("AntiAFK", {
        Title = "Anti AFK",
        Default = Config.AntiAFK,
        Callback = function(v) Config.AntiAFK = v; SaveConfig() end,
    })

    -- === Tab Config ===
    local cfgGroup = Tabs.Config:AddSection("Inventory")
    cfgGroup:AddInput("MaxInv", {
        Title = "Max Inventory (0 = auto)",
        Default = tostring(Config.MaxInventory),
        Placeholder = "0",
        Callback = function(v)
            local n = tonumber(v) or 0
            Config.MaxInventory = n
            _cachedMax = 0
            SaveConfig()
            print("[Config] Max Inventory = " .. n)
        end,
    })
    cfgGroup:AddButton({
        Title = "Reset về Auto Detect",
        Callback = function()
            Config.MaxInventory = 0
            _cachedMax = 0
            SaveConfig()
            print("[Config] Đã reset về auto-detect")
        end,
    })

    -- === Tab Debug ===
    Tabs.Debug:AddButton({
        Title = "Debug Inventory (in ra Output)",
        Callback = function() DebugInventory() end,
    })
    Tabs.Debug:AddButton({
        Title = "Bán Ngay (test)",
        Callback = function()
            pcall(function() SellFish:FireServer() end)
            print("[Debug] Đã fire SellFish")
        end,
    })
    Tabs.Debug:AddButton({
        Title = "Đúc Câu Ngay (test)",
        Callback = function()
            local char = cachedChar or LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                pcall(function() FishingEvent:FireServer(hrp.CFrame) end)
                print("[Debug] Đã fire Fishing")
            end
        end,
    })

    Fluent:Notify({
        Title = "Custom Fish Script",
        Content = "Đã load! Bán khi balo đạt " .. Config.SellWhenFullPercent .. "%",
        Duration = 4,
    })
end

print("[CustomFish] ✅ Script đã load thành công!")
