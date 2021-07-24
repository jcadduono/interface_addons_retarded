local ADDON = 'Retarded'
if select(2, UnitClass('player')) ~= 'PALADIN' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- copy heavily accessed global functions into local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetPowerRegen = _G.GetPowerRegen
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitAura = _G.UnitAura
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitThreatSituation = _G.UnitThreatSituation
-- end copy global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

Retarded = {}
local Opt -- use this as a local table reference to Retarded

SLASH_Retarded1, SLASH_Retarded2, SLASH_Retarded3 = '/ret', '/retard', '/retarded'
BINDING_HEADER_RETARDED = ADDON

local function InitOpts()
	local function SetDefaults(t, ref)
		local k, v
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(Retarded, { -- defaults
		locked = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			color = { r = 1, g = 1, b = 1 },
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		cd_ttd = 8,
		pot = false,
		trinket = true,
		last_aura = false,
		last_blessing = false,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	target_mode = 0,
	execute_remains = 0,
	haste_factor = 1,
	gcd = 1.5,
	gcd_remains = 0,
	health = 0,
	health_max = 0,
	mana = 0,
	mana_base = 0,
	mana_max = 0,
	mana_regen = 0,
	group_size = 1,
	moving = false,
	movement_speed = 100,
	threat = 0,
	last_swing_taken = 0,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
	tanking = false,
	last_aura = false,
	last_blessing = false,
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health_array = {},
	hostile = false,
	estimated_range = 30,
}

local retardedPanel = CreateFrame('Frame', 'retardedPanel', UIParent)
retardedPanel:SetPoint('CENTER', 0, -169)
retardedPanel:SetFrameStrata('BACKGROUND')
retardedPanel:SetSize(64, 64)
retardedPanel:SetMovable(true)
retardedPanel:Hide()
retardedPanel.icon = retardedPanel:CreateTexture(nil, 'BACKGROUND')
retardedPanel.icon:SetAllPoints(retardedPanel)
retardedPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
retardedPanel.border = retardedPanel:CreateTexture(nil, 'ARTWORK')
retardedPanel.border:SetAllPoints(retardedPanel)
retardedPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
retardedPanel.border:Hide()
retardedPanel.dimmer = retardedPanel:CreateTexture(nil, 'BORDER')
retardedPanel.dimmer:SetAllPoints(retardedPanel)
retardedPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
retardedPanel.dimmer:Hide()
retardedPanel.swipe = CreateFrame('Cooldown', nil, retardedPanel, 'CooldownFrameTemplate')
retardedPanel.swipe:SetAllPoints(retardedPanel)
retardedPanel.text = CreateFrame('Frame', nil, retardedPanel)
retardedPanel.text:SetAllPoints(retardedPanel)
retardedPanel.text.tl = retardedPanel.text:CreateFontString(nil, 'OVERLAY')
retardedPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
retardedPanel.text.tl:SetPoint('TOPLEFT', retardedPanel, 'TOPLEFT', 2.5, -3)
retardedPanel.text.tl:SetJustifyH('LEFT')
retardedPanel.text.tr = retardedPanel.text:CreateFontString(nil, 'OVERLAY')
retardedPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
retardedPanel.text.tr:SetPoint('TOPRIGHT', retardedPanel, 'TOPRIGHT', -2.5, -3)
retardedPanel.text.tr:SetJustifyH('RIGHT')
retardedPanel.text.bl = retardedPanel.text:CreateFontString(nil, 'OVERLAY')
retardedPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
retardedPanel.text.bl:SetPoint('BOTTOMLEFT', retardedPanel, 'BOTTOMLEFT', 2.5, 3)
retardedPanel.text.bl:SetJustifyH('LEFT')
retardedPanel.text.br = retardedPanel.text:CreateFontString(nil, 'OVERLAY')
retardedPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
retardedPanel.text.br:SetPoint('BOTTOMRIGHT', retardedPanel, 'BOTTOMRIGHT', -2.5, 3)
retardedPanel.text.br:SetJustifyH('RIGHT')
retardedPanel.text.center = retardedPanel.text:CreateFontString(nil, 'OVERLAY')
retardedPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 11, 'OUTLINE')
retardedPanel.text.center:SetAllPoints(retardedPanel.text)
retardedPanel.text.center:SetJustifyH('CENTER')
retardedPanel.text.center:SetJustifyV('CENTER')
retardedPanel.button = CreateFrame('Button', nil, retardedPanel)
retardedPanel.button:SetAllPoints(retardedPanel)
retardedPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local retardedPreviousPanel = CreateFrame('Frame', 'retardedPreviousPanel', UIParent)
retardedPreviousPanel:SetFrameStrata('BACKGROUND')
retardedPreviousPanel:SetSize(64, 64)
retardedPreviousPanel:Hide()
retardedPreviousPanel:RegisterForDrag('LeftButton')
retardedPreviousPanel:SetScript('OnDragStart', retardedPreviousPanel.StartMoving)
retardedPreviousPanel:SetScript('OnDragStop', retardedPreviousPanel.StopMovingOrSizing)
retardedPreviousPanel:SetMovable(true)
retardedPreviousPanel.icon = retardedPreviousPanel:CreateTexture(nil, 'BACKGROUND')
retardedPreviousPanel.icon:SetAllPoints(retardedPreviousPanel)
retardedPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
retardedPreviousPanel.border = retardedPreviousPanel:CreateTexture(nil, 'ARTWORK')
retardedPreviousPanel.border:SetAllPoints(retardedPreviousPanel)
retardedPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
local retardedCooldownPanel = CreateFrame('Frame', 'retardedCooldownPanel', UIParent)
retardedCooldownPanel:SetSize(64, 64)
retardedCooldownPanel:SetFrameStrata('BACKGROUND')
retardedCooldownPanel:Hide()
retardedCooldownPanel:RegisterForDrag('LeftButton')
retardedCooldownPanel:SetScript('OnDragStart', retardedCooldownPanel.StartMoving)
retardedCooldownPanel:SetScript('OnDragStop', retardedCooldownPanel.StopMovingOrSizing)
retardedCooldownPanel:SetMovable(true)
retardedCooldownPanel.icon = retardedCooldownPanel:CreateTexture(nil, 'BACKGROUND')
retardedCooldownPanel.icon:SetAllPoints(retardedCooldownPanel)
retardedCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
retardedCooldownPanel.border = retardedCooldownPanel:CreateTexture(nil, 'ARTWORK')
retardedCooldownPanel.border:SetAllPoints(retardedCooldownPanel)
retardedCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
retardedCooldownPanel.cd = CreateFrame('Cooldown', nil, retardedCooldownPanel, 'CooldownFrameTemplate')
retardedCooldownPanel.cd:SetAllPoints(retardedCooldownPanel)
local retardedInterruptPanel = CreateFrame('Frame', 'retardedInterruptPanel', UIParent)
retardedInterruptPanel:SetFrameStrata('BACKGROUND')
retardedInterruptPanel:SetSize(64, 64)
retardedInterruptPanel:Hide()
retardedInterruptPanel:RegisterForDrag('LeftButton')
retardedInterruptPanel:SetScript('OnDragStart', retardedInterruptPanel.StartMoving)
retardedInterruptPanel:SetScript('OnDragStop', retardedInterruptPanel.StopMovingOrSizing)
retardedInterruptPanel:SetMovable(true)
retardedInterruptPanel.icon = retardedInterruptPanel:CreateTexture(nil, 'BACKGROUND')
retardedInterruptPanel.icon:SetAllPoints(retardedInterruptPanel)
retardedInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
retardedInterruptPanel.border = retardedInterruptPanel:CreateTexture(nil, 'ARTWORK')
retardedInterruptPanel.border:SetAllPoints(retardedInterruptPanel)
retardedInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
retardedInterruptPanel.cast = CreateFrame('Cooldown', nil, retardedInterruptPanel, 'CooldownFrameTemplate')
retardedInterruptPanel.cast:SetAllPoints(retardedInterruptPanel)
local retardedExtraPanel = CreateFrame('Frame', 'retardedExtraPanel', UIParent)
retardedExtraPanel:SetFrameStrata('BACKGROUND')
retardedExtraPanel:SetSize(64, 64)
retardedExtraPanel:Hide()
retardedExtraPanel:RegisterForDrag('LeftButton')
retardedExtraPanel:SetScript('OnDragStart', retardedExtraPanel.StartMoving)
retardedExtraPanel:SetScript('OnDragStop', retardedExtraPanel.StopMovingOrSizing)
retardedExtraPanel:SetMovable(true)
retardedExtraPanel.icon = retardedExtraPanel:CreateTexture(nil, 'BACKGROUND')
retardedExtraPanel.icon:SetAllPoints(retardedExtraPanel)
retardedExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
retardedExtraPanel.border = retardedExtraPanel:CreateTexture(nil, 'ARTWORK')
retardedExtraPanel.border:SetAllPoints(retardedExtraPanel)
retardedExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')

-- Start AoE

Player.target_modes = {
	{1, ''},
	{2, '2'},
	{3, '3'},
	{4, '4'},
	{5, '5+'},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes)
	self.enemies = self.target_modes[self.target_mode][1]
	retardedPanel.text.br:SetText(self.target_modes[self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes or mode)
end

-- Target Mode Keybinding Wrappers
function Retarded_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function Retarded_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function Retarded_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes, 1, -1 do
		if count >= Player.target_modes[i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:Purge()
	local update, guid, t
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability:Add(spellId, buff, player)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		name = false,
		rank = 0,
		icon = false,
		requires_charge = false,
		triggers_combat = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		health_cost = 0,
		mana_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 30,
		velocity = 0,
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		if spell == self.spellId then
			return true
		end
		local _, id
		for _, id in next, self.spellIds do
			if spell == id then
				return true
			end
		end
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable(seconds)
	if not self.known then
		return false
	end
	if self:Cost() > Player.mana then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains(mine)
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter .. (mine and '|PLAYER' or ''))
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:Up(condition)
	return self:Remains(condition) > 0
end

function Ability:Down(condition)
	return self:Remains(condition) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count, cast, _ = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	local count, ticking, _ = 0, {}
	if self.aura_targets then
		local guid, aura
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		local cast
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:Cost()
	return self.mana_cost
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:CastRegen()
	return Player.mana_regen * self:CastTime() - self:Cost()
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		self.auto_aoe.target_count = 0
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		autoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID, timeStamp)
	self.last_used = timeStamp
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
end

function Ability:CastLanded(dstGUID, timeStamp, eventType)
	if not self.traveling then
		return
	end
	local guid, cast, oldest
	for guid, cast in next, self.traveling do
		if Player.time - cast.start >= self.max_range / self.velocity + 0.2 then
			self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
		elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
			oldest = cast
		end
	end
	if oldest then
		Target.estimated_range = min(self.max_range, floor(self.velocity * max(0, timeStamp - oldest.start)))
		self.traveling[oldest.guid] = nil
	end
end

-- Start DoT Tracking

local trackAuras = {}

function trackAuras:Purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT Tracking

-- Paladin Abilities
---- General

---- Holy
local BlessingOfWisdom = Ability:Add({19742, 19850, 19852, 19853, 19854, 25290, 27142}, true)
BlessingOfWisdom.mana_costs = {30, 45, 65, 90, 115, 125, 150}
BlessingOfWisdom.buff_duration = 600
BlessingOfWisdom.is_blessing = true
local Consecration = Ability:Add({26573, 20116, 20922, 20923, 20924, 27173}, false, true)
Consecration.mana_costs = {120, 205, 290, 390, 505, 660}
Consecration.cooldown_duration = 8
Consecration.tick_interval = 1
Consecration:AutoAoe()
local Exorcism = Ability:Add({879, 5614, 5615, 10312, 10313, 10314, 27138}, false, true)
Exorcism.mana_costs = {70, 115, 155, 200, 240, 295, 340}
Exorcism.cooldown_duration = 15
local HolyLight = Ability:Add({635, 639, 647, 1026, 1042, 3472, 10328, 10329, 25292}, false, true)
HolyLight.mana_costs = {35, 60, 110, 190, 275, 365, 465, 580, 660}
local SealOfRighteousness = Ability:Add({21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293}, true, true)
SealOfRighteousness.mana_costs = {20, 40, 60, 90, 120, 140, 170, 200}
SealOfRighteousness.buff_duration = 30
------ Talents

------ Procs

---- Protection
local DevotionAura = Ability:Add({465, 10290, 643, 10291, 1032, 10292, 10293}, true)
DevotionAura.is_aura = true
local HammerOfJustice = Ability:Add({853, 5588, 5589, 10308}, false)
HammerOfJustice.mana_costs = {30, 50, 75, 100}
HammerOfJustice.buff_duration = 3
local RighteousFury = Ability:Add({25780}, true, true)
RighteousFury.mana_cost_pct = 24
RighteousFury.buff_duration = 1800
------ Talents
local ImprovedRighteousFury = Ability:Add({20468, 20469, 20470}, true, true)
------ Procs

---- Retribution
local BlessingOfMight = Ability:Add({19740, 19834, 19835, 19836, 19837, 19838, 25291}, true)
BlessingOfMight.mana_costs = {20, 30, 45, 60, 85, 110, 130}
BlessingOfMight.buff_duration = 600
BlessingOfMight.is_blessing = true
local Judgement = Ability:Add({20271}, false, true)
Judgement.mana_cost_pct = 5
Judgement.cooldown_duration = 10
local RetributionAura = Ability:Add({7294, 10298, 10299, 10300, 10301, 27150}, true)
RetributionAura.is_aura = true
------ Talents
local Benediction = Ability:Add({20101, 20102, 20103, 20104, 20105}, true, true)
------ Procs

-- Racials

-- Class Debuffs

-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:Cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items

-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Player API

function Player:Enemies()
	return self.enemies
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:ManaPct()
	return self.mana / self.mana_max * 100
end

function Player:UnderAttack()
	return self.threat >= 3 or (self.time - self.last_swing_taken) < 3
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.ability_casting and self.ability_casting.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:UpdateAbilities()
	local int = UnitStat('player', 4)
	self.mana_max = UnitPowerMax('player', 0)
	self.mana_base = self.mana_max - (min(20, int) + 15 * (int - min(20, int)))

	local _, i, ability, spellId, cost
	-- Update spell ranks first
	for _, ability in next, abilities.all do
		ability.known = false
		ability.spellId = ability.spellIds[1]
		ability.rank = 1
		for i, spellId in next, ability.spellIds do
			if IsPlayerSpell(spellId) then
				ability.known = true
				ability.spellId = spellId -- update spellId to current rank
				ability.rank = i
				if ability.mana_costs then
					ability.mana_cost = ability.mana_costs[i] -- update mana_cost to current rank
				end
				if ability.mana_cost_pct then
					ability.mana_cost = floor(self.mana_base * (ability.mana_cost_pct / 100))
				end
				if ability.health_costs then
					ability.health_cost = ability.health_costs[i] -- update health_cost to current rank
				end
			end
			if Opt.last_aura == spellId then
				self.last_aura = ability
			end
			if Opt.last_blessing == spellId then
				self.last_blessing = ability
			end
		end
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
	end
	
	-- Mark specific spells as known if they can be triggered by others
	if self.last_aura then
		Opt.last_aura = self.last_aura.spellId
	end
	if self.last_blessing then
		Opt.last_blessing = self.last_blessing.spellId
	end

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
end

function Player:Update()
	local _, start, duration, remains, spellId, speed, max_speed
	self.ctime = GetTime()
	self.time = self.ctime - self.time_diff
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	start, duration = GetSpellCooldown(47524)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.execute_remains = max(remains and (remains / 1000 - self.ctime) or 0, self.gcd_remains)
	self.haste_factor = 1 / (1 + GetCombatRatingBonus(CR_HASTE_SPELL) / 100)
	self.gcd = 1.5 * self.haste_factor
	self.health = UnitHealth('player')
	self.health_max = UnitHealthMax('player')
	self.mana_regen = GetPowerRegen()
	self.mana = UnitPower('player', 0) + (self.mana_regen * self.execute_remains)
	self.mana_max = UnitPowerMax('player', 0)
	if self.ability_casting then
		self.mana = self.mana - self.ability_casting:Cost()
	end
	self.mana = min(max(self.mana, 0), self.mana_max)
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self.threat = UnitThreatSituation('player', 'target') or 0

	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end
end

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.health_array, 1)
	self.health_array[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * 10
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.health_array[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.type = 'Humanoid'
		self.player = false
		self.level = Player.level
		self.hostile = true
		local i
		for i = 1, 25 do
			self.health_array[i] = 0
		end
		self:UpdateHealth()
		if Opt.always_on then
			UI:UpdateCombat()
			retardedPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			retardedPreviousPanel:Hide()
		end
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		local i
		for i = 1, 25 do
			self.health_array[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.type = UnitCreatureType('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health_max > Player.health_max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		retardedPanel:Show()
		return true
	end
end

-- End Target API

-- Start Ability Modifications

function Exorcism:Usable(seconds)
	if not (Target.type == 'Undead' or Target.type == 'Demon') then
		return false
	end
	return Ability.Usable(self, seconds)
end

function HammerOfJustice:Usable(seconds)
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self, seconds)
end

function Judgement:Usable(seconds)
	if SealOfRighteousness:Down() then
		return false
	end
	return Ability.Usable(self, seconds)
end

function Judgement:Cost()
	local cost = Ability.Cost(self)
	if Benediction.known then
		cost = floor(cost - (cost * 0.03 * Benediction.rank))
	end
	return cost
end
SealOfRighteousness.Cost = Judgement.Cost

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

-- Begin Action Priority Lists

local APL = {}

APL.Main = function(self)
	local apl
	if HolyLight:Usable() and Player:HealthPct() < 40 then
		UseExtra(HolyLight)
	end
	if Player:TimeInCombat() == 0 then
		if Player.tanking and (Player.group_size > 1 or ImprovedRighteousFury.known) and RighteousFury:Usable() and RighteousFury:Remains() < (Target.boss and 180 or 30) then
			return RighteousFury
		end
		apl = self:Auras() or self:Blessings(Target.boss and 180 or 30)
		if apl then return apl end
		if SealOfRighteousness:Usable() and SealOfRighteousness:Down() then
			return SealOfRighteousness
		end
		if Exorcism:Usable() then
			return Exorcism
		end
	else
		if Player.tanking and (Player.group_size > 1 or ImprovedRighteousFury.known) and RighteousFury:Usable() and RighteousFury:Down() then
			UseExtra(RighteousFury)
		end
		apl = self:Auras() or self:Blessings(30)
		if apl then UseExtra(apl) end
	end
	if Judgement:Usable() then
		return Judgement
	end
	if SealOfRighteousness:Usable() and SealOfRighteousness:Down() then
		return SealOfRighteousness
	end
	if Consecration:Usable() and Player.enemies > 1 then
		return Consecration
	end
	if Exorcism:Usable() then
		return Exorcism
	end
end

APL.Auras = function(self)
	if DevotionAura:Up(true) or RetributionAura:Up(true) then
		return
	end
	if Player.last_aura and Player.last_aura:Usable() and Player.last_aura:Down() then
		return Player.last_aura
	end
	if DevotionAura:Usable() then
		return DevotionAura
	end
	if RetributionAura:Usable() then
		return RetributionAura
	end
end

APL.Blessings = function(self, refresh_time)
	if Player.last_blessing then
		if Player.last_blessing:Remains(true) > refresh_time then
			return
		end
		if Player.last_blessing:Usable() and Player.last_blessing:Remains() <= refresh_time then
			return Player.last_blessing
		end
	end
	if BlessingOfMight:Remains(true) > refresh_time or BlessingOfWisdom:Remains(true) > refresh_time then
		return
	end
	if BlessingOfMight:Usable() then
		return BlessingOfMight
	end
	if BlessingOfWisdom:Usable() then
		return BlessingOfWisdom
	end
end

APL.Interrupt = function(self)
	if HammerOfJustice:Usable() then
		return HammerOfJustice
	end
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

function UI:CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon, i
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	retardedPanel:EnableMouse(Opt.aoe or not Opt.locked)
	retardedPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		retardedPanel:SetScript('OnDragStart', nil)
		retardedPanel:SetScript('OnDragStop', nil)
		retardedPanel:RegisterForDrag(nil)
		retardedPreviousPanel:EnableMouse(false)
		retardedCooldownPanel:EnableMouse(false)
		retardedInterruptPanel:EnableMouse(false)
		retardedExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			retardedPanel:SetScript('OnDragStart', retardedPanel.StartMoving)
			retardedPanel:SetScript('OnDragStop', retardedPanel.StopMovingOrSizing)
			retardedPanel:RegisterForDrag('LeftButton')
		end
		retardedPreviousPanel:EnableMouse(true)
		retardedCooldownPanel:EnableMouse(true)
		retardedInterruptPanel:EnableMouse(true)
		retardedExtraPanel:EnableMouse(true)
	end
end

function UI:UpdateAlpha()
	retardedPanel:SetAlpha(Opt.alpha)
	retardedPreviousPanel:SetAlpha(Opt.alpha)
	retardedCooldownPanel:SetAlpha(Opt.alpha)
	retardedInterruptPanel:SetAlpha(Opt.alpha)
	retardedExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	retardedPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	retardedPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	retardedCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	retardedInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	retardedExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	retardedPreviousPanel:ClearAllPoints()
	retardedPreviousPanel:SetPoint('TOPRIGHT', retardedPanel, 'BOTTOMLEFT', -3, 40)
	retardedCooldownPanel:ClearAllPoints()
	retardedCooldownPanel:SetPoint('TOPLEFT', retardedPanel, 'BOTTOMRIGHT', 3, 40)
	retardedInterruptPanel:ClearAllPoints()
	retardedInterruptPanel:SetPoint('BOTTOMLEFT', retardedPanel, 'TOPRIGHT', 3, -21)
	retardedExtraPanel:ClearAllPoints()
	retardedExtraPanel:SetPoint('BOTTOMRIGHT', retardedPanel, 'TOPLEFT', -3, -21)
end

function UI:Disappear()
	retardedPanel:Hide()
	retardedPanel.icon:Hide()
	retardedPanel.border:Hide()
	retardedCooldownPanel:Hide()
	retardedInterruptPanel:Hide()
	retardedExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	retardedPanel.dimmer:SetShown(dim)
	--retardedPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0

	Player:Update()

	Player.main = APL:Main()
	if Player.main then
		retardedPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		retardedCooldownPanel.icon:SetTexture(Player.cd.icon)
	end
	if Player.extra then
		retardedExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends = UnitChannelInfo('target')
		end
		if start then
			Player.interrupt = APL.Interrupt()
			retardedInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			retardedInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		retardedInterruptPanel.icon:SetShown(Player.interrupt)
		retardedInterruptPanel.border:SetShown(Player.interrupt)
		retardedInterruptPanel:SetShown(start)
	end
	retardedPanel.icon:SetShown(Player.main)
	retardedPanel.border:SetShown(Player.main)
	retardedCooldownPanel:SetShown(Player.cd)
	retardedExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Retarded
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Retarded1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
		return
	end
	if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
		if dstGUID == Player.guid then
			Player.last_swing_taken = Player.time
		end
		if Opt.auto_aoe then
			if dstGUID == Player.guid then
				autoAoe:Add(srcGUID, true)
			elseif srcGUID == Player.guid and not (missType == 'EVADE' or missType == 'IMMUNE') then
				autoAoe:Add(dstGUID, true)
			end
		end
	end

	if not srcGUID == Player.guid then
		return
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_ABSORBED' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_ENERGIZE' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		ability:CastSuccess(dstGUID, timeStamp)
		if Opt.previous and retardedPanel:IsVisible() then
			retardedPreviousPanel.ability = ability
			retardedPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
			retardedPreviousPanel.icon:SetTexture(ability.icon)
			retardedPreviousPanel:Show()
		end
		return
	end
	if dstGUID == Player.guid then
		if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
			if ability.is_aura then
				Player.last_aura = ability
				Opt.last_aura = ability.spellId
			end
			if ability.is_blessing then
				Player.last_blessing = ability
				Opt.last_blessing = ability.spellId
			end
		end
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_ABSORBED' or eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, timeStamp, eventType)
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and retardedPanel:IsVisible() and ability == retardedPreviousPanel.ability then
			retardedPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
		end
	end
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.last_swing_taken = 0
	Target.estimated_range = 30
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		retardedPreviousPanel:Hide()
	end
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	local _, i, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end
	Player.tanking = IsEquippedItemType('INVTYPE_SHIELD')
	Player:UpdateAbilities()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(47524)
		end
		retardedPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_SUCCEEDED(srcName, castGUID, spellId)
	if srcName ~= 'player' or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = spellId and abilities.bySpellId[spellId]
	if not ability or not ability.traveling then
		return
	end
	ability.next_castGUID = castGUID
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:GROUP_ROSTER_UPDATE()
	Player.group_size = min(max(GetNumGroupMembers(), 1), 40)
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	Player.level = UnitLevel('player')
	retardedPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	events:GROUP_ROSTER_UPDATE()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
	Target:Update()
	Player:Update()
end

retardedPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

retardedPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

retardedPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	retardedPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local ChatFrame_OnHyperlinkShow_Original = ChatFrame_OnHyperlinkShow
function ChatFrame_OnHyperlinkShow(chatFrame, link, ...)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		return BattleTagInviteFrame_Show(linkData)
	end
	return ChatFrame_OnHyperlinkShow_Original(chatFrame, link, ...)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	print(ADDON, '-', desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 8
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if msg[1] == 'reset' then
		retardedPanel:ClearAllPoints()
		retardedPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Retarded1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
