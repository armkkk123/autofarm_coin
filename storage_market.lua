--[[
================================================================================
  DRAGON ADVENTURES  |  RUAJAD HUB - Storage Market (Main Account)
================================================================================

  หน้าที่
  --------
  - รันบนไอดีหลักที่อยู่ใน Undercity Market
  - ตั้งบอร์ดขายสินค้าใน Player Market (ไม่เกิน 5 ช่อง)
  - คอยเติมบอร์ดโดยอัตโนมัติเมื่อช่องว่างลดลง (ตรวจ SalesLabel)
  - เขียน Beacon ไฟล์ให้บอทฟาร์มรู้ว่า jobId ของตัวหลักอยู่ที่ไหน
  - เมื่อบอทมาซื้อสำเร็จ จะเติมบอร์ดใหม่อัตโนมัติ

  Beacon file : RuajadHub/MarketBeacon.json
  Config file  : RuajadHub/StorageMarket.json

  GUI Path ตรวจสอบบอร์ด:
    PlayerGui.PlayerMarketGui.ContainerFrame.TabFrames.MySales.SalesLabel
    Text เช่น "2/5" (ช่องที่กำลังขาย / สูงสุด)

  Remote ที่ใช้:
    SellPlayerMarketRemote:InvokeServer({Price=..., ItemType="Resources", Name="Carrot", Amount=1})
================================================================================
]]

-- ============================================================
-- [1] SERVICES
-- ============================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local CoreGui           = game:GetService("CoreGui")

local LP = Players.LocalPlayer

-- ============================================================
-- [2] CONFIG
-- ============================================================
local CONFIG = {
    Enabled               = false,
    BoardPrice            = 100000,
    ItemName              = "Apple",
    ItemType              = "Food",
    MaxSlots              = 5,
    AutoRefillEnabled     = true,
    RefillCheckInterval   = 3,
    HideTerrain           = true,
    AntiAfk               = true,
}

local ACCENT = Color3.fromRGB(255, 160, 50)

local function configPath()  return "RuajadHub/StorageMarket.json" end
local function beaconPath()  return "RuajadHub/MarketBeacon.json"  end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function applySaved(data)
    if type(data) ~= "table" then return end
    if data.Enabled               ~= nil then CONFIG.Enabled               = data.Enabled and true or false end
    if data.BoardPrice            ~= nil then CONFIG.BoardPrice            = math.max(1, tonumber(data.BoardPrice) or CONFIG.BoardPrice) end
    if data.ItemName              ~= nil then CONFIG.ItemName              = tostring(data.ItemName) end
    if data.ItemType              ~= nil then CONFIG.ItemType              = tostring(data.ItemType) end
    if data.MaxSlots              ~= nil then CONFIG.MaxSlots              = clamp(math.floor(tonumber(data.MaxSlots) or 5), 1, 5) end
    if data.AutoRefillEnabled     ~= nil then CONFIG.AutoRefillEnabled     = data.AutoRefillEnabled and true or false end
    if data.RefillCheckInterval   ~= nil then CONFIG.RefillCheckInterval   = clamp(tonumber(data.RefillCheckInterval) or 3, 1, 60) end
    if data.HideTerrain           ~= nil then CONFIG.HideTerrain           = data.HideTerrain and true or false end
    if data.AntiAfk               ~= nil then CONFIG.AntiAfk               = data.AntiAfk and true or false end
end

pcall(function()
    if typeof(getgenv) == "function" and type(getgenv().RuajadStorageMarket) == "table" then
        applySaved(getgenv().RuajadStorageMarket)
    end
end)
pcall(function()
    if typeof(isfile) == "function" and isfile(configPath()) then
        applySaved(HttpService:JSONDecode(readfile(configPath())))
    end
end)

local function saveConfig()
    pcall(function()
        local snap = {
            Enabled = CONFIG.Enabled, BoardPrice = CONFIG.BoardPrice,
            ItemName = CONFIG.ItemName, ItemType = CONFIG.ItemType,
            MaxSlots = CONFIG.MaxSlots, AutoRefillEnabled = CONFIG.AutoRefillEnabled,
            RefillCheckInterval = CONFIG.RefillCheckInterval,
            HideTerrain = CONFIG.HideTerrain, AntiAfk = CONFIG.AntiAfk,
        }
        if typeof(getgenv) == "function" then getgenv().RuajadStorageMarket = snap end
        if typeof(isfolder) == "function" and not isfolder("RuajadHub") then makefolder("RuajadHub") end
        if typeof(writefile) == "function" then writefile(configPath(), HttpService:JSONEncode(snap)) end
    end)
end
saveConfig()

-- ============================================================
-- [2b] HIDE TERRAIN / ANTI-AFK
-- ============================================================
local applyHideTerrain
local applyAntiAfk

do
    local terrainOn = false
    local hiddenBackup = {}
    local terrainWaterBackup = nil
    local hideConn = nil

    local function isPlayerDesc(inst)
        if not inst then return false end
        for _, plr in ipairs(Players:GetPlayers()) do
            local c = plr.Character
            if c and inst:IsDescendantOf(c) then return true end
        end
        return false
    end

    local function hideInst(inst)
        if not inst or isPlayerDesc(inst) then return end
        if inst:IsA("BasePart") then
            if hiddenBackup[inst] == nil then hiddenBackup[inst] = inst.LocalTransparencyModifier end
            pcall(function() inst.LocalTransparencyModifier = 1 end)
        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            if hiddenBackup[inst] == nil then hiddenBackup[inst] = inst.Transparency end
            pcall(function() inst.Transparency = 1 end)
        elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
            or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
            if hiddenBackup[inst] == nil then hiddenBackup[inst] = inst.Enabled end
            pcall(function() inst.Enabled = false end)
        end
    end

    applyHideTerrain = function(on)
        if on then
            if terrainOn then return end
            terrainOn = true
            pcall(function()
                local t = workspace:FindFirstChildOfClass("Terrain")
                if t then terrainWaterBackup = t.WaterTransparency; t.WaterTransparency = 1; t.Decoration = false end
            end)
            for _, obj in ipairs(workspace:GetDescendants()) do hideInst(obj) end
            if not hideConn then
                hideConn = workspace.DescendantAdded:Connect(function(obj)
                    if terrainOn then task.defer(function() hideInst(obj) end) end
                end)
            end
        else
            if not terrainOn then return end
            terrainOn = false
            if hideConn then hideConn:Disconnect(); hideConn = nil end
            pcall(function()
                local t = workspace:FindFirstChildOfClass("Terrain")
                if t then t.WaterTransparency = terrainWaterBackup or 0; t.Decoration = true end
            end)
            for inst, orig in pairs(hiddenBackup) do
                if inst and inst.Parent then
                    pcall(function()
                        if inst:IsA("BasePart") then inst.LocalTransparencyModifier = orig
                        elseif inst:IsA("Decal") or inst:IsA("Texture") then inst.Transparency = orig
                        elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
                            or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then inst.Enabled = orig
                        end
                    end)
                end
            end
            table.clear(hiddenBackup)
        end
    end

    local afkToken = 0
    applyAntiAfk = function(on)
        afkToken = afkToken + 1
        local token = afkToken
        if not on then return end
        task.spawn(function()
            while afkToken == token do
                task.wait(55)
                if afkToken ~= token then break end
                pcall(function()
                    local vjump = game:GetService("VirtualUser")
                    vjump:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                    task.wait(0.1)
                    vjump:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                end)
            end
        end)
    end
end

-- ============================================================
-- [3] GUI
-- ============================================================
local function getSafeGuiParent()
    local ok, res = pcall(function()
        if typeof(gethui) == "function" then
            return gethui()
        end
        local cg = game:GetService("CoreGui")
        local _ = cg.Name
        return cg
    end)
    if ok and res then return res end
    return LP:WaitForChild("PlayerGui")
end

local parentGui = getSafeGuiParent()
pcall(function()
    local existing = parentGui:FindFirstChild("RuajadStorageMarket")
    if existing then existing:Destroy() end
end)

local function create(cls, props)
    local obj = Instance.new(cls)
    for k, v in pairs(props) do obj[k] = v end
    return obj
end

local sg = create("ScreenGui", {
    Name = "RuajadStorageMarket", ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 200, Parent = parentGui,
})

local WIN_OPEN = UDim2.new(0, 560, 0, 390)
local WIN_MIN  = UDim2.new(0, 560, 0, 38)
local guiMin   = false

local win = create("Frame", {
    Name = "Main", Size = WIN_OPEN,
    Position = UDim2.new(0, 25, 0.5, -195),
    BackgroundColor3 = Color3.fromRGB(14, 14, 18), BorderSizePixel = 0,
    ClipsDescendants = false, Parent = sg,
})
create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = win})
create("UIStroke", {Color = Color3.fromRGB(80, 55, 20), Thickness = 1.2, Parent = win})

-- Top bar
local top = create("Frame", {
    Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Color3.fromRGB(20, 15, 8),
    BorderSizePixel = 0, Parent = win,
})
create("UICorner", {CornerRadius = UDim.new(0, 10), Parent = top})
create("Frame", {
    Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = Color3.fromRGB(20, 15, 8), BorderSizePixel = 0, Parent = top,
})
create("Frame", {
    Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = ACCENT,
    BorderSizePixel = 0, Parent = top,
})
create("TextLabel", {
    Size = UDim2.new(1, -50, 1, 0), Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13,
    TextColor3 = Color3.fromRGB(255, 200, 100), TextXAlignment = Enum.TextXAlignment.Left,
    Text = "💰  STORAGE MARKET", Parent = top,
})

local bodyFrame = create("Frame", {
    Name = "Body", Size = UDim2.new(1, 0, 1, -38),
    Position = UDim2.new(0, 0, 0, 38),
    BackgroundTransparency = 1,
    Visible = true, Parent = win,
})

local minBtn = create("TextButton", {
    Size = UDim2.new(0, 28, 0, 22), Position = UDim2.new(1, -34, 0.5, -11),
    BackgroundColor3 = Color3.fromRGB(35, 26, 12), BorderSizePixel = 0,
    Font = Enum.Font.GothamBold, TextSize = 16,
    TextColor3 = Color3.fromRGB(220, 180, 100), Text = "–",
    AutoButtonColor = true, ZIndex = 2, Parent = top,
})
create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = minBtn})
minBtn.MouseButton1Click:Connect(function()
    guiMin = not guiMin
    win.Size = guiMin and WIN_MIN or WIN_OPEN
    bodyFrame.Visible = not guiMin
    minBtn.Text = guiMin and "+" or "–"
end)

-- Drag
do
    local UIS = game:GetService("UserInputService")
    local dragging, dragStart, startPos = false, nil, nil
    local skip = false
    minBtn.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then skip = true end end)
    top.InputBegan:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1 and i.UserInputType ~= Enum.UserInputType.Touch then return end
        if skip then skip = false; return end
        dragging = true; dragStart = i.Position; startPos = win.Position
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end end)
end

-- Status labels (Inside bodyFrame)
local statusLbl = create("TextLabel", {
    Size = UDim2.new(0.5, -20, 0, 16), Position = UDim2.new(0, 14, 0, 6),
    BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
    TextColor3 = Color3.fromRGB(160, 220, 140), TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd, Text = "Idle", Parent = bodyFrame,
})
local boardLbl = create("TextLabel", {
    Size = UDim2.new(0.5, -20, 0, 16), Position = UDim2.new(0.5, 6, 0, 6),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 11,
    TextColor3 = Color3.fromRGB(255, 180, 80), TextXAlignment = Enum.TextXAlignment.Right,
    Text = "Board: ?/?", Parent = bodyFrame,
})
local function setStatus(t)
    pcall(function()
        if statusLbl and statusLbl.Parent then
            statusLbl.Text = tostring(t or "Idle")
        end
    end)
end
local function setBoardText(t)
    pcall(function()
        if boardLbl and boardLbl.Parent then
            boardLbl.Text = tostring(t or "")
        end
    end)
end

-- Divider below status
create("Frame", {
    Size = UDim2.new(1, -28, 0, 1), Position = UDim2.new(0, 14, 0, 28),
    BackgroundColor3 = Color3.fromRGB(45, 35, 18), BorderSizePixel = 0, Parent = bodyFrame,
})

-- Two Columns Containers (Inside bodyFrame)
local leftCol = create("Frame", {
    Size = UDim2.new(0.5, -20, 0, 275), Position = UDim2.new(0, 14, 0, 36),
    BackgroundTransparency = 1, ZIndex = 2, Parent = bodyFrame,
})
local rightCol = create("Frame", {
    Size = UDim2.new(0.5, -20, 0, 275), Position = UDim2.new(0.5, 6, 0, 36),
    BackgroundTransparency = 1, ZIndex = 1, Parent = bodyFrame,
})

-- ============================================================
-- UI HELPERS (Column-aware)
-- ============================================================
local function secLabel(parent, y, text)
    create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, y),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 10,
        TextColor3 = Color3.fromRGB(140, 105, 50), TextXAlignment = Enum.TextXAlignment.Left,
        Text = text, Parent = parent,
    })
end

local function mkToggle(parent, y, label, value, onChange)
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, y),
        BackgroundColor3 = Color3.fromRGB(20, 20, 26), BorderSizePixel = 0, Parent = parent,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = row})
    create("UIStroke", {Color = Color3.fromRGB(45, 40, 22), Thickness = 1, Parent = row})
    create("TextLabel", {
        Size = UDim2.new(1, -50, 1, 0), Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
        TextColor3 = Color3.fromRGB(210, 210, 215), TextXAlignment = Enum.TextXAlignment.Left,
        Text = label, Parent = row,
    })
    local sw = create("TextButton", {
        Size = UDim2.new(0, 38, 0, 18), Position = UDim2.new(1, -44, 0.5, -9),
        BackgroundColor3 = value and ACCENT or Color3.fromRGB(48, 48, 54),
        Text = "", BorderSizePixel = 0, Parent = row,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 9), Parent = sw})
    local knob = create("Frame", {
        Size = UDim2.new(0, 14, 0, 14),
        Position = value and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, Parent = sw,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 7), Parent = knob})
    local active = value
    local function set(state)
        active = state
        TweenService:Create(knob, TweenInfo.new(0.2), {Position = state and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)}):Play()
        TweenService:Create(sw,   TweenInfo.new(0.2), {BackgroundColor3 = state and ACCENT or Color3.fromRGB(48,48,54)}):Play()
        onChange(state)
    end
    sw.MouseButton1Click:Connect(function() set(not active) end)
    return {Set = set}
end

local function mkNumInput(parent, y, label, value, minV, maxV, isInt, onChange)
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, y),
        BackgroundColor3 = Color3.fromRGB(20, 20, 26), BorderSizePixel = 0, Parent = parent,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = row})
    create("UIStroke", {Color = Color3.fromRGB(45, 40, 22), Thickness = 1, Parent = row})
    create("TextLabel", {
        Size = UDim2.new(1, -85, 1, 0), Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
        TextColor3 = Color3.fromRGB(185, 185, 200), TextXAlignment = Enum.TextXAlignment.Left,
        Text = label, Parent = row,
    })
    local box = create("TextBox", {
        Size = UDim2.new(0, 75, 0, 20), Position = UDim2.new(1, -79, 0.5, -10),
        BackgroundColor3 = Color3.fromRGB(14, 14, 18), BorderSizePixel = 0,
        Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = Color3.fromRGB(255, 200, 100),
        Text = tostring(value), ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Center, Parent = row,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = box})
    create("UIStroke", {Color = Color3.fromRGB(90, 65, 25), Thickness = 1, Parent = box})
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then
            if isInt then n = math.floor(n) end
            n = clamp(n, minV or -math.huge, maxV or math.huge)
            box.Text = tostring(n); onChange(n)
        else box.Text = tostring(value) end
    end)
    return {Set = function(v) value = v; box.Text = tostring(v) end}
end

local function mkTextInput(parent, y, label, value, ph, onChange)
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, y),
        BackgroundColor3 = Color3.fromRGB(20, 20, 26), BorderSizePixel = 0, Parent = parent,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = row})
    create("UIStroke", {Color = Color3.fromRGB(45, 40, 22), Thickness = 1, Parent = row})
    create("TextLabel", {
        Size = UDim2.new(0.38, 0, 1, 0), Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
        TextColor3 = Color3.fromRGB(185, 185, 200), TextXAlignment = Enum.TextXAlignment.Left,
        Text = label, Parent = row,
    })
    local box = create("TextBox", {
        Size = UDim2.new(0.58, -4, 0, 20), Position = UDim2.new(0.42, 0, 0.5, -10),
        BackgroundColor3 = Color3.fromRGB(14, 14, 18), BorderSizePixel = 0,
        Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = Color3.fromRGB(255, 200, 100),
        Text = tostring(value), ClearTextOnFocus = false,
        PlaceholderText = ph or "", TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = box})
    create("UIStroke", {Color = Color3.fromRGB(90, 65, 25), Thickness = 1, Parent = box})
    box.FocusLost:Connect(function()
        local t = box.Text:gsub("^%s+", ""):gsub("%s+$", "")
        if t ~= "" then onChange(t) end
    end)
    return {Set = function(v) box.Text = tostring(v) end}
end

local function mkDropdown(parent, y, label, options, current, onChange)
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, y),
        BackgroundColor3 = Color3.fromRGB(20, 20, 26), BorderSizePixel = 0,
        ZIndex = 1, Parent = parent,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = row})
    create("UIStroke", {Color = Color3.fromRGB(45, 40, 22), Thickness = 1, Parent = row})
    create("TextLabel", {
        Size = UDim2.new(0.38, 0, 1, 0), Position = UDim2.new(0, 8, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
        TextColor3 = Color3.fromRGB(185, 185, 200), TextXAlignment = Enum.TextXAlignment.Left,
        Text = label, ZIndex = 2, Parent = row,
    })
    
    local sel = current or options[1]
    local btn = create("TextButton", {
        Size = UDim2.new(0.58, -4, 0, 20), Position = UDim2.new(0.42, 0, 0.5, -10),
        BackgroundColor3 = Color3.fromRGB(14, 14, 18), BorderSizePixel = 0,
        Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = Color3.fromRGB(255, 200, 100),
        Text = sel .. "  ▼",
        ZIndex = 5,
        Parent = row,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = btn})
    create("UIStroke", {Color = Color3.fromRGB(90, 65, 25), Thickness = 1, Parent = btn})

    local listOpen = false
    local listH = #options * 24 + 4
    local listFrame = create("Frame", {
        Name = "DropdownList",
        Size = UDim2.new(0.58, -4, 0, listH),
        Position = UDim2.new(0.42, 0, 1, 2),
        BackgroundColor3 = Color3.fromRGB(18, 18, 22),
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 150,
        Parent = row,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 4), Parent = listFrame})
    create("UIStroke", {Color = Color3.fromRGB(110, 85, 35), Thickness = 1, Parent = listFrame})
    create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 0), Parent = listFrame})

    local function setOpen(open)
        listOpen = open
        listFrame.Visible = listOpen
        row.ZIndex = listOpen and 100 or 1
        parent.ZIndex = listOpen and 100 or 2
        btn.ZIndex = listOpen and 105 or 5
        btn.Text = sel .. (listOpen and "  ▲" or "  ▼")
    end

    local function setVal(v)
        sel = v
        btn.Text = sel .. "  ▼"
        setOpen(false)
        onChange(sel)
    end

    for i, opt in ipairs(options) do
        local item = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundColor3 = Color3.fromRGB(18, 18, 22),
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextColor3 = Color3.fromRGB(220, 220, 230),
            Text = opt,
            LayoutOrder = i,
            ZIndex = 151,
            Parent = listFrame,
        })
        item.MouseEnter:Connect(function() item.BackgroundColor3 = Color3.fromRGB(45, 38, 20) end)
        item.MouseLeave:Connect(function() item.BackgroundColor3 = Color3.fromRGB(18, 18, 22) end)
        item.MouseButton1Click:Connect(function()
            setVal(opt)
        end)
    end

    btn.MouseButton1Click:Connect(function()
        setOpen(not listOpen)
    end)

    return {Set = setVal}
end

local function mkBtn(parent, y, label, bgColor, onClick)
    local btn = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, y),
        BackgroundColor3 = bgColor or Color3.fromRGB(40, 32, 14),
        BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = Color3.fromRGB(255, 220, 130), Text = label,
        AutoButtonColor = true, Parent = parent,
    })
    create("UICorner", {CornerRadius = UDim.new(0, 6), Parent = btn})
    create("UIStroke", {Color = ACCENT, Thickness = 1, Parent = btn})
    btn.MouseButton1Click:Connect(onClick)
    return btn
end

-- Forward decl
local fillBoardNow, clearMyBoard, ensureMarketGuiOpen

-- ============================================================
-- [3a] TWEEN TO STALL  (ความเร็ว 100 ไปยังพิกัดบอร์ด)
-- ============================================================
local STALL_POS   = Vector3.new(-986.6943359375, 357.2279968261719, -608.388671875)
local TWEEN_SPEED = 100

local function tweenToStall(onComplete)
    local char = LP.Character or LP.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if not hrp then
        if onComplete then onComplete() end
        return
    end

    local dist = (hrp.Position - STALL_POS).Magnitude
    if dist < 12 then
        if ensureMarketGuiOpen then ensureMarketGuiOpen() end
        if onComplete then onComplete() end
        return
    end

    setStatus("Flying to stall (" .. math.floor(dist) .. " studs)...")
    local duration = math.max(0.5, dist / TWEEN_SPEED)
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
    local tween = TweenService:Create(hrp, tweenInfo, {CFrame = CFrame.new(STALL_POS)})

    -- Noclip Connection: ปิด CanCollide ทุก Part ของตัวละคร/มังกร ตลอดช่วงที่บิน
    local noclipConn
    noclipConn = RunService.Stepped:Connect(function()
        if not char or not char.Parent then
            if noclipConn then noclipConn:Disconnect() end
            return
        end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
                part.AssemblyLinearVelocity = Vector3.zero
                part.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end)

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum:ChangeState(Enum.HumanoidStateType.Physics)
    end

    tween:Play()
    tween.Completed:Connect(function()
        if noclipConn then
            noclipConn:Disconnect()
            noclipConn = nil
        end
        if char and char.Parent then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    if part.Name == "HumanoidRootPart" then
                        part.CanCollide = false
                    elseif part.Name == "Head" or part.Name == "Torso" or part.Name == "UpperTorso" or part.Name == "LowerTorso" then
                        part.CanCollide = true
                    end
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                end
            end
        end
        if hum and hum.Parent then
            hum.PlatformStand = false
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            task.wait(0.1)
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end
        setStatus("Arrived at stall ✓")
        task.wait(0.5)

        -- เปิดหน้าต่าง PlayerMarketGui และคลิกไปที่แท็บ MySales
        if ensureMarketGuiOpen then
            ensureMarketGuiOpen()
        end
        task.wait(0.5)

        if onComplete then onComplete() end
    end)
end

-- ============================================================
-- [3b] 2-COLUMN LAYOUT POPULATION
-- ============================================================

-- LEFT COLUMN: Market Stall Settings
local ly = 0
secLabel(leftCol, ly, "━━  MARKET STALL  ━━") ; ly = ly + 18

mkToggle(leftCol, ly, "Enable Market Stall", CONFIG.Enabled, function(s)
    CONFIG.Enabled = s ; saveConfig()
    if s then
        task.spawn(function()
            tweenToStall(function()
                if CONFIG.Enabled then
                    fillBoardNow()
                end
            end)
        end)
    else
        setStatus("Paused")
    end
end) ; ly = ly + 32

mkNumInput(leftCol, ly, "Board Price (per slot)", CONFIG.BoardPrice, 1, 999999999, true, function(v)
    CONFIG.BoardPrice = v ; saveConfig()
end) ; ly = ly + 32

mkNumInput(leftCol, ly, "Max Slots  (1 – 5)", CONFIG.MaxSlots, 1, 5, true, function(v)
    CONFIG.MaxSlots = v ; saveConfig()
end) ; ly = ly + 32

mkTextInput(leftCol, ly, "Item Name", CONFIG.ItemName, "e.g. Apple, Carrot", function(v)
    CONFIG.ItemName = v ; saveConfig()
end) ; ly = ly + 32

mkDropdown(leftCol, ly, "Item Type", { "Food", "Resources", "Potions", "Eggs", "Healing", "Tools" }, CONFIG.ItemType or "Food", function(v)
    CONFIG.ItemType = v ; saveConfig()
end) ; ly = ly + 32

-- RIGHT COLUMN: Auto Refill, Controls, Utility
local ry = 0
secLabel(rightCol, ry, "━━  AUTO REFILL  ━━") ; ry = ry + 18

mkToggle(rightCol, ry, "Auto Refill Board", CONFIG.AutoRefillEnabled, function(s)
    CONFIG.AutoRefillEnabled = s ; saveConfig()
end) ; ry = ry + 32

mkNumInput(rightCol, ry, "Check Interval (sec)", CONFIG.RefillCheckInterval, 3, 60, true, function(v)
    CONFIG.RefillCheckInterval = v ; saveConfig()
end) ; ry = ry + 36

secLabel(rightCol, ry, "━━  CONTROLS  ━━") ; ry = ry + 18

mkBtn(rightCol, ry, "📋  Fill Board Now  (Manual)", Color3.fromRGB(22, 45, 18), function()
    setStatus("Filling board...") ; task.spawn(function() fillBoardNow() end)
end) ; ry = ry + 32

mkBtn(rightCol, ry, "🗑️  Clear My Board  (Manual)", Color3.fromRGB(45, 18, 18), function()
    setStatus("Clearing...") ; task.spawn(function() clearMyBoard() ; setStatus("Board cleared") end)
end) ; ry = ry + 36

secLabel(rightCol, ry, "━━  UTILITY  ━━") ; ry = ry + 18

mkToggle(rightCol, ry, "Hide Map / Objects", CONFIG.HideTerrain, function(s)
    CONFIG.HideTerrain = s ; saveConfig() ; applyHideTerrain(s)
end) ; ry = ry + 32

mkToggle(rightCol, ry, "Anti-AFK", CONFIG.AntiAfk, function(s)
    CONFIG.AntiAfk = s ; saveConfig() ; applyAntiAfk(s)
end) ; ry = ry + 32

-- Footer (Inside bodyFrame)
create("Frame", {
    Size = UDim2.new(1, -28, 0, 1), Position = UDim2.new(0, 14, 1, -22),
    BackgroundColor3 = Color3.fromRGB(45, 35, 18), BorderSizePixel = 0, Parent = bodyFrame,
})
create("TextLabel", {
    Size = UDim2.new(1, -28, 0, 14), Position = UDim2.new(0, 14, 1, -18),
    BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 10,
    TextColor3 = Color3.fromRGB(90, 75, 45), TextXAlignment = Enum.TextXAlignment.Left,
    Text = "Ruajad Hub  •  Storage Market  v2.0 (2-Column)", Parent = bodyFrame,
})

-- ============================================================
-- [4] MARKET LOGIC (Auto Open GUI + Remote Stall Support)
-- ============================================================

-- ฟังก์ชันเปิด PlayerMarketGui และคลิกเปลี่ยนแท็บไปที่ MySales อัตโนมัติ
local function ensureMarketGuiOpen()
    pcall(function()
        local pg = LP:FindFirstChild("PlayerGui")
        if not pg then return end
        local pmg = pg:FindFirstChild("PlayerMarketGui")
        if not pmg then return end

        if not pmg.Enabled then pmg.Enabled = true end

        local cf = pmg:FindFirstChild("ContainerFrame")
        if cf then
            cf.Visible = true

            -- คลิกปุ่ม MySales บน TabButtons
            local tabBtns = cf:FindFirstChild("TabButtons")
            if tabBtns then
                local mySalesBtn = tabBtns:FindFirstChild("MySales")
                if mySalesBtn then
                    if mySalesBtn:IsA("GuiButton") and typeof(firesignal) == "function" then
                        pcall(function() firesignal(mySalesBtn.MouseButton1Click) end)
                        pcall(function() firesignal(mySalesBtn.Activated) end)
                    end
                    for _, child in ipairs(mySalesBtn:GetDescendants()) do
                        if child:IsA("GuiButton") and typeof(firesignal) == "function" then
                            pcall(function() firesignal(child.MouseButton1Click) end)
                            pcall(function() firesignal(child.Activated) end)
                        end
                    end
                end
            end

            -- สลับ Frame ให้แสดง MySales และซ่อนหน้า Market
            local tf = cf:FindFirstChild("TabFrames")
            if tf then
                local marketFrame = tf:FindFirstChild("Market")
                if marketFrame then marketFrame.Visible = false end

                local ms = tf:FindFirstChild("MySales")
                if ms then ms.Visible = true end
            end
        end
    end)
end

-- อ่านจำนวนช่องขายปัจจุบัน จาก SalesLabel ("2/5" → cur=2, max=5)
local function getCurrentSalesCount()
    ensureMarketGuiOpen()
    local pg  = LP:FindFirstChild("PlayerGui") ; if not pg  then return nil, nil end
    local pmg = pg:FindFirstChild("PlayerMarketGui") ; if not pmg then return nil, nil end

    local lbl
    -- 1. Direct path check
    pcall(function()
        lbl = pmg.ContainerFrame.TabFrames.MySales.SalesLabel
    end)

    -- 2. Recursive descendant check if direct path missed
    if not lbl then
        for _, obj in ipairs(pmg:GetDescendants()) do
            if obj:IsA("TextLabel") and obj.Name == "SalesLabel" then
                lbl = obj
                break
            end
        end
    end

    if lbl then
        local txt = tostring(lbl.Text or "")
        local cur, max = txt:match("(%d+)%s*/%s*(%d+)")
        if cur and max then
            return tonumber(cur), tonumber(max)
        end
    end

    -- 3. Search any TextLabel in PlayerMarketGui with digits/digits
    for _, obj in ipairs(pmg:GetDescendants()) do
        if obj:IsA("TextLabel") then
            local txt = tostring(obj.Text or "")
            local cur, max = txt:match("(%d+)%s*/%s*(%d+)")
            if cur and max then
                return tonumber(cur), tonumber(max)
            end
        end
    end

    return nil, nil
end

-- ยิง Remote ตั้งขายหนึ่งช่อง
local function sellOneSlot()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        or ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotes then error("Remotes not found") end
    local remote = remotes:FindFirstChild("SellPlayerMarketRemote")
    if not remote then error("SellPlayerMarketRemote not found") end
    return remote:InvokeServer({
        Price    = CONFIG.BoardPrice,
        ItemType = CONFIG.ItemType,
        Name     = CONFIG.ItemName,
        Amount   = 1,
    })
end

local function claimAllSales()
    ensureMarketGuiOpen()
    local pg = LP:FindFirstChild("PlayerGui")
    local pmg = pg and pg:FindFirstChild("PlayerMarketGui")
    if not pmg then return end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local claimRemote = remotes and remotes:FindFirstChild("ClaimPlayerMarketRemote")

    local ms = pmg.ContainerFrame.TabFrames:FindFirstChild("MySales")
    if not ms then return end

    local sf = ms:FindFirstChild("ScrollingFrame")
    if not sf then return end

    local claimed = 0
    -- ใช้ index ตรงๆ จาก GetChildren แบบสคริปต์แสกน
    for i, child in ipairs(sf:GetChildren()) do
        if child:IsA("GuiObject") and child.Name ~= "UIGridLayout" and child.Name ~= "UIPadding" then
            local targetBtn = nil
            local foundClaim = false

            for _, desc in ipairs(child:GetDescendants()) do
                if (desc:IsA("TextLabel") or desc:IsA("TextBox")) and string.find(string.lower(desc.Text or ""), "claim") then
                    foundClaim = true
                    local p = desc.Parent
                    while p and p ~= child do
                        if p:IsA("GuiButton") or string.find(string.lower(p.Name), "interact") then
                            targetBtn = p
                            break
                        end
                        p = p.Parent
                    end
                    break
                end
            end

            if foundClaim then
                if targetBtn and typeof(firesignal) == "function" then
                    pcall(function() firesignal(targetBtn.MouseButton1Click) end)
                    pcall(function() firesignal(targetBtn.Activated) end)
                    
                    local ul = targetBtn:FindFirstChild("UpperLabel") or targetBtn:FindFirstChildWhichIsA("ImageButton")
                    if ul then
                        pcall(function() firesignal(ul.MouseButton1Click) end)
                        pcall(function() firesignal(ul.Activated) end)
                    end
                end

                if claimRemote then
                    pcall(function()
                        if claimRemote:IsA("RemoteFunction") then
                            claimRemote:InvokeServer(tostring(i))
                        else
                            claimRemote:FireServer(tostring(i))
                        end
                    end)
                end

                claimed = claimed + 1
                task.wait(0.3)
            end
        end
    end

    if claimed > 0 then
        setStatus("Claimed " .. claimed .. " sale(s) 💰")
        task.wait(0.8)
    end
end

-- เติมบอร์ดให้ครบ MaxSlots (รองรับตั้งขายระยะไกลได้ทันที)
fillBoardNow = function()
    claimAllSales()
    local cur, max = getCurrentSalesCount()
    local target = math.min(CONFIG.MaxSlots, max or 5)
    local need   = (cur ~= nil) and (target - cur) or target
    
    if cur ~= nil and need <= 0 then
        setStatus("Board full (" .. cur .. "/" .. target .. ")")
        setBoardText("Board: " .. cur .. "/" .. target)
        return
    end
    
    setStatus("Filling " .. need .. " slot(s)...")
    local filled = 0
    for i = 1, need do
        local ok, err = pcall(sellOneSlot)
        if ok then filled = filled + 1 ; task.wait(1.0)
        else setStatus("⚠️ Slot " .. i .. " err: " .. tostring(err):sub(1,40)) ; task.wait(1.2)
        end
    end
    task.wait(0.5)
    local c2, m2 = getCurrentSalesCount()
    local s = c2 ~= nil and (c2 .. "/" .. (m2 or 5)) or (filled .. "/" .. target)
    setStatus("Filled " .. filled .. " slot(s) — Board: " .. s)
    setBoardText("Board: " .. s)
end

-- ลบบอร์ดทั้งหมด (Manual: วนลบ slot 1 - 5 พร้อมดีเลย์ 2 วิ)
clearMyBoard = function()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        or ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotes then setStatus("⚠️ Remotes not found") return end
    
    local cancelRemote = remotes:FindFirstChild("CancelPlayerMarketRemote")
    if not cancelRemote then
        setStatus("⚠️ CancelPlayerMarketRemote not found")
        return
    end

    local maxSlots = CONFIG.MaxSlots or 5
    for slot = 1, maxSlots do
        setStatus("Clearing slot " .. slot .. "/" .. maxSlots .. "...")
        pcall(function()
            if cancelRemote:IsA("RemoteFunction") then
                cancelRemote:InvokeServer(tostring(slot))
            else
                cancelRemote:FireServer(tostring(slot))
            end
        end)
        task.wait(2) -- ดีเลย์ 2 วินาทีต่อ 1 การลบ
    end
    
    task.wait(0.5)
    local cur, max = getCurrentSalesCount()
    local s = cur ~= nil and (cur .. "/" .. (max or 5)) or "0/5"
    setStatus("Board cleared ✓ (" .. s .. ")")
    setBoardText("Board: " .. s)
end

-- ============================================================
-- [5] AUTO REFILL LOOP
-- ============================================================
task.spawn(function()
    while sg and sg.Parent do
        if CONFIG.Enabled and CONFIG.AutoRefillEnabled then
            pcall(function()
                claimAllSales()
                local cur, max = getCurrentSalesCount()
                if cur ~= nil then
                    local target = math.min(CONFIG.MaxSlots, max or 5)
                    setBoardText("Board: " .. cur .. "/" .. target)
                    if cur < target then
                        setStatus("Refilling board...") ; fillBoardNow()
                    else
                        setStatus("Market active — board full ✓")
                    end
                else
                    setBoardText("Board: Market GUI not visible")
                    setStatus("Waiting for Market GUI...")
                end
            end)
        elseif not CONFIG.Enabled then
            setStatus("Paused")
        end
        task.wait(CONFIG.RefillCheckInterval)
    end
end)

-- ============================================================
-- [6] BEACON WRITER  (Farm Bots read this to find Main Account)
-- ============================================================
local function writeBeacon()
    pcall(function()
        if typeof(isfolder) == "function" and not isfolder("RuajadHub") then makefolder("RuajadHub") end
        if typeof(writefile) ~= "function" then return end
        writefile(beaconPath(), HttpService:JSONEncode({
            username   = LP.Name,
            userId     = LP.UserId,
            placeId    = game.PlaceId,
            jobId      = game.JobId,
            t          = os.time(),
            enabled    = CONFIG.Enabled,
            boardPrice = CONFIG.BoardPrice,
            maxSlots   = CONFIG.MaxSlots,
            itemName   = CONFIG.ItemName,
            itemType   = CONFIG.ItemType,
        }))
    end)
end

writeBeacon()
task.spawn(function()
    while sg and sg.Parent do
        pcall(writeBeacon)
        task.wait(10)
    end
end)

-- ============================================================
-- [7] STARTUP
-- ============================================================
pcall(function()
    if CONFIG.HideTerrain then applyHideTerrain(true) end
    if CONFIG.AntiAfk      then applyAntiAfk(true)     end
    ensureMarketGuiOpen()
end)

if CONFIG.Enabled then
    setStatus("Market Stall active — moving to stall...")
    task.spawn(function()
        tweenToStall(function()
            if CONFIG.Enabled then
                fillBoardNow()
            end
        end)
    end)
else
    setStatus("Idle — Enable to start")
end
setBoardText("Board: checking...")

print("[Ruajad] Storage Market loaded  •  PlaceId=" .. tostring(game.PlaceId))
