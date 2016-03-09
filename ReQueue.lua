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
local ReQueue = {
  uiMapperLib = "uiMapper:0.9",
  EnumQueueType = {
    SoloQueue = 0,
    GroupQueue = 1
  },
  defaults = {},
  config = {},
  version = "0.3.1",
  author = "Zod Bain@Jabbit"
}

local InInstanceGroup = GroupLib.InInstance
local InGroup = GroupLib.InGroup
local Queue = MatchingGame.Queue
local QueueAsGroup = MatchingGame.QueueAsGroup
local IsCharacterLoaded = GameLib.IsCharacterLoaded
local GetSelectedRoles = MatchingGame.GetSelectedRoles
local IsRoleCheckActive = MatchingGame.IsRoleCheckActive
local ConfirmRole = MatchingGame.ConfirmRole
local DeclineRoleCheck = MatchingGame.DeclineRoleCheck
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function ReQueue:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  self.lastQueueData = {}
  self.inInstanceGroup = InInstanceGroup()
  self.MatchMaker = nil

  return o
end

function ReQueue:Init()
  Apollo.RegisterAddon(self, true, "ReQueue", {self.uiMapperLib})
end

function ReQueue:GetDefaults()
  return {
    autoQueue = false,
    queueType = self.EnumQueueType.SoloQueue,
    ignoreWarning = false,
    autoRoleSelect = true
  }
end

-----------------------------------------------------------------------------------------------
-- ReQueue OnLoad
-----------------------------------------------------------------------------------------------
function ReQueue:OnLoad()
  self.defaults = self:GetDefaults()
  self.config = self:GetDefaults()
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

  local uiMapper = Apollo.GetPackage(self.uiMapperLib).tPackage
  self.ui = uiMapper:new({
    container = self.config,
    defaults  = self.defaults,
    name      = "ReQueue Configuration",
    author    = self.author,
    version   = self.version
  })
  self.ui:build(function(ui)
    self:BuildConfig(ui)
  end)
end

function ReQueue:InitHooks()
  self:Hook(MatchingGame, "Queue")
  self:Hook(MatchingGame, "QueueAsGroup")
  self:PostHook(self.MatchMaker, "OnRoleCheck")
  self:RawHook(self.MatchMaker, "OnSoloQueue")
  self:RawHook(self.MatchMaker, "OnGroupQueue")
end

-----------------------------------------------------------------------------------------------
-- ReQueue Hooks
-----------------------------------------------------------------------------------------------
function ReQueue:OnRoleCheck()
  if self.config.autoRoleSelect and #GetSelectedRoles() > 0 then
    self.MatchMaker:OnAcceptRole()
  end
end

function ReQueue:Queue(queueData)
  self.config.queueType = self.EnumQueueType.SoloQueue
  self:OnQueue(queueData)
end

function ReQueue:QueueAsGroup(queueData)
  self.config.queueType = self.EnumQueueType.GroupQueue
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
function ReQueue:OnSlashCommand(cmd, args)
  if args == "config" then
    self:OnConfigure()
    return
  elseif args == "roles" or args == "role" then
    self:DisplayRoleConfirm()
    return
  end

  if MatchingGame.IsQueuedForMatching() then
    self:ToggleQueueStatusWindow()
    return
  end

  if self:IsQueueDataEmpty() then
    --TODO: Display a message
    return
  end

  if self:IsQueueingSoloInGroup() and not self.config.ignoreWarning then
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
    self:SetConfig("ignoreWarning", false)
  end
end

function ReQueue:OnCharacterCreated()
  self:LoadSaveData()
end

function ReQueue:OnGroupJoin()
  self.inInstanceGroup = InInstanceGroup()
end

function ReQueue:OnSave(eType)
  if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then
    return nil
  end

  local saveData = {
    config = self.config,
    autoQueue = self.autoQueue,
    lastQueueData = {}
  }

  for k, qd in pairs(self.lastQueueData) do
    table.insert(saveData.lastQueueData, self:SerializeMatchingGame(qd))
  end
  return saveData
end

function ReQueue:OnRestore(eType, saveData)
  if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then
    return
  end
  self.saveData = saveData

  --When logging in wait for character to be loaded
  if IsCharacterLoaded() then
    self:LoadSaveData()
  end
end

function ReQueue:LoadSaveData()
  if not self.saveData then
    return
  end

  for k, v in pairs(self.config) do
    if self.saveData.config[k] ~= nil then
      self.config[k] = self.saveData.config[k]
    end
  end

  if not InGroup() then
    self.config.queueType = self.defaults.queueType
    self:SetConfig("ignoreWarning", self.defaults.ignoreWarning)
  end

  self.lastQueueData = {}
  for k, qd in pairs(self.saveData.lastQueueData or {}) do
    table.insert(self.lastQueueData, self:UnWrapSerializedMatchingGame(qd))
  end
  self.saveData = nil
end

-----------------------------------------------------------------------------------------------
-- ReQueue Functions
-----------------------------------------------------------------------------------------------
function ReQueue:OnConfigure()
  if self.ui then
    self.ui.wndMain:Show(true,true)
  end
end

function ReQueue:IsQueueingSoloInGroup()
  return self.config.queueType == self.EnumQueueType.SoloQueue and InGroup()
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

function ReQueue:DisplayRoleConfirm()
  if not self.xmlDoc then
    return
  elseif not self.xmlDoc:IsLoaded() then
    self.xmlDoc:RegisterCallback("DisplayRoleConfirm", self)
    return
  end

  self.wndRoleConfirm = Apollo.LoadForm(self.xmlDoc, "RoleConfirm", nil, self)

  self.wndRoleConfirm:Show(true)
  self.wndRoleConfirm:ToFront()
end

function ReQueue:DisplaySoloQueueWarning()
  if not self.xmlDoc then
    return
  elseif not self.xmlDoc:IsLoaded() then
    self.xmlDoc:RegisterCallback("DisplaySoloQueueWarning", self)
    return
  end

  self.wndSoloQW = Apollo.LoadForm(self.xmlDoc, "SoloQueueWarning", nil, self)

  self:UpdateGroupQueueButtonStatus()
  self.wndSoloQW:FindChild("RememberCheckBox"):SetCheck(false)
  self.wndSoloQW:Show(true)
  self.wndSoloQW:ToFront()
end

function ReQueue:StartQueue()
  if self.config.queueType == self.EnumQueueType.SoloQueue then
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
function ReQueue:SetConfig(map, value)
  self.config[map] = value
  if self.ui and self.ui.wndMain then
    self.ui.wndMain:FindChild(self.ui.conventions.controlPrefix .. map):SetCheck(value)
  end
end

function ReQueue:OnButtonGroupQueue(wndHandler, wndControl, eMouseButton)
  self:OnButtonUse(self.EnumQueueType.GroupQueue)
end

function ReQueue:OnButtonSoloQueue(wndHandler, wndControl, eMouseButton)
  self:OnButtonUse(self.EnumQueueType.SoloQueue)
end

function ReQueue:OnButtonUse(queueType)
  self.config.queueType = queueType
  self:SetConfig("ignoreWarning", self.wndSoloQW:FindChild("RememberCheckBox"):IsChecked())

  self:OnButtonDecline()
  self:StartQueue()
end

function ReQueue:OnButtonDecline(wndHandler, wndControl, eMouseButton)
  self.wndSoloQW:Close()
end

function ReQueue:OnSoloQWClosed(wndHandler, wndControl, eMouseButton)
  --free memory
  self.wndSoloQW = nil
end

---------------------------------------------------------------------------------------------------
-- ConfirmRole Form Functions
---------------------------------------------------------------------------------------------------
function ReQueue:OnAcceptRole(wndHandler, wndControl, eMouseButton)
  if IsRoleCheckActive() then
    ConfirmRole()
  end
  self.wndRoleConfirm:Close()
end

function ReQueue:OnCancelRole(wndHandler, wndControl, eMouseButton)
  if IsRoleCheckActive() then
    DeclineRoleCheck()
  end
  self.wndRoleConfirm:Close()
end

function ReQueue:OnToggleRoleCheck(wndHandler, wndControl, eMouseButton)
  if wndHandler ~= wndControl then
    return
  end

  MatchingGame.SelectRole(wndHandler:GetData(), wndHandler:IsChecked())

  local selectedRoles = MatchingGame.GetSelectedRoles()
  self.wndRoleConfirm:FindChild("AcceptButton"):Enable(#selectedRoles > 0)
end

function ReQueue:OnRoleConfirmClosed(wndHandler, wndControl, eMouseButton)
  --free memory
  self.wndRoleConfirm = nil
end

function ReQueue:OnRoleConfirmShow(wndHandler, wndControl, eMouseButton)
  local roleConfirmButtons = {
    [MatchingGame.Roles.Tank] = self.wndRoleConfirm:FindChild("TankBtn"),
    [MatchingGame.Roles.Healer] = self.wndRoleConfirm:FindChild("HealerBtn"),
    [MatchingGame.Roles.DPS] = self.wndRoleConfirm:FindChild("DPSBtn"),
  }

  for role, wndButton in pairs(roleConfirmButtons) do
    wndButton:Enable(false)
    wndButton:SetData(role)
  end

  for idx, role in pairs(MatchingGame.GetEligibleRoles()) do
    roleConfirmButtons[role]:Enable(true)
  end

  local selectedRoles = MatchingGame.GetSelectedRoles()
  for idx, role in pairs(selectedRoles) do
    roleConfirmButtons[role]:SetCheck(true)
  end

  self.wndRoleConfirm:FindChild("AcceptButton"):Enable(#selectedRoles > 0)
end
-----------------------------------------------------------------------------------------------
-- ReQueue Instance
-----------------------------------------------------------------------------------------------
local ReQueueInst = ReQueue:new()
ReQueueInst:Init()
