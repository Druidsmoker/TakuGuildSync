local TakuGuildSync = LibStub("AceAddon-3.0"):NewAddon("TakuGuildSync", "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0", "AceTimer-3.0", "AceHook-3.0")
local AceGUI = LibStub("AceGUI-3.0")
local HBDP = LibStub("HereBeDragons-Pins-2.0")

-- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\ Locals /////////////////////////////////////////////
local gmatch = gmatch
local tinsert = tinsert
local order = order
local sort = sort
local assert = assert
local tremove = tremove
local next = next
local foreach = foreach
local time = time
local date = date
local pairs = pairs
local random = random
local fmod = math.fmod
local strbyte = strbyte
local strlen = strlen
local tostring = tostring
local tonumber = tonumber
local floor = floor
local strsub = strsub
local strfind = strfind
local strupper = strupper
local UnitName = UnitName
local UnitClass = UnitClass
local UnitLevel = UnitLevel
local UnitRace = UnitRace
local GetGuildInfo = GetGuildInfo
local UnitIsPlayer = UnitIsPlayer
local UnitFactionGroup = UnitFactionGroup
local GetNumGuildMembers = GetNumGuildMembers
local GetGuildRosterInfo = GetGuildRosterInfo

-- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\ Constants /////////////////////////////////////////////
local DEBUG                         = false -- handle our own broadcast messages + verbose + friends as enemies + custom commands
local DEBUG_TEST_INVALID_DISCOVER   = false -- DEBUG skips sending invalid discovers, except if this is set
local DEBUG_SELF_DISCOVER           = false -- discover ourself, basically skips discovery

local GLOBAL_COMM_CHANNEL   = "TGSv101" -- change this for major updates that can't coexist (ex: changes to the hash function)
local DB_VERSION_NAME       = "TakuGuildSyncDBv101" -- change here + in .toc for major updates on the data structure

local MAX_EVENT_LOG_SIZE            = 200 -- freeze for a few seconds on open but it's not a problem
local MAX_RECENT_ENCOUNTERS_SIZE    = 20
local MAX_KOS_SIZE                  = 50 -- takes about 12s to sync, 100 takes about 28s

local MSG_TYPE = {
    DISCOVER            = 1,
    WELCOME             = 2,
    SHARE               = 3,
    INVALID_DISCOVER    = 4,
    ALERT               = 5,
}

local KOS_TILE_WIDGET = {
    NAME    = 1,
    LEVEL   = 3,
    GUILD   = 2,
    REASON  = 4,
    CLOSE   = 5,
    TIME    = 6,
}

local EVT_LOG_TYPE = {
    KOS_INSERT              = 1,
    KOS_UPDATE_REASON       = 2,
    KOS_UPDATE_INTERNAL     = 3,
    KOS_UPDATE_ARCHIVE      = 4,
    KOS_FAILED_INSERT_FULL  = 5,
}
local EVT_LOG_LABEL = {
    "KOSInsert",
    "KOSUpdateReason",
    "KOSUpdateInternal",
    "KOSUpdateArchive",
    "KOSFailedInsertFull",
}

local SYNC_STATE = {
     NOT_STARTED    = 1,
     IN_PROGRESS    = 2,
     FINISHED       = 3
}

local DEFAULT_DISCOVER_TIMEOUT          =   20 -- 20 sec
local INTERVAL_BETWEEN_ALERTS           =   60 * 5 -- 5 minutes (playerscan)
local INTERVAL_BETWEEN_DETECTED_SOUND   =   60 -- 1 minute (avoid sound spamming)
local WORLD_MAP_ICON_FADEOUT_TIMER      =   60 * 15 -- 15 minutes
local INTERVAL_BETWEEN_INTERNAL_UPDATES =   60 * 15 -- 15 minutes (playerscan)
local INTERVAL_BETWEEN_SCANS            =   10 -- 10 sec (playerscan)
local REMOVE_KOS_ENTRIES_AFTER          =   3600 * 2 -- 2 hours after last internal or reason update
local NOTIFY_KOS_ENTRY_EXPIRY           =   60 * 15 -- 15 minutes before removal

local DEFAULT_FONT = 'Fonts\\FRIZQT__.TTF'

local dbdefaults = {
    global = {
        KOSList = {
        },
        KOSIgnoreList = {
        },
        EventLog = {
        },
        modules = {
            ChatGuildRank = {
                enabled = true
            }
        },
        KOSOptions = {
            alertSoundId    = 8332, -- PvP Warning
            enlistSoundId   = 890, -- Quest Accepted
            seenSoundId     = 4574, -- PvP Update
        },
        minimap = {
        },
    }
}

local options = {
    name = "TakuGuildSync Options",
    handler = TakuGuildSync,
    type = 'group',
    args = {
        addkos = {
            guiHidden = true,
            type = 'execute',
            name = 'Add target to KOS',
            func = 'AddTargetToKOS',
        },
        kos = {
            guiHidden = true,
            type = 'execute',
            name = 'Show KOS',
            func = 'ShowKOS'
        },
        debug_unarchivekos = {
            guiHidden = true, 
            cmdHidden = not DEBUG,
            type = 'execute',
            name = 'Unarchive all kos [DEBUG]',
            func = 'UnarchiveAll'
        },
        debug_addlog = {
            guiHidden = true,
            cmdHidden = not DEBUG,
            type = 'execute',
            name = 'Add fake event log [DEBUG]',
            func = 'AddEventLogDebug',
        },
        log = {
            guiHidden = true,
            type = 'execute',
            name = 'Event log',
            func = 'ShowEventLog',
        },
        chooseSoundKOSAlert = {
            cmdHidden = true,
            name = "KOS alert sound",
            desc = "Played when an enemy is detected",
            type = "select",
            set = "SetSoundKOSAlert",
            get = "GetSoundKOSAlert",
            style = "dropdown",
            values = {[8332] = "PvP Warning", [847] = "Quest Failed", [8959] = "Raid Warning", [890] = "Quest Accepted", [4574] = "PvP Update", [0] = "Off"},
            order = 1,
        },
        chooseSoundKOSEnlist = {
            cmdHidden = true,
            name = "KOS enlist sound",
            desc = "Played when an enemy is enlisted",
            type = "select",
            set = "SetSoundKOSEnlist",
            get = "GetSoundKOSEnlist",
            style = "dropdown",
            values = {[8332] = "PvP Warning", [847] = "Quest Failed", [8959] = "Raid Warning", [890] = "Quest Accepted", [4574] = "PvP Update", [0] = "Off"},
            order = 2,
        },
        chooseSoundKOSSeen = {
            cmdHidden = true,
            name = "KOS seen sound",
            desc = "Played when an enemy is seen",
            type = "select",
            set = "SetSoundKOSSeen",
            get = "GetSoundKOSSeen",
            style = "dropdown",
            values = {[8332] = "PvP Warning", [847] = "Quest Failed", [8959] = "Raid Warning", [890] = "Quest Accepted", [4574] = "PvP Update", [0] = "Off"},
            order = 3,
        },
        enableChatGuildRank = {
            cmdHidden = true,
            name = "Chat guild rank",
            desc = "Display guild ranks in the chat",
            type = "toggle",
            set = "SetChatGuildRankMod",
            get = "GetChatGuildRankMod",
            order = 4,
        },
        clearHiddenKOS = {
            cmdHidden = true,
            name = "Clear Hidden KOS",
            desc = "If you have ignored some entries in your KOS, this will show them again.",
            type = "execute",
            func = "ClearHiddenKOS",
            confirm = true,
            order = 5,
        },
        restoreDefaults = {
            cmdHidden = true,
            name = "Default Settings",
            desc = "Restore default settings ?",
            type = "execute",
            func = "RestoreDefaultSettings",
            confirm = true,
            order = 6,
        },
        options = {
            guiHidden = true,
            name = "Config menu",
            type = 'execute',
            func = 'ShowOptionsMenu',
        },
        debug_wipekos = {
            guiHidden = true,
            cmdHidden = not DEBUG,
            name = "Wipe KOS",
            desc = "Drop local KOS [DEBUG]",
            type = 'execute',
            func = 'WipeKOS',
        },
        debug_fillkos = {
            guiHidden = true,
            cmdHidden = not DEBUG,
            name = "Fill KOS",
            desc = "Network stress test [DEBUG]",
            type = 'execute',
            func = 'DebugFillKOS'
        },
        clearlogs = {
            guiHidden = true,
            name = "Clear event logs",
            type = 'execute',
            func = 'ClearEventLogs',
        },
        debug_persistkos = {
            guiHidden = true,
            cmdHidden = not DEBUG,
            name = "PersistKOS",
            desc = "Make KOS entry persistant [DEBUG]",
            type = 'input',
            set = 'PersistKOSEntry',
        },
    },
}

-- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\ Utils /////////////////////////////////////////////

local function SplitStringWithDelimiter(s, delimiter)
    result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        tinsert(result, match);
    end
    return result;
end

local function spairs(t, order)
    -- collect the keys
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys 
    if order then
        sort(keys, function(a,b) return order(t, a, b) end)
    else
        sort(keys)
    end

    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end

-- https://wowwiki-archive.fandom.com/wiki/USERAPI_StringHash
local function StringHash(text)
    local counter = 1
    local len = strlen(text)
    for i = 1, len, 3 do 
      counter = fmod(counter*8161, 4294967279) +  -- 2^32 - 17: Prime!
          (strbyte(text,i)*16776193) +
          ((strbyte(text,i+1) or (len-i+256))*8372226) +
          ((strbyte(text,i+2) or (len-i+256))*3932164)
    end
    return fmod(counter, 4294967291) -- 2^32 - 5: Prime (and different from the prime in the loop)
end

-- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\ TakuGuildSync /////////////////////////////////////////////
-- DebugPrint
-- HashKOS
-- UnarchiveAll
-- DebugFillKOS
-- WipeKOS
-- ClearEventLogs
-- PersistKOSEntry
-- ToggleChatGuildRanks
-- SetSoundKOSAlert
-- GetSoundKOSAlert
-- SetSoundKOSEnlist
-- GetSoundKOSEnlist
-- SetSoundKOSSeen
-- GetSoundKOSSeen
-- SetChatGuildRankMod
-- GetChatGuildRankMod
-- RestoreDefaultSettings
-- ClearHiddenKOS
-- AddPlayerToKOS
-- ShareKOS
-- ShareAlert
-- RemoveWorldMapIconForKOS
-- CreateOrUpdateWorldMapIconForKOS
-- HandleAlert
-- AddTargetToKOS
-- RefreshKOSTiles
-- MostRecentKOSEntryBetween
-- RefreshRecentEncountersDropdown
-- CreateKOSTiles
-- ShowKOS
-- InitUI
-- AddEventLogDebug
-- CreateEventLogs
-- ShowEventLog
-- RefreshEventLog
-- SelectNextGuildMemberOnlineFromSnapshot
-- DiscoverTimeout
-- IsGuildMemberOnline
-- GetGuildMemberRank
-- IsInGuild
-- SendDiscover
-- PrepareInitialSync
-- IsKOSEntryOutdated
-- PurgeOutdatedKOSEntries
-- InitSession
-- InitDB
-- ShowOptionsMenu
-- InitMinimapButton
-- OnInitialize
-- AddMessage
-- PlayerScan
-- OnMouseOver
-- OnTargetChanged
-- UnitIsEnemyFaction
-- UnitClassification
-- OnEnable
-- UnitPopup_ShowMenu
-- OnRosterUpdate
-- OnDisable
-- HandleDiscover
-- PostInEventLog
-- MergeKOS
-- ShareNewerKOSDiff
-- HandleWelcome
-- HandleShare
-- HandleInvalidDiscover
-- GlobalCommHandler

function TakuGuildSync:DebugPrint(text)
    if DEBUG then self:Print(text) end
end

function TakuGuildSync:HashKOS()
    self.CountKOSEntries = 0
    result = ''
    foreach(self.db.global.KOSList, function(name,details)
        self.CountKOSEntries = self.CountKOSEntries + 1
        result = result .. name .. details.date_internal_update .. details.date_archive_update .. details.date_reason_update
    end)
    return StringHash(result)
end

function TakuGuildSync:UnarchiveAll() -- DEBUG, does not change the date on purpose
    foreach(self.db.global.KOSList, function(name, details)
        details.archive = false
    end)
    self:RefreshKOSTiles()
end

function TakuGuildSync:DebugFillKOS()
    local id = 1
    local now = time(date("!*t"))
    while self.CountKOSEntries < MAX_KOS_SIZE do
        self.db.global.KOSList["Player"..id] = {
            ["class"] = "Rogue", ["level"] = 42, ["race"] = "Human",
            ["guild"] = "No Guild", ["grank"] = "Soldat",
            ["date_internal_update"] = now,
            ["date_reason_update"] = now, ["reason"] = "by " .. UnitName("player"),
            ["archive"] = false,
            ["initiator"] = UnitName("player"),
            ["date_archive_update"] = now
        }
        self.CountKOSEntries = self.CountKOSEntries + 1
        id = id + 1
    end
    self.stateId = self:HashKOS()
    self:RefreshKOSTiles()
end

function TakuGuildSync:WipeKOS()
    assert(self.syncState ~= SYNC_STATE.IN_PROGRESS, "A sync is already running.")
    self.db.global.KOSList = {}
    self.stateId = self:HashKOS()
    self:RefreshKOSTiles()
end

function TakuGuildSync:ClearEventLogs()
    self.db.global.EventLog = {}
    self:RefreshEventLog()
end

function TakuGuildSync:PersistKOSEntry(_, input)
    local parsedInput = SplitStringWithDelimiter(input," : ")
    if #parsedInput == 2 then
        local name = parsedInput[1]
        local duration = parsedInput[2]
        if self.db.global.KOSList[name] ~= nil then
            local daysDuration = tonumber(duration)
            if daysDuration ~= nil and daysDuration >= 1 and daysDuration <= 30 then
                self:Print("PersistKOSEntry: enlisting of " .. name .. " will last at least " .. daysDuration .. " days.")
                self.db.global.KOSList[name].date_reason_update = time(date("!*t")) + 86400 * daysDuration
                self.stateId = self:HashKOS()
                self:RefreshKOSTiles()
                self:ShareKOS({[name] = self.db.global.KOSList[name]})
            else
                self:Print("PersistKOSEntry: Invalid duration.")
            end
        else
            self:Print("PersistKOSEntry: Invalid name.")
        end
    else
        self:Print("Usage: |cffFF00FF/tgs debug_persistkos [name] : [1-30]|r")
    end
end

function TakuGuildSync:ToggleChatGuildRanks()
    if self.db.global.modules.ChatGuildRank.enabled == true then
        for i = 1, NUM_CHAT_WINDOWS do
            local cf = _G["ChatFrame" .. i]
            if cf ~= COMBATLOG then
                self:RawHook(cf, "AddMessage", true)
            end
        end
    else
        self:Unhook("AddMessage")
    end
end

function TakuGuildSync:SetSoundKOSAlert(info, val)
    PlaySound(val, "Master")
    self.db.global.KOSOptions.alertSoundId = val
end

function TakuGuildSync:GetSoundKOSAlert(info)
    return self.db.global.KOSOptions.alertSoundId
end

function TakuGuildSync:SetSoundKOSEnlist(info, val)
    PlaySound(val, "Master")
    self.db.global.KOSOptions.enlistSoundId = val
end

function TakuGuildSync:GetSoundKOSEnlist(info)
    return self.db.global.KOSOptions.enlistSoundId
end

function TakuGuildSync:SetSoundKOSSeen(info, val)
    PlaySound(val, "Master")
    self.db.global.KOSOptions.seenSoundId = val
end

function TakuGuildSync:GetSoundKOSSeen(info)
    return self.db.global.KOSOptions.seenSoundId
end

function TakuGuildSync:SetChatGuildRankMod(info, val)
    self.db.global.modules.ChatGuildRank.enabled = val
    self:ToggleChatGuildRanks()
end

function TakuGuildSync:GetChatGuildRankMod(info)
    return self.db.global.modules.ChatGuildRank.enabled
end

function TakuGuildSync:RestoreDefaultSettings(info)
    self.db.global.modules.ChatGuildRank.enabled = true
    self.db.global.KOSOptions.seenSoundId = 4574
    self.db.global.KOSOptions.enlistSoundId = 890
    self.db.global.KOSOptions.alertSoundId = 8332
end

function TakuGuildSync:ClearHiddenKOS(info)
    self.db.global.KOSIgnoreList = {}
    self:RefreshKOSTiles()
end

function TakuGuildSync:AddPlayerToKOS(name, class, level, race, guildName, guildRank, date)
    assert(self.CountKOSEntries < MAX_KOS_SIZE, "KOS list has reached its maximum size.")
    self.db.global.KOSList[name] = {
        ["class"] = class, ["level"] = level, ["race"] = race,
        ["guild"] = guildName, ["grank"] = guildRank,
        ["date_internal_update"] = date,
        ["date_reason_update"] = date, ["reason"] = "by " .. UnitName("player"),
        ["initiator"] = UnitName("player"),
        ["archive"] = false, ["date_archive_update"] = date
    }
    self.KOSTimers[name] = {["date_last_alert"] = date, ["date_last_scan"] = date}
    -- remove from recent encounters list
    for key, value in pairs(self.KOSRecentEncounters) do
        if name == value.name then
            tremove(self.KOSRecentEncounters, key)
            break
        end
    end
    self.stateId = self:HashKOS()
    self:RefreshKOSTiles()
    self:ShareKOS({[name] = self.db.global.KOSList[name]})
    self:ShareAlert(name, true)
end

function TakuGuildSync:ShareKOS(data)
    self:DebugPrint("Share -> *")
    local msgMeta = {["stateId"] = self.stateId, ["type"] = MSG_TYPE.SHARE, ["KOSdata"] = data}
    self:SendCommMessage(GLOBAL_COMM_CHANNEL, self:Serialize(msgMeta), "GUILD")
end

function TakuGuildSync:ShareAlert(name, isNewEntry)
    local mapId = C_Map.GetBestMapForUnit("player")
    if mapId ~= nil then
        local position = C_Map.GetPlayerMapPosition(mapId, "player")
        local x = -1
        local y = -1
        if position then
            x, y = position:GetXY()
            x = floor(x * 100)/100
            y = floor(y * 100)/100
            -- if valid position : create or update world map icon
            if isNewEntry then
                self:CreateOrUpdateWorldMapIconForKOS(name, mapId, x, y, true, true)
            else
                self:CreateOrUpdateWorldMapIconForKOS(name, mapId, x, y, false, false)
            end
        end
        self:DebugPrint("Alert -> *")
        local msgMeta = {["type"] = MSG_TYPE.ALERT, ["enemy"] = name, ["mapId"] = mapId, ["posX"] = x, ["posY"] = y, ["newEntry"] = isNewEntry}
        self:SendCommMessage(GLOBAL_COMM_CHANNEL, self:Serialize(msgMeta), "GUILD")
    else
        self:DebugPrint("Unknown map")
    end
end

function TakuGuildSync:RemoveWorldMapIconForKOS(name)
    if self.KOSWorldMapIcons[name] ~= nil then
        self:DebugPrint("Removing icon for " .. name)
        HBDP:RemoveWorldMapIcon(self, self.KOSWorldMapIcons[name].frame)
        self:CancelTimer(self.KOSWorldMapIcons[name].fadeOutTimer)
        self.KOSWorldMapIcons[name]:Release()
        self.KOSWorldMapIcons[name] = nil
    end
end

function TakuGuildSync:CreateOrUpdateWorldMapIconForKOS(name, mapId, posX, posY, soundIfIconCreated, isNewEntry)
    -- update
    if self.KOSWorldMapIcons[name] ~= nil then
        HBDP:RemoveWorldMapIcon(self, self.KOSWorldMapIcons[name].frame)
        self:CancelTimer(self.KOSWorldMapIcons[name].fadeOutTimer)
    else
        -- create
        if soundIfIconCreated then
            if isNewEntry and self.db.global.KOSOptions.enlistSoundId ~= 0 then
                PlaySound(self.db.global.KOSOptions.enlistSoundId, "Master")
            elseif not isNewEntry and self.db.global.KOSOptions.seenSoundId ~= 0 then
                PlaySound(self.db.global.KOSOptions.seenSoundId, "Master")
            end
        end
        self.KOSWorldMapIcons[name] = AceGUI:Create("Icon")
        self.KOSWorldMapIcons[name]:SetImage("Interface\\Icons\\classicon_" .. self.db.global.KOSList[name].class)
        self.KOSWorldMapIcons[name]:SetImageSize(16,16)
        self.KOSWorldMapIcons[name]:SetUserData("name", name)
        self.KOSWorldMapIcons[name]:SetCallback("OnEnter", function(widget)
            local tooltip = AceGUI.tooltip
            local name = widget:GetUserData("name")
            tooltip:SetOwner(widget.frame, "ANCHOR_NONE")
            tooltip:ClearAllPoints()
            tooltip:SetPoint("TOP",widget.frame, 0, 40)
            tooltip:SetText(name, 1, .82, 0, true)
            if self.KOSTimers[name] ~= nil then
                local now = time(date("!*t"))
                local secondsDiff = now - self.KOSTimers[name].date_last_scan
                local timeTooltipText = ""
                if secondsDiff < 60 then
                    timeTooltipText = secondsDiff .. " second(s) ago"
                else
                    timeTooltipText = floor(secondsDiff / 60) .. " minute(s) ago"
                end
                tooltip:AddLine(timeTooltipText, 1, 1, 1)
            end
            tooltip:Show()
        end)
        self.KOSWorldMapIcons[name]:SetCallback("OnLeave", function(widget)
            local tooltip = AceGUI.tooltip
            tooltip:Hide()
        end)
    end
    -- in both cases
    self.KOSWorldMapIcons[name].fadeOutTimer = self:ScheduleTimer("RemoveWorldMapIconForKOS", WORLD_MAP_ICON_FADEOUT_TIMER, name)
    HBDP:AddWorldMapIconMap(self, self.KOSWorldMapIcons[name].frame, mapId, posX, posY, 3)
end

function TakuGuildSync:HandleAlert(sender, data)
    self:DebugPrint("<- Alert")
    if not DEBUG and sender == UnitName("player") then
        return
    end
    if self.db.global.KOSList[data.enemy] ~= nil and self.db.global.KOSList[data.enemy].archive == false and self.db.global.KOSIgnoreList[data.enemy] == nil then
        local now = time(date("!*t"))
        if self.KOSTimers[data.enemy] == nil then
            self.KOSTimers[data.enemy] = {["date_last_alert"] = 0, ["date_last_scan"] = 0}
        end
        local chatAlertEnabled = false
        -- [receiver side text alert] if no one, including us, have seen the enemy since INTERVAL_BETWEEN_ALERTS
        if now > self.KOSTimers[data.enemy].date_last_scan + INTERVAL_BETWEEN_ALERTS then
            chatAlertEnabled = true
            local mapInfo = C_Map.GetMapInfo(data.mapId)
            local chatAlert = "|cffFF0000KOS - " .. data.enemy .. "|r"
            chatAlert = chatAlert .. " |cffffc800[" .. mapInfo.name .. "]|r"
            if data.posX > 0 and data.posY > 0 then
                chatAlert = chatAlert .. " (" .. data.posX .. ", " .. data.posY .. ")"
            end
            chatAlert = chatAlert .. " via " .. sender
            self:Print(chatAlert)
        end
        -- always update world map icon if coords are valid
        if data.posX > 0 and data.posY > 0 then
            self:CreateOrUpdateWorldMapIconForKOS(data.enemy, data.mapId, data.posX, data.posY, chatAlertEnabled and now > self.date_last_detect_sound + INTERVAL_BETWEEN_DETECTED_SOUND, data.isNewEntry)
            self.date_last_detect_sound = now
        end
        self.KOSTimers[data.enemy].date_last_scan = now
    end
end

function TakuGuildSync:AddTargetToKOS(info)
    -- verify target
    local enemy = self:UnitIsEnemyFaction("target")
    local player = UnitIsPlayer("target")
    if (DEBUG or enemy) and player then
        local name, server = UnitName("target")
        if server ~= nil and strlen(server) > 0 then
            name = name .. " - " .. server
        end
        if TakuGuildSync.db.global.KOSList[name] == nil or TakuGuildSync.db.global.KOSList[name].archive == true then
            local now = time(date("!*t"))
            local _, class = UnitClass("target")
            local level = UnitLevel("target")
            if level == -1 then
                level = "??"
            end
            local _, race = UnitRace("target")
            local guildName, guildRank = GetGuildInfo("target")
            self:AddPlayerToKOS(name, class, level, race, guildName, guildRank, now)
        end
    end
end

function TakuGuildSync:RefreshKOSTiles()
    if self.KOSWindow:IsShown() then
        self.KOSTilesContainer:ReleaseChildren()
        self:CreateKOSTiles()
    end
end

function TakuGuildSync:MostRecentKOSEntryBetween(a, b)
    return self.db.global.KOSList[a].date_internal_update > self.db.global.KOSList[b].date_internal_update
end

function TakuGuildSync:RefreshRecentEncountersDropdown()
    if self.RecentEncountersGroup ~= nil then
        self.RecentEncountersGroup:ReleaseChildren()
        -- create dropdown
        local recentEncountersDropdown = AceGUI:Create("Dropdown")
        recentEncountersDropdown:SetLabel("Recent encounters")
        recentEncountersDropdown:SetText("See the players")
        recentEncountersDropdown:SetWidth(200)
        recentEncountersDropdown:SetCallback("OnValueChanged", function(widget, event, key)
            TakuGuildSync.SelectedRecentEncounter = key
            TakuGuildSync.AddRecentEncounterToKOSButton:SetDisabled(false)
        end)
        self.RecentEncountersGroup:AddChild(recentEncountersDropdown)
        self.AddRecentEncounterToKOSButton = AceGUI:Create("Button")
        self.AddRecentEncounterToKOSButton:SetText("Add")
        self.AddRecentEncounterToKOSButton:SetDisabled(true)
        self.AddRecentEncounterToKOSButton:SetWidth(90)
        self.AddRecentEncounterToKOSButton:SetCallback("OnClick", function()
            local details = TakuGuildSync.KOSRecentEncounters[TakuGuildSync.SelectedRecentEncounter]
            if TakuGuildSync.db.global.KOSIgnoreList[details.name] then
                TakuGuildSync.db.global.KOSIgnoreList[details.name] = nil
                -- remove from recent encounters list
                for key, value in pairs(TakuGuildSync.KOSRecentEncounters) do
                    if details.name == value.name then
                        tremove(TakuGuildSync.KOSRecentEncounters, key)
                        break
                    end
                end
                TakuGuildSync:RefreshKOSTiles()
            end
            if TakuGuildSync.db.global.KOSList[details.name] == nil or TakuGuildSync.db.global.KOSList[details.name].archive == true then
                TakuGuildSync:AddPlayerToKOS(details.name, details.class, details.level, details.race, details.guild, details.grank, time(date("!*t")))
            end
        end)
        self.RecentEncountersGroup:AddChild(self.AddRecentEncounterToKOSButton)
        -- populate and enable
        if #self.KOSRecentEncounters == 0 then
            recentEncountersDropdown:SetDisabled(true)
        else
            recentEncountersDropdown:SetDisabled(false)
            foreach(self.KOSRecentEncounters, function(key, details)
                recentEncountersDropdown:AddItem(key, details.name .. " (" .. details.level .. " " .. details.class .. ")")
            end)
        end
    end
end

function TakuGuildSync:CreateKOSTiles()
    -- recent encounters
    self.RecentEncountersGroup = AceGUI:Create("SimpleGroup")
    self.RecentEncountersGroup:SetFullWidth(true)
    self.RecentEncountersGroup:SetAutoAdjustHeight(false)
    self.RecentEncountersGroup:SetHeight(60)
    self.RecentEncountersGroup:SetLayout("Flow")
    self:RefreshRecentEncountersDropdown()
    self.KOSTilesContainer:AddChild(self.RecentEncountersGroup)

    -- KOS list
    for name, details in spairs(self.db.global.KOSList, function(t, a, b) return TakuGuildSync:MostRecentKOSEntryBetween(a, b) end) do
        if not details.archive and self.db.global.KOSIgnoreList[name] == nil then
            local tileFrame = AceGUI:Create("TakuGuildSyncInlineGroup")
            tileFrame:SetLayout("KOSTile")
            tileFrame:SetAutoAdjustHeight(false)
            tileFrame:SetWidth(220)
            tileFrame:SetHeight(130)
            tileFrame.frame.border:SetBackdropColor(0.1,0,0,1)
            tileFrame.frame.border:SetPoint("TOPLEFT", 0, 0)
            tileFrame.frame.border:SetPoint("BOTTOMRIGHT", -8, 6)
            tileFrame.content:SetPoint("TOPLEFT", 12, -12)
            tileFrame.content:SetPoint("BOTTOMRIGHT", -12, 12)

            self.KOSTilesContainer:AddChild(tileFrame)

            local expirationDate = REMOVE_KOS_ENTRIES_AFTER + max(details.date_internal_update, details.date_reason_update)
            local now = time(date("!*t"))
            local alertExpiry = (expirationDate - now < NOTIFY_KOS_ENTRY_EXPIRY)
            --
            local nameLabel = AceGUI:Create("Label")
            nameLabel:SetText(name)
            nameLabel:SetFont(DEFAULT_FONT, 13, '')
            local r, g, b = GetClassColor(strupper(details.class))
            nameLabel:SetColor(r,g,b)
            tileFrame:AddChild(nameLabel)

            local levelRaceLabel = AceGUI:Create("Label")
            levelRaceLabel:SetText(details.level .. " " .. details.race)
            levelRaceLabel:SetFont(DEFAULT_FONT, 11, '')
            tileFrame:AddChild(levelRaceLabel)

            local guildLabel = AceGUI:Create("Label")
            if details.guild then
                guildLabel:SetText("<"..details.guild..">")
                guildLabel:SetColor(1,0,0)
            end
            guildLabel:SetFont(DEFAULT_FONT, 11, '')
            tileFrame:AddChild(guildLabel)

            local reasonText = AceGUI:Create("EditBox")
            if details.reason then
                reasonText:SetText(details.reason)
            end
            if details.date_reason_update > now then
                reasonText:SetDisabled(true)
            end
            reasonText.button:ClearAllPoints()
            reasonText.button:SetPoint("RIGHT",reasonText.frame, 40, 0)
            reasonText:SetWidth(152)
            reasonText:SetMaxLetters(20)
            reasonText:SetUserData("name", name)
            reasonText:SetCallback("OnEnterPressed", function(widget, event, text)
                local name = widget:GetUserData("name")
                TakuGuildSync.db.global.KOSList[name].reason = text
                TakuGuildSync.db.global.KOSList[name].date_reason_update = time(date("!*t"))
                TakuGuildSync.stateId = TakuGuildSync:HashKOS()
                TakuGuildSync:RefreshKOSTiles()
                TakuGuildSync:ShareKOS({[name] = TakuGuildSync.db.global.KOSList[name]})
            end)
            tileFrame:AddChild(reasonText)

            local closeBtn = AceGUI:Create("TakuGuildSyncCloseButton")
            closeBtn:SetUserData("name", name)
            closeBtn:SetUserData("initiator", details.initiator)
            closeBtn:SetCallback("OnClick", function(widget)
                if widget:GetUserData("initiator") == UnitName("player") then
                    local dialog = StaticPopup_Show("TAKUGUILDSYNC_CONFIRM_ARCHIVE")
                    dialog.tgs_name = widget:GetUserData("name")
                else
                    local dialog = StaticPopup_Show("TAKUGUILDSYNC_CONFIRM_IGNORE")
                    dialog.tgs_name = widget:GetUserData("name")
                end
            end)
            tileFrame:AddChild(closeBtn)

            local updateLabel = AceGUI:Create("Label")
            updateLabel:SetJustifyH("LEFT")
            updateLabel:SetFont(DEFAULT_FONT, 10, '')
            if alertExpiry then
                updateLabel:SetText("Expires soon")
                updateLabel:SetColor(1,0,0)
            else
                updateLabel:SetColor(0.5,0.5,0.5)
                local localOffsetWithUTC = time(date('*t')) - time(date('!*t'))
                local localDate = max(details.date_internal_update, details.date_reason_update) + localOffsetWithUTC
                updateLabel:SetText(date("%d/%m/%y %H:%M",localDate))
            end
            tileFrame:AddChild(updateLabel)
        end
    end
end

function TakuGuildSync:ShowKOS()
    if self.KOSWindow:IsShown() == false then
        self:CreateKOSTiles()
        self.KOSWindow:Show()
    end
end

function TakuGuildSync:InitUI()
    StaticPopupDialogs["TAKUGUILDSYNC_CONFIRM_ARCHIVE"] = {
        text = "Remove this player from KOS ?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function(self)
            TakuGuildSync.db.global.KOSList[self.tgs_name].archive = true
            TakuGuildSync.db.global.KOSList[self.tgs_name].date_archive_update = time(date("!*t"))
            --
            TakuGuildSync.stateId = TakuGuildSync:HashKOS()
            TakuGuildSync:RemoveWorldMapIconForKOS(self.tgs_name)
            TakuGuildSync:RefreshKOSTiles()
            TakuGuildSync:ShareKOS({[self.tgs_name] = TakuGuildSync.db.global.KOSList[self.tgs_name]})
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    }
    StaticPopupDialogs["TAKUGUILDSYNC_CONFIRM_IGNORE"] = {
        text = "Hide this player on your KOS ?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function(self)
            TakuGuildSync:RemoveWorldMapIconForKOS(self.tgs_name)
            TakuGuildSync.db.global.KOSIgnoreList[self.tgs_name] = true
            TakuGuildSync:RefreshKOSTiles()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    }
    
    AceGUI:RegisterLayout("KOSTile", function(content, children)
        for i = 1, #children do
			local child = children[i]
            local frame = child.frame
            frame:Show()
            frame:ClearAllPoints()
            if i == KOS_TILE_WIDGET.NAME then
                frame:SetPoint("TOPLEFT", content, 0, 0)
            elseif i == KOS_TILE_WIDGET.LEVEL then
                frame:SetPoint("BOTTOM", children[KOS_TILE_WIDGET.GUILD].frame, 0, -14)
            elseif i == KOS_TILE_WIDGET.GUILD then
                frame:SetPoint("BOTTOM", children[KOS_TILE_WIDGET.NAME].frame, 0, -14)
            elseif i == KOS_TILE_WIDGET.REASON then
                frame:SetPoint("BOTTOM", children[KOS_TILE_WIDGET.GUILD].frame, 0, -50)
                frame:SetPoint("LEFT", content, -2, 0)
            elseif i == KOS_TILE_WIDGET.CLOSE then
                frame:SetPoint("TOPRIGHT", content, 8, 8)
            elseif i == KOS_TILE_WIDGET.TIME then
                frame:SetPoint("BOTTOMLEFT", content, 0, 0)
            end
        end
     end
    )

    -- KOS --
    self.KOSWindow = AceGUI:Create("TakuGuildSyncWindow")
    self.KOSWindow:SetTitle("Taku Guild Sync - Kill on sight (KOS)")
    self.KOSWindow.content:ClearAllPoints()
    self.KOSWindow.content:SetPoint("TOPLEFT",20,-36)
    self.KOSWindow.content:SetPoint("BOTTOMRIGHT",-10, 26)
    self.KOSWindow.frame:SetMinResize(500,260)
    self.KOSWindow:SetWidth(712)
    self.KOSWindow.dialogbg:SetVertexColor(0, 0, 0, 1)
    self.KOSWindow:Hide()
    _G["TakuGuildSyncKOSWindow"] = self.KOSWindow.frame
    tinsert(UISpecialFrames, "TakuGuildSyncKOSWindow")

    self.KOSTilesContainer = AceGUI:Create("ScrollFrame")
    self.KOSTilesContainer:SetFullWidth(true)
    self.KOSTilesContainer:SetFullHeight(true)
    self.KOSTilesContainer:SetLayout("Flow")
    self.KOSWindow:SetCallback("OnClose", function(widget) TakuGuildSync.KOSTilesContainer:ReleaseChildren() end)
    self.KOSWindow:AddChild(self.KOSTilesContainer)

    -- EVENT LOG --
    self.EventLogWindow = AceGUI:Create("TakuGuildSyncWindow")
    self.EventLogWindow:SetTitle("Taku Guild Sync - Event log")
    self.EventLogWindow:Hide()
    self.EventLogWindow.content:ClearAllPoints()
    self.EventLogWindow.content:SetPoint("TOPLEFT",10,-26)
    self.EventLogWindow.content:SetPoint("BOTTOMRIGHT",-10, 26)
    self.EventLogWindow:SetWidth(1200)
    _G["TakuGuildSyncEventLogWindow"] = self.EventLogWindow.frame
    tinsert(UISpecialFrames, "TakuGuildSyncEventLogWindow")
    --self.EventLogWindow:SetPoint("TOPLEFT", UIParent, 0,0)
    self.EventLogContainer = AceGUI:Create("ScrollFrame")
    self.EventLogContainer:SetFullWidth(true)
    self.EventLogContainer:SetFullHeight(true)
    self.EventLogContainer:SetLayout("List")
    self.EventLogWindow:SetCallback("OnClose", function(widget) TakuGuildSync.EventLogContainer:ReleaseChildren() end)
    self.EventLogWindow:AddChild(self.EventLogContainer)

    -- World map icons, created on the fly
    self.KOSWorldMapIcons = {}
end

function TakuGuildSync:AddEventLogDebug()
    if #self.db.global.EventLog >= MAX_EVENT_LOG_SIZE then
        tremove(self.db.global.EventLog, #self.db.global.EventLog)
    end
    tinsert(self.db.global.EventLog, 1, {
        ["action"] = EVT_LOG_TYPE.KOS_INSERT,
        ["initiator"] = "System",
        ["date"] = time(date("!*t")),
        ["entry"] = "Debug",
        ["extra"] = "Some extra data"
    })
    self:RefreshEventLog()
end

function TakuGuildSync:CreateEventLogs()
    -- HEADER row
    local headerRow = AceGUI:Create("SimpleGroup")
    headerRow:SetLayout("Flow")
    headerRow:SetFullWidth(true)
    headerRow:SetHeight(25)
    headerRow:SetAutoAdjustHeight(false)
    headerRow.content:SetPoint("TOPLEFT", 3, -3)
    self.EventLogContainer:AddChild(headerRow)

    local idLabel = AceGUI:Create("Label")
    idLabel:SetWidth(100)
    idLabel:SetText("#")
    idLabel:SetFont(DEFAULT_FONT, 13, '')
    headerRow:AddChild(idLabel)

    local actionLabel = AceGUI:Create("Label")
    actionLabel:SetWidth(200)
    actionLabel:SetText("Action")
    actionLabel:SetFont(DEFAULT_FONT, 13, '')
    headerRow:AddChild(actionLabel)

    local dateLabel = AceGUI:Create("Label")
    dateLabel:SetText("Date")
    dateLabel:SetWidth(200)
    dateLabel:SetFont(DEFAULT_FONT, 13, '')
    headerRow:AddChild(dateLabel)

    local initiatorLabel = AceGUI:Create("Label")
    initiatorLabel:SetWidth(200)
    initiatorLabel:SetText("Initiator")
    initiatorLabel:SetFont(DEFAULT_FONT, 13, '')
    headerRow:AddChild(initiatorLabel)

    local entryLabel = AceGUI:Create("Label")
    entryLabel:SetWidth(200)
    entryLabel:SetText("Subject")
    entryLabel:SetFont(DEFAULT_FONT, 13, '')
    headerRow:AddChild(entryLabel)

    local extraLabel = AceGUI:Create("Label")
    extraLabel:SetWidth(200)
    extraLabel:SetText("Extra")
    extraLabel:SetFont(DEFAULT_FONT, 13, '')
    headerRow:AddChild(extraLabel)

    -- content
    foreach(self.db.global.EventLog, function(index, value)
        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        row:SetHeight(20)
        row:SetAutoAdjustHeight(false)
        row.content:SetPoint("TOPLEFT", 3, 0)
        self.EventLogContainer:AddChild(row)

        local idLabel = AceGUI:Create("Label")
        idLabel:SetWidth(100)
        idLabel:SetText(index)
        idLabel:SetFont(DEFAULT_FONT, 13, '')
        row:AddChild(idLabel)

        local actionLabel = AceGUI:Create("Label")
        actionLabel:SetWidth(200)
        actionLabel:SetText(EVT_LOG_LABEL[value.action])
        actionLabel:SetFont(DEFAULT_FONT, 12, '')
        row:AddChild(actionLabel)

        local dateLabel = AceGUI:Create("Label")
        dateLabel:SetWidth(200)
        local localOffsetWithUTC = time(date('*t')) - time(date('!*t'))
        local localDate = value.date + localOffsetWithUTC
        dateLabel:SetText(date("%d/%m/%y %H:%M",localDate))
        dateLabel:SetFont(DEFAULT_FONT, 12, '')
        row:AddChild(dateLabel)

        local initiatorLabel = AceGUI:Create("Label")
        initiatorLabel:SetWidth(200)
        initiatorLabel:SetText(value.initiator)
        initiatorLabel:SetFont(DEFAULT_FONT, 12, '')
        row:AddChild(initiatorLabel)

        local entryLabel = AceGUI:Create("Label")
        entryLabel:SetWidth(200)
        entryLabel:SetText(value.entry)
        entryLabel:SetFont(DEFAULT_FONT, 12, '')
        row:AddChild(entryLabel)

        local extraLabel = AceGUI:Create("Label")
        extraLabel:SetWidth(200)
        extraLabel:SetText(tostring(value.extra))
        extraLabel:SetFont(DEFAULT_FONT, 12, '')
        row:AddChild(extraLabel)
    end)
end

function TakuGuildSync:ShowEventLog()
    self:CreateEventLogs()
    self.EventLogWindow:Show()
end

function TakuGuildSync:RefreshEventLog()
    if self.EventLogWindow:IsShown() then
        self.EventLogContainer:ReleaseChildren()
        self:CreateEventLogs()
    end
end

function TakuGuildSync:SelectNextGuildMemberOnlineFromSnapshot()
    assert(#self.snapshotOfOnlineGuildMembers > 0, "There should be members left.")
    self:DebugPrint(self.snapshotOfOnlineGuildMembers[self.currentGuildMemberIndexForDiscover] .. " has not replied or is offline, removing him from the list.")
    tremove(self.snapshotOfOnlineGuildMembers, self.currentGuildMemberIndexForDiscover)
    if #self.snapshotOfOnlineGuildMembers > 0 then
        self.currentGuildMemberIndexForDiscover = random(#self.snapshotOfOnlineGuildMembers)
    else
        self.currentGuildMemberIndexForDiscover = -1
    end
end

function TakuGuildSync:DiscoverTimeout()
    assert(self.syncState == SYNC_STATE.IN_PROGRESS, "DiscoverTimeout outside sync ? Should not happen.")
    self:SelectNextGuildMemberOnlineFromSnapshot()
    -- keep trying until list is empty (we don't know who is lagging in the process)
    while #self.snapshotOfOnlineGuildMembers > 0 do
        -- check that he's still online
        if self:IsGuildMemberOnline(self.snapshotOfOnlineGuildMembers[self.currentGuildMemberIndexForDiscover]) then
            self:SendDiscover()
            return
        else
            -- if he went offline, skip to next
            self:SelectNextGuildMemberOnlineFromSnapshot()
        end
    end
    -- if we run out of parents to sync with,
    -- we set ourself sync'd and we share our state for nodes that came online in the meantime.
    self.syncState = SYNC_STATE.FINISHED
    self:Print("Now synchronized.")
    self:DebugPrint("I'm now sync'd because I ran out of priority peers to sync with.")
    self:ShareKOS(self.db.global.KOSList)
end

function TakuGuildSync:IsGuildMemberOnline(name)
    local _,_, numberOfGuildMembersOnline = GetNumGuildMembers()
    for guildMemberIndex = 1, numberOfGuildMembersOnline do
        local fullMemberName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(guildMemberIndex)
        local memberCharacterName = SplitStringWithDelimiter(fullMemberName,"-")[1]
        if memberCharacterName == name and online then
            return true
        end
    end
    return false
end

function TakuGuildSync:GetGuildMemberRank(name)
    local numTotalMembers = GetNumGuildMembers()
    for guildMemberIndex = 1, numTotalMembers do
        local fullMemberName, rank = GetGuildRosterInfo(guildMemberIndex)
        local memberCharacterName = SplitStringWithDelimiter(fullMemberName,"-")[1]
        if memberCharacterName == name then
            return rank
        end
    end
    return nil
end

function TakuGuildSync:IsInGuild(name)
    local numTotalMembers = GetNumGuildMembers()
    for guildMemberIndex = 1, numTotalMembers do
        local fullMemberName = GetGuildRosterInfo(guildMemberIndex)
        local memberCharacterName = SplitStringWithDelimiter(fullMemberName,"-")[1]
        if memberCharacterName == name then
            return true
        end
    end
    return false
end

function TakuGuildSync:SendDiscover()
    self:DebugPrint("Discover -> " .. self.snapshotOfOnlineGuildMembers[self.currentGuildMemberIndexForDiscover])
    local msgMeta = {["stateId"] = self.stateId, ["type"] = MSG_TYPE.DISCOVER}
    if DEBUG_SELF_DISCOVER then
        self:SendCommMessage(GLOBAL_COMM_CHANNEL, self:Serialize(msgMeta), "WHISPER", UnitName("player"))
    else
        self:SendCommMessage(GLOBAL_COMM_CHANNEL, self:Serialize(msgMeta), "WHISPER", self.snapshotOfOnlineGuildMembers[self.currentGuildMemberIndexForDiscover])
    end
    
    self.discoverTimer = self:ScheduleTimer("DiscoverTimeout", DEFAULT_DISCOVER_TIMEOUT)
end

function TakuGuildSync:PrepareInitialSync()
    self.syncState = SYNC_STATE.IN_PROGRESS
    -- fetch online members
    self.snapshotOfOnlineGuildMembers = {}
    local _,_, numberOfGuildMembersOnline = GetNumGuildMembers()
    for guildMemberIndex = 1, numberOfGuildMembersOnline do
        local fullMemberName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(guildMemberIndex)
        -- double check that he's online
        if online then
            -- get rid of server in the name
            local memberCharacterName = SplitStringWithDelimiter(fullMemberName,"-")[1]
            -- exclude self
            if UnitName("player") ~= memberCharacterName then
                tinsert(self.snapshotOfOnlineGuildMembers, memberCharacterName)
            end
        end
    end
    -- if there are members online, pick one at random for sync
    if #self.snapshotOfOnlineGuildMembers > 0 then
        self:Print("Awaiting synchronization ...")
        self.currentGuildMemberIndexForDiscover = random(#self.snapshotOfOnlineGuildMembers)
        self:RegisterComm(GLOBAL_COMM_CHANNEL, "GlobalCommHandler")
        self:SendDiscover()
    else
        -- im the only player online
        self:DebugPrint("I'm the only player online.")
        self.syncState = SYNC_STATE.FINISHED
        self:Print("Now synchronized.")
        self:RegisterComm(GLOBAL_COMM_CHANNEL, "GlobalCommHandler")
    end
end

-- to keep alive an entry, update his listing reason often
function TakuGuildSync:IsKOSEntryOutdated(details)
    return (time(date("!*t")) - max(details.date_internal_update, details.date_reason_update) > REMOVE_KOS_ENTRIES_AFTER)
end

function TakuGuildSync:PurgeOutdatedKOSEntries()
    local now = time(date("!*t"))
    foreach(self.db.global.KOSList, function(name, details)
        if self:IsKOSEntryOutdated(details) then
            self.db.global.KOSList[name] = nil
        end
    end)
end

function TakuGuildSync:InitSession()
    -- timers of last scan and last alert for each enemy
    self.KOSTimers = {}
    -- recent encounters
    self.KOSRecentEncounters = {}
    -- misc timer
    self.date_last_detect_sound = 0 -- for both enlist and seen alerts
    -- state
    self.syncState = SYNC_STATE.NOT_STARTED
    self.stateId = self:HashKOS()
    self:DebugPrint("stateId " .. self.stateId)
end

function TakuGuildSync:InitDB()
    self.db = LibStub("AceDB-3.0"):New(DB_VERSION_NAME, dbdefaults)
    self:PurgeOutdatedKOSEntries()
end

function TakuGuildSync:ShowOptionsMenu()
    InterfaceOptionsFrame_OpenToCategory("TakuGuildSync")
    InterfaceOptionsFrame_OpenToCategory("TakuGuildSync") -- dirty blizzard ui bug, dirty fix
end

function TakuGuildSync:InitMinimapButton()
    local icon = LibStub("LibDBIcon-1.0")
    local minimapLDB = LibStub("LibDataBroker-1.1"):NewDataObject("TakuGuildSyncMiniMap", {
        type = "launcher",
        icon = "Interface\\AddOns\\TakuGuildSync\\Artwork\\takuguildsync-icon.tga",
        OnTooltipShow = function(tooltip)
            tooltip:SetText("Taku Guild Sync")
            tooltip:AddLine("Left click for KOS", 1, 1, 1)
            tooltip:AddLine("Right click for Options", 1, 1, 1)
            tooltip:Show()
        end,
        OnClick = function(_, button)
            if button == "LeftButton" then
                TakuGuildSync:ShowKOS()
            else
                TakuGuildSync:ShowOptionsMenu()
            end
        end,
    })
    icon:Register("TakuGuildSyncMiniMap", minimapLDB, self.db.global.minimap)
end

function TakuGuildSync:OnInitialize()
    self:InitDB() -- load persistant data
    self:InitSession() -- data
    self:InitUI()
    self:InitMinimapButton()
    -- option tables
    LibStub("AceConfig-3.0"):RegisterOptionsTable("TakuGuildSync", options, {'tgs', 'takuguildsync'})
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("TakuGuildSync")
end

function TakuGuildSync:AddMessage(frame, text, ...)
    local parm={...}
    for i=1, #parm do
        if i == 4 and parm[i] == 5 then
            local startGuildIndex, endGuildIndex = strfind(text, "(%[(.-)%])")
            if endGuildIndex ~= nil then
                local _, _, nameInBrackets = strfind(text, "(%[(.-)%])", endGuildIndex + 1)
                if nameInBrackets ~= nil then
                    local name = strsub(nameInBrackets, 2, #nameInBrackets - 1)
                    local guildRank = self:GetGuildMemberRank(name)
                    if guildRank ~= nil then
                        local beforeSub = strsub(text, 1, startGuildIndex - 1)
                        local afterSub = strsub(text, endGuildIndex + 1)
                        text = beforeSub .. "[" .. guildRank .. "]" .. afterSub
                    end
                end
            end
        end
    end
    return self.hooks[frame].AddMessage(frame, text, ...)
end

function TakuGuildSync:PlayerScan(unit)
    local enemy = self:UnitIsEnemyFaction(unit)
    local player = UnitIsPlayer(unit)
    if (DEBUG or enemy) and player then
        local name, server = UnitName(unit)
        if server ~= nil and strlen(server) > 0 then
            name = name .. " - " .. server
        end
        if self.db.global.KOSList[name] and self.db.global.KOSList[name].archive == false and self.db.global.KOSIgnoreList[name] == nil then
            local now = time(date("!*t"))
            -- create timers if needed
            if self.KOSTimers[name] == nil then
                self.KOSTimers[name] = {["date_last_alert"] = 0, ["date_last_scan"] = 0}
            end
            -- [personal alert sound] when you actually see the enemy for the first time in a while,
            -- has to be done first because scan part also set the date_last_alert
            if now > self.KOSTimers[name].date_last_alert + INTERVAL_BETWEEN_ALERTS then
                if self.db.global.KOSOptions.alertSoundId ~= 0 then
                    PlaySound(self.db.global.KOSOptions.alertSoundId, "Master")
                end
                local chatAlert = "|cffFF0000KOS - " .. name .. "|r"
                if self.db.global.KOSList[name].reason then
                    chatAlert = chatAlert .. "|cffc9c9c9 (" .. self.db.global.KOSList[name].reason .. ")|r"
                end
                self:Print(chatAlert)
                -- not really needed because INTERVAL_BETWEEN_SCANS < INTERVAL_BETWEEN_ALERTS but whatever
                self.KOSTimers[name].date_last_alert = now
            end
            -- scan, happens every couple seconds to update position
            if now > self.KOSTimers[name].date_last_scan + INTERVAL_BETWEEN_SCANS then
                -- internal updates (not too often)
                if now > self.db.global.KOSList[name].date_internal_update + INTERVAL_BETWEEN_INTERNAL_UPDATES then
                    local _, class = UnitClass(unit)
                    local level = UnitLevel(unit)
                    if level == -1 then
                        level = "??"
                    end
                    local _, race = UnitRace(unit)
                    local guildName, guildRank = GetGuildInfo(unit)
                    self.db.global.KOSList[name].date_internal_update = now
                    self.db.global.KOSList[name].class = class
                    self.db.global.KOSList[name].race = race
                    self.db.global.KOSList[name].level = level
                    self.db.global.KOSList[name].guild = guildName
                    self.db.global.KOSList[name].grank = guildRank
                    self.stateId = self:HashKOS()
                    self:RefreshKOSTiles()
                    self:ShareKOS({[name] = self.db.global.KOSList[name]})
                end
                -- save & share
                self.KOSTimers[name].date_last_alert = now
                self.KOSTimers[name].date_last_scan = now
                self:ShareAlert(name, false)
            end
        else -- player not in KOS so keep him in the recent encounters list
            for key, value in pairs(self.KOSRecentEncounters) do
                if value.name == name then
                    tremove(self.KOSRecentEncounters, key)
                    break
                end
            end
            local _, class = UnitClass(unit)
            local level = UnitLevel(unit)
            if level == -1 then
                level = "??"
            end
            local _, race = UnitRace(unit)
            local guildName, guildRank = GetGuildInfo(unit)
            tinsert(self.KOSRecentEncounters, 1, {
                ["name"] = name, ["class"] = class, ["level"] = level, ["race"] = race,
                ["guild"] = guildName, ["grank"] = guildRank})
            if #self.KOSRecentEncounters > MAX_RECENT_ENCOUNTERS_SIZE then
                tremove(self.KOSRecentEncounters, #self.KOSRecentEncounters)
            end
            if self.KOSWindow:IsShown() then
                self:RefreshRecentEncountersDropdown()
            end
        end
    end
end

function TakuGuildSync:OnMouseOver()
    self:PlayerScan("mouseover")
end

function TakuGuildSync:OnTargetChanged()
    self:PlayerScan("target")
end

function TakuGuildSync:UnitIsEnemyFaction(unit)
    local selfFaction = UnitFactionGroup("player")
    local unitFaction = UnitFactionGroup(unit)
    return (selfFaction ~= unitFaction)
end

function TakuGuildSync:UnitClassification(unit)
    local enemy = self:UnitIsEnemyFaction(unit)
    local player = UnitIsPlayer(unit)
    if (DEBUG or enemy) and player then
        local name, server = UnitName(unit)
        if server ~= nil and strlen(server) > 0 then
            name = name .. " - " .. server
        end
        if self.db.global.KOSList[name] and self.db.global.KOSList[name].archive == false and not self.db.global.KOSIgnoreList[name] then
            return "rare"
        end
    end
    return self.hooks.UnitClassification(unit)
end

function TakuGuildSync:OnEnable()
    self:RegisterEvent("GUILD_ROSTER_UPDATE", "OnRosterUpdate")
    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "OnMouseOver")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
    self:ToggleChatGuildRanks()
    self:SecureHook("UnitPopup_ShowMenu")
    self:RawHook("UnitClassification", true)
end

function TakuGuildSync:UnitPopup_ShowMenu(dropdownMenu, which, unit)
    -- skip submenus
	if UIDROPDOWNMENU_MENU_LEVEL > 1 or unit ~= "target" then
		return
	end
    -- verify target
    local enemy = self:UnitIsEnemyFaction("target")
    local player = UnitIsPlayer("target")
    if (DEBUG or enemy) and player then
        local name, server = UnitName("target")
        if server ~= nil and strlen(server) > 0 then
            name = name .. " - " .. server
        end
        -- create menu
        local info = UIDropDownMenu_CreateInfo()
        UIDropDownMenu_AddSeparator(1)
        info.text = "Taku Guild Sync"
        info.owner = which
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)
        info.isTitle = false
        if self.db.global.KOSList[name] and self.db.global.KOSList[name].archive == false and TakuGuildSync.db.global.KOSIgnoreList[name] == nil then
            info.disabled = true
        else
            local _, class = UnitClass("target")
            local level = UnitLevel("target")
            if level == -1 then
                level = "??"
            end
            local _, race = UnitRace("target")
            local guildName, guildRank = GetGuildInfo("target")
            info.disabled = false
            info.arg1 = {
                name = name,
                class = class,
                level = level,
                race = race,
                guildName = guildName,
                guildRank = guildRank,
            }
            info.func = function(self, info)
                if TakuGuildSync.db.global.KOSIgnoreList[info.name] then
                    TakuGuildSync.db.global.KOSIgnoreList[info.name] = nil
                    -- remove from recent encounters list
                    for key, value in pairs(TakuGuildSync.KOSRecentEncounters) do
                        if info.name == value.name then
                            tremove(TakuGuildSync.KOSRecentEncounters, key)
                            break
                        end
                    end
                    TakuGuildSync:RefreshKOSTiles()
                end
                if TakuGuildSync.db.global.KOSList[info.name] == nil or TakuGuildSync.db.global.KOSList[info.name].archive == true then
                    TakuGuildSync:AddPlayerToKOS(info.name, info.class, info.level, info.race, info.guildName, info.guildRank, time(date("!*t")))
                end
            end
        end
        info.text = "Add to KOS"
        info.owner = which
        info.notCheckable = 1
        UIDropDownMenu_AddButton(info)
        if self.db.global.KOSList[name] and self.db.global.KOSList[name].initiator ~= UnitName("player") then
            info.text = "Hide on your KOS"
        else
            info.text = "Remove from KOS"
        end
        if self.db.global.KOSList[name] and
           ((self.db.global.KOSList[name].initiator == UnitName("player") and self.db.global.KOSList[name].archive == false) or
           (self.db.global.KOSList[name].initiator ~= UnitName("player") and TakuGuildSync.db.global.KOSIgnoreList[name] == nil)) then
            info.disabled = false
            info.arg1 = {
                name = name,
            }
            info.func = function(self, info)
                if TakuGuildSync.db.global.KOSList[info.name].initiator ~= UnitName("player") then
                    TakuGuildSync.db.global.KOSIgnoreList[info.name] = true
                    TakuGuildSync:RemoveWorldMapIconForKOS(info.name)
                    TakuGuildSync:RefreshKOSTiles()
                elseif TakuGuildSync.db.global.KOSList[info.name].archive == false then
                    TakuGuildSync.db.global.KOSList[info.name].archive = true
                    TakuGuildSync.db.global.KOSList[info.name].date_archive_update = time(date("!*t"))
                    --
                    TakuGuildSync.stateId = TakuGuildSync:HashKOS()
                    TakuGuildSync:RemoveWorldMapIconForKOS(info.name)
                    TakuGuildSync:RefreshKOSTiles()
                    TakuGuildSync:ShareKOS({[info.name] = TakuGuildSync.db.global.KOSList[info.name]})
                end
            end
        else
            info.disabled = true
        end
        UIDropDownMenu_AddButton(info)
    end
end

function TakuGuildSync:OnRosterUpdate()
    local _,_, numberOfGuildMembersOnline = GetNumGuildMembers()
    if numberOfGuildMembersOnline > 0 then
        self:UnregisterEvent("GUILD_ROSTER_UPDATE")
        assert(self.syncState == SYNC_STATE.NOT_STARTED, "Sync should not be started at this point.")
        self:PrepareInitialSync()
    end
end

function TakuGuildSync:OnDisable()
	self:UnregisterAllEvents()
    self:Unhook("UnitPopup_ShowMenu")
    self:Unhook("UnitClassification")
end

function TakuGuildSync:HandleDiscover(sender, otherStateId)
    self:DebugPrint("<- Discover (" .. sender .. ") " .. otherStateId)
    -- if we are not sync'd ourself, we reject this discover
    if (not DEBUG or DEBUG_TEST_INVALID_DISCOVER) and self.syncState ~= SYNC_STATE.FINISHED then
        local msgMeta = {["type"] = MSG_TYPE.INVALID_DISCOVER}
        self:DebugPrint("Invalid Discover -> " .. sender)
        self:SendCommMessage(GLOBAL_COMM_CHANNEL, self:Serialize(msgMeta), "WHISPER", sender)
        return
    end
    local msgMeta = {["stateId"] = self.stateId, ["type"] = MSG_TYPE.WELCOME}
    if otherStateId ~= self.stateId then
        msgMeta["KOSdata"] = self.db.global.KOSList
    end
    self:DebugPrint("Welcome -> " .. sender)
    self:SendCommMessage(GLOBAL_COMM_CHANNEL, self:Serialize(msgMeta), "WHISPER", sender)
end

function TakuGuildSync:PostInEventLog(action, initiator, date, entry, extra)
    if #self.db.global.EventLog >= MAX_EVENT_LOG_SIZE then
        tremove(self.db.global.EventLog, #self.db.global.EventLog)
    end
    tinsert(self.db.global.EventLog, 1, {
        ["action"] = action, 
        ["initiator"] = initiator, 
        ["date"] = date, 
        ["entry"] = entry,
        ["extra"] = extra
    })
    self:RefreshEventLog()
end

function TakuGuildSync:MergeKOS(sender, otherData)
    self:DebugPrint("Merging KOS ...")
    local refreshKOS = false
    local now = time(date("!*t"))
    foreach(otherData, function(name, details)
        -- ignore outdated
        if self:IsKOSEntryOutdated(details) then
            return
        end
        -- update
        if self.db.global.KOSList[name] then
            -- internal updates (everything that is not human action)
            if details.date_internal_update > self.db.global.KOSList[name].date_internal_update then
                refreshKOS = true
                self:PostInEventLog(EVT_LOG_TYPE.KOS_UPDATE_INTERNAL, sender, now, name, details.date_internal_update)
                self.db.global.KOSList[name].level = details.level
                self.db.global.KOSList[name].class = details.class
                self.db.global.KOSList[name].race = details.race
                self.db.global.KOSList[name].guild = details.guild
                self.db.global.KOSList[name].grank = details.grank
                self.db.global.KOSList[name].date_internal_update = details.date_internal_update      
            end
            -- (un)archive action
            if details.date_archive_update > self.db.global.KOSList[name].date_archive_update then
                refreshKOS = true
                self:PostInEventLog(EVT_LOG_TYPE.KOS_UPDATE_ARCHIVE, sender, now, name, details.archive)
                self.db.global.KOSList[name].archive = details.archive
                self.db.global.KOSList[name].date_archive_update = details.date_archive_update
                -- remove world map icon if archived
                if details.archive == true then
                    self:RemoveWorldMapIconForKOS(name)
                end
            end
            -- reason action
            if details.date_reason_update > self.db.global.KOSList[name].date_reason_update then
                refreshKOS = true
                self:PostInEventLog(EVT_LOG_TYPE.KOS_UPDATE_REASON, sender, now, name, details.reason)
                self.db.global.KOSList[name].reason = details.reason
                self.db.global.KOSList[name].date_reason_update = details.date_reason_update
            end
        else -- add
            if self.CountKOSEntries >= MAX_KOS_SIZE then
                self:PostInEventLog(EVT_LOG_TYPE.KOS_FAILED_INSERT_FULL, sender, now, name, nil)
            else
                refreshKOS = true
                self:PostInEventLog(EVT_LOG_TYPE.KOS_INSERT, sender, now, name, details.date_internal_update)
                self.db.global.KOSList[name] = details
            end
        end
    end)
    if refreshKOS == true then
        self.stateId = self:HashKOS()
        self:RefreshKOSTiles()
    end
end

function TakuGuildSync:ShareNewerKOSDiff(otherData)
    local newerKOSDiff = {}
    foreach(self.db.global.KOSList, function(name, details)
        if otherData[name] ~= nil then
            if details.date_internal_update > otherData[name].date_internal_update or 
            details.date_archive_update > otherData[name].date_archive_update or
            details.date_reason_update > otherData[name].date_reason_update then
                newerKOSDiff[name] = details
            end
        else
            newerKOSDiff[name] = details
        end
    end)
    if next(newerKOSDiff) ~= nil then
        self:ShareKOS(newerKOSDiff)
    end
end

function TakuGuildSync:HandleWelcome(sender, otherStateId, otherData)
    -- Welcome msg is handled even if we're already sync'd (in case our discover target was lagging)
    self:CancelTimer(self.discoverTimer)
    self:DebugPrint("<- Welcome " .. sender .. " " .. otherStateId)
    if self.stateId ~= otherStateId and otherData ~= nil then
        self:MergeKOS(sender, otherData)
        -- share parts of our version that are newer than theirs
        self:ShareNewerKOSDiff(otherData)
    else
        self:DebugPrint("Already up to date.")
    end
    self.syncState = SYNC_STATE.FINISHED
    self:Print("Now synchronized.")
end

function TakuGuildSync:HandleShare(sender, otherStateId, otherData)
    self:DebugPrint("<- Share " .. sender .. " " .. otherStateId)
    if not DEBUG and sender == UnitName("player") then
        return
    end
    if otherStateId ~= self.stateId then
        self:MergeKOS(sender, otherData)
    else
        self:DebugPrint("Already up to date.")
    end
end

function TakuGuildSync:HandleInvalidDiscover(sender)
    self:DebugPrint("<- Invalid Discover (" .. sender .. ")")
    -- discard if we receive too late
    if self.syncState == SYNC_STATE.FINISHED then
        return
    end
    -- remove this player from the list and try again
    self:CancelTimer(self.discoverTimer)
    tremove(self.snapshotOfOnlineGuildMembers, self.currentGuildMemberIndexForDiscover)
    -- keep trying until list is empty
    if #self.snapshotOfOnlineGuildMembers > 0 then
        self.currentGuildMemberIndexForDiscover = random(#self.snapshotOfOnlineGuildMembers)
        self:SendDiscover()
    else
        -- if we run out of parents to sync with,
        -- we set ourself sync'd and we share our state for nodes that came online in the meantime.
        self.syncState = SYNC_STATE.FINISHED
        self:Print("Now synchronized.")
        self:DebugPrint("I'm now sync'd because I ran out of priority peers to sync with.")
        self:ShareKOS(self.db.global.KOSList)
    end
end

function TakuGuildSync:GlobalCommHandler(prefix, message, scope, sender)
    local success, msgMeta = self:Deserialize(message)
    if success then
        if self:IsInGuild(sender) then
            if msgMeta.type == MSG_TYPE.DISCOVER then
                self:HandleDiscover(sender, msgMeta.stateId)
            elseif msgMeta.type == MSG_TYPE.WELCOME then
                self:HandleWelcome(sender, msgMeta.stateId, msgMeta.KOSdata)
            elseif msgMeta.type == MSG_TYPE.SHARE then
                self:HandleShare(sender, msgMeta.stateId, msgMeta.KOSdata)
            elseif msgMeta.type == MSG_TYPE.INVALID_DISCOVER then
                self:HandleInvalidDiscover(sender)
            elseif msgMeta.type == MSG_TYPE.ALERT then
                self:HandleAlert(sender, msgMeta)
            end
        else
            self:DebugPrint("Player in not in the guild - discard message.")
        end
    else
        self:DebugPrint("Error in comm msg format.")
    end
end
