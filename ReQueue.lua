-----------------------------------------------------------------------------------------------
-- Client Lua Script for ReQueue
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
require "Apollo"
require "Window"
require "GameLib"
require "GroupLib"
require "MatchingGame"

-----------------------------------------------------------------------------------------------
-- ReQueue Module Definition
-----------------------------------------------------------------------------------------------
local ReQueue = {}

ReQueue.EnumQueueType = {
    ["SoloQueue"] = 0,
    ["GroupQueue"] = 1
}

local InInstanceGroup = GroupLib.InInstance
local InGroup = GroupLib.InGroup
local Queue = MatchingGame.Queue
local QueueAsGroup = MatchingGame.QueueAsGroup
local IsCharacterLoaded = GameLib.IsCharacterLoaded
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function ReQueue:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    self.autoQueue = false
    self.lastQueueData = {}
    self.queueType = self.EnumQueueType.SoloQueue
    self.ignoreWarning = false
    self.inInstanceGroup = InInstanceGroup()
    self.MatchMaker = nil

    return o
end

function ReQueue:Init()
    Apollo.RegisterAddon(self, false, "", {})
end

-----------------------------------------------------------------------------------------------
-- ReQueue OnLoad
-----------------------------------------------------------------------------------------------
function ReQueue:OnLoad()
    Apollo.GetPackage("Gemini:Hook-1.0").tPackage:Embed(self)

    Apollo.RegisterSlashCommand("requeue", "OnSlashCommand", self)
    Apollo.RegisterSlashCommand("rq", "OnSlashCommand", self)

		Apollo.RegisterEventHandler("Group_Left", "OnGroupLeave", self)
		Apollo.RegisterEventHandler("Group_Join", "OnGroupJoin", self)
		Apollo.RegisterEventHandler("Group_MemberPromoted", "UpdateGroupQueueButtonStatus", self)
		Apollo.RegisterEventHandler("MatchingEligibilityChanged", "UpdateGroupQueueButtonStatus", self)
		Apollo.RegisterEventHandler("CharacterCreated", "OnCharacterCreated", self)

    self.MatchMaker = Apollo.GetAddon("MatchMaker")

    self:InitHooks()

	  self.xmlDoc = XmlDoc.CreateFromFile("ReQueue.xml")
	  self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

function ReQueue:InitHooks()
    self:Hook(MatchingGame, "Queue")
    self:Hook(MatchingGame, "QueueAsGroup")
    self:RawHook(self.MatchMaker, "OnSoloQueue")
    self:RawHook(self.MatchMaker, "OnGroupQueue")
end

function ReQueue:OnDocLoaded()
	 if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
        self.wndSoloQW = Apollo.LoadForm(self.xmlDoc, "SoloQueueWarningForm", nil, self)
        self.wndSoloQW:Show(false, true)
	  end
end

-----------------------------------------------------------------------------------------------
-- ReQueue Hooks
-----------------------------------------------------------------------------------------------
function ReQueue:Queue(queueData)
    self.queueType = self.EnumQueueType.SoloQueue
    self:OnQueue(queueData)
end

function ReQueue:QueueAsGroup(queueData)
    self.queueType = self.EnumQueueType.GroupQueue
    self:OnQueue(queueData)
end

function ReQueue:OnQueue(queueData)
    self.lastQueueData = queueData
end

--Contentfinder queue events, here we start the queue after getting the data
function ReQueue:OnSoloQueue()
    self:Queue(self.MatchMaker.arMatchesToQueue)
    self:OnSlashCommand()
end

function ReQueue:OnGroupQueue()
    self:QueueAsGroup(self.MatchMaker.arMatchesToQueue)
    self:OnSlashCommand()
end

-----------------------------------------------------------------------------------------------
-- ReQueue Events
-----------------------------------------------------------------------------------------------
function ReQueue:OnSlashCommand()
    if MatchingGame.IsQueuedForMatching() then
        self:ToggleQueueStatusWindow()
        return
    end

    if self:IsQueueDataEmpty() then
        --TODO: Display a message
        return
    end

    if self:IsQueueingSoloInGroup() and not self.ignoreWarning then
        self:DisplaySoloQueueWarning()
    else
        self:StartQueue()
    end
end

function ReQueue:OnGroupLeave()
    if self.inInstanceGroup then
        self.inInstanceGroup = false
        --TODO: Auto ReQueue here?

        --Group_Left does not get fired when leaving a normal party while
        --being in an instance party so we have to check again to be sure
        if not InGroup() then
            self:OnGroupLeave()
        end
    else
        self.ignoreWarning = false
    end
end

function ReQueue:OnCharacterCreated()
    self:LoadSaveData()
end

function ReQueue:OnGroupJoin()
    self.inInstanceGroup = InInstanceGroup()
end

function ReQueue:OnSave(eType)
    local saveData = {
        ignoreWarning = self.ignoreWarning,
        queueType = self.queueType,
        autoQueue = self.autoQueue,
        lastQueueData = {}
    }

    for k, qd in pairs(self.lastQueueData) do
        table.insert(saveData.lastQueueData, self:SerializeMatchingGame(qd))
    end
    return saveData
end

function ReQueue:OnRestore(eType, saveData)
    if eType == GameLib.CodeEnumAddonSaveLevel.Character then
        self.saveData = saveData

        --When logging in wait for character to be loaded
        if IsCharacterLoaded() then
            self:LoadSaveData()
        end
    end
end

function ReQueue:LoadSaveData()
    if not self.saveData then
        return
    end

    if InGroup() then
        self.ignoreWarning = self.saveData.ignoreWarning
        self.queueType = self.saveData.queueType
    else
        self.queueType = self.EnumQueueType.SoloQueue
    end
    self.autoQueue = self.saveData.autoQueue
    if not self.saveData.lastQueueData then
        self.saveData.lastQueueData = {}
    end

    self.lastQueueData = {}
    for k, qd in pairs(self.saveData.lastQueueData) do
        table.insert(self.lastQueueData, self:UnWrapSerializedMatchingGame(qd))
    end
    self.saveData = nil
end

-----------------------------------------------------------------------------------------------
-- ReQueue Functions
-----------------------------------------------------------------------------------------------
function ReQueue:IsQueueingSoloInGroup()
    return self.queueType == self.EnumQueueType.SoloQueue and InGroup()
end

function ReQueue:IsQueueDataEmpty()
    return #self.lastQueueData == 0
end

function ReQueue:GetGroupQueueButtonStatus()
    local buttonEnabled = GroupLib.AmILeader()
    if not buttonEnabled then
        return buttonEnabled
    end

    for k, queueData in pairs(self.lastQueueData) do
  			buttonEnabled = queueData:DoesGroupMeetRequirements()
  			if not buttonEnabled then
  					break
  			end
  	end
    return buttonEnabled
end

function ReQueue:UpdateGroupQueueButtonStatus()
    if self.wndSoloQW then
        self.wndSoloQW:FindChild("GroupQueueButton"):Enable(self:GetGroupQueueButtonStatus())
    end
end

function ReQueue:DisplaySoloQueueWarning()
    self:UpdateGroupQueueButtonStatus()
    self.wndSoloQW:FindChild("RememberCheckBox"):SetCheck(false)
    self.wndSoloQW:Show(true)
    self.wndSoloQW:ToFront()
end

function ReQueue:StartQueue()
    if self.queueType == self.EnumQueueType.SoloQueue then
        Queue(self.lastQueueData)
    else
        QueueAsGroup(self.lastQueueData)
    end
end

function ReQueue:SerializeMatchingGame(matchingGame)
    return {
      description = matchingGame:GetDescription(),
      gameId = matchingGame:GetGameId(),
      maxLevel = matchingGame:GetMaxLevel(),
      minLevel = matchingGame:GetMinLevel(),
      name = matchingGame:GetName(),
      recommendedItemLevel = matchingGame:GetRecommendedItemLevel(),
      teamSize = matchingGame:GetTeamSize(),
      type = matchingGame:GetType(),
      isRandom = matchingGame:IsRandom(),
      isVeteran = matchingGame:IsVeteran()
    }
end

function ReQueue:UnWrapSerializedMatchingGame(serialized)
    local matchingGame = nil
    local matchingGames = MatchingGame.GetMatchingGames(
      serialized.type,
      serialized.isVeteran,
      true
    )
    for k, mg in pairs(matchingGames) do
      if  serialized.description == mg:GetDescription() and
          serialized.gameId == mg:GetGameId() and
          serialized.maxLevel == mg:GetMaxLevel() and
          serialized.minLevel == mg:GetMinLevel() and
          serialized.name == mg:GetName() and
          serialized.recommendedItemLevel == mg:GetRecommendedItemLevel() and
          serialized.teamSize == mg:GetTeamSize() and
          serialized.isRandom == mg:IsRandom() then
            matchingGame = mg
            break
        end
    end
    return matchingGame
end

function ReQueue:ToggleQueueStatusWindow()
    local wnd = self.MatchMaker.tWndRefs.wndQueueStatus
    if not wnd then
        return
    end
    if wnd:IsVisible() then
        self.MatchMaker:OnCloseQueueStatus()
    else
        self.MatchMaker:OnShowQueueStatus()
    end
end
---------------------------------------------------------------------------------------------------
-- SoloQueueWarningForm Functions
---------------------------------------------------------------------------------------------------
function ReQueue:OnButtonGroupQueue(wndHandler, wndControl, eMouseButton)
    self:OnButtonUse(self.EnumQueueType.GroupQueue)
end

function ReQueue:OnButtonSoloQueue(wndHandler, wndControl, eMouseButton)
    self:OnButtonUse(self.EnumQueueType.SoloQueue)
end

function ReQueue:OnButtonUse(queueType)
    self.queueType = queueType
    self.ignoreWarning = self.wndSoloQW:FindChild("RememberCheckBox"):IsChecked()
    self.wndSoloQW:Close()
    self:StartQueue()
end

function ReQueue:OnButtonDecline(wndHandler, wndControl, eMouseButton)
    self.wndSoloQW:Close()
end

-----------------------------------------------------------------------------------------------
-- ReQueue Instance
-----------------------------------------------------------------------------------------------
local ReQueueInst = ReQueue:new()
ReQueueInst:Init()
