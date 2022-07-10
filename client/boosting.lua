local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = QBCore.Functions.GetPlayerData()
local Contracts = {}
local ActivePlates = {} -- Just using this for a quick check to see if a plate is already active on the client side to prevent server spam.
local PZone = nil
local PZone2 = nil
local NetID = nil
local missionBlip = nil
local CanVinscratch = false
local inZone = false
local canHack = true
local dropoffBlip = nil

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PlayerData = {}
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(val)
    PlayerData = val
end)

RegisterCommand('boost', function()

    TriggerServerEvent('ps-laptop:server:StartBoosting', 1)

end, false)

RegisterCommand('getcontract', function()
    TriggerServerEvent('jl-motel:debug', Contracts)
end)

RegisterCommand('queue', function()

    TriggerServerEvent('ps-laptop:server:JoinQueue')

end, false)


---- ** Local functions ** ----

local function HackDelay()
    canHack = false
    Wait(1000 * Config.Boosting.HackDelay)
    canHack = true
end

local function DelayDelivery()
    Wait(math.random(10, 30 * 1000))
    TriggerServerEvent('ps-laptop:server:FinalDestination')
end

local function UpdateBlips()
    local car = NetworkGetEntityFromNetworkId(NetID)
    local Plate = GetVehicleNumberPlateText(car)
    if ActivePlates[Plate] then
        CreateThread(function()
            while ActivePlates[Plate] > 0 do
                if DoesEntityExist(car) then
                    Wait(10000 / ActivePlates[Plate]) -- Max 10 seconds, the more times hacked the less time it updates
                    local pos = GetEntityCoords(car)
                    TriggerServerEvent('ps-laptop:server:SyncBlips', pos, Plate)
                else
                    Wait(500)
                    if not DoesEntityExist(car) then return end -- additional safety check JUST incase, make a cancel events cancelling everything
                end
            end

            TriggerServerEvent('ps-laptop:server:SyncBlips', nil, Plate)
            QBCore.Functions.Notify('Successfully removed tracker', 'success', 7500)
            DelayDelivery()
        end)
    end
end

---- ** Register Net Events ** ----

local AntiSpam = false -- Just a true / false boolean to not spam the shit out of the server.
-- Sends information from server to client that it will start now
RegisterNetEvent('ps-laptop:client:MissionStarted',
    function(netID, coords) -- Pretty much just resets every boolean to make sure no issues will occour.
        NetID = netID
        AntiSpam = false
        canHack = true
        inZone = false

        if PZone then PZone:destroy() PZone = nil end

        if missionBlip then RemoveBlip(missionBlip) end

        if coords then
            missionBlip = AddBlipForRadius(coords.x, coords.y, coords.z, 150.0)
            SetBlipAlpha(missionBlip, 150)
            SetBlipHighDetail(missionBlip, true)
            SetBlipColour(missionBlip, 1)
            SetBlipAsShortRange(missionBlip, true)
        end
    end)

-- sends information from server to client that we found the car and we started lockpicking
RegisterNetEvent('lockpicks:UseLockpick', function()
    if AntiSpam then return end
    if NetID and DoesEntityExist(NetworkGetEntityFromNetworkId(NetID)) then
        local carSpawned = NetworkGetEntityFromNetworkId(NetID)
        local dist = #(GetEntityCoords(carSpawned) - GetEntityCoords(PlayerPedId()))
        if dist <= 2.5 then -- 2.5 is the distance in qbcore vehiclekeys if you use more or less then please edit this.
            AntiSpam = true
            TriggerServerEvent('ps-laptop:server:SpawnPed')
            RemoveBlip(missionBlip)
            --exports['ps-dispatch']:CarJacking(carSpawned)
            UpdateBlips()
        end
    end
end)

-- use this for vinscratching --
exports['qb-target']:AddGlobalVehicle({
    options = {
        {
            type = "client",
            event = "ps-laptop:client:DeliverVehicle",
            icon = 'fas fa-example',
            label = 'Turn in Vehicle',
            canInteract = function(entity)
                if inZone and entity == NetworkGetEntityFromNetworkId(NetID) then return true end
            end,
        }
    },
    distance = 2.5, -- This is the distance for you to be at for the target to turn blue, this is in GTA units and has to be a float value
})

-- Use this for normal boosting --
local function DeliverVehicle()
    CreateThread(function()
        local inCar = false
        while inZone do
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                print("HELLO BRUV")
                inCar = true
            end

            if inCar and not IsPedInAnyVehicle(ped, false) then
                print("IM IN THIS BITCH")
                local veh = GetVehiclePedIsIn(ped, true)
                if veh == NetworkGetEntityFromNetworkId(NetID) then
                    print("ALMOST THERE")
                    if not GetIsVehicleEngineRunning(veh) then
                        inZone = false
                        TriggerEvent('ps-laptop:client:DeliverVehicle')
                    end
                end
            end
            Wait(100)
        end
    end)
end

-- Creates the PolyZone for when you return the car.
RegisterNetEvent('ps-laptop:client:ReturnCar', function(coords, vinscratch, coords2)
    PZone = CircleZone:Create(coords, 5, {
        name = "NewReturnWhoDis",
        debugPoly = true,
    })

    local info = {
        ['blip'] = {
            ['Text'] = 'Boost Drop-off',
            ['Coords'] = coords
        },
        Notification = 'GPS updated with the drop-off location. Bring the car there.'
    }

    PZone:onPlayerInOut(function(isPointInside)
        if isPointInside then
            inZone = true
            DeliverVehicle()
        else
            inZone = false
        end
    end)

    if vinscratch and coords2 then
        PZone2 = CircleZone:Create(coords2, 5, {
            name = "NewScratchWhoDis",
            debugPoly = true,
        })

        PZone2:onPlayerInOut(function(isPointInside)
            if isPointInside then
                CanVinscratch = true
            else
                CanVinscratch = false
            end
        end)

        info['Notification'] = 'GPS updated with the VIN scratch location. Bring the car there.'
        info['blip'].Coords = coords2
        info['blip'].Text = 'VIN Scratch'
    end

    QBCore.Functions.Notify(info.Notification)

    dropoffBlip = AddBlipForCoord(info['blip'].Coords.x, info['blip'].Coords.y, info['blip'].Coords.z)
    SetBlipSprite(dropoffBlip, 326)
    SetBlipScale(dropoffBlip, 1.0)
    SetBlipColour(dropoffBlip, 40)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(info['blip'].Text)
    EndTextCommandSetBlipName(dropoffBlip)
    SetBlipFlashTimer(dropoffBlip, 5000)
end)

RegisterCommand('hackcar', function()
    TriggerEvent("ps-laptop:client:HackCar")
end, false)

-- The event where you can start to hack the vehicle
RegisterNetEvent('ps-laptop:client:HackCar', function()
    local ped = PlayerPedId()
    --if haveItem(Config.Boosting.HackingDevice) then
    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        local plate = GetVehicleNumberPlateText(vehicle)
        if ActivePlates[plate] and ActivePlates[plate] > 0 then
            if canHack then
                -- local pushingP = promise.new()
                -- exports['ps-ui']:Scrambler(function(cb)
                --     pushingP:resolve(cb)
                -- end, "numeric", 30, 0)
                -- local success = Citizen.Await(pushingP)
                local success = true
                if success then
                    QBCore.Functions.Notify('You delayed the police Tracker', 'success', 7500)
                    TriggerServerEvent('ps-laptop:server:SyncPlates', true)
                else
                    QBCore.Functions.Notify('You failed nuub :)', 'error', 7500)
                end
                HackDelay()
            else
                QBCore.Functions.Notify("You must wait atleast " .. Config.Boosting.HackDelay, 'error', 7500)
            end
        end
    end
    --end
end)

-- Gets the ped from the server side and then gives them tasks and weapons on the client side.
RegisterNetEvent('ps-laptop:client:SpawnPeds', function(netIds, Location)
    for i = 1, #netIds do
        local APed = NetworkGetEntityFromNetworkId(netIds[i])
        SetPedDropsWeaponsWhenDead(APed, false)
        GiveWeaponToPed(APed, joaat(Location.peds[i].weapon), 250, false, true)
        SetPedMaxHealth(APed, 500)
        SetPedArmour(APed, 200)
        SetCanAttackFriendly(APed, false, true)
        TaskCombatPed(APed, PlayerPedId(), 0, 16)
        SetPedCombatAttributes(APed, 46, true)
        SetPedCombatAttributes(APed, 0, false)
        SetPedCombatAbility(APed, 100)
        SetPedAsCop(APed, true)
        SetPedRelationshipGroupHash(APed, joaat("HATES_PLAYER"))
        SetPedAccuracy(APed, 60)
        SetPedFleeAttributes(APed, 0, 0)
        SetPedKeepTask(APed, true)
        TaskGoStraightToCoord(APed, Location.carCoords.x, Location.carCoords.y, Location.carCoords.z, 1, -1, 0.0, 0.0)
    end
end)


-- Sennds a event from target to client to say now the vehicle has been delivered.
RegisterNetEvent('ps-laptop:client:DeliverVehicle', function()
    QBCore.Functions.Notify('Get away before noone sees you!', 'error', 7500)
    local car = NetworkGetEntityFromNetworkId(NetID)
    FreezeEntityPosition(car, true)
    if PZone then
        PZone:destroy()
        PZone = nil
    end
    while #QBCore.Functions.GetPlayersFromCoords(GetEntityCoords(car), 100.0) > 0 do
        print(#QBCore.Functions.GetPlayersFromCoords(GetEntityCoords(car), 100.0))
        Wait(7500)
    end
    TriggerServerEvent('ps-laptop:server:finishBoost', NetID)
    RemoveBlip(dropoffBlip)
end)


---- ALL THE SYNCS ----
-- This sync just makes it so anyone can hack a vehicle, that is hackable from boosting
RegisterNetEvent('ps-laptop:client:SyncPlates', function(data)
    ActivePlates = data
end)

-- Sends the information to client when their contracts update
RegisterNetEvent('ps-laptop:client:recieveContract', function(table, recieved)
    print(recieved)
    print(json.encode(table))
    if recieved then
        QBCore.Functions.Notify('You recieved a new contract!', 'success', 7500)
    else

        QBCore.Functions.Notify('Contract started!', 'success', 7500)
    end
    SendNUIMessage({
        action = 'receivecontracts',
        contracts = table
    })
end)

local blips = {} -- Stores all the blips in a table so that PD can see multiple blips at the same time

-- The event that does everything for the blips, checks if the client is police then checks if the blip is active and if it is then remove it and spawn a new
RegisterNetEvent('ps-laptop:client:SyncBlips', function(coords, plate)
    if not isPolice() then return end
    if blips[plate] then RemoveBlip(blips[plate]) end
    if coords then
        blips[plate] = AddBlipForRadius(coords.x, coords.y, coords.z, 35.0)
        SetBlipHighDetail(blips[plate], true)
        SetBlipColour(blips[plate], 1)
        SetBlipAsShortRange(blips[plate], true)
    end
end)

RegisterNetEvent('ps-laptop:client:finishContract', function(table, recieved)
    SendNUIMessage({ action = 'booting/delivered' })
end)

---- ** NUI CALLBACKS ** ----
RegisterNUICallback('boosting/queue', function(cb)
    TriggerServerEvent('ps-laptop:server:JoinQueue', cb.status)
end)

RegisterNUICallback('boosting/start', function(data, cb)
    -- Zoo you can do your stuff here
    local canDo = false
    if canDo then
        TriggerServerEvent('ps-laptop:server:StartBoosting', data.id)
        cb({
            status = 'success'
        })
    else
        cb({
            status = 'error',
            message = "Man.. wth"
        })
    end
    -- print(data.id)


end)

RegisterNUICallback("boosting/getrep", function(_, cb)
    local data = {
        rep = PlayerData.metadata['carboostrep'] or 0,
        repconfig = Config.Boosting.TiersPerRep
    }
    cb(data)
end)
