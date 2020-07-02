local easing = require("easing")
local MakePlayerCharacter = require("prefabs/player_common")

local assets =
{
    Asset("SCRIPT", "scripts/prefabs/player_common.lua"),
    Asset("ANIM", "anim/player_wolfgang.zip"),
    Asset("ANIM", "anim/player_mount_wolfgang.zip"),
    Asset("SOUND", "sound/wolfgang.fsb"),
}

local start_inv = {}
for k, v in pairs(TUNING.GAMEMODE_STARTING_ITEMS) do
	start_inv[string.lower(k)] = v.WOLFGANG
end

local prefabs = FlattenTree(start_inv, true)

local function OnMounted(inst)
    inst.components.locomotor:SetExternalSpeedMultiplier(inst, "mounted_mightiness", 1 / inst._mightiness_scale)
end

local function OnDismounted(inst)
    inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "mounted_mightiness")
end

local function applymightiness(inst)
    local damage_mult = TUNING.WOLFGANG_ATTACKMULT_NORMAL

    local mighty_scale = 1.3
    local normal_scale = 1.1
    local wimpy_scale = 0.9

    -- set plus max body scale
    local scale_max = 0.5 -- ex: (NORMAL FORM) normal_scale + 0.5 = 1.6
    -- set plus multiplier damage
    local mult_max = 2 -- ex: (NORMAL FORM) damage_mult + 2 = 3

    if inst.strength == "mighty" then
        damage_mult = TUNING.WOLFGANG_ATTACKMULT_MIGHTY_MAX
        inst._mightiness_scale = mighty_scale
    elseif inst.strength == "wimpy" then
        damage_mult = TUNING.WOLFGANG_ATTACKMULT_WIMPY_MAX
        inst._mightiness_scale = wimpy_scale
    else
        inst._mightiness_scale = normal_scale
    end

    if inst.components.health:GetPercent() < TUNING.WOLFGANG_TRIGGERED_PERCENT then
        if TheWorld.state.phase == "day" then
            damage_mult = TUNING.WOLFGANG_ATTACKMULT_MIGHTY_MAX
            inst._mightiness_scale = mighty_scale
        elseif TheWorld.state.phase == "dusk" then
            damage_mult = TUNING.WOLFGANG_ATTACKMULT_NORMAL
            inst._mightiness_scale = normal_scale
        elseif TheWorld.state.phase == "night" then
            damage_mult = TUNING.WOLFGANG_ATTACKMULT_WIMPY_MAX
            inst._mightiness_scale = wimpy_scale
        end
        local health_delta = (TUNING.WOLFGANG_TRIGGERED_PERCENT - inst.components.health:GetPercent())/TUNING.WOLFGANG_TRIGGERED_PERCENT
        damage_mult = damage_mult + (health_delta * mult_max)
        inst._mightiness_scale = inst._mightiness_scale + (health_delta * scale_max)
    end

    inst:ApplyScale("mightiness", inst._mightiness_scale)
    inst.components.combat.damagemultiplier = damage_mult

    if inst.components.rider:IsRiding() then
        OnMounted(inst)
    end
end

local function becomewimpy(inst, silent)
    if inst.strength == "wimpy" then
        return
    end

    inst.components.skinner:SetSkinMode("wimpy_skin", "wolfgang_skinny")

    if not silent then
        inst.sg:PushEvent("powerdown")
        inst.components.talker:Say(GetString(inst, "ANNOUNCE_NORMALTOWIMPY"))
        inst.SoundEmitter:PlaySound("dontstarve/characters/wolfgang/shrink_medtosml")
    end

    inst.talksoundoverride = "dontstarve/characters/wolfgang/talk_small_LP"
    inst.hurtsoundoverride = "dontstarve/characters/wolfgang/hurt_small"
    inst.strength = "wimpy"
end

local function becomenormal(inst, silent)
    if inst.strength == "normal" then
        return
    end

    inst.components.skinner:SetSkinMode("normal_skin", "wolfgang")

    if not silent then
        if inst.strength == "mighty" then
            inst.components.talker:Say(GetString(inst, "ANNOUNCE_MIGHTYTONORMAL"))
            inst.sg:PushEvent("powerdown")
            inst.SoundEmitter:PlaySound("dontstarve/characters/wolfgang/shrink_lrgtomed")
        elseif inst.strength == "wimpy" then
            inst.components.talker:Say(GetString(inst, "ANNOUNCE_WIMPYTONORMAL"))
            inst.sg:PushEvent("powerup")
            inst.SoundEmitter:PlaySound("dontstarve/characters/wolfgang/grow_smtomed")
        end
    end

    inst.talksoundoverride = nil
    inst.hurtsoundoverride = nil
    inst.strength = "normal"
end

local function becomemighty(inst, silent)
    if inst.strength == "mighty" then
        return
    end

    inst.components.skinner:SetSkinMode("mighty_skin", "wolfgang_mighty")

    if not silent then
        inst.components.talker:Say(GetString(inst, "ANNOUNCE_NORMALTOMIGHTY"))
        inst.sg:PushEvent("powerup")
        inst.SoundEmitter:PlaySound("dontstarve/characters/wolfgang/grow_medtolrg")
    end

    inst.talksoundoverride = "dontstarve/characters/wolfgang/talk_large_LP"
    inst.hurtsoundoverride = "dontstarve/characters/wolfgang/hurt_large"
    inst.strength = "mighty"
end

local function onPhaseChanged(inst, data, forcesilent)
    if inst.components.health:GetPercent() > TUNING.WOLFGANG_TRIGGERED_PERCENT then
        if inst.sg:HasStateTag("nomorph") or
            inst:HasTag("playerghost") or
            inst.components.health:IsDead() then
            return
        end

        if TheWorld.state.phase == "day" then
            becomemighty(inst, false)
        elseif TheWorld.state.phase == "dusk" then
            becomenormal(inst, false)
        elseif TheWorld.state.phase == "night" then
            becomewimpy(inst, false)
        end

        applymightiness(inst)
    end
end

local function onhealthchange(inst, data, forcesilent)
    if inst.sg:HasStateTag("nomorph") or
        inst:HasTag("playerghost") or
        inst.components.health:IsDead() then
        return
    end

    if inst.components.health:GetPercent() < TUNING.WOLFGANG_TRIGGERED_PERCENT then
        becomemighty(inst, false) 
        applymightiness(inst)
    else 
        onPhaseChanged(inst, nil, true) 
    end
end

local function onnewstate(inst)
    if inst._wasnomorph ~= inst.sg:HasStateTag("nomorph") then
        inst._wasnomorph = not inst._wasnomorph
        if not inst._wasnomorph then
            onhealthchange(inst)
        end
    end
end

local function onbecamehuman(inst, data)
    print("---------------------- ON BECAME HUMAN ----------------------")
    if inst._wasnomorph == nil then
        if not (data ~= nil and data.corpse) then
            inst.strength = "normal"
        end
        inst._wasnomorph = inst.sg:HasStateTag("nomorph")
        inst.talksoundoverride = nil
        inst.hurtsoundoverride = nil
        
        inst:WatchWorldState("phase", onPhaseChanged)
        inst:ListenForEvent("newstate", onnewstate)
        inst:ListenForEvent("healthdelta", onhealthchange)
        onhealthchange(inst, nil, true)
        inst.components.health:SetPercent(TUNING.WOLFGANG_TRIGGERED_PERCENT, true)
        becomenormal(inst, true)
    end
end

local function onbecameghost(inst, data)
    print("---------------------- ON BECAME GHOST ----------------------")
    if inst._wasnomorph ~= nil then
        if not (data ~= nil and data.corpse) then
            inst.strength = "normal"
        end
        inst._wasnomorph = nil
        inst.talksoundoverride = nil
        inst.hurtsoundoverride = nil
        inst:StopWatchingWorldState("phase", onPhaseChanged)
        inst:RemoveEventCallback("newstate", onnewstate)
        inst:RemoveEventCallback("healthdelta", onhealthchange)
    end
end

local function onload(inst)
    print("---------------------- ON LOAD ----------------------")
    inst:ListenForEvent("ms_respawnedfromghost", onbecamehuman)
    inst:ListenForEvent("ms_becameghost", onbecameghost)

    --Restore absolute health value from loading after mightiness scaling
    local loadhealth = inst._loadhealth or inst.components.health.currenthealth
    inst._loadhealth = nil

    if inst:HasTag("playerghost") then
        onbecameghost(inst)
    elseif inst:HasTag("corpse") then
        onbecameghost(inst, { corpse = true })
    else
        onbecamehuman(inst)
    end

    inst.components.health:SetPercent(loadhealth / inst.components.health.maxhealth, true)
end

local function onpreload(inst, data)
    print("---------------------- PRE LOAD ----------------------")
    if data ~= nil and data.health ~= nil then
        inst._loadhealth = data.health.health
    end
end

--------------------------------------------------------------------------

local BASE_PHYSICS_RADIUS = .5
local AVATAR_SCALE = 1.5

local function lavaarena_onisavatardirty(inst)
    inst:SetPhysicsRadiusOverride(inst._isavatar:value() and AVATAR_SCALE * BASE_PHYSICS_RADIUS or BASE_PHYSICS_RADIUS)
end

--------------------------------------------------------------------------

local function common_postinit(inst)
    print("----------------------COMMON POS INIT----------------------")
    if TheNet:GetServerGameMode() == "lavaarena" then
        inst._isavatar = net_bool(inst.GUID, "wolfgang._isavatar", "isavatardirty")

        if not TheWorld.ismastersim then
            inst:ListenForEvent("isavatardirty", lavaarena_onisavatardirty)
        end

        lavaarena_onisavatardirty(inst)
    elseif TheNet:GetServerGameMode() == "quagmire" then
        inst:AddTag("quagmire_ovenmaster")
        inst:AddTag("quagmire_shopper")
    end
end

local function master_postinit(inst)
    print("----------------------MASTER POS INIT----------------------")
    inst.starting_inventory = start_inv[TheNet:GetServerGameMode()] or start_inv.default

    inst.strength = "normal"
    inst._mightiness_scale = 1
    inst._wasnomorph = nil
    inst.talksoundoverride = nil
    inst.hurtsoundoverride = nil

    inst.components.hunger:SetMax(TUNING.WOLFGANG_HUNGER)

    inst.components.foodaffinity:AddPrefabAffinity("potato_cooked", TUNING.AFFINITY_15_CALORIES_MED)

    if TheNet:GetServerGameMode() == "lavaarena" then
        inst.OnIsAvatarDirty = lavaarena_onisavatardirty
        event_server_data("lavaarena", "prefabs/wolfgang").master_postinit(inst)
    else
        inst.components.health:SetMaxHealth(TUNING.WOLFGANG_HEALTH_NORMAL)
        inst.components.hunger.current = TUNING.WOLFGANG_START_HUNGER

		inst.components.sanity:SetMax(TUNING.WOLFGANG_SANITY)
        inst.components.sanity.night_drain_mult = 1.1
        inst.components.sanity.neg_aura_mult = 1.1

        inst.OnPreLoad = onpreload
        inst.OnLoad = onload
        inst.OnNewSpawn = onload
    end

    inst:ListenForEvent("mounted", OnMounted)
    inst:ListenForEvent("dismounted", OnDismounted)
end

return MakePlayerCharacter("wolfgang", prefabs, assets, common_postinit, master_postinit)
