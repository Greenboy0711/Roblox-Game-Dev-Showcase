local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServicesLoader = {}

local PriorityServicesServer = require(script.Parent.PriorityServicesServer)
local PriorityServicesClient = require(script.Parent.PriorityServicesClient)
local Promise = require(ReplicatedStorage.Packages.Promise)

local function initService(services, module)
    if module.init then
        Promise.try(function()
            module:init()
        end)
    end
    table.insert(services, module)
end

function ServicesLoader.getServices(servicesFolder: Folder, isServer: boolean)
    local services = {}
    local endTag = isServer and "Server" or "Client"
    local PriorityServices = isServer and PriorityServicesServer or PriorityServicesClient

    if isServer then -- Indicate player has loaded
        local BlinkMain = require(game:GetService("ServerScriptService").Server.BlinkServer.BlinkMain)
        BlinkMain.Player.ClientLoaded.On(function(player)
            player:SetAttribute("ClientLoaded", true)
        end)
    else
        local player = game:GetService("Players").LocalPlayer
        player:SetAttribute("ClientServicesLoaded", 0)
    end

    -- Load priority services first
    for _, serviceName in pairs(PriorityServices) do
        local module = require(servicesFolder:WaitForChild(serviceName):WaitForChild(serviceName..endTag))
        initService(services, module)
    end

    -- Load rest of the services
    for _, serviceModule in pairs(servicesFolder:GetChildren()) do
        if table.find(PriorityServices, serviceModule.Name) then continue end
        local module = require(serviceModule:WaitForChild(serviceModule.Name..endTag))
        initService(services, module)
    end

    if not isServer then -- Wait until all client services and ui loaded, then tell server
        local player = game:GetService("Players").LocalPlayer
        local CLIENT_SERV_TOTAL = #servicesFolder:GetChildren()

        Promise.try(function()
            repeat task.wait() until player:GetAttribute("ClientServicesLoaded") == CLIENT_SERV_TOTAL and player:GetAttribute("ClientUILoaded") == true and player:GetAttribute("LoadingScreenDone") == true
            local BlinkMain = require(ReplicatedStorage.Shared.BlinkClient.BlinkMain)
            BlinkMain.Player.ClientLoaded.Fire()
        end)
    end

    return services
end

-- Roblox events broadcast system
function ServicesLoader.runMethod(services, methodName, ...)
    local args = {...}
    for _, service in pairs(services) do
        if service[methodName] then
            Promise.try(function()
                service[methodName](args)
            end)
        end
    end
end

return ServicesLoader