-----------------------------------------------------------------------------------------------
-- Client Lua Script for ReQueue
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
require "Apollo"
require "Window"
require "GameLib"
require "GroupLib"
require "MatchingGameLib"
require "MatchMakingLib"

-----------------------------------------------------------------------------------------------
-- ReQueue Module Definition
-----------------------------------------------------------------------------------------------
local ReQueue = {
  uiMapperLib = "uiMapper:0.9.3",
  uiMapperPath = "libs/_uiMapper/",
  EnumQueueType = {
    SoloQueue = 0,
    GroupQueue = 1
  },
  defaults = {},
  config = {},
  version = "0.5.2",
  author = "Zod Bain@Jabbit"
}

local InInstanceGroup = GroupLib.InInstance
local InGroup = GroupLib.InGroup
local AmILeader = GroupLib.AmILeader
local Queue = MatchMakingLib.Queue
local QueueAsGroup = MatchMakingLib.QueueAsGroup
local IsCharacterLoaded = GameLib.IsCharacterLoaded
local IsRoleCheckActive = MatchingGameLib.IsRoleCheckActive
local ConfirmRole = MatchingGameLib.ConfirmRole
local DeclineRoleCheck = MatchingGameLib.DeclineRoleCheck
local IsInGameInstance = MatchingGameLib.IsInGameInstance
local IsFinished = MatchingGameLib.IsFinished
local IsQueuedForMatching = MatchMakingLib.IsQueuedForMatching
local IsQueuedAsGroupForMatching = MatchMakingLib.IsQueuedAsGroupForMatching
local GetMatchMakingEntries = MatchMakingLib.GetMatchMakingEntries
local Roles = MatchMakingLib.Roles
local GetEligibleRoles = MatchMakingLib.GetEligibleRoles
local next = next
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
  self.newQueueData = false
  self.queuesToLeave = 0
  self.leftMatch = false
  return o
end

function ReQueue:Init()
  Apollo.RegisterAddon(self, true, "ReQueue", {self.uiMapperLib, "MatchMaker"})
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
  Apollo.RegisterEventHandler("MatchLeft", "OnLeaveMatch", self)
  Apollo.RegisterEventHandler("MatchingLeaveQueue", "OnLeaveQueue", self)

  self.MatchMaker = Apollo.GetAddon("MatchMaker")

  self:InitHooks()

  self.xmlDoc = XmlDoc.CreateFromFile("ReQueue.xml")

  local uiMapper = Apollo.GetPackage(self.uiMapperLib).tPackage
  self.ui = uiMapper:new({
      container = self.config,
      defaults = self.defaults,
      name = "ReQueue Configuration",
      author = self.author,
      version = self.version,
      path = self.uiMapperPath,
    }
  ):build(self.BuildConfig, self)
end

function ReQueue:InitHooks()
  self:Hook(MatchMakingLib, "Queue")
  self:Hook(MatchMakingLib, "QueueAsGroup")
  self:Hook(MatchMakingLib, "LeaveAllQueues")
  self:PostHook(self.MatchMaker, "OnRoleCheck")
  self:RawHook(self.MatchMaker, "OnSoloQueue")
  self:RawHook(self.MatchMaker, "OnGroupQueue")
end

-----------------------------------------------------------------------------------------------
-- ReQueue Hooks
-----------------------------------------------------------------------------------------------
function ReQueue:OnRoleCheck()
  if self.config.autoRoleSelect and #self:GetSelectedRoles() > 0 then
    self.MatchMaker:OnAcceptRole()
  end
end

function ReQueue:LeaveAllQueues()
  self.queuesToLeave = 0
  local size = #self.lastQueueData
  for i = 1, size do
    local queueData = self.lastQueueData[i]
    if queueData:IsQueued() or queueData:IsQueuedAsGroup() then
      self.queuesToLeave = self.queuesToLeave + 1
    end
  end
end

function ReQueue:Queue(queueData, queueOptions)
  self.config.queueType = self.EnumQueueType.SoloQueue
  self:OnQueue(queueData, queueOptions)
end

function ReQueue:QueueAsGroup(queueData, queueOptions)
  self.config.queueType = self.EnumQueueType.GroupQueue
  self:OnQueue(queueData, queueOptions)
end

function ReQueue:OnQueue(queueData, queueOptions)
  if self:IsQueued() then
    for _, v in next, queueData do
      table.insert(self.lastQueueData, v)
    end
    self.newQueueData = true
  else
    self.newQueueData = false
    self.lastQueueData = queueData
  end
  self.queueOptions = queueOptions
end

--Contentfinder queue events, here we start the queue after getting the data
function ReQueue:OnSoloQueue()
  self:Queue(self.MatchMaker.arMatchesToQueue, self:GetQueueOptions())
  self:OnSlashCommand()
end

function ReQueue:OnGroupQueue()
  self:QueueAsGroup(self.MatchMaker.arMatchesToQueue, self:GetQueueOptions())
  self:OnSlashCommand()
end
-----------------------------------------------------------------------------------------------
-- ReQueue Events
-----------------------------------------------------------------------------------------------
function ReQueue:OnSlashCommand(_, args)
  if args == "config" then
    self:OnConfigure()
    return
  elseif args == "roles" or args == "role" then
    self:DisplayRoleConfirm()
    return
  end

  if not self.newQueueData and self:IsQueued() then
    self:ToggleQueueStatusWindow()
    return
  end

  if IsInGameInstance() and not IsFinished() then
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
  else --Left all groups
    self.config.queueType = self.EnumQueueType.SoloQueue
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
    lastQueueData = {},
    queueOptions = self.queueOptions
  }

  local size = #self.lastQueueData
  for i = 1, size do
    local queueData = self.lastQueueData[i]
    table.insert(saveData.lastQueueData, self:SerializeMatchingGame(queueData))
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

  for k, _ in next, self.config do
    if self.saveData.config[k] ~= nil then
      self.config[k] = self.saveData.config[k]
    end
  end

  if not InGroup() then
    self.config.queueType = self.defaults.queueType
    self:SetConfig("ignoreWarning", self.defaults.ignoreWarning)
  end

  self.lastQueueData = {}
  for _, qd in pairs(self.saveData.lastQueueData or {}) do
    table.insert(self.lastQueueData, self:UnWrapSerializedMatchingGame(qd))
  end
  self.queueOptions = self.saveData.queueOptions
  self.saveData = nil
end

function ReQueue:OnLeaveMatch()
  self.leftMatch = true
end

function ReQueue:OnLeaveQueue()
  if self.leftMatch then
    self.leftMatch = false
    if AmILeader() then
      self.newQueueData = true
    end
    return
  end

  if self.queuesToLeave > 0 then
    self.queuesToLeave = self.queuesToLeave - 1
    return
  end

  if not self:IsQueued() then
    return
  end

  self:RemoveNotQueuedEntries()
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
  local buttonEnabled = AmILeader()
  if not buttonEnabled then
    return buttonEnabled
  end

  local size = #self.lastQueueData
  for i = 1, size do
    local queueData = self.lastQueueData[i]
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
  if not self.xmlDoc or self.wndRoleConfirm ~= nil then
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
  if not self.xmlDoc or self.wndSoloQW ~= nil then
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
  self.newQueueData = false
  if self.config.queueType == self.EnumQueueType.SoloQueue then
    Queue(self.lastQueueData, self.queueOptions)
  else
    QueueAsGroup(self.lastQueueData, self.queueOptions)
  end
end

function ReQueue:SerializeMatchingGame(matchingGame)
  local t = {
    bIsRandom = matchingGame:IsRandom(),
    bIsVeteran = matchingGame:IsVeteran()
  }
  for k, v in pairs(matchingGame:GetInfo()) do
    t[k] = v
  end
  return t
end

function ReQueue:UnWrapSerializedMatchingGame(serialized)
  local matchingGame = nil
  local matchingGames = GetMatchMakingEntries(
    serialized.eMatchType,
    serialized.bIsVeteran,
    true
  )
  for _, mg in next, matchingGames do
    local found = true
    local cnt = 0
    for k, v in next, mg:GetInfo() do
      if serialized[k] ~= v then
        found = false
        break
      end
      cnt = cnt + 1
    end
    self.debug = self.debug or ""
    self.debug = self.debug .. " " .. tostring(cnt)
    if serialized.bIsRandom ~= mg:IsRandom() then
      found = false
    end
    if found then
      matchingGame = mg
      break
    end
  end
  return matchingGame
end

function ReQueue:ToggleQueueStatusWindow()
  local wnd = self.MatchMaker.tWndRefs.wndQueueStatus
  if wnd and wnd:IsVisible() then
    self.MatchMaker:OnCloseQueueStatus()
  else
    self.MatchMaker:OnShowQueueStatus()
  end
end

function ReQueue:GetQueueOptions()
  return self.MatchMaker.tQueueOptions[self.MatchMaker.eSelectedMasterType]
end

function ReQueue:RemoveNotQueuedEntries()
  --iterate backwards and remove not queued entries
  for i = #self.lastQueueData, 1, -1 do
    local entry = self.lastQueueData[i]
    if not entry:IsQueued() and not entry:IsQueuedAsGroup() then
      table.remove(self.lastQueueData, i)
    end
  end
end

function ReQueue:IsQueued()
  return IsQueuedForMatching() or IsQueuedAsGroupForMatching()
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

function ReQueue:OnButtonGroupQueue()
  self:OnButtonUse(self.EnumQueueType.GroupQueue)
end

function ReQueue:OnButtonSoloQueue()
  self:OnButtonUse(self.EnumQueueType.SoloQueue)
end

function ReQueue:OnButtonUse(queueType)
  self.config.queueType = queueType
  self:SetConfig("ignoreWarning", self.wndSoloQW:FindChild("RememberCheckBox"):IsChecked())

  self:OnButtonDecline()
  self:StartQueue()
end

function ReQueue:OnButtonDecline()
  self.wndSoloQW:Close()
end

function ReQueue:OnSoloQWClosed()
  --free memory
  self.wndSoloQW = nil
end

---------------------------------------------------------------------------------------------------
-- ConfirmRole Form Functions
---------------------------------------------------------------------------------------------------
function ReQueue:OnAcceptRole()
  if IsRoleCheckActive() then
    ConfirmRole(self:GetSelectedRoles())
  end
  self.wndRoleConfirm:Close()
end

function ReQueue:OnCancelRole()
  if IsRoleCheckActive() then
    DeclineRoleCheck()
  end
  self.wndRoleConfirm:Close()
end

function ReQueue:OnToggleRoleCheck(wndHandler, wndControl)
  if wndHandler ~= wndControl then
    return
  end

  self.MatchMaker:HelperToggleRole(wndHandler:GetData(), self.MatchMaker.eSelectedMasterType, wndHandler:IsChecked())

  local selectedRoles = self:GetSelectedRoles()
  self.wndRoleConfirm:FindChild("AcceptButton"):Enable(selectedRoles and #selectedRoles > 0)
end

function ReQueue:GetSelectedRoles()
  return self.MatchMaker.tQueueOptions[self.MatchMaker.eSelectedMasterType].arRoles
end

function ReQueue:OnRoleConfirmClosed()
  --free memory
  self.wndRoleConfirm = nil
end

function ReQueue:OnRoleConfirmShow()
  local roleConfirmButtons = {
    [Roles.Tank] = self.wndRoleConfirm:FindChild("TankBtn"),
    [Roles.Healer] = self.wndRoleConfirm:FindChild("HealerBtn"),
    [Roles.DPS] = self.wndRoleConfirm:FindChild("DPSBtn"),
  }

  for role, wndButton in pairs(roleConfirmButtons) do
    wndButton:Enable(false)
    wndButton:SetData(role)
  end

  for _, role in next, GetEligibleRoles() do
    roleConfirmButtons[role]:Enable(true)
  end

  local selectedRoles = self:GetSelectedRoles()
  for _, role in next, selectedRoles do
    roleConfirmButtons[role]:SetCheck(true)
  end

  self.wndRoleConfirm:FindChild("AcceptButton"):Enable(#selectedRoles > 0)
end
-----------------------------------------------------------------------------------------------
-- ReQueue Instance
-----------------------------------------------------------------------------------------------
local ReQueueInst = ReQueue:new()
ReQueueInst:Init()
