--[[
================================================================================
  DRAGON ADVENTURES  |  RUAJAD HUB - Storage Trade (Backup Account)
================================================================================
  รันไฟล์นี้บนรหัสสำรอง — ไม่ใช่ main_src.lua

  หน้าที่
  --------
  - รับเทรดจากรหัสหลักที่อยู่ในลิสต์ (กด + Add ได้ไม่จำกัด)
  - Slot ID แยกไฟล์ join/config ไม่ให้หลายจอสำรองทับกัน
  - คิว: ถ้ากำลังเทรดอยู่ คนถัดไปรอ — ยิง AcceptRequest เฉพาะหัวคิว
  - busy ดูจาก *TradeRemote ใน ReplicatedStorage.Remotes (หน้าต่างเกมเปิดจริง)
  - Hide Terrain / Low RAM / Anti-AFK เหมือนเดิม

  Persist: RuajadHub/StorageTrade_{slotId}.json
  Join beacon: RuajadHub/StorageJoinTarget_{slotId}.json
  Fallback slot 1: ยังเขียน StorageJoinTarget.json / อ่าน StorageTrade.json เก่าได้
================================================================================
]]

-- ============================================================
-- [1] SERVICES
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LP = Players.LocalPlayer

-- ============================================================
-- [2] CONFIG
-- ============================================================
local CONFIG = {
    Enabled = true,
    SlotId = 1, -- เลขหน้าต่างสำรอง — ต้องไม่ซ้ำกับจอสำรองอื่นบนเครื่องเดียวกัน
    MainUsernames = { "" }, -- รหัสหลักที่อนุญาตให้รับเทรด
    AcceptInterval = 2,
    HideTerrain = true,
    LowRam = false,
    AntiAfk = true,
}

local ACCENT = Color3.fromRGB(50, 150, 250)

local function clampSlotId(n)
    return math.clamp(math.floor(tonumber(n) or 1), 1, 99)
end

local function configPath(slotId)
    return "RuajadHub/StorageTrade_" .. tostring(clampSlotId(slotId)) .. ".json"
end

local function joinPath(slotId)
    return "RuajadHub/StorageJoinTarget_" .. tostring(clampSlotId(slotId)) .. ".json"
end

local function normalizeName(name)
    return string.lower((tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")))
end

local function cleanedMains()
    local out = {}
    local seen = {}
    for _, n in ipairs(CONFIG.MainUsernames or {}) do
        local t = tostring(n or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local key = normalizeName(t)
        if t ~= "" and not seen[key] then
            seen[key] = true
            table.insert(out, t)
        end
    end
    return out
end

local function isAllowedMain(name)
    local want = normalizeName(name)
    if want == "" then
        return false
    end
    for _, n in ipairs(cleanedMains()) do
        if normalizeName(n) == want then
            return true
        end
    end
    return false
end

local function applySaved(data)
    if type(data) ~= "table" then
        return
    end
    if data.Enabled ~= nil then
        CONFIG.Enabled = data.Enabled and true or false
    end
    if data.SlotId ~= nil then
        CONFIG.SlotId = clampSlotId(data.SlotId)
    end
    if type(data.MainUsernames) == "table" then
        local names = {}
        for _, n in ipairs(data.MainUsernames) do
            table.insert(names, tostring(n or ""))
        end
        if #names == 0 then
            names = { "" }
        end
        CONFIG.MainUsernames = names
    elseif data.MainUsername ~= nil then
        -- ของเก่า: ช่องเดียว
        local one = tostring(data.MainUsername or ""):gsub("^%s+", ""):gsub("%s+$", "")
        CONFIG.MainUsernames = { one }
    end
    if data.AcceptInterval ~= nil then
        CONFIG.AcceptInterval = math.clamp(tonumber(data.AcceptInterval) or 2, 1, 10)
    end
    if data.HideTerrain ~= nil then
        CONFIG.HideTerrain = data.HideTerrain and true or false
    end
    -- if data.LowRam ~= nil then
    --     CONFIG.LowRam = data.LowRam and true or false
    -- end
    if data.AntiAfk ~= nil then
        CONFIG.AntiAfk = data.AntiAfk and true or false
    end
end

-- โหลด SlotId จาก getgenv / ไฟล์เก่า แล้วค่อยโหลดไฟล์แยกตามเลข
pcall(function()
    if typeof(getgenv) == "function" and type(getgenv().RuajadStorageTrade) == "table" then
        applySaved(getgenv().RuajadStorageTrade)
    end
end)
pcall(function()
    if typeof(isfile) == "function" and isfile("RuajadHub/StorageTrade.json") then
        applySaved(HttpService:JSONDecode(readfile("RuajadHub/StorageTrade.json")))
    end
end)
pcall(function()
    local path = configPath(CONFIG.SlotId)
    if typeof(isfile) == "function" and isfile(path) then
        applySaved(HttpService:JSONDecode(readfile(path)))
    end
end)

local function snapshotConfig()
    return {
        Enabled = CONFIG.Enabled,
        SlotId = clampSlotId(CONFIG.SlotId),
        MainUsernames = CONFIG.MainUsernames,
        MainUsername = (cleanedMains()[1] or ""),
        AcceptInterval = CONFIG.AcceptInterval,
        HideTerrain = CONFIG.HideTerrain,
        LowRam = CONFIG.LowRam,
        AntiAfk = CONFIG.AntiAfk,
    }
end

local function saveConfig()
    pcall(function()
        CONFIG.SlotId = clampSlotId(CONFIG.SlotId)
        local snap = snapshotConfig()
        if typeof(getgenv) == "function" then
            getgenv().RuajadStorageTrade = snap
        end
        if typeof(isfolder) == "function" and not isfolder("RuajadHub") then
            makefolder("RuajadHub")
        end
        if typeof(writefile) == "function" then
            writefile(configPath(CONFIG.SlotId), HttpService:JSONEncode(snap))
            -- slot 1: เขียนไฟล์เก่าด้วย เพื่อของเดิมยังอ่านได้
            if CONFIG.SlotId == 1 then
                writefile("RuajadHub/StorageTrade.json", HttpService:JSONEncode(snap))
            end
        end
    end)
end

saveConfig()

-- ============================================================
-- [2b] LOW RAM (บอทยืนรอ)
-- ============================================================
local applyHideTerrain
local applyLowRam
local applyAntiAfk

do
    local Lighting = game:GetService("Lighting")
    local RunService = game:GetService("RunService")

    local terrainOn = false
    local lowRamOn = false
    local lightingBackup = nil

    local function freezeCharacter(char)
        char = char or LP.Character
        if not char then
            return
        end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hrp then
            hrp.Anchored = true
        end
        if hum then
            hum.WalkSpeed = 0
            hum.JumpPower = 0
            pcall(function()
                hum.JumpHeight = 0
            end)
            hum.AutoRotate = false
        end
    end

    LP.CharacterAdded:Connect(function(char)
        task.defer(function()
            task.wait(0.4)
            if CONFIG.HideTerrain or CONFIG.LowRam then
                freezeCharacter(char)
            end
        end)
    end)

    local hiddenObjectsBackup = {}
    local terrainBackup = nil

    applyHideTerrain = function(on)
        if on then
            if terrainOn then
                return
            end
            freezeCharacter()

            -- ซ่อน Terrain แบบไม่ลบ (ซ่อนชั่วคราว)
            pcall(function()
                local t = workspace:FindFirstChildOfClass("Terrain") or workspace.Terrain
                if t then
                    terrainBackup = {
                        Decoration = t.Decoration,
                        WaterWaveSize = t.WaterWaveSize,
                        WaterWaveSpeed = t.WaterWaveSpeed,
                        WaterReflectance = t.WaterReflectance,
                        WaterTransparency = t.WaterTransparency,
                        Transparency = pcall(function() return t.Transparency end) and t.Transparency or nil,
                    }
                    t.Decoration = false
                    t.WaterWaveSize = 0
                    t.WaterWaveSpeed = 0
                    t.WaterReflectance = 0
                    t.WaterTransparency = 1
                    pcall(function()
                        t.Transparency = 1
                    end)
                end
            end)

            -- ซ่อน Objects / Models ของแมพใน workspace (เก็บ backup เพื่อกู้คืนเมื่อปิด)
            hiddenObjectsBackup = {}
            pcall(function()
                for _, obj in ipairs(workspace:GetChildren()) do
                    -- ไม่ซ่อน ตัวละคร, กล้อง, Terrain
                    if obj ~= workspace.CurrentCamera
                        and not obj:IsA("Terrain")
                        and not Players:GetPlayerFromCharacter(obj)
                    then
                        -- โฟลเดอร์/โมเดลแมพ อาหาร ทรัพยากร สิ่งก่อสร้าง
                        if obj:IsA("Folder") or obj:IsA("Model") or obj:IsA("BasePart") then
                            -- ถ้าเป็น BasePart
                            if obj:IsA("BasePart") then
                                table.insert(hiddenObjectsBackup, {
                                    inst = obj,
                                    prop = "Transparency",
                                    val = obj.Transparency
                                })
                                obj.Transparency = 1
                            else
                                -- สำหรับ Model / Folder ซ่อนลูกที่เป็น BasePart / Decal / Particle
                                for _, desc in ipairs(obj:GetDescendants()) do
                                    if desc:IsA("BasePart") then
                                        table.insert(hiddenObjectsBackup, {
                                            inst = desc,
                                            prop = "Transparency",
                                            val = desc.Transparency
                                        })
                                        desc.Transparency = 1
                                    elseif desc:IsA("Decal") or desc:IsA("Texture") then
                                        table.insert(hiddenObjectsBackup, {
                                            inst = desc,
                                            prop = "Transparency",
                                            val = desc.Transparency
                                        })
                                        desc.Transparency = 1
                                    elseif desc:IsA("ParticleEmitter") or desc:IsA("Beam") or desc:IsA("Trail") or desc:IsA("Fire") or desc:IsA("Smoke") or desc:IsA("Sparkles") then
                                        table.insert(hiddenObjectsBackup, {
                                            inst = desc,
                                            prop = "Enabled",
                                            val = desc.Enabled
                                        })
                                        desc.Enabled = false
                                    end
                                end
                            end
                        end
                    end
                end
            end)

            terrainOn = true
        else
            if not terrainOn then
                return
            end

            -- กู้คืน Terrain
            pcall(function()
                local t = workspace:FindFirstChildOfClass("Terrain") or workspace.Terrain
                if t and terrainBackup then
                    t.Decoration = terrainBackup.Decoration ~= nil and terrainBackup.Decoration or true
                    t.WaterWaveSize = terrainBackup.WaterWaveSize or 0.15
                    t.WaterWaveSpeed = terrainBackup.WaterWaveSpeed or 10
                    t.WaterReflectance = terrainBackup.WaterReflectance or 0.05
                    t.WaterTransparency = terrainBackup.WaterTransparency or 0.3
                    pcall(function()
                        if terrainBackup.Transparency ~= nil then
                            t.Transparency = terrainBackup.Transparency
                        end
                    end)
                end
                terrainBackup = nil
            end)

            -- คืนค่า Object / Part ทั้งหมดที่ถูกซ่อนไว้
            pcall(function()
                for _, item in ipairs(hiddenObjectsBackup) do
                    if item.inst and item.inst.Parent then
                        pcall(function()
                            item.inst[item.prop] = item.val
                        end)
                    end
                end
                hiddenObjectsBackup = {}
            end)

            terrainOn = false
        end
    end

    applyLowRam = function(on)
        if on then
            if lowRamOn then
                return
            end
            freezeCharacter()
            pcall(function()
                RunService:Set3dRenderingEnabled(false)
            end)
            pcall(function()
                if setfpscap then
                    setfpscap(30)
                end
            end)
            pcall(function()
                settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            end)
            pcall(function()
                lightingBackup = {
                    GlobalShadows = Lighting.GlobalShadows,
                    FogEnd = Lighting.FogEnd,
                    Brightness = Lighting.Brightness,
                    effects = {},
                }
                Lighting.GlobalShadows = false
                Lighting.FogEnd = 0
                Lighting.Brightness = 0
                for _, eff in ipairs(Lighting:GetChildren()) do
                    if eff:IsA("PostEffect") then
                        table.insert(lightingBackup.effects, {obj = eff, enabled = eff.Enabled})
                        eff.Enabled = false
                    elseif eff:IsA("Atmosphere") then
                        table.insert(lightingBackup.effects, {obj = eff, density = eff.Density})
                        eff.Density = 0
                    end
                end
            end)
            lowRamOn = true
        else
            if not lowRamOn then
                return
            end
            pcall(function()
                RunService:Set3dRenderingEnabled(true)
            end)
            pcall(function()
                if setfpscap then
                    setfpscap(60)
                end
            end)
            pcall(function()
                settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
            end)
            pcall(function()
                if lightingBackup then
                    Lighting.GlobalShadows = lightingBackup.GlobalShadows
                    Lighting.FogEnd = lightingBackup.FogEnd
                    Lighting.Brightness = lightingBackup.Brightness
                    for _, data in ipairs(lightingBackup.effects or {}) do
                        if data.obj then
                            if data.enabled ~= nil then
                                data.obj.Enabled = data.enabled
                            elseif data.density ~= nil then
                                data.obj.Density = data.density
                            end
                        end
                    end
                end
                lightingBackup = nil
            end)
            lowRamOn = false
        end
    end
end

do
    local idleConn = nil
    local nudgeToken = nil

    local function pokeIdle()
        pcall(function()
            local vu = game:GetService("VirtualUser")
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end)
        pcall(function()
            local cam = workspace.CurrentCamera
            if cam then
                local vu = game:GetService("VirtualUser")
                vu:Button2Down(Vector2.new(0, 0), cam.CFrame)
                task.wait(0.1)
                vu:Button2Up(Vector2.new(0, 0), cam.CFrame)
            end
        end)
    end

    applyAntiAfk = function(on)
        if idleConn then
            idleConn:Disconnect()
            idleConn = nil
        end
        nudgeToken = nil
        if not on then
            return
        end
        idleConn = LP.Idled:Connect(function()
            task.spawn(pokeIdle)
        end)
        local token = {}
        nudgeToken = token
        task.spawn(function()
            while nudgeToken == token do
                task.wait(90)
                if nudgeToken == token and CONFIG.AntiAfk then
                    pokeIdle()
                end
            end
        end)
    end
end

-- ============================================================
-- [3] GUI
-- ============================================================
local existing = CoreGui:FindFirstChild("RuajadStorageTrade")
if existing then
    existing:Destroy()
end

local function create(className, props)
    local obj = Instance.new(className)
    for k, v in pairs(props) do
        obj[k] = v
    end
    return obj
end

local sg = create("ScreenGui", {
    Name = "RuajadStorageTrade",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = CoreGui,
})

local win = create("Frame", {
    Name = "Main",
    Size = UDim2.new(0, 320, 0, 468),
    Position = UDim2.new(0, 20, 0.5, -234),
    BackgroundColor3 = Color3.fromRGB(16, 16, 20),
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Parent = sg,
})
create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = win})
create("UIStroke", {Color = Color3.fromRGB(40, 42, 52), Thickness = 1, Parent = win})

local top = create("Frame", {
    Size = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = Color3.fromRGB(12, 12, 16),
    BorderSizePixel = 0,
    Parent = win,
})
create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = top})
create("Frame", {
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = Color3.fromRGB(12, 12, 16),
    BorderSizePixel = 0,
    Parent = top,
})
create("TextLabel", {
    Size = UDim2.new(1, -48, 1, 0),
    Position = UDim2.new(0, 12, 0, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = Color3.fromRGB(240, 240, 245),
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "STORAGE TRADE",
    Parent = top,
})

local WIN_OPEN = UDim2.new(0, 320, 0, 468)
local WIN_MIN = UDim2.new(0, 320, 0, 36)
local guiMinimized = false
local minBtn = create("TextButton", {
    Size = UDim2.new(0, 28, 0, 22),
    Position = UDim2.new(1, -34, 0.5, -11),
    BackgroundColor3 = Color3.fromRGB(28, 28, 36),
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextColor3 = Color3.fromRGB(220, 220, 230),
    Text = "–",
    AutoButtonColor = true,
    ZIndex = 2,
    Parent = top,
})
create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = minBtn})
minBtn.MouseButton1Click:Connect(function()
    guiMinimized = not guiMinimized
    win.Size = guiMinimized and WIN_MIN or WIN_OPEN
    minBtn.Text = guiMinimized and "+" or "–"
end)

local statusLbl = create("TextLabel", {
    Size = UDim2.new(1, -20, 0, 16),
    Position = UDim2.new(0, 12, 0, 42),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = Color3.fromRGB(140, 210, 255),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Text = "Idle",
    Parent = win,
})

local slotWarnLbl = create("TextLabel", {
    Size = UDim2.new(1, -20, 0, 14),
    Position = UDim2.new(0, 12, 0, 56),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextColor3 = Color3.fromRGB(255, 170, 90),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Text = "",
    Parent = win,
})

local function setStatus(text)
    statusLbl.Text = tostring(text or "Idle")
end

do
    local dragging = false
    local dragStart, startPos
    local UIS = game:GetService("UserInputService")
    local skipDrag = false
    minBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            skipDrag = true
        end
    end)
    top.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if skipDrag then
            skipDrag = false
            return
        end
        dragging = true
        dragStart = input.Position
        startPos = win.Position
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local function makeToggle(y, label, value, onChange)
    local row = create("Frame", {
        Size = UDim2.new(1, -24, 0, 26),
        Position = UDim2.new(0, 12, 0, y),
        BackgroundTransparency = 1,
        Parent = win,
    })
    create("TextLabel", {
        Size = UDim2.new(1, -50, 1, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Color3.fromRGB(210, 210, 215),
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = label,
        Parent = row,
    })
    local sw = create("TextButton", {
        Size = UDim2.new(0, 42, 0, 20),
        Position = UDim2.new(1, -42, 0.5, -10),
        BackgroundColor3 = value and ACCENT or Color3.fromRGB(50, 50, 55),
        Text = "",
        BorderSizePixel = 0,
        Parent = row,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = sw})
    local knob = create("Frame", {
        Size = UDim2.new(0, 16, 0, 16),
        Position = value and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Parent = sw,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 8), Parent = knob})
    local active = value
    local function set(state)
        active = state
        TweenService:Create(knob, TweenInfo.new(0.2), {
            Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
        }):Play()
        TweenService:Create(sw, TweenInfo.new(0.2), {
            BackgroundColor3 = state and ACCENT or Color3.fromRGB(50, 50, 55),
        }):Play()
        onChange(state)
    end
    sw.MouseButton1Click:Connect(function()
        set(not active)
    end)
    return { Set = set }
end

makeToggle(74, "Enable Auto Accept", CONFIG.Enabled, function(state)
    CONFIG.Enabled = state
    saveConfig()
    setStatus(state and "Accepting..." or "Paused")
end)

makeToggle(102, "Hide Terrain", CONFIG.HideTerrain, function(state)
    CONFIG.HideTerrain = state
    saveConfig()
    applyHideTerrain(state)
end)

-- makeToggle(130, "Low RAM (3D off / low graphics)", CONFIG.LowRam, function(state)
--     CONFIG.LowRam = state
--     saveConfig()
--     applyLowRam(state)
-- end)

makeToggle(130, "Anti-AFK", CONFIG.AntiAfk, function(state)
    CONFIG.AntiAfk = state
    saveConfig()
    applyAntiAfk(state)
end)

create("TextLabel", {
    Size = UDim2.new(0.55, -12, 0, 14),
    Position = UDim2.new(0, 12, 0, 190),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = Color3.fromRGB(140, 140, 150),
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "Slot ID (match main)",
    Parent = win,
})

local slotBox = create("TextBox", {
    Size = UDim2.new(0, 72, 0, 24),
    Position = UDim2.new(1, -84, 0, 186),
    BackgroundColor3 = Color3.fromRGB(24, 24, 30),
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Text = tostring(CONFIG.SlotId),
    ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Center,
    Parent = win,
})
create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = slotBox})
create("UIStroke", {Color = Color3.fromRGB(45, 45, 55), Thickness = 1, Parent = slotBox})

create("TextLabel", {
    Size = UDim2.new(1, -24, 0, 14),
    Position = UDim2.new(0, 12, 0, 220),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = Color3.fromRGB(140, 140, 150),
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "Main account usernames",
    Parent = win,
})

local nameScroll = create("ScrollingFrame", {
    Size = UDim2.new(1, -24, 0, 132),
    Position = UDim2.new(0, 12, 0, 234),
    BackgroundColor3 = Color3.fromRGB(20, 20, 26),
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Parent = win,
})
create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = nameScroll})
local nameLayout = Instance.new("UIListLayout")
nameLayout.SortOrder = Enum.SortOrder.LayoutOrder
nameLayout.Padding = UDim.new(0, 4)
nameLayout.Parent = nameScroll
create("UIPadding", {
    PaddingTop = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
    Parent = nameScroll,
})

local rebuildNameRows
local writeJoinBeacon

rebuildNameRows = function()
    for _, child in ipairs(nameScroll:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    if type(CONFIG.MainUsernames) ~= "table" or #CONFIG.MainUsernames == 0 then
        CONFIG.MainUsernames = { "" }
    end
    for i, name in ipairs(CONFIG.MainUsernames) do
        local row = create("Frame", {
            Size = UDim2.new(1, -8, 0, 28),
            BackgroundTransparency = 1,
            LayoutOrder = i,
            Parent = nameScroll,
        })
        local box = create("TextBox", {
            Size = UDim2.new(1, -32, 1, 0),
            BackgroundColor3 = Color3.fromRGB(24, 24, 30),
            BorderSizePixel = 0,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            PlaceholderColor3 = Color3.fromRGB(110, 110, 120),
            PlaceholderText = "farmer username",
            Text = tostring(name or ""),
            ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })
        create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = box})
        create("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = box})
        box.FocusLost:Connect(function()
            CONFIG.MainUsernames[i] = tostring(box.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            box.Text = CONFIG.MainUsernames[i]
            saveConfig()
            local n = #cleanedMains()
            setStatus(n > 0 and ("Watching " .. n .. " main(s)") or "Add a main username")
        end)
        local del = create("TextButton", {
            Size = UDim2.new(0, 26, 1, 0),
            Position = UDim2.new(1, -26, 0, 0),
            BackgroundColor3 = Color3.fromRGB(40, 22, 24),
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = Color3.fromRGB(255, 130, 130),
            Text = "x",
            AutoButtonColor = true,
            Parent = row,
        })
        create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = del})
        del.MouseButton1Click:Connect(function()
            if #CONFIG.MainUsernames <= 1 then
                CONFIG.MainUsernames = { "" }
            else
                table.remove(CONFIG.MainUsernames, i)
            end
            saveConfig()
            rebuildNameRows()
        end)
    end
end

rebuildNameRows()

local addBtn = create("TextButton", {
    Size = UDim2.new(1, -24, 0, 26),
    Position = UDim2.new(0, 12, 0, 372),
    BackgroundColor3 = Color3.fromRGB(28, 40, 56),
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(160, 210, 255),
    Text = "+ Add main username",
    AutoButtonColor = true,
    Parent = win,
})
create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = addBtn})
addBtn.MouseButton1Click:Connect(function()
    table.insert(CONFIG.MainUsernames, "")
    saveConfig()
    rebuildNameRows()
end)

create("TextLabel", {
    Size = UDim2.new(1, -24, 0, 40),
    Position = UDim2.new(0, 12, 0, 404),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextColor3 = Color3.fromRGB(110, 115, 125),
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
    Text = "Queue: only one trade at a time. Main Slot ID must match this window. Duplicate Slot ID = last writer wins.",
    Parent = win,
})

local applySlotId
applySlotId = function(newId)
    newId = clampSlotId(newId)
    if newId == CONFIG.SlotId then
        slotBox.Text = tostring(CONFIG.SlotId)
        return
    end
    saveConfig()
    CONFIG.SlotId = newId
    pcall(function()
        local path = configPath(newId)
        if typeof(isfile) == "function" and isfile(path) then
            applySaved(HttpService:JSONDecode(readfile(path)))
            CONFIG.SlotId = newId
        end
    end)
    slotBox.Text = tostring(CONFIG.SlotId)
    saveConfig()
    rebuildNameRows()
    if writeJoinBeacon then
        pcall(writeJoinBeacon)
    end
end

slotBox.FocusLost:Connect(function()
    applySlotId(slotBox.Text)
end)

-- ============================================================
-- [4] QUEUE + TRADE ACCEPT
-- busy = มี *TradeRemote — ยิง Accept เฉพาะหัวคิว / คนที่กำลังเทรด
-- ============================================================
local session = {
    phase = "idle",
    remoteName = nil,
    phaseAt = 0,
}
local WAIT_ITEMS_SEC = 3.5
local TICK_SEC = 10
local lastHadRemote = false
local farmerSeenAt = 0
local tradingWith = nil -- ชื่อคนที่หน้าต่างเทรดเปิดอยู่
local waitQueue = {} -- ชื่อคนรอ (FIFO)

local function findPlayerByName(name)
    local want = normalizeName(name)
    if want == "" then
        return nil
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and normalizeName(plr.Name) == want then
            return plr
        end
    end
    return nil
end

local function queueHas(name)
    local k = normalizeName(name)
    for _, n in ipairs(waitQueue) do
        if normalizeName(n) == k then
            return true
        end
    end
    return false
end

local function enqueue(plr)
    if not (plr and plr.Parent) then
        return
    end
    if not isAllowedMain(plr.Name) then
        return
    end
    if tradingWith and normalizeName(tradingWith) == normalizeName(plr.Name) then
        return
    end
    if queueHas(plr.Name) then
        return
    end
    table.insert(waitQueue, plr.Name)
end

local function dequeueName(name)
    local k = normalizeName(name)
    local out = {}
    for _, n in ipairs(waitQueue) do
        if normalizeName(n) ~= k then
            table.insert(out, n)
        end
    end
    waitQueue = out
end

-- ดึงคนที่ยังอยู่ในเซิร์ฟออกจากหัวคิว
local function queueHead()
    while #waitQueue > 0 do
        local name = waitQueue[1]
        local plr = findPlayerByName(name)
        if plr then
            return plr
        end
        table.remove(waitQueue, 1)
    end
    return nil
end

local function parseTradePartner(remoteName)
    local n = tostring(remoteName or "")
    n = string.gsub(n, "TradeRemote$", "")
    local a, b = string.match(n, "^(.-)%-(.+)$")
    if not a then
        return nil
    end
    if normalizeName(a) == normalizeName(LP.Name) then
        return b
    end
    if normalizeName(b) == normalizeName(LP.Name) then
        return a
    end
    return nil
end

local function findTradeRemote(farmer)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes or not farmer then
        return nil
    end
    local a, b = LP.Name, farmer.Name
    return remotes:FindFirstChild(a .. "-" .. b .. "TradeRemote")
        or remotes:FindFirstChild(b .. "-" .. a .. "TradeRemote")
end

local function fireAcceptRequest(farmer)
    local folder = farmer:FindFirstChild("Remotes")
    local remote = folder and folder:FindFirstChild("TradeRequestRemote")
    if remote and remote:IsA("RemoteEvent") then
        remote:FireServer("AcceptRequest")
    end
end

local function fireAcceptTradeAsync(farmer)
    local remote = findTradeRemote(farmer)
    if not remote then
        return false
    end
    task.spawn(function()
        pcall(function()
            if remote:IsA("RemoteFunction") then
                remote:InvokeServer("AcceptTrade")
            elseif remote:IsA("RemoteEvent") then
                remote:FireServer("AcceptTrade")
            end
        end)
    end)
    return true
end

local function beginWaitItems(remote)
    session.phase = "wait_items"
    session.remoteName = remote and remote.Name or nil
    session.phaseAt = os.clock()
    local partner = remote and parseTradePartner(remote.Name)
    if partner then
        tradingWith = partner
        dequeueName(partner)
        pcall(writeJoinBeacon)
    end
end

local function clearBusy()
    tradingWith = nil
    session.phase = "idle"
    session.remoteName = nil
    session.phaseAt = 0
    lastHadRemote = false
    pcall(writeJoinBeacon)
end

pcall(function()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotes then
        return
    end
    remotes.ChildAdded:Connect(function(child)
        if type(child.Name) ~= "string" or not string.find(child.Name, "TradeRemote", 1, true) then
            return
        end
        beginWaitItems(child)
    end)
    remotes.ChildRemoved:Connect(function(child)
        if session.remoteName and child.Name == session.remoteName then
            clearBusy()
        end
    end)
end)

pcall(function()
    local folder = LP:FindFirstChild("Remotes") or LP:WaitForChild("Remotes", 8)
    local ev = folder and folder:FindFirstChild("TradeStatusRemote")
    if ev and ev:IsA("RemoteEvent") then
        ev.OnClientEvent:Connect(function()
            if session.phase ~= "idle" and session.phase ~= "done" then
                return
            end
            if session.phase == "done" and (os.clock() - session.phaseAt) < 3 then
                return
            end
            local farmer = tradingWith and findPlayerByName(tradingWith) or queueHead()
            local remote = farmer and findTradeRemote(farmer)
            if remote then
                beginWaitItems(remote)
            end
        end)
    end
end)

pcall(function()
    Players.PlayerAdded:Connect(function(plr)
        if not isAllowedMain(plr.Name) then
            return
        end
        farmerSeenAt = os.clock()
        enqueue(plr)
        -- ถ้าว่างอยู่ ค่อยยิง Accept หัวคิว — ห้ามยิงตอน busy (unable to trade)
        if not tradingWith then
            task.spawn(function()
                for _ = 1, 12 do
                    if tradingWith then
                        break
                    end
                    local head = queueHead()
                    if not (head and head == plr) then
                        break
                    end
                    pcall(fireAcceptRequest, plr)
                    task.wait(0.4)
                end
            end)
        end
    end)
    Players.PlayerRemoving:Connect(function(plr)
        dequeueName(plr.Name)
        if tradingWith and normalizeName(tradingWith) == normalizeName(plr.Name) then
            clearBusy()
        end
    end)
end)

-- คนที่อยู่ในเซิร์ฟแล้วตอนโหลดสคริปต์
task.defer(function()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and isAllowedMain(plr.Name) then
            enqueue(plr)
        end
    end
end)

task.spawn(function()
    while sg and sg.Parent do
        local burst = farmerSeenAt > 0 and (os.clock() - farmerSeenAt) < 20
        local waitSec = burst and 0.45 or math.clamp(tonumber(CONFIG.AcceptInterval) or 2, 1, 10)
        if CONFIG.Enabled then
            -- เก็บคนที่อนุญาตและอยู่ในเซิร์ฟเข้าคิว
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and isAllowedMain(plr.Name) then
                    enqueue(plr)
                end
            end

            local mains = cleanedMains()
            if #mains == 0 then
                lastHadRemote = false
                setStatus("Add a main username")
            else
                local farmer = tradingWith and findPlayerByName(tradingWith) or nil
                if tradingWith and not farmer then
                    clearBusy()
                end
                if not farmer then
                    farmer = queueHead()
                end

                if farmer then
                    local isHead = (not tradingWith) or (normalizeName(tradingWith) == normalizeName(farmer.Name))
                    -- ยิง AcceptRequest เฉพาะหัวคิว และตอนยังไม่มีหน้าต่าง
                    if isHead and not tradingWith then
                        pcall(fireAcceptRequest, farmer)
                    end

                    local remote = findTradeRemote(farmer)
                    if remote and not lastHadRemote then
                        if session.phase == "idle" or session.phase == "done" then
                            beginWaitItems(remote)
                        end
                    end
                    if tradingWith and remote then
                        if session.phase == "idle" then
                            setStatus("Waiting next  ·  " .. farmer.Name)
                        elseif session.phase == "wait_items" then
                            if os.clock() - session.phaseAt >= WAIT_ITEMS_SEC then
                                session.phase = "tick"
                                session.phaseAt = os.clock()
                            else
                                setStatus("Busy  ·  wait items  ·  " .. farmer.Name)
                            end
                        end
                        if session.phase == "tick" then
                            if os.clock() - session.phaseAt <= TICK_SEC then
                                pcall(fireAcceptTradeAsync, farmer)
                                setStatus("Busy  ·  tick  ·  " .. farmer.Name)
                            else
                                session.phase = "done"
                                session.phaseAt = os.clock()
                                setStatus("Trade done  ·  " .. farmer.Name)
                            end
                        elseif session.phase == "done" then
                            setStatus("Busy  ·  finishing  ·  " .. farmer.Name)
                        end
                    elseif farmer then
                        local qn = #waitQueue
                        if tradingWith then
                            setStatus("Busy  ·  " .. tostring(tradingWith) .. "  ·  queue " .. tostring(qn))
                        else
                            setStatus("Queue head  ·  " .. farmer.Name .. (qn > 1 and ("  ·  +" .. tostring(qn - 1)) or ""))
                        end
                    end
                    lastHadRemote = remote ~= nil
                else
                    lastHadRemote = false
                    setStatus("Slot #" .. tostring(CONFIG.SlotId) .. "  ·  waiting mains")
                end
            end
        else
            setStatus("Paused")
        end
        task.wait(waitSec)
    end
end)

-- ============================================================
-- [5] JOIN BEACON (สำรองเขียนอย่างเดียว)
-- ============================================================
writeJoinBeacon = function()
    if typeof(isfolder) == "function" and not isfolder("RuajadHub") then
        makefolder("RuajadHub")
    end
    if typeof(writefile) ~= "function" then
        return
    end
    local slot = clampSlotId(CONFIG.SlotId)
    local path = joinPath(slot)
    local warnTxt = ""
    pcall(function()
        if typeof(isfile) == "function" and isfile(path) then
            local prev = HttpService:JSONDecode(readfile(path))
            if type(prev) == "table" then
                local age = os.time() - (tonumber(prev.t) or 0)
                local otherId = tonumber(prev.userId)
                if otherId and otherId ~= LP.UserId and age <= 180 then
                    warnTxt = "Slot #" .. tostring(slot) .. " in use by " .. tostring(prev.username) .. " (last writer wins)"
                end
            end
        end
    end)
    slotWarnLbl.Text = warnTxt

    local qcopy = {}
    for _, n in ipairs(waitQueue) do
        table.insert(qcopy, n)
    end
    local payload = {
        slotId = slot,
        username = LP.Name,
        userId = LP.UserId,
        placeId = game.PlaceId,
        jobId = game.JobId,
        t = os.time(),
        busy = tradingWith ~= nil,
        tradingWith = tradingWith,
        queue = qcopy,
    }
    writefile(path, HttpService:JSONEncode(payload))
    -- slot 1: ไฟล์ชื่อเดิมสำหรับหลักที่ยังไม่อัปเดต
    if slot == 1 then
        writefile("RuajadHub/StorageJoinTarget.json", HttpService:JSONEncode(payload))
    end
end

pcall(writeJoinBeacon)
print("[Ruajad] Join beacon → " .. joinPath(CONFIG.SlotId) .. " placeId=" .. tostring(game.PlaceId) .. " jobId=" .. tostring(game.JobId))

task.spawn(function()
    while sg and sg.Parent do
        pcall(writeJoinBeacon)
        task.wait(5)
    end
end)

do
    local n = #cleanedMains()
    setStatus(CONFIG.Enabled and (n > 0 and ("Watching " .. n .. " main(s)  ·  slot #" .. tostring(CONFIG.SlotId)) or "Add a main username") or "Paused")
end

pcall(function()
    if CONFIG.HideTerrain then
        applyHideTerrain(true)
    end
    -- if CONFIG.LowRam then
    --     applyLowRam(true)
    -- end
    if CONFIG.AntiAfk then
        applyAntiAfk(true)
    end
end)

print("[Ruajad] Storage Trade loaded — BACKUP  slot #" .. tostring(CONFIG.SlotId))
