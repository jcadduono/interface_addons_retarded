if select(2, UnitClass('player')) ~= 'PALADIN' then
	DisableAddOn('Retarded')
	return
end

-- copy heavily accessed global functions into local scope for performance
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitAura = _G.UnitAura
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

SLASH_Retarded1, SLASH_Retarded2 = '/ret', '/retard'
BINDING_HEADER_RETARDED = 'Retarded'

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
		snap = false,
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
		hide = {
			holy = false,
			protection = false,
			retribution = false,
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
		pot = false,
		trinket = true,
		defensives = true,
		blessings = true,
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

-- specialization constants
local SPEC = {
	NONE = 0,
	HOLY = 1,
	PROTECTION = 2,
	RETRIBUTION = 3,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	target_mode = 0,
	group_size = 1,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	mana = 0,
	mana_max = 100,
	mana_regen = 0,
	holy_power = 0,
	holy_power_max = 5,
	moving = false,
	movement_speed = 100,
	last_swing_taken = 0,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[174044] = true, -- Humming Black Dragonscale (parachute)
	},
	aw_remains = 0,
	crusade_remains = 0,
	consecration_remains = 0,
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false,
	estimated_range = 30,
}

-- Azerite trait API access
local Azerite = {}

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
retardedPanel.border:SetTexture('Interface\\AddOns\\Retarded\\border.blp')
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
retardedPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 9, 'OUTLINE')
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
retardedPreviousPanel.border:SetTexture('Interface\\AddOns\\Retarded\\border.blp')
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
retardedCooldownPanel.border:SetTexture('Interface\\AddOns\\Retarded\\border.blp')
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
retardedInterruptPanel.border:SetTexture('Interface\\AddOns\\Retarded\\border.blp')
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
retardedExtraPanel.border:SetTexture('Interface\\AddOns\\Retarded\\border.blp')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.HOLY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.PROTECTION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.RETRIBUTION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	retardedPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
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
		[161895] = true, -- Thing From Beyond (40+ Corruption)
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
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
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

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		mana_cost = 0,
		power_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
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

function Ability:Usable()
	if not self.known then
		return false
	end
	if self:ManaCost() > Player.mana then
		return false
	end
	if self:HolyPowerCost() > Player.holy_power then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready()
end

function Ability:Remains()
	if self:Casting() or self:Traveling() then
		return self:Duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
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

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up()
	return self:Remains() > 0
end

function Ability:Down()
	return not self:Up()
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:Traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:Up() and 1 or 0
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

function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana_max) or 0
end

function Ability:HolyPowerCost()
	return self.power_cost
end

function Ability:Charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
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

function Ability:AzeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {}
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
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:Update()
	end
end

-- start DoT tracking

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

function Ability:RefreshAuraAll()
	local guid, aura, remains
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Paladin Abilities
---- Multiple Specializations
local AvengingWrath = Ability:Add(31884, true, true)
AvengingWrath.buff_duration = 20
AvengingWrath.cooldown_duration = 120
AvengingWrath.autocrit = Ability:Add(294027, true, true)
AvengingWrath.autocrit.buff_duration = 20
local BlessingOfProtection = Ability:Add(1022, true, false)
BlessingOfProtection.buff_duration = 10
BlessingOfProtection.cooldown_duration = 300
local DivineShield = Ability:Add(642, true, true)
DivineShield.buff_duration = 8
DivineShield.cooldown_duration = 300
local FlashOfLight = Ability:Add(19750, true, true)
FlashOfLight.mana_cost = 22
local Forbearance = Ability:Add(25771, false, false)
Forbearance.buff_duration = 30
Forbearance.auraTarget = 'player'
local HammerOfJustice = Ability:Add(853, false, true)
HammerOfJustice.buff_duration = 6
HammerOfJustice.cooldown_duration = 60
local BlessingOfFreedom = Ability:Add(1044, true, false)
BlessingOfFreedom.buff_duration = 8
BlessingOfFreedom.cooldown_duration = 25
BlessingOfFreedom.mana_cost = 7
local HandOfReckoning = Ability:Add(62124, false, true)
HandOfReckoning.buff_duration = 4
HandOfReckoning.cooldown_duration = 8
local LayOnHands = Ability:Add(633, true, true)
LayOnHands.cooldown_duration = 600
local Rebuke = Ability:Add(96231, false, true)
Rebuke.buff_duration = 4
Rebuke.cooldown_duration = 15
local WordOfGlory = Ability:Add(210191, true, true)
WordOfGlory.cooldown_duration = 60
WordOfGlory.power_cost = 3
WordOfGlory.requires_charge = true
------ Talents

------ Procs

---- Holy

------ Talents

------ Procs

---- Protection
local AvengersShield = Ability:Add(31935, false, true)
AvengersShield.buff_duration = 3
AvengersShield.cooldown_duration = 15
AvengersShield.hasted_cooldown = true
AvengersShield:SetVelocity(35)
AvengersShield:AutoAoe()
local Consecration = Ability:Add(26573, true, true, 188370)
Consecration.buff_duration = 12
Consecration.cooldown_duration = 4.5
Consecration.hasted_cooldown = true
Consecration.dot = Ability:Add(204242, false, true, 81297)
Consecration.dot.buff_duration = 12
Consecration.dot.tick_interval = 1
Consecration.dot.hasted_ticks = true
Consecration.dot:AutoAoe()
local HammerOfTheRighteous = Ability:Add(53595, false, true)
HammerOfTheRighteous.cooldown_duration = 4.5
HammerOfTheRighteous.requires_charge = true
HammerOfTheRighteous:AutoAoe()
local JudgmentProt = Ability:Add(275779, false, true)
JudgmentProt.cooldown_duration = 12
JudgmentProt.mana_cost = 3
JudgmentProt.max_range = 30
JudgmentProt.hasted_cooldown = true
JudgmentProt.requires_charge = true
JudgmentProt:SetVelocity(35)
local Seraphim = Ability:Add(152262, true, true)
Seraphim.buff_duration = 8
Seraphim.cooldown_duration = 45
local ShieldOfTheRighteous = Ability:Add(53600, false, true)
ShieldOfTheRighteous.cooldown_duration = 18
ShieldOfTheRighteous.hasted_cooldown = true
ShieldOfTheRighteous.requires_charge = true
ShieldOfTheRighteous.triggers_gcd = false
ShieldOfTheRighteous:AutoAoe()
ShieldOfTheRighteous.buff = Ability:Add(132403, true, true)
ShieldOfTheRighteous.buff.buff_duration = 4.5
local LightOfTheProtector = Ability:Add(184092, true, true)
LightOfTheProtector.cooldown_duration = 17
LightOfTheProtector.hasted_cooldown = true
------ Talents
local BastionOfLight = Ability:Add(204035, true, true)
BastionOfLight.cooldown_duration = 120
local BlessedHammer = Ability:Add(204019, false, true)
BlessedHammer.buff_duration = 5
BlessedHammer.cooldown_duration = 4.5
BlessedHammer.requires_charge = true
BlessedHammer:AutoAoe()
local CrusadersJudgment = Ability:Add(204023, true, true)
------ Procs
local AvengersValor = Ability:Add(197561, true, true)
AvengersValor.buff_duration = 15
---- Retribution
local BladeOfJustice = Ability:Add(184575, false, true)
BladeOfJustice.cooldown_duration = 10.5
BladeOfJustice.hasted_cooldown = true
local CrusaderStrike = Ability:Add(35395, false, true)
CrusaderStrike.cooldown_duration = 6
CrusaderStrike.hasted_cooldown = true
CrusaderStrike.requires_charge = true
local DivineStorm = Ability:Add(53385, false, true)
DivineStorm.power_cost = 3
DivineStorm:AutoAoe(true)
local GreaterBlessingOfKings = Ability:Add(203538, true, false)
GreaterBlessingOfKings.buff_duration = 1800
local GreaterBlessingOfWisdom = Ability:Add(203539, true, false)
GreaterBlessingOfWisdom.buff_duration = 1800
local Judgment = Ability:Add(20271, false, true, 197277)
Judgment.buff_duration = 15
Judgment.cooldown_duration = 12
Judgment.max_range = 30
Judgment.hasted_cooldown = true
Judgment:SetVelocity(35)
local ShieldOfVengeance = Ability:Add(184662, true, true)
ShieldOfVengeance.buff_duration = 15
ShieldOfVengeance.cooldown_duration = 120
local TemplarsVerdict = Ability:Add(85256, false, true, 224266)
TemplarsVerdict.power_cost = 3
------ Talents
local ConsecrationRet = Ability:Add(205228, false, true, 81297)
ConsecrationRet.buff_duration = 6
ConsecrationRet.cooldown_duration = 20
ConsecrationRet.tick_interval = 1
ConsecrationRet.hasted_ticks = true
ConsecrationRet:AutoAoe()
local Crusade = Ability:Add(231895, true, true)
Crusade.buff_duration = 30
Crusade.cooldown_duration = 120
Crusade.requires_charge = true
local DivinePurpose = Ability:Add(223817, true, true, 223819)
DivinePurpose.buff_duration = 12
local ExecutionSentence = Ability:Add(267798, false, true, 267799)
ExecutionSentence.buff_duration = 12
ExecutionSentence.cooldown_duration = 30
ExecutionSentence.power_cost = 3
local EyeForAnEye = Ability:Add(205191, true, true)
EyeForAnEye.buff_duration = 10
EyeForAnEye.cooldown_duration = 60
local FiresOfJustice = Ability:Add(203316, true, true, 209785)
FiresOfJustice.buff_duration = 15
local Inquisition = Ability:Add(84963, true, true)
Inquisition.buff_duration = 15
Inquisition.power_cost = 1
local HammerOfWrath = Ability:Add(24275, false, true)
HammerOfWrath.cooldown_duration = 7.5
HammerOfWrath.hasted_cooldown = true
HammerOfWrath.max_range = 30
HammerOfWrath:SetVelocity(40)
local SelflessHealer = Ability:Add(85804, true, true, 114250)
SelflessHealer.buff_duration = 15
local WakeOfAshes = Ability:Add(255937, false, true)
WakeOfAshes.buff_duration = 5
WakeOfAshes.cooldown_duration = 45
WakeOfAshes:AutoAoe()
local RighteousVerdict = Ability:Add(267610, true, true, 267611)
RighteousVerdict.buff_duration = 6
------ Procs

-- Azerite Traits
local EmpyreanPower = Ability:Add(286390, true, true, 286393)
EmpyreanPower.buff_duration = 15
local LightsDecree = Ability:Add(286229, false, true, 286232)
LightsDecree:AutoAoe()
-- Heart of Azeroth
---- Major Essences
local AnimaOfDeath = Ability:Add({294926, 300002, 300003}, false, true)
AnimaOfDeath.cooldown_duration = 120
AnimaOfDeath.essence_id = 24
AnimaOfDeath.essence_major = true
local BloodOfTheEnemy = Ability:Add({297108, 298273, 298277} , false, true)
BloodOfTheEnemy.buff_duration = 10
BloodOfTheEnemy.cooldown_duration = 120
BloodOfTheEnemy.essence_id = 23
BloodOfTheEnemy.essence_major = true
BloodOfTheEnemy:AutoAoe(true)
BloodOfTheEnemy.buff = Ability:Add(297126, true, true) -- Seething Rage
BloodOfTheEnemy.buff.buff_duration = 5
BloodOfTheEnemy.buff.essence_id = 23
local ConcentratedFlame = Ability:Add({295373, 299349, 299353}, true, true, 295378)
ConcentratedFlame.buff_duration = 180
ConcentratedFlame.cooldown_duration = 30
ConcentratedFlame.requires_charge = true
ConcentratedFlame.essence_id = 12
ConcentratedFlame.essence_major = true
ConcentratedFlame:SetVelocity(40)
ConcentratedFlame.dot = Ability:Add(295368, false, true)
ConcentratedFlame.dot.buff_duration = 6
ConcentratedFlame.dot.tick_interval = 2
ConcentratedFlame.dot.essence_id = 12
ConcentratedFlame.dot.essence_major = true
local GuardianOfAzeroth = Ability:Add({295840, 299355, 299358}, false, true)
GuardianOfAzeroth.cooldown_duration = 180
GuardianOfAzeroth.essence_id = 14
GuardianOfAzeroth.essence_major = true
local FocusedAzeriteBeam = Ability:Add({295258, 299336, 299338}, false, true)
FocusedAzeriteBeam.cooldown_duration = 90
FocusedAzeriteBeam.essence_id = 5
FocusedAzeriteBeam.essence_major = true
FocusedAzeriteBeam:AutoAoe()
local MemoryOfLucidDreams = Ability:Add({298357, 299372, 299374}, true, true)
MemoryOfLucidDreams.buff_duration = 15
MemoryOfLucidDreams.cooldown_duration = 120
MemoryOfLucidDreams.essence_id = 27
MemoryOfLucidDreams.essence_major = true
local PurifyingBlast = Ability:Add({295337, 299345, 299347}, false, true, 295338)
PurifyingBlast.cooldown_duration = 60
PurifyingBlast.essence_id = 6
PurifyingBlast.essence_major = true
PurifyingBlast:AutoAoe(true)
local ReapingFlames = Ability:Add({310690, 311194, 311195}, false, true)
ReapingFlames.cooldown_duration = 45
ReapingFlames.essence_id = 35
ReapingFlames.essence_major = true
local RippleInSpace = Ability:Add({302731, 302982, 302983}, true, true)
RippleInSpace.buff_duration = 2
RippleInSpace.cooldown_duration = 60
RippleInSpace.essence_id = 15
RippleInSpace.essence_major = true
local TheUnboundForce = Ability:Add({298452, 299376,299378}, false, true)
TheUnboundForce.cooldown_duration = 45
TheUnboundForce.essence_id = 28
TheUnboundForce.essence_major = true
local VigilantProtector = Ability:Add({310592, 310601, 310602}, false, true)
VigilantProtector.cooldown_duration = 120
VigilantProtector.essence_id = 34
VigilantProtector.essence_major = true
local VisionOfPerfection = Ability:Add({296325, 299368, 299370}, true, true, 303345)
VisionOfPerfection.buff_duration = 10
VisionOfPerfection.essence_id = 22
VisionOfPerfection.essence_major = true
local WorldveinResonance = Ability:Add({295186, 298628, 299334}, true, true)
WorldveinResonance.cooldown_duration = 60
WorldveinResonance.essence_id = 4
WorldveinResonance.essence_major = true
---- Minor Essences
local AncientFlame = Ability:Add(295367, false, true)
AncientFlame.buff_duration = 10
AncientFlame.essence_id = 12
local CondensedLifeForce = Ability:Add(295367, false, true)
CondensedLifeForce.essence_id = 14
local FocusedEnergy = Ability:Add(295248, true, true)
FocusedEnergy.buff_duration = 4
FocusedEnergy.essence_id = 5
local Lifeblood = Ability:Add(295137, true, true)
Lifeblood.essence_id = 4
local LucidDreams = Ability:Add(298343, true, true)
LucidDreams.buff_duration = 8
LucidDreams.essence_id = 27
local PurificationProtocol = Ability:Add(295305, false, true)
PurificationProtocol.essence_id = 6
PurificationProtocol:AutoAoe()
local RealityShift = Ability:Add(302952, true, true)
RealityShift.buff_duration = 20
RealityShift.cooldown_duration = 30
RealityShift.essence_id = 15
local RecklessForce = Ability:Add(302932, true, true)
RecklessForce.buff_duration = 3
RecklessForce.essence_id = 28
RecklessForce.counter = Ability:Add(302917, true, true)
RecklessForce.counter.essence_id = 28
local StriveForPerfection = Ability:Add(299369, true, true)
StriveForPerfection.essence_id = 22
-- PvP talents
local DivinePunisher = Ability:Add(204914, true, true, 216762)
local HammerOfReckoning = Ability:Add(247675, true, true, 247677)
HammerOfReckoning.buff_duration = 30
HammerOfReckoning.cooldown_duration = 60
-- Racials
local LightsJudgment = Ability:Add(255647, false, true)
LightsJudgment.buff_duration = 3
LightsJudgment.cooldown_duration = 150
LightsJudgment:AutoAoe()
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
local GreaterFlaskOfTheUndertow = InventoryItem:Add(168654)
GreaterFlaskOfTheUndertow.buff = Ability:Add(298841, true, true)
local PotionOfUnbridledFury = InventoryItem:Add(169299)
PotionOfUnbridledFury.buff = Ability:Add(300714, true, true)
PotionOfUnbridledFury.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:Init()
	self.locations = {}
	self.traits = {}
	self.essences = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:Update()
	local _, loc, slot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for pid in next, self.essences do
		self.essences[pid] = nil
	end
	if UnitEffectiveLevel('player') < 110 then
		--print('disabling azerite, player is effectively level', UnitEffectiveLevel('player'))
		return -- disable all Azerite/Essences for players scaled under 110
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			for _, slot in next, C_AzeriteEmpoweredItem.GetAllTierInfo(loc) do
				if slot.azeritePowerIDs then
					for _, pid in next, slot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								--print('Azerite found:', pinfo.azeritePowerID, GetSpellInfo(pinfo.spellID))
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
	for _, loc in next, C_AzeriteEssence.GetMilestones() or {} do
		if loc.slot then
			pid = C_AzeriteEssence.GetMilestoneEssence(loc.ID)
			if pid then
				pinfo = C_AzeriteEssence.GetEssenceInfo(pid)
				self.essences[pid] = {
					id = pid,
					rank = pinfo.rank,
					major = loc.slot == 0,
				}
			end
		end
	end
end

-- End Azerite Trait API

-- Start Player API

function Player:Health()
	return self.health
end

function Player:HealthMax()
	return self.health_max
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:HolyPower()
	return self.holy_power
end

function Player:UnderAttack()
	return (Player.time - self.last_swing_taken) < 3
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

function Player:Dazed()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HARMFUL')
		if not id then
			return false
		elseif (
			id == 1604 -- Dazed (hit from behind)
		) then
			return true
		end
	end
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

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateAbilities()
	Player.mana_max = UnitPowerMax('player', 0)
	Player.holy_power_max = UnitPowerMax('player', 9)

	local _, ability, spellId

	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or Azerite.traits[spellId] then
				ability.known = true
				break
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) then
			ability.known = false -- spell is locked, do not mark as known
		elseif ability.essence_id and Azerite.essences[ability.essence_id] then
			if ability.essence_major then
				ability.known = Azerite.essences[ability.essence_id].major
			else
				ability.known = true
			end
		end
	end

	if Crusade.known then
		AvengingWrath.known = false
	end
	AvengersValor.known = AvengersShield.known
	AvengingWrath.autocrit.known = AvengingWrath.known
	Consecration.dot.known = Consecration.known
	ShieldOfTheRighteous.buff.known = ShieldOfTheRighteous.known

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
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

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.healthArray, 1)
	self.healthArray[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * 15
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.healthArray[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	if UI:ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = UnitLevel('player')
		self.hostile = true
		local i
		for i = 1, 25 do
			self.healthArray[i] = 0
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
			self.healthArray[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= UnitLevel('player') + 3) then
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

function Ability:HolyPowerCost()
	if DivinePurpose.known and DivinePurpose:Up() then
		return 0
	end
	local cost = self.power_cost
	if cost > 0 and FiresOfJustice.known and FiresOfJustice:Up() then
		cost = cost - 1
	end
	return cost
end

function ConcentratedFlame.dot:Remains()
	if ConcentratedFlame:Traveling() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function HammerOfJustice:Usable()
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self)
end

function Consecration:Remains()
	if Ability.Remains(self) <= 0 then
		return 0
	end
	return min(self.buff_duration, max(0, self.buff_duration - (Player.time - self.last_used) - Player.execute_remains))
end
ConsecrationRet.Remains = Consecration.Remains

function Inquisition:HolyPowerCost()
	return min(3, max(1, Player.holy_power))
end

function HammerOfWrath:Usable()
	if Target.healthPercentage >= 20 and AvengingWrath:Down() and Crusade:Down() then
		return false
	end
	return Ability.Usable(self)
end

function DivineStorm:HolyPowerCost()
	if EmpyreanPower.known and EmpyreanPower:Up() then
		return 0
	end
	return Ability.HolyPowerCost(self)
end

function DivineShield:Usable()
	if Forbearance:Up() then
		return false
	end
	return Ability.Usable(self)
end
LayOnHands.Usable = DivineShield.Usable
BlessingOfProtection.Usable = DivineShield.Usable

function DivinePunisher:Remains()
	if self.target and self.target == Target.guid then
		return 60
	end
	return 0
end

function HammerOfReckoning:Usable()
	if self:Stack() < 50 or Player.aw_remains > 0 or Player.crusade_remains > 0 then
		return false
	end
	return Ability.Usable(self)
end

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

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.HOLY] = {},
	[SPEC.PROTECTION] = {},
	[SPEC.RETRIBUTION] = {},
}

APL[SPEC.HOLY].main = function(self)

end

APL[SPEC.PROTECTION].main = function(self)
	if Opt.defensives then
		if Player:HealthPct() < 75 then
			if LayOnHands:Usable() and Player:HealthPct() < 20 then
				UseExtra(LayOnHands)
			elseif DivineShield:Usable() and Player:HealthPct() < 20 then
				UseExtra(DivineShield)
			elseif BlessingOfProtection:Usable() and Player:UnderAttack() and Player:HealthPct() < 20 then
				UseExtra(BlessingOfProtection)
			end
		end
		if Player.movement_speed < 75 and BlessingOfFreedom:Usable() and not Player:Dazed() then
			UseExtra(BlessingOfFreedom)
		end
	end
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
actions.precombat+=/consecration
actions.precombat+=/lights_judgment
]]
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheUndertow:Usable() and GreaterFlaskOfTheUndertow.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheUndertow)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
		if AvengersShield:Usable() then
			return AvengersShield
		end
	end
--[[
actions=auto_attack
actions+=/call_action_list,name=cooldowns
actions+=/worldvein_resonance,if=buff.lifeblood.stack<3
# Dumping SotR charges
actions+=/shield_of_the_righteous,if=(buff.avengers_valor.up&cooldown.shield_of_the_righteous.charges_fractional>=2.5)&(cooldown.seraphim.remains>gcd|!talent.seraphim.enabled)
actions+=/shield_of_the_righteous,if=(buff.avenging_wrath.up&!talent.seraphim.enabled)|buff.seraphim.up&buff.avengers_valor.up
actions+=/shield_of_the_righteous,if=(buff.avenging_wrath.up&buff.avenging_wrath.remains<4&!talent.seraphim.enabled)|(buff.seraphim.remains<4&buff.seraphim.up)
actions+=/lights_judgment,if=buff.seraphim.up&buff.seraphim.remains<3
actions+=/consecration,if=!consecration.up
actions+=/judgment,if=(cooldown.judgment.remains<gcd&cooldown.judgment.charges_fractional>1&cooldown_react)|!talent.crusaders_judgment.enabled
actions+=/avengers_shield,if=cooldown_react
actions+=/judgment,if=cooldown_react|!talent.crusaders_judgment.enabled
actions+=/concentrated_flame,if=(!talent.seraphim.enabled|buff.seraphim.up)&!dot.concentrated_flame_burn.remains>0|essence.the_crucible_of_flame.rank<3
actions+=/lights_judgment,if=!talent.seraphim.enabled|buff.seraphim.up
actions+=/anima_of_death
actions+=/blessed_hammer,strikes=3
actions+=/hammer_of_the_righteous
actions+=/consecration
actions+=/heart_essence,if=!(essence.the_crucible_of_flame.major|essence.worldvein_resonance.major|essence.anima_of_life_and_death.major|essence.memory_of_lucid_dreams.major)
]]
	self:cooldowns()
	if WorldveinResonance:Usable() and Lifeblood:stack() < 3 then
		UseCooldown(WorldveinResonance)
	end
	if ShieldOfTheRighteous:Usable() and (
		(AvengersValor:Up() and ShieldOfTheRighteous:ChargesFractional() >= 2.5 and (not Seraphim.known or not Seraphim:Ready(Player.gcd))) or
		((not Seraphim.known and between(Player.aw_remains, 0.1, 4)) or (Seraphim.known and between(Seraphim:Remains(), 0.1, 4))) or
		((not Seraphim.known or Seraphim:Up()) and (not AvengingWrath.known or not AvengingWrath:Ready(4) or Player.aw_remains > 0) and (((ShieldOfTheRighteous.buff:Down() or AvengersShield:Ready()) and AvengersValor:Up()) or (ShieldOfTheRighteous:ChargesFractional() >= 2.5 and not AvengersShield:Ready() or AvengersValor:Up())))
	) then
		UseCooldown(ShieldOfTheRighteous, true)
	end
	if Seraphim.known and LightsJudgment:Usable() and Seraphim:Up() and Seraphim:Remains() < 3 then
		UseCooldown(LightsJudgment)
	end
	if Consecration:Usable() and Player.consecration_remains < 0.5 then
		return Consecration
	end
	if AvengersShield:Usable() and (Player.enemies > 1 or ShieldOfTheRighteous:ChargesFractional() >= 2.3 or (ShieldOfTheRighteous:Ready() and ShieldOfTheRighteous.buff:Down())) then
		return AvengersShield
	end
	if JudgmentProt:Usable() and (not CrusadersJudgment.known or JudgmentProt:ChargesFractional() > 1) then
		return JudgmentProt
	end
	if AvengersShield:Usable() then
		return AvengersShield
	end
	if JudgmentProt:Usable() then
		return JudgmentProt
	end
	if ConcentratedFlame:Usable() and (not Seraphim.known or Seraphim:Up()) and ConcentratedFlame.dot:Down() then
		return ConcentratedFlame
	end
	if LightsJudgment:Usable() and (not Seraphim.known or Seraphim:Up()) then
		UseCooldown(LightsJudgment)
	end
	if AnimaOfDeath:Usable() then
		UseCooldown(AnimaOfDeath)
	end
	if BlessedHammer:Usable() then
		return BlessedHammer
	end
	if HammerOfTheRighteous:Usable() then
		return HammerOfTheRighteous
	end
	if Consecration:Usable() then
		return Consecration
	end
	if VigilantProtector:Usable() then
		UseCooldown(VigilantProtector)
	end
end

APL[SPEC.PROTECTION].cooldowns = function(self)
--[[
actions.cooldowns=fireblood,if=buff.avenging_wrath.up
actions.cooldowns+=/use_item,name=azsharas_font_of_power,if=cooldown.seraphim.remains<=10|!talent.seraphim.enabled
actions.cooldowns+=/use_item,name=ashvanes_razor_coral,if=(debuff.razor_coral_debuff.stack>7&buff.avenging_wrath.up)|debuff.razor_coral_debuff.stack=0
actions.cooldowns+=/seraphim,if=cooldown.shield_of_the_righteous.charges_fractional>=2
actions.cooldowns+=/avenging_wrath,if=buff.seraphim.up|cooldown.seraphim.remains<2|!talent.seraphim.enabled
actions.cooldowns+=/memory_of_lucid_dreams,if=!talent.seraphim.enabled|cooldown.seraphim.remains<=gcd|buff.seraphim.up
actions.cooldowns+=/bastion_of_light,if=cooldown.shield_of_the_righteous.charges_fractional<=0.5
actions.cooldowns+=/potion,if=buff.avenging_wrath.up
actions.cooldowns+=/use_items,if=buff.seraphim.up|!talent.seraphim.enabled
actions.cooldowns+=/use_item,name=grongs_primal_rage,if=cooldown.judgment.full_recharge_time>4&cooldown.avengers_shield.remains>4&(buff.seraphim.up|cooldown.seraphim.remains+4+gcd>expected_combat_length-time)&consecration.up
actions.cooldowns+=/use_item,name=pocketsized_computation_device,if=cooldown.judgment.full_recharge_time>4*spell_haste&cooldown.avengers_shield.remains>4*spell_haste&(!equipped.grongs_primal_rage|!trinket.grongs_primal_rage.cooldown.up)&consecration.up
actions.cooldowns+=/use_item,name=merekthas_fang,if=!buff.avenging_wrath.up&(buff.seraphim.up|!talent.seraphim.enabled)
actions.cooldowns+=/use_item,name=razdunks_big_red_button
]]
	if LightOfTheProtector:Usable() and Player:HealthPct() < 40 then
		UseCooldown(LightOfTheProtector)
	end
	if Seraphim:Usable() and ShieldOfTheRighteous:ChargesFractional() >= 2 then
		UseCooldown(Seraphim)
	end
	if AvengingWrath:Usable() and (not Seraphim.known or Seraphim:Up() or Seraphim:Ready(2)) then
		UseCooldown(AvengingWrath)
	end
	if MemoryOfLucidDreams:Usable() and (not Seraphim.known or Seraphim:Ready(Player.gcd) or Seraphim:Up()) then
		UseCooldown(MemoryOfLucidDreams)
	end
	if BastionOfLight:Usable() and ShieldOfTheRighteous:ChargesFractional() < 0.5 then
		UseCooldown(BastionOfLight)
	end
	if Opt.pot and Target.boss and not Player:InArenaOrBattleground() and PotionOfUnbridledFury:Usable() then
		UseCooldown(PotionOfUnbridledFury)
	end
	if LightOfTheProtector:Usable() and Player:HealthPct() < 80 then
		UseCooldown(LightOfTheProtector)
	end
end

APL[SPEC.RETRIBUTION].main = function(self)
	if Opt.defensives then
		if Player:HealthPct() < 75 then
			if DivineShield:Usable() and Player:HealthPct() < 20 then
				UseExtra(DivineShield)
			elseif LayOnHands:Usable() and Player:HealthPct() < 20 then
				UseExtra(LayOnHands)
			elseif SelflessHealer.known and FlashOfLight:Usable() and SelflessHealer:Stack() >= 4 and Player:HealthPct() < (Player.group_size < 5 and 75 or 50) then
				UseExtra(FlashOfLight)
			elseif WordOfGlory:Usable() and Player:HealthPct() < (Player.group_size < 5 and 60 or 35) then
				UseExtra(WordOfGlory)
			elseif BlessingOfProtection:Usable() and Player:UnderAttack() and Player:HealthPct() < 20 then
				UseExtra(BlessingOfProtection)
			end
		end
		if Player.movement_speed < 75 and BlessingOfFreedom:Usable() and not Player:Dazed() then
			UseExtra(BlessingOfFreedom)
		end
	end
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
actions.precombat+=/use_item,name=azsharas_font_of_power
actions.precombat+=/arcane_torrent,if=!talent.wake_of_ashes.enabled
]]
		if Opt.blessings and Player.group_size == 1 then
			if GreaterBlessingOfKings:Usable() and GreaterBlessingOfKings:Remains() < 300 then
				UseExtra(GreaterBlessingOfKings)
			elseif GreaterBlessingOfWisdom:Usable() and GreaterBlessingOfWisdom:Remains() < 300 then
				UseExtra(GreaterBlessingOfWisdom)
			end
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheUndertow:Usable() and GreaterFlaskOfTheUndertow.buff:Remains() < 300 then
				UseCooldown(FlaskOfTheUndertow)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
	elseif Opt.blessings and Player.group_size == 1 then
		if GreaterBlessingOfKings:Usable() and GreaterBlessingOfKings:Remains() < 30 then
			UseExtra(GreaterBlessingOfKings)
		elseif GreaterBlessingOfWisdom:Usable() and GreaterBlessingOfWisdom:Remains() < 30 then
			UseExtra(GreaterBlessingOfWisdom)
		end
	end
--[[
actions=auto_attack
actions+=/rebuke
actions+=/call_action_list,name=cooldowns
actions+=/call_action_list,name=generators
]]
	Player.use_wings = (not AvengingWrath.known or Player.aw_remains == 0) and (not Crusade.known or Player.crusade_remains == 0) and (Target.boss or Target.timeToDie > (Player.gcd * 5) or Player.enemies >= 3)
	self:cooldowns()
	return self:generators()
end

APL[SPEC.RETRIBUTION].cooldowns = function(self)
--[[
actions.cooldowns=potion,if=(cooldown.guardian_of_azeroth.remains>90|!essence.condensed_lifeforce.major)&(buff.bloodlust.react|buff.avenging_wrath.up&buff.avenging_wrath.remains>18|buff.crusade.up&buff.crusade.remains<25)
actions.cooldowns+=/lights_judgment,if=spell_targets.lights_judgment>=2|(!raid_event.adds.exists|raid_event.adds.in>75)
actions.cooldowns+=/fireblood,if=buff.avenging_wrath.up|buff.crusade.up&buff.crusade.stack=10
actions.cooldowns+=/shield_of_vengeance,if=buff.seething_rage.down&buff.memory_of_lucid_dreams.down
actions.cooldowns+=/use_item,name=ashvanes_razor_coral,if=debuff.razor_coral_debuff.down|(buff.avenging_wrath.remains>=20|buff.crusade.stack=10&buff.crusade.remains>15)&(cooldown.guardian_of_azeroth.remains>90|target.time_to_die<30|!essence.condensed_lifeforce.major)
actions.cooldowns+=/the_unbound_force,if=time<=2|buff.reckless_force.up
actions.cooldowns+=/blood_of_the_enemy,if=buff.avenging_wrath.up|buff.crusade.up&buff.crusade.stack=10
actions.cooldowns+=/guardian_of_azeroth,if=!talent.crusade.enabled&(cooldown.avenging_wrath.remains<5&holy_power>=3&(buff.inquisition.up|!talent.inquisition.enabled)|cooldown.avenging_wrath.remains>=45)|(talent.crusade.enabled&cooldown.crusade.remains<gcd&holy_power>=4|holy_power>=3&time<10&talent.wake_of_ashes.enabled|cooldown.crusade.remains>=45)
actions.cooldowns+=/worldvein_resonance,if=cooldown.avenging_wrath.remains<gcd&holy_power>=3|talent.crusade.enabled&cooldown.crusade.remains<gcd&holy_power>=4|cooldown.avenging_wrath.remains>=45|cooldown.crusade.remains>=45
actions.cooldowns+=/focused_azerite_beam,if=(!raid_event.adds.exists|raid_event.adds.in>30|spell_targets.divine_storm>=2)&!(buff.avenging_wrath.up|buff.crusade.up)&(cooldown.blade_of_justice.remains>gcd*3&cooldown.judgment.remains>gcd*3)
actions.cooldowns+=/memory_of_lucid_dreams,if=(buff.avenging_wrath.up|buff.crusade.up&buff.crusade.stack=10)&holy_power<=3
actions.cooldowns+=/purifying_blast,if=(!raid_event.adds.exists|raid_event.adds.in>30|spell_targets.divine_storm>=2)
actions.cooldowns+=/use_item,effect_name=cyclotronic_blast,if=!(buff.avenging_wrath.up|buff.crusade.up)&(cooldown.blade_of_justice.remains>gcd*3&cooldown.judgment.remains>gcd*3)
actions.cooldowns+=/avenging_wrath,if=(!talent.inquisition.enabled|buff.inquisition.up)&holy_power>=3
actions.cooldowns+=/crusade,if=holy_power>=4|holy_power>=3&time<10&talent.wake_of_ashes.enabled
]]
	if Opt.pot and not Player:InArenaOrBattleground() and PotionOfUnbridledFury:Usable() and (not GuardianOfAzeroth.known or not GuardianOfAzeroth:Ready(90)) and (Player:BloodlustActive() or Player.aw_remains > 18 or (Player.crusade_remains > 0 and Player.crusade_remains < 25)) then
		UseCooldown(PotionOfUnbridledFury)
	end
	if LightsJudgment:Usable() and Player.enemies >= 2 then
		UseCooldown(LightsJudgment)
	end
	if Opt.defensives and Player:UnderAttack() and BloodOfTheEnemy.buff:Down() and MemoryOfLucidDreams:Down() and DivineShield:Down() and BlessingOfProtection:Down() then
		if ShieldOfVengeance:Usable() and (not EyeForAnEye.known or EyeForAnEye:Down()) then
			UseExtra(ShieldOfVengeance)
		elseif EyeForAnEye:Usable() and ShieldOfVengeance:Down() then
			UseExtra(EyeForAnEye)
		end
	end
	if TheUnboundForce:Usable() and (RecklessForce:Up() or RecklessForce.counter:Stack() < 4) then
		UseCooldown(TheUnboundForce)
	elseif BloodOfTheEnemy:Usable() and (Player.aw_remains > 0 or Crusade.known and Crusade:Stack() >= 10) then
		UseCooldown(BloodOfTheEnemy)
	elseif GuardianOfAzeroth:Usable() and ((not Crusade.known and (AvengingWrath:Ready(5) and Player:HolyPower() >= 3 and (not Inquisition.known or Inquisition:Up()) or not AvengingWrath:Ready(45))) or (Crusade.known and (not Crusade:Ready(45) or (Crusade:Ready(Player.gcd) and Player:HolyPower() >= 4))) or (WakeOfAshes.known and Player:HolyPower() >= 3 and Player:TimeInCombat() < 10)) then
		UseCooldown(GuardianOfAzeroth)
	elseif WorldveinResonance:Usable() and Lifeblood:Stack() < 4 and ((AvengingWrath:Ready(Player.gcd) and Player:HolyPower() >= 3) or (Crusade.known and Crusade:Ready(Player.gcd) and Player:HolyPower() >= 4) or not AvengingWrath:Ready(45) or (Crusade.known and not Crusade:Ready(45))) then
		UseCooldown(WorldveinResonance)
	elseif FocusedAzeriteBeam:Usable() and not (Player.aw_remains > 0 or Player.crusade_remains > 0 or BladeOfJustice:Ready(Player.gcd * 3) or Judgment:Ready(Player.gcd * 3)) then
		UseCooldown(FocusedAzeriteBeam)
	elseif MemoryOfLucidDreams:Usable() and (Player.aw_remains > 0 or Crusade:Stack() >= 10) and Player:HolyPower() <= 3 then
		UseCooldown(MemoryOfLucidDreams)
	elseif PurifyingBlast:Usable() then
		UseCooldown(PurifyingBlast)
	end
	if HammerOfReckoning:Usable() and Player:HolyPower() >= 4 then
		UseCooldown(HammerOfReckoning)
	end
	if Player.use_wings and AvengingWrath:Usable() and (not Inquisition.known or Inquisition:Up()) and Player:HolyPower() >= 3 then
		UseCooldown(AvengingWrath)
	end
	if Player.use_wings and Crusade:Usable() and (Player:HolyPower() >= 4 or (WakeOfAshes.known and Player:HolyPower() >= 3 and Player:TimeInCombat() < 10)) then
		UseCooldown(Crusade)
	end
end

APL[SPEC.RETRIBUTION].finishers = function(self)
--[[
actions.finishers=variable,name=pool_for_wings,value=!talent.crusade.enabled&!buff.avenging_wrath.up&cooldown.avenging_wrath.remains<gcd*3|talent.crusade.enabled&!buff.crusade.up&cooldown.crusade.remains<gcd*3
actions.finishers+=/variable,name=use_ds,value=spell_targets.divine_storm>=2&!talent.righteous_verdict.enabled|spell_targets.divine_storm>=3&talent.righteous_verdict.enabled|buff.empyrean_power.up&debuff.judgment.down&buff.divine_purpose.down&buff.avenging_wrath_autocrit.down
actions.finishers+=/inquisition,if=buff.avenging_wrath.down&(buff.inquisition.down|buff.inquisition.remains<8&holy_power>=3|talent.execution_sentence.enabled&cooldown.execution_sentence.remains<10&buff.inquisition.remains<15|cooldown.avenging_wrath.remains<15&buff.inquisition.remains<20&holy_power>=3)
actions.finishers+=/execution_sentence,if=spell_targets.divine_storm<=2&(!talent.crusade.enabled&cooldown.avenging_wrath.remains>10|talent.crusade.enabled&buff.crusade.down&cooldown.crusade.remains>10|buff.crusade.stack>=7)
actions.finishers+=/divine_storm,if=variable.use_ds&!variable.pool_for_wings&((!talent.execution_sentence.enabled|(spell_targets.divine_storm>=2|cooldown.execution_sentence.remains>gcd*2))|(cooldown.avenging_wrath.remains>gcd*3&cooldown.avenging_wrath.remains<10|cooldown.crusade.remains>gcd*3&cooldown.crusade.remains<10|buff.crusade.up&buff.crusade.stack<10))
actions.finishers+=/templars_verdict,if=variable.pool_for_wings&(!talent.execution_sentence.enabled|cooldown.execution_sentence.remains>gcd*2|cooldown.avenging_wrath.remains>gcd*3&cooldown.avenging_wrath.remains<10|cooldown.crusade.remains>gcd*3&cooldown.crusade.remains<10|buff.crusade.up&buff.crusade.stack<10)
]]
	Player.pool_for_wings = Player.use_wings and ((AvengingWrath.known and AvengingWrath:Ready(Player.gcd * 3)) or (Crusade.known and Crusade:Ready(Player.gcd * 3)))
	Player.use_ds = Player.enemies >= (RighteousVerdict.known and 3 or 2) or (EmpyreanPower.known and EmpyreanPower:Up() and Judgment:Down() and DivinePurpose:Down() and AvengingWrath.autocrit:Down())
	if Inquisition:Usable() and Player.aw_remains == 0 and (Inquisition:Down() or (Inquisition:Remains() < 8 and Player:HolyPower() >= 3) or (ExecutionSentence.known and ExecutionSentence:Ready(10) and Inquisition:Remains() < 15) or (AvengingWrath:Ready(15) and Inquisition:Remains() < 20 and Player:HolyPower() >= 3)) then
		return Inquisition
	end
	if ExecutionSentence:Usable() and Player.enemies <= 2 and ((AvengingWrath.known and not AvengingWrath:Ready(10)) or (Crusade.known and ((Player.crusade_remains == 0 and not Crusade:Ready(10)) or Crusade:stack() >= 7))) then
		return ExecutionSentence
	end
	if Player.pool_for_wings then
		return
	end
	if Player.use_ds and DivineStorm:Usable() and ((not ExecutionSentence.known or (Player.enemies >= 2 or not ExecutionSentence:Ready(Player.gcd * 2))) or ((AvengingWrath.known and between(AvengingWrath:Cooldown(), Player.gcd * 3, 10)) or (Crusade.known and between(Crusade:Cooldown(), Player.gcd * 3, 10) or (Player.crusade_remains > 0 and Crusade:Stack() < 10)))) then
		return DivineStorm
	end
	if TemplarsVerdict:Usable() and (not ExecutionSentence.known or not ExecutionSentence:Ready(Player.gcd * 2) or (AvengingWrath.known and between(AvengingWrath:Cooldown(), Player.gcd * 3, 10)) or (Crusade.known and between(Crusade:Cooldown(), Player.gcd * 3, 10) or (Player.crusade_remains > 0 and Crusade:Stack() < 10))) then
		return TemplarsVerdict
	end
end

APL[SPEC.RETRIBUTION].generators = function(self)
--[[
actions.generators=variable,name=HoW,value=(!talent.hammer_of_wrath.enabled|target.health.pct>=20&!(buff.avenging_wrath.up|buff.crusade.up))
actions.generators+=/call_action_list,name=finishers,if=holy_power>=5|buff.memory_of_lucid_dreams.up|buff.seething_rage.up|talent.inquisition.enabled&buff.inquisition.down&holy_power>=3
actions.generators+=/wake_of_ashes,if=(!raid_event.adds.exists|raid_event.adds.in>15|spell_targets.wake_of_ashes>=2)&(holy_power<=0|holy_power=1&cooldown.blade_of_justice.remains>gcd)&(cooldown.avenging_wrath.remains>10|talent.crusade.enabled&cooldown.crusade.remains>10)
actions.generators+=/blade_of_justice,if=holy_power<=2|(holy_power=3&(cooldown.hammer_of_wrath.remains>gcd*2|variable.HoW))
actions.generators+=/judgment,if=holy_power<=2|(holy_power<=4&(cooldown.blade_of_justice.remains>gcd*2|variable.HoW))
actions.generators+=/hammer_of_wrath,if=holy_power<=4
actions.generators+=/consecration,if=holy_power<=2|holy_power<=3&cooldown.blade_of_justice.remains>gcd*2|holy_power=4&cooldown.blade_of_justice.remains>gcd*2&cooldown.judgment.remains>gcd*2
actions.generators+=/call_action_list,name=finishers,if=talent.hammer_of_wrath.enabled&target.health.pct<=20|buff.avenging_wrath.up|buff.crusade.up
actions.generators+=/crusader_strike,if=cooldown.crusader_strike.charges_fractional>=1.75&(holy_power<=2|holy_power<=3&cooldown.blade_of_justice.remains>gcd*2|holy_power=4&cooldown.blade_of_justice.remains>gcd*2&cooldown.judgment.remains>gcd*2&cooldown.consecration.remains>gcd*2)
actions.generators+=/call_action_list,name=finishers
actions.generators+=/concentrated_flame
actions.generators+=/reaping_flames
actions.generators+=/crusader_strike,if=holy_power<=4
actions.generators+=/arcane_torrent,if=holy_power<=4
]]
	Player.how = not HammerOfWrath.known or (Target.healthPercentage >= 20 and not (Player.aw_remains > 0 or Player.crusade_remains > 0))
	local finisher = self:finishers()
	if Player:HolyPower() >= 5 or MemoryOfLucidDreams:Up() or BloodOfTheEnemy.buff:Up() or (Inquisition.known and Inquisition:Down() and Player:HolyPower() >= 3) then
		if finisher then return finisher end
	end
	if WakeOfAshes:Usable() and (Player:HolyPower() <= 0 or (Player:HolyPower() <= 1 and not BladeOfJustice:Ready(Player.gcd))) and ((AvengingWrath.known and not AvengingWrath:Ready(10)) or (Crusade.known and not Crusade:Ready(10))) then
		UseCooldown(WakeOfAshes)
	end
	if BladeOfJustice:Usable() and (Player:HolyPower() <= 2 or (Player:HolyPower() <= 3 and (Player.how or not HammerOfWrath:Ready(Player.gcd * 2)))) then
		return BladeOfJustice
	end
	if Judgment:Usable() and (Player:HolyPower() <= 2 or (Player:HolyPower() <= 4 and DivinePunisher:Down() and (Player.how or not HammerOfWrath:Ready(Player.gcd * 2)))) then
		return Judgment
	end
	if HammerOfWrath:Usable() and Player:HolyPower() <= 4 then
		return HammerOfWrath
	end
	if ConsecrationRet:Usable() and (Player:HolyPower() <= 2 or (not BladeOfJustice:Ready(Player.gcd * 2) and (Player:HolyPower() <= 3 or (Player:HolyPower() <= 4 and not Judgment:Ready(Player.gcd * 2))))) then
		return ConsecrationRet
	end
	if Player.aw_remains > 0 or Player.crusade_remains > 0 or (HammerOfWrath.known and Target.healthPercentage <= 20) or (DivinePunisher:Up() and Judgment:Ready(Player.gcd)) then
		if finisher then return finisher end
	end
	if CrusaderStrike:Usable() and CrusaderStrike:ChargesFractional() >= 1.75 and (Player:HolyPower() <= 2 or (not BladeOfJustice:Ready(Player.gcd * 2) and (Player:HolyPower() <= 3 or (Player:HolyPower() <= 4 and not Judgment:Ready(Player.gcd * 2) and (not ConsecrationRet.known or not ConsecrationRet:Ready(Player.gcd * 2)))))) then
		return CrusaderStrike
	end
	if finisher then return finisher end
	if ConcentratedFlame:Usable() and ConcentratedFlame.dot:Down() then
		return ConcentratedFlame
	end
	if ReapingFlames:Usable() then
		return ReapingFlames
	end
	if CrusaderStrike:Usable() and Player:HolyPower() <= 4 then
		return CrusaderStrike
	end
end

APL.Interrupt = function(self)
	if Rebuke:Usable() then
		return Rebuke
	end
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

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.HOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -3 }
		},
		[SPEC.PROTECTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -3 }
		},
		[SPEC.RETRIBUTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -3 }
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.HOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
		[SPEC.PROTECTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
		[SPEC.RETRIBUTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		retardedPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		retardedPanel:ClearAllPoints()
		retardedPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		   (Player.spec == SPEC.HOLY and Opt.hide.holy) or
		   (Player.spec == SPEC.PROTECTION and Opt.hide.protection) or
		   (Player.spec == SPEC.RETRIBUTION and Opt.hide.retribution))
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
	local dim, text_tl, text_bl
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end

	if AvengingWrath.known and Player.aw_remains > 0 then
		text_tl = format('%.1fs', Player.aw_remains)
	elseif Crusade.known and Player.crusade_remains > 0 then
		text_tl = format('%.1fs', Player.crusade_remains)
	end
	if (Consecration.known or ConsecrationRet.known) and Player.consecration_remains > 0 then
		text_bl = format('%.1fs', Player.consecration_remains)
	end

	retardedPanel.dimmer:SetShown(dim)
	retardedPanel.text.tl:SetText(text_tl)
	retardedPanel.text.bl:SetText(text_bl)
	--retardedPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId, speed, max_speed
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.main =  nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	start, duration = GetSpellCooldown(61304)
	Player.gcd_remains = start > 0 and duration - (Player.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	Player.ability_casting = abilities.bySpellId[spellId]
	Player.execute_remains = max(remains and (remains / 1000 - Player.ctime) or 0, Player.gcd_remains)
	Player.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	Player.gcd = 1.5 * Player.haste_factor
	Player.health = UnitHealth('player')
	Player.health_max = UnitHealthMax('player')
	Player.mana_regen = GetPowerRegen()
	Player.mana = UnitPower('player', 0) + (Player.mana_regen * Player.execute_remains)
	if Player.ability_casting then
		Player.mana = Player.mana - Player.ability_casting:ManaCost()
	end
	Player.mana = min(max(Player.mana, 0), Player.mana_max)
	Player.holy_power = UnitPower('player', 9)
	speed, max_speed = GetUnitSpeed('player')
	Player.moving = speed ~= 0
	Player.movement_speed = max_speed / 7 * 100

	if AvengingWrath.known then
		Player.aw_remains = AvengingWrath:Remains()
	end
	if Crusade.known then
		Player.crusade_remains = Crusade:Remains()
	end
	if Consecration.known then
		Player.consecration_remains = Consecration:Remains()
	elseif ConsecrationRet.known then
		Player.consecration_remains = ConsecrationRet:Remains()
	end

	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end

	Player.main = APL[Player.spec]:main()
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
		local ends, notInterruptible
		_, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			retardedInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			retardedInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		retardedInterruptPanel.icon:SetShown(Player.interrupt)
		retardedInterruptPanel.border:SetShown(Player.interrupt)
		retardedInterruptPanel:SetShown(start and not notInterruptible)
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
	if name == 'Retarded' then
		Opt = Retarded
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. name .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Retarded1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] ' .. name .. ' is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitOpts()
		Azerite:Init()
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

	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName or 'Unknown', spellId or 0))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
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
		Player.last_ability = ability
		ability.last_used = Player.time
		if ability.triggers_gcd then
			Player.previous_gcd[10] = nil
			table.insert(Player.previous_gcd, 1, ability)
		end
		if ability.travel_start then
			ability.travel_start[dstGUID] = Player.time
		end
		if Opt.previous and retardedPanel:IsVisible() then
			retardedPreviousPanel.ability = ability
			retardedPreviousPanel.border:SetTexture('Interface\\AddOns\\Retarded\\border.blp')
			retardedPreviousPanel.icon:SetTexture(ability.icon)
			retardedPreviousPanel:Show()
		end
		if ability == Judgment and DivinePunisher.known then
			DivinePunisher.target = dstGUID
		end
		return
	elseif eventType == 'SPELL_ENERGIZE' then
		if ability == DivinePunisher then
			DivinePunisher.target = nil
		end
	end

	if dstGUID == Player.guid then
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
		if ability.travel_start and ability.travel_start[dstGUID] then
			ability.travel_start[dstGUID] = nil
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and retardedPanel:IsVisible() and ability == retardedPreviousPanel.ability then
			retardedPreviousPanel.border:SetTexture('Interface\\AddOns\\Retarded\\misseffect.blp')
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
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
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
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	retardedPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Target:Update()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		retardedPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'RUNIC_POWER' then
		UI:UpdateCombatWithin(0.05)
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

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:AZERITE_ESSENCE_UPDATE()
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:GROUP_ROSTER_UPDATE()
	Player.group_size = min(max(GetNumGroupMembers(), 1), 10)
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	events:GROUP_ROSTER_UPDATE()
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
	print('Retarded -', desc .. ':', opt_view, ...)
end

function SlashCmdList.Retarded(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				doomedPanel:ClearAllPoints()
			end
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
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
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra/Pet cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000pet 0.4|r, and |cFFFFD000glow 1|r')
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
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra/pet cooldown icon)', Opt.glow.extra)
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
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000pet|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
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
		return Status('Show the Doomed UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use Doomed for cooldown management', Opt.cooldown)
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
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'h') then
				Opt.hide.holy = not Opt.hide.holy
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Holy specialization', not Opt.hide.holy)
			end
			if startsWith(msg[2], 'p') then
				Opt.hide.protection = not Opt.hide.protection
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Protection specialization', not Opt.hide.protection)
			end
			if startsWith(msg[2], 'r') then
				Opt.hide.retribution = not Opt.hide.retribution
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Retribution specialization', not Opt.hide.retribution)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000holy|r/|cFFFFD000protection|r/|cFFFFD000retribution|r')
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
	if startsWith(msg[1], 'de') then
		if msg[2] then
			Opt.defensives = msg[2] == 'on'
		end
		return Status('Show defensives/emergency heals in extra UI', Opt.defensives)
	end
	if startsWith(msg[1], 'bl') then
		if msg[2] then
			Opt.blessings = msg[2] == 'on'
		end
		return Status('show Greater Blessings reminders in extra UI (solo only)', Opt.blessings)
	end
	if msg[1] == 'reset' then
		retardedPanel:ClearAllPoints()
		retardedPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print('Retarded (version: |cFFFFD000' .. GetAddOnMetadata('Retarded', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Retarded UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Retarded UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Retarded UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Retarded UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Retarded UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Retarded for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000holy|r/|cFFFFD000protection|r/|cFFFFD000retribution|r - toggle disabling Retarded for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'defensives |cFF00C000on|r/|cFFC00000off|r - show defensives/emergency heals in extra UI',
		'blessings |cFF00C000on|r/|cFFC00000off|r - show Greater Blessings reminders in extra UI (solo only)',
		'|cFFFFD000reset|r - reset the location of the Retarded UI to default',
	} do
		print('  ' .. SLASH_Retarded1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end
