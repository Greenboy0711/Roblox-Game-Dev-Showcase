local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local DataService = require(ReplicatedStorage.Packages.DataService).server
local AbilitiesData = require(ReplicatedStorage.Shared.Modules.Data.AbilitiesData)
local ItemsData = require(ReplicatedStorage.Shared.Modules.Data.ItemsData)
local MonetizationData = require(ReplicatedStorage.Shared.Modules.Data.MonetizationData)
local SafeDestroy = require(ReplicatedStorage.Shared.Modules.Data.SafeDestroy)
local TrailsData = require(ReplicatedStorage.Shared.Modules.Data.TrailsData)
local DayTimer = require(ReplicatedStorage.Shared.Modules.Platform.DayTimer)
local ModelServiceClient = require(ReplicatedStorage.Shared.Services.ModelService.ModelServiceClient)
local BlinkMain = require(ServerScriptService.Server.BlinkServer.BlinkMain)
local PlayerStore = require(ServerScriptService.Server.Classes.Stores.PlayerStore)
local PlrCharServiceServer = {}

local function setPlayerChrCollisions(character)
   for _, bodyPart in pairs(character:GetChildren()) do
      if bodyPart:IsA("BasePart") then
         bodyPart.CollisionGroup = "Player"
      end
   end
end

local function genAtt(parent, name, pos)
    local att = Instance.new("Attachment", parent)
    att.Name = name
    att.Position = pos
end

local function characterAdded(player, character)
    setPlayerChrCollisions(character)

    local humanoid = character:WaitForChild("Humanoid")
    humanoid.BreakJointsOnDeath = true
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

    -- Char tag
    local tag = ReplicatedStorage.Templates.CharacterTag:Clone()
    tag.Adornee = character.Head
    tag.Username.Text = player.DisplayName
    tag.Parent = character

    local success, ownsPass = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, MonetizationData.GamepassData.VIP.Id)
    end)
    if success and ownsPass then tag.Title.Visible = true end

    DataService:waitForData(player)
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

    -- Trails
    genAtt(humanoidRootPart, "TrailAttTop", Vector3.new(0, 1, 0))
    genAtt(humanoidRootPart, "TrailAttBottom", Vector3.new(0, -1, 0))

    genAtt(humanoidRootPart, "SubTrailAttTop1", Vector3.new(0, 1.25, 0))
    genAtt(humanoidRootPart, "SubTrailAttTop2", Vector3.new(0, 1.5, 0))

    genAtt(humanoidRootPart, "SubTrailAttBottom1", Vector3.new(0, -1.25, 0))
    genAtt(humanoidRootPart, "SubTrailAttBottom2", Vector3.new(0, -1.5, 0))

    ModelServiceClient.loadTrail(TrailsData.getType(DataService:get(player, {"Equipped", "Trails"})), character)
end

function PlrCharServiceServer.init()
    for _, player in pairs(Players:GetPlayers()) do
        local character = player.Character or player.CharacterAdded:Wait()
        characterAdded(player, character)
    end

    BlinkMain.Player.ToggleAFK.On(function(player)
        local playerObj = PlayerStore[player.UserId]
        if not playerObj then return end
        playerObj.AFK = not playerObj.AFK

        local char = playerObj:getChar()
        if not char then return end
        local humanoidRootPart = char:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then return end

        if playerObj.AFK then
            local billboard = ServerStorage.Templates.AFKBillboard:Clone()
            billboard.Parent = humanoidRootPart
        else
            SafeDestroy(humanoidRootPart, "AFKBillboard")
        end
    end)

    BlinkMain.Player.InventoryEquip.On(function(player, id, type)
        if not id or not type or (type ~= "Abilities" and not ItemsData.isValidType(type)) then return false end
        
        local invData = DataService:get(player, {"Inventory", type})

        local idFound = false
        if type == "Abilities" then
            idFound = AbilitiesData.checkIfIdIsPresent(invData, id)
        else
            for _, v in pairs(invData) do if v == id then idFound = true; break end end
        end
        if not idFound then return false end
        
        if type == "Skins" then
            local minesData = DataService:get(player, {"Inventory", "Mines"})
            local equippedMineId = DataService:get(player, {"Equipped", "Mines"})

            local mineFound = false
            for i, t in pairs(minesData) do
                if t[1] == equippedMineId then
                    DataService:set(player, {"Inventory", "Mines", i, 2}, id)
                    mineFound = true
                    break
                end
            end

            DataService:set(player, {"Equipped", type}, id)
            if not mineFound then return false end
        else
            DataService:set(player, {"Equipped", type}, id)
        end

        if type == "Trails" then
            local character = player.Character or player.CharacterAdded:Wait()
            ModelServiceClient.loadTrail(TrailsData.getType(id), character)
        end
        
        return true
    end)

    BlinkMain.Player.DailyClaim.On(function(player, dayClaim) -- Player attempts to claim
        local dailyData = DataService:get(player, {"DailyRewards"})
        if dailyData["Day"] ~= dayClaim then return false end
        if dayClaim < 1 or dayClaim > MonetizationData.MAX_DAY then return false end

        local plrObj = PlayerStore[player.UserId]
        if not plrObj then return false end

        local timePassed = DayTimer.getSecPassed(dailyData["Time"])
        if timePassed < MonetizationData.SECOND_WAIT then return false end

        local newRewardsData = {["Time"] = os.time()}

        if dailyData["Day"] == 7 and dailyData["Special"] ~= MonetizationData.CURRENT_SPECIAL then -- Grant rewards
            newRewardsData["Special"] = MonetizationData.CURRENT_SPECIAL

            local itemType, id = ItemsData.getType(MonetizationData.Day7Specials[MonetizationData.CURRENT_SPECIAL]["Type"])
            local success = plrObj:addToInv(itemType, id)
            if not success or success ~= 1 then return false end
        else
            -- Regular reward
            local rewardData = MonetizationData.DailyRewardsData[dayClaim]
            
            plrObj:addCurrency(rewardData["Currency"], rewardData["Quantity"], "Daily Reward")
            newRewardsData["Special"] = dailyData["Special"]
        end

        if dailyData["Day"] == MonetizationData.MAX_DAY then -- Upodate day
            newRewardsData["Day"] = 1
        else
            newRewardsData["Day"] = dailyData["Day"] + 1
        end

        DataService:set(player, {"DailyRewards"}, newRewardsData)

        return true
    end)
end

function PlrCharServiceServer.CharacterAdded(args)
    local character = table.unpack(args)
    characterAdded(Players:GetPlayerFromCharacter(character), character)
end

function PlrCharServiceServer.PromptTriggered(args)
    local prompt, player = table.unpack(args)
    
    if prompt.Name == "CratesShopPrompt" then
        BlinkMain.Player.ChangeModal.Fire(player, "Crates")
    elseif prompt.Name == "WheelPrompt" then
        BlinkMain.Player.ChangeModal.Fire(player, "Wheel")
    elseif prompt.Name == "GroupReward" then
        local plrObj = PlayerStore[player.UserId]
        if not plrObj then return end

        local claimed = DataService:get(player, {"Misc", "ClaimedGroup"})
        if player:IsInGroupAsync(9794868) and claimed == nil then
            plrObj:addCurrency("BoomBux", MonetizationData.BoomBuxData.GroupReward, "Group Reward")
            DataService:set(player, {"Misc", "ClaimedGroup"}, true)
        elseif claimed then
            BlinkMain.Effects.Notification.Fire(player, "Reward Already Claimed!", "ShortError", Color3.fromRGB(255, 255, 255))
        else
            BlinkMain.Effects.Notification.Fire(player, "Like the Game and Join Duo Dynamics to Receive your Reward!", "SmallClick", Color3.fromRGB(255, 255, 255))
        end

    end
end

type PlrCharServiceServer = typeof(PlrCharServiceServer) & {

}

return PlrCharServiceServer