local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local AntiLag = {}

function AntiLag:DisableEffects()
    pcall(function()
        for _, effect in ipairs(workspace:GetDescendants()) do
            if effect:IsA("ParticleEmitter") or effect:IsA("Trail") or effect:IsA("Beam") or effect:IsA("Smoke") or effect:IsA("Fire") or effect:IsA("Sparkles") then
                effect.Enabled = false
            end
        end
        for _, effect in ipairs(Lighting:GetDescendants()) do
            if effect:IsA("PostEffect") then
                effect.Enabled = false
            end
        end
        workspace.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") or descendant:IsA("Smoke") or descendant:IsA("Fire") or descendant:IsA("Sparkles") then
                descendant.Enabled = false
            elseif descendant:IsA("Explosion") then
                descendant:Destroy()
            end
        end)
    end)
end

function AntiLag:OptimizeGraphics()
    pcall(function()
        settings():GetService("Rendering"):SetQualityLevel("Level01")
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 999999
        Lighting.Brightness = 0.1
    end)
end

function AntiLag:SimplifyWorkspace()
    pcall(function()
        for _, thing in ipairs(workspace:GetDescendants()) do
            if thing:IsA("Part") or thing:IsA("MeshPart") then
                thing.Material = Enum.Material.Plastic
                thing.Reflectance = 0
            elseif thing:IsA("Decal") or thing:IsA("Texture") then
                thing:Destroy()
            elseif thing:IsA("Model") and thing.Name == "Debris" then
                thing:Destroy()
            end
        end
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= Players.LocalPlayer and player.Character then
                for _, part in ipairs(player.Character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.Transparency = 1
                    elseif part:IsA("Decal") or part:IsA("Texture") then
                        part:Destroy()
                    end
                end
            end
        end
    end)
end

function AntiLag:DisableSounds()
    pcall(function()
        for _, sound in ipairs(workspace:GetDescendants()) do
            if sound:IsA("Sound") then
                sound.Volume = 0
                sound:Stop()
            end
        end
        workspace.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("Sound") then
                descendant.Volume = 0
                descendant:Stop()
            end
        end)
    end)
end

function AntiLag:RunAll()
    self:DisableEffects()
    self:OptimizeGraphics()
    self:SimplifyWorkspace()
    self:DisableSounds()
end

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Humanoid
local Brainrots = workspace:WaitForChild("ScriptedMap"):WaitForChild("Brainrots")

local function getHumanoid()
    while not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Humanoid") do
        LocalPlayer.CharacterAdded:Wait()
    end
    Humanoid = LocalPlayer.Character.Humanoid
end
task.spawn(getHumanoid)

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Utility = Modules:WaitForChild("Utility")
local Library = Modules:WaitForChild("Library")
local Assets = ReplicatedStorage:WaitForChild("Assets")

local PlayerData = require(ReplicatedStorage:WaitForChild("PlayerData"))
local BrainrotMutations = require(Library:WaitForChild("BrainrotMutations"))
local RarityChances = require(Library:WaitForChild("Chances"))
local BrainrotAssets = Assets:WaitForChild("Brainrots")
local SeedData = require(Library:WaitForChild("SeedStocks"))
local GearData = require(Library:WaitForChild("GearStocks"))

local FavoriteItemRemote = ReplicatedStorage.Remotes:WaitForChild("FavoriteItem")
local ItemSellRemote = ReplicatedStorage.Remotes:WaitForChild("ItemSell")
local EquipBestBrainrotsRemote = ReplicatedStorage.Remotes:WaitForChild("EquipBestBrainrots")
local BuyGearRemote = ReplicatedStorage.Remotes:WaitForChild("BuyGear")
local BuyItemRemote = ReplicatedStorage.Remotes:WaitForChild("BuyItem")

local AutoManager = {
    CHECK_INTERVAL = 60,
    autoFavoriteEnabled = false,
    autoSellEnabled = false,
    equipBeforeSell = false,
    autoBuyEnabled = false,
    autoClaimEnabled = false,
    autoBatEnabled = false,
    antiLagEnabled = false,
    isProcessingBackpack = false,
    keepKgThreshold = 50,
    keepSettings = {
        Rarities = {},
        Mutations = {}
    },
    autoBuySettings = {
        Seeds = {}
    },
    toggles = {},
    uiElements = {},
    timerTarget = nil,
    attackStartTime = 0,
    isUsingGrenades = false,
    lastGrenadeTime = 0
}

local defaultKeepRarities = {Secret = true, Mythic = true, Limited = true, Godly = true}
for rarityName, data in pairs(RarityChances) do
    AutoManager.keepSettings.Rarities[rarityName] = defaultKeepRarities[rarityName] or false
end

for mutationName, _ in pairs(BrainrotMutations.Colors) do
    AutoManager.keepSettings.Mutations[mutationName] = (mutationName ~= "Normal")
end

for seedName, _ in pairs(SeedData) do
    AutoManager.autoBuySettings.Seeds[seedName] = false
end

function AutoManager:ProcessBackpack()
    if self.autoFavoriteEnabled then
        local backpack = LocalPlayer:WaitForChild("Backpack")
        local playerData = PlayerData:GetData()
        if not playerData or not playerData.Data then return end
        local favorites = playerData.Data.Favorites
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("Brainrot") then
                local itemID = tool:GetAttribute("ID")
                if not itemID or favorites[itemID] then continue end
                local brainrotName = tool:GetAttribute("Brainrot")
                local brainrotAsset = BrainrotAssets:FindFirstChild(brainrotName)
                if not brainrotAsset then continue end
                local rarity = brainrotAsset:GetAttribute("Rarity")
                local mutation = tool:GetAttribute("Colors") or "Normal"
                
                local weight = 1
                local weightString = string.match(tool.Name, "%[(%d+%.?%d*) kg%]")
                if weightString then
                    weight = tonumber(weightString) or 1
                end

                local shouldKeep = (
                    (weight >= self.keepKgThreshold) or
                    (self.keepSettings.Rarities[rarity] == true) or
                    (self.keepSettings.Mutations[mutation] == true)
                )

                if shouldKeep then
                    FavoriteItemRemote:FireServer(itemID)
                end
            end
        end
    end

    if self.autoSellEnabled then
        ItemSellRemote:FireServer()
    end
end

function AutoManager:DisableAutoFeatures()
    if self.autoFavoriteEnabled or self.autoSellEnabled then
        self.autoFavoriteEnabled = false
        self.autoSellEnabled = false
        if self.toggles.autoFavorite then self.toggles.autoFavorite(false) end
        if self.toggles.autoSell then self.toggles.autoSell(false) end
        StarterGui:SetCore("SendNotification", {
            Title = "Cheetos Hub",
            Text = "Auto features disabled for safety. Please re-enable them.",
            Duration = 5
        })
    end
end

function AutoManager:CreateGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoManagerGUI_V6"
    screenGui.Parent = PlayerGui
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Enabled = false

    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 260, 0, 0)
    mainFrame.AutomaticSize = Enum.AutomaticSize.Y
    mainFrame.Position = UDim2.new(0, 70, 0, 70)
    mainFrame.BackgroundColor3 = Color3.fromRGB(28, 29, 34)
    mainFrame.BorderSizePixel = 0
    mainFrame.Draggable = true
    mainFrame.Active = true
    mainFrame.Parent = screenGui
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
    Instance.new("UIStroke", mainFrame).Color = Color3.fromRGB(60, 62, 67)
    
    local listLayout = Instance.new("UIListLayout", mainFrame)
    listLayout.Padding = UDim.new(0, 8)
    local padding = Instance.new("UIPadding", mainFrame)
    padding.PaddingLeft, padding.PaddingRight, padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 10)

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 35)
    header.BackgroundColor3 = Color3.fromRGB(40, 42, 47)
    header.BorderSizePixel = 0
    header.Parent = mainFrame
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -60, 1, 0)
    title.Position = UDim2.new(0, 15, 0, 0)
    title.Text = "Cheetos Hub"
    title.Font = Enum.Font.GothamBold
    title.TextColor3 = Color3.fromRGB(230, 230, 230)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.BackgroundTransparency = 1
    title.Parent = header

    local function createToggle(key, name, enabled, iconId, callback)
        local button = Instance.new("TextButton")
        button.Size = UDim2.new(1, 0, 0, 28)
        button.Text = ""
        button.BackgroundColor3 = Color3.fromRGB(40, 42, 47)
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
        Instance.new("UIStroke", button).Color = Color3.fromRGB(60, 62, 67)
        
        if iconId then
            local icon = Instance.new("ImageLabel", button)
            icon.Size = UDim2.new(0, 20, 0, 20)
            icon.Position = UDim2.new(0, 8, 0.5, -10)
            icon.Image = iconId
            icon.ImageColor3 = Color3.fromRGB(200, 200, 200)
            icon.BackgroundTransparency = 1
        end

        local label = Instance.new("TextLabel", button)
        label.Size = UDim2.new(0.7, -32, 1, 0)
        label.Position = UDim2.new(0, 32, 0, 0)
        label.Text = name
        label.Font = Enum.Font.Gotham
        label.TextColor3 = Color3.fromRGB(220, 220, 220)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.BackgroundTransparency = 1

        local status = Instance.new("TextLabel", button)
        status.Size = UDim2.new(0.3, -10, 1, 0)
        status.Position = UDim2.new(0.7, 0, 0, 0)
        status.Font = Enum.Font.GothamBold
        status.BackgroundTransparency = 1

        local function updateStatus(state)
            status.Text = state and "ON" or "OFF"
            status.TextColor3 = state and Color3.fromRGB(80, 200, 80) or Color3.fromRGB(200, 80, 80)
        end
        
        self.toggles[key] = updateStatus
        self.uiElements[key] = {button = button, label = label}

        button.MouseButton1Click:Connect(function() 
            if button.Selectable then updateStatus(callback()) end 
        end)
        updateStatus(enabled)
        return button
    end

    local toggleGridFrame = Instance.new("Frame", mainFrame)
    toggleGridFrame.Size = UDim2.new(1, 0, 0, 0)
    toggleGridFrame.AutomaticSize = Enum.AutomaticSize.Y
    toggleGridFrame.BackgroundTransparency = 1
    
    local gridLayout = Instance.new("UIGridLayout", toggleGridFrame)
    gridLayout.CellSize = UDim2.new(0.5, -4, 0, 30)
    gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
    gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    gridLayout.FillDirection = Enum.FillDirection.Horizontal
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder

    createToggle("autoBat", "Auto Bat", self.autoBatEnabled, "rbxassetid://10212796135", function() self.autoBatEnabled = not self.autoBatEnabled; return self.autoBatEnabled end).Parent = toggleGridFrame
    createToggle("autoFavorite", "Auto Favorite", self.autoFavoriteEnabled, "rbxassetid://10212783020", function() self.autoFavoriteEnabled = not self.autoFavoriteEnabled; return self.autoFavoriteEnabled end).Parent = toggleGridFrame
    
    local autoSellToggle = createToggle("autoSell", "Auto Sell", self.autoSellEnabled, "rbxassetid://10212800392", function() 
        self.autoSellEnabled = not self.autoSellEnabled
        return self.autoSellEnabled 
    end)
    autoSellToggle.Parent = toggleGridFrame
    
    local equipToggle = createToggle("equipBeforeSell", "Equip (Obsolete)", self.equipBeforeSell, "rbxassetid://10212805953", function() 
        return false 
    end)
    equipToggle.Parent = toggleGridFrame
    Instance.new("UIPadding", equipToggle).PaddingLeft = UDim.new(0, 20)

    createToggle("autoBuy", "Auto Buy All Stock", self.autoBuyEnabled, "rbxassetid://10212790938", function() self.autoBuyEnabled = not self.autoBuyEnabled; return self.autoBuyEnabled end).Parent = toggleGridFrame
    createToggle("autoClaim", "Auto Claim Money", self.autoClaimEnabled, "rbxassetid://10212809630", function() self.autoClaimEnabled = not self.autoClaimEnabled; return self.autoClaimEnabled end).Parent = toggleGridFrame
    
    createToggle("antiLag", "Extreme Anti-Lag", self.antiLagEnabled, "rbxassetid://6031399981", function()
        self.antiLagEnabled = not self.antiLagEnabled
        if self.antiLagEnabled then
            AntiLag:RunAll()
            StarterGui:SetCore("SendNotification", {
                Title = "Cheetos Hub",
                Text = "Anti-Lag applied. Rejoin to revert changes.",
                Duration = 5
            })
        end
        return self.antiLagEnabled
    end).Parent = toggleGridFrame

    local equipUI = self.uiElements.equipBeforeSell
    equipUI.button.Selectable = false
    equipUI.label.TextColor3 = Color3.fromRGB(120, 120, 120)

    local kgInputFrame = Instance.new("Frame", mainFrame)
    kgInputFrame.Size = UDim2.new(1, 0, 0, 28)
    kgInputFrame.BackgroundTransparency = 1
    
    local kgLabel = Instance.new("TextLabel", kgInputFrame)
    kgLabel.Size = UDim2.new(0.6, 0, 1, 0)
    kgLabel.Text = "Keep KG Above:"
    kgLabel.Font = Enum.Font.Gotham
    kgLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
    kgLabel.TextXAlignment = Enum.TextXAlignment.Left
    kgLabel.BackgroundTransparency = 1

    local kgInput = Instance.new("TextBox", kgInputFrame)
    kgInput.Size = UDim2.new(0.4, -10, 1, 0)
    kgInput.Position = UDim2.new(0.6, 0, 0, 0)
    kgInput.BackgroundColor3 = Color3.fromRGB(40, 42, 47)
    kgInput.Font = Enum.Font.GothamBold
    kgInput.TextColor3 = Color3.fromRGB(230, 230, 230)
    kgInput.Text = tostring(self.keepKgThreshold)
    kgInput.TextXAlignment = Enum.TextXAlignment.Center
    kgInput.ClearTextOnFocus = false
    Instance.new("UICorner", kgInput).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", kgInput).Color = Color3.fromRGB(60, 62, 67)
    
    kgInput.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local num = tonumber(kgInput.Text)
            self.keepKgThreshold = (num and num >= 0) and num or 50
            kgInput.Text = tostring(self.keepKgThreshold)
            self:DisableAutoFeatures()
        end
    end)
    
    local settingsButton = Instance.new("TextButton")
    settingsButton.Size = UDim2.new(1, 0, 0, 28)
    settingsButton.Text = "Keep Settings"
    settingsButton.Font = Enum.Font.Gotham
    settingsButton.TextColor3 = Color3.fromRGB(220, 220, 220)
    settingsButton.BackgroundColor3 = Color3.fromRGB(60, 62, 67)
    settingsButton.Parent = mainFrame
    Instance.new("UICorner", settingsButton).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", settingsButton).Color = Color3.fromRGB(80, 82, 87)

    local autoBuySettingsButton = Instance.new("TextButton")
    autoBuySettingsButton.Size = UDim2.new(1, 0, 0, 28)
    autoBuySettingsButton.Text = "Auto-Buy Settings"
    autoBuySettingsButton.Font = Enum.Font.Gotham
    autoBuySettingsButton.TextColor3 = Color3.fromRGB(220, 220, 220)
    autoBuySettingsButton.BackgroundColor3 = Color3.fromRGB(60, 62, 67)
    autoBuySettingsButton.Parent = mainFrame
    Instance.new("UICorner", autoBuySettingsButton).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", autoBuySettingsButton).Color = Color3.fromRGB(80, 82, 87)

    local unfavoriteButton = Instance.new("TextButton")
    unfavoriteButton.Size = UDim2.new(1, 0, 0, 28)
    unfavoriteButton.Text = "Unfavorite All"
    unfavoriteButton.Font = Enum.Font.Gotham
    unfavoriteButton.TextColor3 = Color3.fromRGB(220, 220, 220)
    unfavoriteButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
    unfavoriteButton.Parent = mainFrame
    Instance.new("UICorner", unfavoriteButton).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", unfavoriteButton).Color = Color3.fromRGB(200, 80, 80)
    
    unfavoriteButton.MouseButton1Click:Connect(function()
        local playerData = PlayerData:GetData()
        if playerData and playerData.Data and playerData.Data.Favorites then
            local count = 0
            for itemID, _ in pairs(playerData.Data.Favorites) do
                FavoriteItemRemote:FireServer(itemID)
                count = count + 1
                task.wait(0.05)
            end
            StarterGui:SetCore("SendNotification", {
                Title = "Cheetos Hub",
                Text = "Unfavorited " .. count .. " items.",
                Duration = 5
            })
        end
    end)

    local function createSettingsFrame(titleText)
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 350, 0, 250)
        frame.Position = UDim2.new(0.5, -175, 0.5, -125)
        frame.BackgroundColor3 = Color3.fromRGB(28, 29, 34)
        frame.BorderSizePixel = 0
        frame.Visible = false
        frame.Draggable = true
        frame.Active = true
        frame.Parent = screenGui
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
        Instance.new("UIStroke", frame).Color = Color3.fromRGB(60, 62, 67)
        
        local header = Instance.new("Frame", frame)
        header.Size = UDim2.new(1, 0, 0, 35)
        header.BackgroundColor3 = Color3.fromRGB(40, 42, 47)
        Instance.new("UICorner", header).CornerRadius = UDim.new(0, 12)
        
        local title = Instance.new("TextLabel", header)
        title.Size = UDim2.new(1, 0, 1, 0)
        title.Text = titleText
        title.Font = Enum.Font.GothamBold
        title.TextColor3 = Color3.fromRGB(230, 230, 230)
        title.BackgroundTransparency = 1
        
        local closeBtn = Instance.new("TextButton", header)
        closeBtn.Size = UDim2.new(0, 20, 0, 20)
        closeBtn.Position = UDim2.new(1, -25, 0.5, -10)
        closeBtn.Text = "X"
        closeBtn.Font = Enum.Font.GothamBold
        closeBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
        closeBtn.BackgroundTransparency = 1
        closeBtn.MouseButton1Click:Connect(function() frame.Visible = false end)
        return frame
    end

    local settingsFrame = createSettingsFrame("Select what to KEEP")
    settingsButton.MouseButton1Click:Connect(function() settingsFrame.Visible = true end)

    local autoBuySettingsFrame = createSettingsFrame("Select Seeds to Auto-Buy")
    autoBuySettingsButton.MouseButton1Click:Connect(function() autoBuySettingsFrame.Visible = true end)

    local function createSelectionButton(parent, name, settingsTable, onToggle)
        local button = Instance.new("TextButton", parent)
        button.Size = UDim2.new(0, 90, 0, 30)
        button.Text = name
        button.Font = Enum.Font.GothamBold
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
        local stroke = Instance.new("UIStroke", button)
        stroke.Thickness = 1.5
        
        local grad = Instance.new("UIGradient", button)
        grad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 220, 80)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 180, 60))
        })

        local function updateVisual()
            if settingsTable[name] then
                grad.Enabled = true
                button.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
                button.TextColor3 = Color3.fromRGB(255, 255, 255)
                stroke.Color = Color3.fromRGB(255, 255, 255)
                stroke.Enabled = true
            else
                grad.Enabled = false
                button.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
                button.TextColor3 = Color3.fromRGB(150, 150, 150)
                stroke.Enabled = false
            end
        end
        button.MouseButton1Click:Connect(function()
            settingsTable[name] = not settingsTable[name]
            updateVisual()
            if onToggle then onToggle() end
        end)
        updateVisual()
    end

    local pageFrame = Instance.new("Frame", settingsFrame)
    pageFrame.Size = UDim2.new(1, -20, 1, -85)
    pageFrame.Position = UDim2.new(0, 10, 0, 40)
    pageFrame.BackgroundTransparency = 1
    
    local raritiesPage = Instance.new("ScrollingFrame", pageFrame)
    raritiesPage.Size = UDim2.new(1, 0, 1, 0)
    raritiesPage.BackgroundTransparency = 1
    raritiesPage.BorderSizePixel = 0
    raritiesPage.Visible = true
    Instance.new("UIGridLayout", raritiesPage).CellSize = UDim2.new(0, 100, 0, 40)
    
    local mutationsPage = Instance.new("ScrollingFrame", pageFrame)
    mutationsPage.Size = UDim2.new(1, 0, 1, 0)
    mutationsPage.BackgroundTransparency = 1
    mutationsPage.BorderSizePixel = 0
    mutationsPage.Visible = false
    Instance.new("UIGridLayout", mutationsPage).CellSize = UDim2.new(0, 100, 0, 40)
    
    for rarityName, _ in pairs(self.keepSettings.Rarities) do
        createSelectionButton(raritiesPage, rarityName, self.keepSettings.Rarities, function() self:DisableAutoFeatures() end)
    end
    
    for mutationName, _ in pairs(self.keepSettings.Mutations) do
        createSelectionButton(mutationsPage, mutationName, self.keepSettings.Mutations, function() self:DisableAutoFeatures() end)
    end

    local raritiesTab = Instance.new("TextButton", settingsFrame)
    raritiesTab.Size = UDim2.new(0.5, 0, 0, 35)
    raritiesTab.Position = UDim2.new(0, 0, 1, -35)
    raritiesTab.Text = "Rarities"
    raritiesTab.Font = Enum.Font.GothamBold
    raritiesTab.BackgroundColor3 = Color3.fromRGB(60, 62, 67)
    
    local mutationsTab = Instance.new("TextButton", settingsFrame)
    mutationsTab.Size = UDim2.new(0.5, 0, 0, 35)
    mutationsTab.Position = UDim2.new(0.5, 0, 1, -35)
    mutationsTab.Text = "Mutations"
    mutationsTab.Font = Enum.Font.GothamBold
    mutationsTab.BackgroundColor3 = Color3.fromRGB(45, 47, 52)
    
    raritiesTab.MouseButton1Click:Connect(function()
        raritiesPage.Visible = true
        mutationsPage.Visible = false
        raritiesTab.BackgroundColor3 = Color3.fromRGB(60, 62, 67)
        mutationsTab.BackgroundColor3 = Color3.fromRGB(45, 47, 52)
    end)
    
    mutationsTab.MouseButton1Click:Connect(function()
        raritiesPage.Visible = false
        mutationsPage.Visible = true
        raritiesTab.BackgroundColor3 = Color3.fromRGB(45, 47, 52)
        mutationsTab.BackgroundColor3 = Color3.fromRGB(60, 62, 67)
    end)

    local autoBuyPage = Instance.new("ScrollingFrame", autoBuySettingsFrame)
    autoBuyPage.Size = UDim2.new(1, -20, 1, -45)
    autoBuyPage.Position = UDim2.new(0, 10, 0, 40)
    autoBuyPage.BackgroundTransparency = 1
    autoBuyPage.BorderSizePixel = 0
    Instance.new("UIGridLayout", autoBuyPage).CellSize = UDim2.new(0, 100, 0, 40)

    for seedName, _ in pairs(self.autoBuySettings.Seeds) do
        createSelectionButton(autoBuyPage, seedName, self.autoBuySettings.Seeds)
    end

    return screenGui
end

function AutoManager:InitializeHub()
    local hubGui = self:CreateGUI()
    hubGui.Enabled = true

    local toggleButton = Instance.new("ImageButton")
    toggleButton.Name = "CheetosHubToggle"
    toggleButton.Size = UDim2.new(0, 50, 0, 50)
    toggleButton.Position = UDim2.new(0, 10, 0, 10)
    toggleButton.BackgroundColor3 = Color3.fromRGB(28, 29, 34)
    toggleButton.Image = "rbxassetid://13522162906"
    toggleButton.ImageColor3 = Color3.fromRGB(230, 230, 230)
    toggleButton.Parent = hubGui
    Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(1, 0)
    Instance.new("UIStroke", toggleButton).Color = Color3.fromRGB(60, 62, 67)

    toggleButton.MouseButton1Click:Connect(function()
        hubGui.Frame.Visible = not hubGui.Frame.Visible
    end)

    task.spawn(function()
        local batTool = nil
        local currentTarget = nil

        local function findBatTool()
            local character = LocalPlayer.Character
            local backpack = LocalPlayer.Backpack
            if character then
                for _, child in ipairs(character:GetChildren()) do
                    if child:IsA("Tool") and string.find(child.Name, "Bat") then
                        return child
                    end
                end
            end
            if backpack then
                for _, child in ipairs(backpack:GetChildren()) do
                    if child:IsA("Tool") and string.find(child.Name, "Bat") then
                        return child
                    end
                end
            end
            return nil
        end

        local function findGrenadeTool()
            local character = LocalPlayer.Character
            local backpack = LocalPlayer.Backpack
            if character then
                for _, child in ipairs(character:GetChildren()) do
                    if child:IsA("Tool") and child.Name == "Frost Grenade" then
                        return child
                    end
                end
            end
            if backpack then
                for _, child in ipairs(backpack:GetChildren()) do
                    if child:IsA("Tool") and child.Name == "Frost Grenade" then
                        return child
                    end
                end
            end
            return nil
        end

        local function findClosestBrainrot()
            local closestBrainrot = nil
            local minDistance = math.huge
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then return nil end
            for _, brainrot in ipairs(Brainrots:GetChildren()) do
                if brainrot and brainrot:IsA("Model") and brainrot.PrimaryPart then
                    local distance = (hrp.Position - brainrot.PrimaryPart.Position).Magnitude
                    if distance < minDistance then
                        minDistance = distance
                        closestBrainrot = brainrot
                    end
                end
            end
            return closestBrainrot
        end

        while task.wait() and hubGui.Parent do
            if self.autoBatEnabled and not self.isProcessingBackpack then
                local character = LocalPlayer.Character
                if not character or not character:FindFirstChild("HumanoidRootPart") then
                    currentTarget = nil
                    batTool = nil
                else
                    if not batTool or batTool.Parent == nil then
                        batTool = findBatTool()
                    end
                    if batTool then
                        if batTool.Parent ~= character then
                            local humanoid = character:FindFirstChildOfClass("Humanoid")
                            if humanoid then
                                humanoid:EquipTool(batTool)
                            end
                        else
                            if not currentTarget or not currentTarget.Parent or not currentTarget:IsDescendantOf(Brainrots) then
                                currentTarget = findClosestBrainrot()
                                if currentTarget ~= self.timerTarget then
                                    self.timerTarget = currentTarget
                                    self.attackStartTime = tick()
                                    self.isUsingGrenades = false
                                    self.lastGrenadeTime = 0
                                end
                            end
                            if currentTarget and currentTarget.PrimaryPart then
                                local hrp = character.HumanoidRootPart
                                local targetPart = currentTarget.PrimaryPart
                                local attackDistance = 4
                                local direction = (hrp.Position - targetPart.Position).Unit
                                local newPos = targetPart.Position + direction * attackDistance
                                hrp.CFrame = CFrame.new(newPos, targetPart.Position)
                                for i = 1, 10 do
                                    batTool:Activate()
                                end

                                if tick() - self.attackStartTime > 10 then
                                    self.isUsingGrenades = true
                                end

                                if self.isUsingGrenades and tick() - self.lastGrenadeTime > 4 then
                                    local grenadeTool = findGrenadeTool()
                                    if grenadeTool then
                                        local humanoid = character:FindFirstChildOfClass("Humanoid")
                                        if humanoid then
                                            humanoid:EquipTool(grenadeTool)
                                            task.wait(0.1)
                                            grenadeTool:Activate()
                                            self.lastGrenadeTime = tick()
                                            task.wait(0.1)
                                            humanoid:EquipTool(batTool)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    task.spawn(function()
        while task.wait(self.CHECK_INTERVAL) and hubGui.Parent do
            if self.autoSellEnabled or self.autoFavoriteEnabled then
                self.isProcessingBackpack = true
                pcall(function() self:ProcessBackpack() end)
                self.isProcessingBackpack = false
            end
        end
    end)
    
    task.spawn(function()
        while task.wait(1) and hubGui.Parent do
            if self.autoBuyEnabled then
                pcall(function()
                    local playerData = PlayerData:GetData()
                    if not playerData or not playerData.Data then return end

                    for seedName, shouldBuy in pairs(self.autoBuySettings.Seeds) do
                        if not self.autoBuyEnabled then break end
                        if shouldBuy then
                            local seedAsset = ReplicatedStorage.Assets.Seeds:FindFirstChild(seedName)
                            if seedAsset then
                                local totalStock = seedAsset:GetAttribute("Stock") or 0
                                local price = seedAsset:GetAttribute("Price") or 0
                                local purchasedStock = (playerData.Data.Stock and playerData.Data.Stock.Seeds and playerData.Data.Stock.Seeds.Stock and playerData.Data.Stock.Seeds.Stock[seedName]) or 0
                                local itemsToBuy = totalStock - purchasedStock

                                for i = 1, itemsToBuy do
                                    if not self.autoBuyEnabled or playerData.Data.Money < price then break end
                                    BuyItemRemote:FireServer(seedName)
                                    task.wait(0.1)
                                end
                            end
                        end
                    end

                    for gearName, _ in pairs(GearData) do
                        if not self.autoBuyEnabled then break end
                        local gearAsset = ReplicatedStorage.Assets.Gears:FindFirstChild(gearName)
                        if gearAsset then
                            local totalStock = gearAsset:GetAttribute("Stock") or 0
                            local price = gearAsset:GetAttribute("Price") or 0
                            local purchasedStock = (playerData.Data.Stock and playerData.Data.Stock.Gears and playerData.Data.Stock.Gears.Stock and playerData.Data.Stock.Gears.Stock[gearName]) or 0
                            local itemsToBuy = totalStock - purchasedStock

                            for i = 1, itemsToBuy do
                                if not self.autoBuyEnabled or playerData.Data.Money < price then break end
                                BuyGearRemote:FireServer(gearName)
                                task.wait(0.1)
                            end
                        end
                    end
                end)
            end
        end
    end)

    task.spawn(function()
        while task.wait(30) and hubGui.Parent do
            if self.autoClaimEnabled and not self.isProcessingBackpack then
                pcall(function() EquipBestBrainrotsRemote:FireServer() end)
            end
        end
    end)
end

--// NEW: Advanced Anti-AFK system
local AntiAFKSystem = {}
function AntiAFKSystem:SimulateHumanActivity()
    local actions = {
        function() -- Walk Forward
            if Humanoid then
                Humanoid.MoveDirection = Vector3.new(0, 0, -1)
                task.wait(math.random(5, 20) / 10)
                Humanoid.MoveDirection = Vector3.new(0, 0, 0)
            end
        end,
        function() -- Walk Backward
            if Humanoid then
                Humanoid.MoveDirection = Vector3.new(0, 0, 1)
                task.wait(math.random(5, 15) / 10)
                Humanoid.MoveDirection = Vector3.new(0, 0, 0)
            end
        end,
        function() -- Strafe
            if Humanoid then
                local dir = math.random() > 0.5 and 1 or -1
                Humanoid.MoveDirection = Vector3.new(dir, 0, 0)
                task.wait(math.random(5, 15) / 10)
                Humanoid.MoveDirection = Vector3.new(0, 0, 0)
            end
        end,
        function() -- Jump
            if Humanoid then Humanoid.Jump = true end
        end,
        function() -- Pan Camera
            local camera = workspace.CurrentCamera
            if camera then
                local currentCFrame = camera.CFrame
                local randomAngle = CFrame.Angles(0, math.rad(math.random(-15, 15)), 0)
                camera.CFrame = currentCFrame * randomAngle
            end
        end
    }
    
    task.spawn(function()
        while task.wait(math.random(20, 45)) do
            pcall(function()
                if Humanoid and Humanoid:GetState() ~= Enum.HumanoidStateType.Dead then
                    local randomAction = actions[math.random(#actions)]
                    randomAction()
                end
            end)
        end
    end)
end

AutoManager:InitializeHub()
AntiAFKSystem:SimulateHumanActivity() 
