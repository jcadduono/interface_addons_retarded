local ADDON = 'Retarded'
if select(2, UnitClass('player')) ~= 'PALADIN' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = _G.UnitAura
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
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
			animation = false,
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
		cd_ttd = 10,
		pot = false,
		trinket = true,
		heal_threshold = 60,
		defensives = true,
		auras = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- timers for updating combat/display/hp info
local Timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- specialization constants
local SPEC = {
	NONE = 0,
	HOLY = 1,
	PROTECTION = 2,
	RETRIBUTION = 3,
}

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.HOLY] = {},
	[SPEC.PROTECTION] = {},
	[SPEC.RETRIBUTION] = {},
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	spec = 0,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	movement_speed = 100,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	mana = {
		current = 0,
		deficit = 0,
		max = 100,
		regen = 0,
	},
	holy_power = {
		current = 0,
		deficit = 0,
		max = 5,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		chained = false,
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		ticks_extra = 0,
		interruptible = false,
		early_chainable = false,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		last_taken = 0,
	},
	set_bonus = {
		t29 = 0, -- Virtuous Silver Cataphract
		t30 = 0, -- Heartfire Sentinel's Authority
		t31 = 0, -- Zealous Pyreknight's Ardor
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
	major_cd_remains = 0,
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
}

local retardedPanel = CreateFrame('Frame', 'retardedPanel', UIParent)
retardedPanel:SetPoint('CENTER', 0, -169)
retardedPanel:SetFrameStrata('BACKGROUND')
retardedPanel:SetSize(64, 64)
retardedPanel:SetMovable(true)
retardedPanel:SetUserPlaced(true)
retardedPanel:RegisterForDrag('LeftButton')
retardedPanel:SetScript('OnDragStart', retardedPanel.StartMoving)
retardedPanel:SetScript('OnDragStop', retardedPanel.StopMovingOrSizing)
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
retardedPanel.swipe:SetDrawBling(false)
retardedPanel.swipe:SetDrawEdge(false)
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
retardedPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
retardedPanel.text.center:SetAllPoints(retardedPanel.text)
retardedPanel.text.center:SetJustifyH('CENTER')
retardedPanel.text.center:SetJustifyV('CENTER')
retardedPanel.button = CreateFrame('Button', nil, retardedPanel)
retardedPanel.button:SetAllPoints(retardedPanel)
retardedPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local retardedPreviousPanel = CreateFrame('Frame', 'retardedPreviousPanel', UIParent)
retardedPreviousPanel:SetFrameStrata('BACKGROUND')
retardedPreviousPanel:SetSize(64, 64)
retardedPreviousPanel:SetMovable(true)
retardedPreviousPanel:SetUserPlaced(true)
retardedPreviousPanel:RegisterForDrag('LeftButton')
retardedPreviousPanel:SetScript('OnDragStart', retardedPreviousPanel.StartMoving)
retardedPreviousPanel:SetScript('OnDragStop', retardedPreviousPanel.StopMovingOrSizing)
retardedPreviousPanel:Hide()
retardedPreviousPanel.icon = retardedPreviousPanel:CreateTexture(nil, 'BACKGROUND')
retardedPreviousPanel.icon:SetAllPoints(retardedPreviousPanel)
retardedPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
retardedPreviousPanel.border = retardedPreviousPanel:CreateTexture(nil, 'ARTWORK')
retardedPreviousPanel.border:SetAllPoints(retardedPreviousPanel)
retardedPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
local retardedCooldownPanel = CreateFrame('Frame', 'retardedCooldownPanel', UIParent)
retardedCooldownPanel:SetFrameStrata('BACKGROUND')
retardedCooldownPanel:SetSize(64, 64)
retardedCooldownPanel:SetMovable(true)
retardedCooldownPanel:SetUserPlaced(true)
retardedCooldownPanel:RegisterForDrag('LeftButton')
retardedCooldownPanel:SetScript('OnDragStart', retardedCooldownPanel.StartMoving)
retardedCooldownPanel:SetScript('OnDragStop', retardedCooldownPanel.StopMovingOrSizing)
retardedCooldownPanel:Hide()
retardedCooldownPanel.icon = retardedCooldownPanel:CreateTexture(nil, 'BACKGROUND')
retardedCooldownPanel.icon:SetAllPoints(retardedCooldownPanel)
retardedCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
retardedCooldownPanel.border = retardedCooldownPanel:CreateTexture(nil, 'ARTWORK')
retardedCooldownPanel.border:SetAllPoints(retardedCooldownPanel)
retardedCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
retardedCooldownPanel.dimmer = retardedCooldownPanel:CreateTexture(nil, 'BORDER')
retardedCooldownPanel.dimmer:SetAllPoints(retardedCooldownPanel)
retardedCooldownPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
retardedCooldownPanel.dimmer:Hide()
retardedCooldownPanel.swipe = CreateFrame('Cooldown', nil, retardedCooldownPanel, 'CooldownFrameTemplate')
retardedCooldownPanel.swipe:SetAllPoints(retardedCooldownPanel)
retardedCooldownPanel.swipe:SetDrawBling(false)
retardedCooldownPanel.swipe:SetDrawEdge(false)
retardedCooldownPanel.text = retardedCooldownPanel:CreateFontString(nil, 'OVERLAY')
retardedCooldownPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
retardedCooldownPanel.text:SetAllPoints(retardedCooldownPanel)
retardedCooldownPanel.text:SetJustifyH('CENTER')
retardedCooldownPanel.text:SetJustifyV('CENTER')
local retardedInterruptPanel = CreateFrame('Frame', 'retardedInterruptPanel', UIParent)
retardedInterruptPanel:SetFrameStrata('BACKGROUND')
retardedInterruptPanel:SetSize(64, 64)
retardedInterruptPanel:SetMovable(true)
retardedInterruptPanel:SetUserPlaced(true)
retardedInterruptPanel:RegisterForDrag('LeftButton')
retardedInterruptPanel:SetScript('OnDragStart', retardedInterruptPanel.StartMoving)
retardedInterruptPanel:SetScript('OnDragStop', retardedInterruptPanel.StopMovingOrSizing)
retardedInterruptPanel:Hide()
retardedInterruptPanel.icon = retardedInterruptPanel:CreateTexture(nil, 'BACKGROUND')
retardedInterruptPanel.icon:SetAllPoints(retardedInterruptPanel)
retardedInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
retardedInterruptPanel.border = retardedInterruptPanel:CreateTexture(nil, 'ARTWORK')
retardedInterruptPanel.border:SetAllPoints(retardedInterruptPanel)
retardedInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
retardedInterruptPanel.swipe = CreateFrame('Cooldown', nil, retardedInterruptPanel, 'CooldownFrameTemplate')
retardedInterruptPanel.swipe:SetAllPoints(retardedInterruptPanel)
retardedInterruptPanel.swipe:SetDrawBling(false)
retardedInterruptPanel.swipe:SetDrawEdge(false)
local retardedExtraPanel = CreateFrame('Frame', 'retardedExtraPanel', UIParent)
retardedExtraPanel:SetFrameStrata('BACKGROUND')
retardedExtraPanel:SetSize(64, 64)
retardedExtraPanel:SetMovable(true)
retardedExtraPanel:SetUserPlaced(true)
retardedExtraPanel:RegisterForDrag('LeftButton')
retardedExtraPanel:SetScript('OnDragStart', retardedExtraPanel.StartMoving)
retardedExtraPanel:SetScript('OnDragStop', retardedExtraPanel.StopMovingOrSizing)
retardedExtraPanel:Hide()
retardedExtraPanel.icon = retardedExtraPanel:CreateTexture(nil, 'BACKGROUND')
retardedExtraPanel.icon:SetAllPoints(retardedExtraPanel)
retardedExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
retardedExtraPanel.border = retardedExtraPanel:CreateTexture(nil, 'ARTWORK')
retardedExtraPanel.border:SetAllPoints(retardedExtraPanel)
retardedExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.HOLY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.PROTECTION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.RETRIBUTION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
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

function AutoAoe:Add(guid, update)
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

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
	local count = 0
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

function AutoAoe:Purge()
	local update
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

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		mana_cost = 0,
		holy_power_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
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
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if self:ManaCost() > Player.mana.current then
		return false
	end
	if self:HolyPowerCost() > Player.holy_power.current then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains(offGCD)
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(0, expires - Player.ctime - (offGCD and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
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
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
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
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	local remains = duration - (Player.ctime - start)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and count or 0
		end
	end
	return 0
end

function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana.max) or 0
end

function Ability:HolyPowerCost()
	return self.holy_power_cost
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
	return charges + ((max(0, Player.ctime - recharge_start + (self.off_gcd and 0 or Player.execute_remains))) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
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
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return Player.channel.ability == self
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return 0
	end
	return castTime / 1000
end

function Ability:Previous(n)
	local i = n or 1
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
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
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	if self.ignore_cast then
		return
	end
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		retardedPreviousPanel.ability = self
		retardedPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		retardedPreviousPanel.icon:SetTexture(self.icon)
		retardedPreviousPanel:SetShown(retardedPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.auto_aoe and self.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not self.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif event == self.auto_aoe.trigger or (self.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			self:RecordTargetHit(dstGUID)
		end
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and retardedPreviousPanel.ability == self then
		retardedPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, Abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, Abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	return aura
end

function Ability:RefreshAuraAll()
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFocus():GetNodeID()
]]

-- Paladin Abilities
---- Class
------ Baseline
local AvengingWrath = Ability:Add(31884, true, true)
AvengingWrath.buff_duration = 20
AvengingWrath.cooldown_duration = 60
AvengingWrath.triggers_gcd = false
AvengingWrath.off_gcd = true
local Cleanse = Ability:Add(4987, false, true)
Cleanse.mana_cost = 1.3
Cleanse.cooldown_duration = 8
local Consecration = Ability:Add(26573, false, true)
Consecration.cooldown_duration = 9
Consecration.damage = Ability:Add(204242, false, true, 81297)
Consecration.damage.cooldown_duration = 9
Consecration.damage.buff_duration = 12
Consecration.damage.tick_interval = 1
Consecration.damage.hasted_ticks = true
Consecration.damage.ignore_immune = true
Consecration.damage:AutoAoe()
local CrusaderStrike = Ability:Add(35395, false, true)
CrusaderStrike.mana_cost = 1.6
CrusaderStrike.cooldown_duration = 6
local DivineProtection = Ability:Add({498, 403876}, true, true)
DivineProtection.mana_cost = 0.7
DivineProtection.buff_duration = 8
DivineProtection.cooldown_duration = 60
DivineProtection.triggers_gcd = false
DivineProtection.off_gcd = true
local FlashOfLight = Ability:Add(19750, true, true)
FlashOfLight.mana_cost = 10
local Forbearance = Ability:Add(25771, false, false)
Forbearance.buff_duration = 30
Forbearance.aura_target = 'player'
local HandOfReckoning = Ability:Add(62124, false, true)
HandOfReckoning.mana_cost = 0.6
HandOfReckoning.buff_duration = 3
HandOfReckoning.cooldown_duration = 8
HandOfReckoning.triggers_gcd = false
HandOfReckoning.off_gcd = true
local Judgment = Ability:Add(20271, false, true, 197277)
Judgment.mana_cost = 0.6
Judgment.buff_duration = 15
Judgment.cooldown_duration = 12
Judgment.max_range = 30
Judgment.hasted_cooldown = true
Judgment:SetVelocity(35)
------ Talents
local BlessingOfProtection = Ability:Add(1022, true, false)
BlessingOfProtection.mana_cost = 3
BlessingOfProtection.buff_duration = 10
BlessingOfProtection.cooldown_duration = 300
local BlessingOfSacrifice = Ability:Add(6940, true, false)
BlessingOfSacrifice.mana_cost = 1.4
BlessingOfSacrifice.buff_duration = 12
BlessingOfSacrifice.cooldown_duration = 120
local BlindingLight = Ability:Add(115750, false, false, 105421)
BlindingLight.mana_cost = 1.2
BlindingLight.buff_duration = 6
BlindingLight.cooldown_duration = 90
local CrusaderAura = Ability:Add(32223, true, false)
local DevotionAura = Ability:Add(465, true, false)
local DivinePurpose = Ability:Add(408459, true, true, 408458)
DivinePurpose.buff_duration = 12
local DivineResonance = Ability:Add(384027, true, true, 384029)
DivineResonance.buff_duration = 15
DivineResonance.tick_interval = 5
local DivineShield = Ability:Add(642, true, true)
DivineShield.buff_duration = 8
DivineShield.cooldown_duration = 300
local DivineSteed = Ability:Add(190784, true, true)
DivineSteed.cooldown_duration = 45
DivineSteed.requires_charge = true
DivineSteed.triggers_gcd = false
DivineSteed.off_gcd = true
local DivineToll = Ability:Add(375576, true, true)
DivineToll.mana_cost = 3
DivineToll.cooldown_duration = 60
local HammerOfJustice = Ability:Add(853, false, true)
HammerOfJustice.mana_cost = 0.7
HammerOfJustice.buff_duration = 6
HammerOfJustice.cooldown_duration = 60
local HammerOfWrath = Ability:Add(24275, false, true)
HammerOfWrath.cooldown_duration = 7.5
HammerOfWrath.hasted_cooldown = true
HammerOfWrath.max_range = 30
HammerOfWrath:SetVelocity(40)
HammerOfWrath.rank_2 = Ability:Add(326730, false, true)
local BlessingOfFreedom = Ability:Add(1044, true, false)
BlessingOfFreedom.mana_cost = 1.4
BlessingOfFreedom.buff_duration = 8
BlessingOfFreedom.cooldown_duration = 25
local LayOnHands = Ability:Add(633, true, true)
LayOnHands.cooldown_duration = 600
LayOnHands.off_gcd = true
local Rebuke = Ability:Add(96231, false, true)
Rebuke.buff_duration = 4
Rebuke.cooldown_duration = 15
Rebuke.triggers_gcd = false
Rebuke.off_gcd = true
local Repentance = Ability:Add(20066, false, false)
Repentance.mana_cost = 1.2
Repentance.buff_duration = 60
Repentance.cooldown_duration = 15
local RetributionAura = Ability:Add(183435, true, false)
local TurnEvil = Ability:Add(10326, false, true)
TurnEvil.mana_cost = 2.1
TurnEvil.buff_duration = 40
TurnEvil.cooldown_duration = 15
local WordOfGlory = Ability:Add(85673, true, true)
WordOfGlory.mana_cost = 10
WordOfGlory.holy_power_cost = 3
------ Procs

---- Holy
------ Talents

------ Procs

---- Protection
------ Talents

------ Procs

---- Retribution
------ Talents
local BladeOfJustice = Ability:Add(184575, false, true)
BladeOfJustice.cooldown_duration = 10.5
BladeOfJustice.max_range = 12
BladeOfJustice.hasted_cooldown = true
BladeOfJustice.requires_charge = true
local BladeOfVengeance = Ability:Add(403826, false, true, 404358)
local BlessedChampion = Ability:Add(403010, false, true)
local BoundlessJudgment = Ability:Add(405278, false, true)
local ConsecratedBlade = Ability:Add(404834, false, true)
local Crusade = Ability:Add(231895, true, true)
Crusade.buff_duration = 27
Crusade.cooldown_duration = 120
Crusade.triggers_gcd = false
Crusade.off_gcd = true
local CrusadingStrikes = Ability:Add(404542, false, true, 408385)
CrusadingStrikes.triggers_gcd = false
CrusadingStrikes.off_gcd = true
CrusadingStrikes.ignore_cast = true
CrusadingStrikes:AutoAoe()
local CrusaderStrike = Ability:Add(35395, false, true)
CrusaderStrike.cooldown_duration = 6
CrusaderStrike.hasted_cooldown = true
CrusaderStrike.requires_charge = true
local DivineArbiter = Ability:Add(404306, true, true, 406975)
DivineArbiter.buff_duration = 30
local DivineAuxiliary = Ability:Add(406158, false, true)
local DivineHammer = Ability:Add(198034, false, true, 198137)
DivineHammer.buff_duration = 12
DivineHammer.cooldown_duration = 20
DivineHammer.tick_interval = 2
DivineHammer.hasted_ticks = true
DivineHammer:AutoAoe(true)
local DivineStorm = Ability:Add(53385, false, true)
DivineStorm.holy_power_cost = 3
DivineStorm:AutoAoe(true)
local EmpyreanLegacy = Ability:Add(387170, true, true, 387178)
EmpyreanLegacy.buff_duration = 20
local EmpyreanPower = Ability:Add(326732, true, true, 326733)
EmpyreanPower.buff_duration = 15
local ExecutionSentence = Ability:Add(343527, false, true)
ExecutionSentence.buff_duration = 8
ExecutionSentence.cooldown_duration = 30
local ExecutionersWill = Ability:Add(406940, false, true)
local Expurgation = Ability:Add(383344, false, true, 383346)
Expurgation.buff_duration = 6
Expurgation.tick_interval = 3
Expurgation.hasted_ticks = true
Expurgation:AutoAoe(true, 'apply')
local FinalReckoning = Ability:Add(343721, true, true)
FinalReckoning.buff_duration = 12
FinalReckoning.cooldown_duration = 60
FinalReckoning:AutoAoe()
local FinalVerdict = Ability:Add(383328, true, true, 383329)
FinalVerdict.buff_duration = 15
FinalVerdict.holy_power_cost = 3
local HolyBlade = Ability:Add(383342, false, true)
local JusticarsVengeance = Ability:Add(215661, false, true)
JusticarsVengeance.holy_power_cost = 3
local ShieldOfVengeance = Ability:Add(184662, true, true)
ShieldOfVengeance.buff_duration = 15
ShieldOfVengeance.cooldown_duration = 90
local TemplarsVerdict = Ability:Add(85256, false, true)
TemplarsVerdict.holy_power_cost = 3
local TemplarStrikes = Ability:Add(406646, false, true)
local TemplarStrike = Ability:Add(407480, false, true)
TemplarStrike.mana_cost = 0.4
TemplarStrike.cooldown_duration = 6
TemplarStrike.requires_charge = true
TemplarStrike.hasted_cooldown = true
local TemplarSlash = Ability:Add(406647, false, true)
TemplarSlash.buff_duration = 4
TemplarSlash.mana_cost = 0.4
local VanguardsMomentum = Ability:Add(383314, false, true)
local VanguardOfJustice = Ability:Add(406545, false, true)
local WakeOfAshes = Ability:Add(255937, false, true, 255941)
WakeOfAshes.buff_duration = 5
WakeOfAshes.cooldown_duration = 30
WakeOfAshes.ignore_immune = true
WakeOfAshes:AutoAoe()
------ Procs

-- Tier set bonuses
local EchoesOfWrath = Ability:Add(423590, true, true) -- T31 4pc (Retribution)
EchoesOfWrath.buff_duration = 12
local WrathfulSanction = Ability:Add(424590, false, true) -- T31 2pc (Retribution)
-- Racials

-- PvP talents

-- Trinket effects
local MarkOfFyralath = Ability:Add(414532, false, true) -- DoT applied by Fyr'alath the Dreamrender
MarkOfFyralath.buff_duration = 15
MarkOfFyralath.tick_interval = 3
MarkOfFyralath.hasted_ticks = true
MarkOfFyralath.no_pandemic = true
-- Class cooldowns
local PowerInfusion = Ability:Add(10060, true)
PowerInfusion.buff_duration = 20
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
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
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
local FyralathTheDreamrender = InventoryItem:Add(206448)
FyralathTheDreamrender.cooldown_duration = 120
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.trackAuras)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.trackAuras[#self.trackAuras + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local _, id
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
			id == 381301 or -- Feral Hide Drums (Leatherworking)
			id == 390386    -- Fury of the Aspects (Evoker)
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
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdateKnown()
	self.mana.max = UnitPowerMax('player', 0)
	self.holy_power.max = UnitPowerMax('player', 9)

	local node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.talent_node and configId then
			node = C_Traits.GetNodeInfo(configId, ability.talent_node)
			if node then
				ability.rank = node.activeRank
				ability.known = ability.rank > 0
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsUsableSpell(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	if ConsecratedBlade.known or DivineHammer.known then
		Consecration.known = false
	end
	if CrusadingStrikes.known or TemplarStrikes.known then
		CrusaderStrike.known = false
	end
	if FinalVerdict.known or JusticarsVengeance.known then
		TemplarsVerdict.known = false
	end
	if TemplarStrikes.known then
		TemplarStrike.known = true
		TemplarSlash.known = true
	end
	if Consecration.known or ConsecratedBlade.known then
		Consecration.damage.known = true
	end
	if BlessedChampion.known then
		CrusaderStrike:AutoAoe()
		Judgment:AutoAoe()
	else
		CrusaderStrike.auto_aoe = nil
		Judgment.auto_aoe = nil
	end
	if self.spec == SPEC.RETRIBUTION then
		EchoesOfWrath.known = self.set_bonus.t31 >= 4
		WrathfulSanction.known = self.set_bonus.t31 >= 2
	end
	MarkOfFyralath.known = FyralathTheDreamrender:Equipped()

	Abilities:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.chained = false
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.ticks_extra = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		channel.early_chain_if = nil
		channel.early_chainable = false
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if ability and ability == channel.ability then
		channel.chained = true
	else
		channel.ability = ability
	end
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	if channel.chained then
		channel.ticks_extra = channel.tick_count - floor(channel.tick_count)
	else
		channel.ticks_extra = 0
	end
	channel.ticks_remain = channel.tick_count
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, start, ends, duration, spellId, speed, max_speed
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	if self.channel.tick_count > 1 then
		self.channel.ticks = ((self.ctime - self.channel.start) / self.channel.tick_interval) - self.channel.ticks_extra
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end
	self.mana.regen = GetPowerRegenForPowerType(0)
	self.mana.current = UnitPower('player', 0) + (self.mana.regen * self.execute_remains)
	if self.cast.ability then
		self.mana.current = self.mana.current - self.cast.ability:ManaCost()
	end
	self.mana.current = clamp(self.mana.current, 0, self.mana.max)
	self.holy_power.current = UnitPower('player', 9)
	if self.cast.ability and self.cast.ability.holy_power_cost then
		self.holy_power.current = self.holy_power.current - self.cast.ability:HolyPowerCost()
	end
	self.holy_power.current = clamp(self.holy_power.current, 0, self.holy_power.max)
	self.holy_power.deficit = self.holy_power.max - self.holy_power.current
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()

	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.major_cd_remains = (AvengingWrath.known and AvengingWrath:Remains()) or (Crusade.known and Crusade:Remains()) or 0

	self.main = APL[self.spec]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
	if self.channel.early_chain_if then
		self.channel.early_chainable = self.channel.ability == self.main and self.channel.early_chain_if()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	retardedPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * 10
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec) or self.timeToDieMax
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
		if Opt.always_on then
			UI:UpdateCombat()
			retardedPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			retardedPreviousPanel:Hide()
		end
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self.level = UnitLevel('target')
	if self.level == -1 then
		self.level = Player.level + 3
	end
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		self.boss = self.level >= (Player.level + 3)
		self.stunnable = self.level < (Player.level + 2)
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		retardedPanel:Show()
		return true
	end
	UI:Disappear()
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

-- End Target Functions

-- Start Ability Modifications

function Ability:HolyPowerCost()
	if DivinePurpose.known and DivinePurpose:Up() then
		return 0
	end
	return self.holy_power_cost
end

function TemplarsVerdict:HolyPowerCost()
	if DivinePurpose.known and DivinePurpose:Up() then
		return 0
	end
	if VanguardOfJustice.known then
		return self.holy_power_cost + 1
	end
	return self.holy_power_cost
end
FinalVerdict.HolyPowerCost = TemplarsVerdict.HolyPowerCost
JusticarsVengeance.HolyPowerCost = TemplarsVerdict.HolyPowerCost

function DivineStorm:HolyPowerCost()
	if EmpyreanPower.known and EmpyreanPower:Up() then
		return 0
	end
	return TemplarsVerdict.HolyPowerCost(self)
end

function HammerOfJustice:Usable()
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self)
end

function HammerOfWrath:Usable()
	if not (
		Target.health.pct < 20 or
		(HammerOfWrath.rank_2.known and AvengingWrath:Up()) or
		(FinalVerdict.known and FinalVerdict:Up())
	) then
		return false
	end
	return Ability.Usable(self)
end

function DivineShield:Usable()
	if Forbearance:Up() then
		return false
	end
	return Ability.Usable(self)
end
LayOnHands.Usable = DivineShield.Usable
BlessingOfProtection.Usable = DivineShield.Usable

function TemplarSlash:Available()
	return self.activation_time and (Player.time + Player.execute_remains - self.activation_time) < self.buff_duration
end

function TemplarSlash:Usable()
	return self:Available() and Ability.Usable(self)
end

function TemplarSlash:CastSuccess(...)
	self.activation_time = nil
	Ability.CastSuccess(self, ...)
end

function TemplarStrike:Usable()
	return not TemplarSlash:Available() and Ability.Usable(self)
end

function TemplarStrike:CastSuccess(...)
	TemplarSlash.activation_time = Player.time
	Ability.CastSuccess(self, ...)
end

function Judgment:Remains()
	if Player.set_bonus.t30 >= 2 and HammerOfWrath:Traveling() > 0 then
		return self:Duration()
	end
	return Ability.Remains(self)
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

local function WaitFor(ability, wait_time)
	Player.wait_time = wait_time and (Player.ctime + wait_time) or (Player.ctime + ability:Cooldown())
	return ability
end

-- Begin Action Priority Lists

APL[SPEC.NONE].Main = function(self)
end

APL[SPEC.HOLY].Main = function(self)
	if Opt.defensives then
		if Player.health.pct < Opt.heal_threshold then
			if LayOnHands:Usable() and Player.health.pct < 20 then
				UseExtra(LayOnHands)
			elseif DivineShield:Usable() and Player.health.pct < 20 then
				UseExtra(DivineShield)
			elseif BlessingOfProtection:Usable() and Player:UnderAttack() and Player.health.pct < 20 then
				UseExtra(BlessingOfProtection)
			end
		end
		if Player.movement_speed < 75 and BlessingOfFreedom:Usable() and not Player:Dazed() then
			UseExtra(BlessingOfFreedom)
		end
	end
	if Opt.auras and not Player.aura then
		if DevotionAura:Usable() and DevotionAura:Down() then
			UseExtra(DevotionAura)
		elseif RetributionAura:Usable() and RetributionAura:Down() then
			UseExtra(RetributionAura)
		elseif CrusaderAura:Usable() and CrusaderAura:Down() then
			UseExtra(CrusaderAura)
		end
	end
	if Player:TimeInCombat() == 0 then
		if not Player:InArenaOrBattleground() then

		end
	else

	end
end

APL[SPEC.PROTECTION].Main = function(self)
	if Opt.defensives then
		if Player.health.pct < Opt.heal_threshold then
			if LayOnHands:Usable() and Player.health.pct < 20 then
				UseExtra(LayOnHands)
			elseif DivineShield:Usable() and Player.health.pct < 20 then
				UseExtra(DivineShield)
			elseif BlessingOfProtection:Usable() and Player:UnderAttack() and Player.health.pct < 20 then
				UseExtra(BlessingOfProtection)
			end
		end
		if Player.movement_speed < 75 and BlessingOfFreedom:Usable() and not Player:Dazed() then
			UseExtra(BlessingOfFreedom)
		end
	end
	if Opt.auras and not Player.aura then
		if DevotionAura:Usable() and DevotionAura:Down() then
			UseExtra(DevotionAura)
		elseif RetributionAura:Usable() and RetributionAura:Down() then
			UseExtra(RetributionAura)
		elseif CrusaderAura:Usable() and CrusaderAura:Down() then
			UseExtra(CrusaderAura)
		end
	end
	if Player:TimeInCombat() == 0 then
		if not Player:InArenaOrBattleground() then

		end
	else

	end
end

APL[SPEC.RETRIBUTION].Main = function(self)
	if Opt.defensives then
		if Player.health.pct < Opt.heal_threshold then
			if DivineShield:Usable() and Player.health.pct < 20 then
				UseExtra(DivineShield)
			elseif LayOnHands:Usable() and Player.health.pct < 20 then
				UseExtra(LayOnHands)
			elseif WordOfGlory:Usable() and Player.health.pct < (Player.group_size < 5 and 60 or 35) then
				UseExtra(WordOfGlory)
			elseif BlessingOfProtection:Usable() and Player:UnderAttack() and Player.health.pct < 20 then
				UseExtra(BlessingOfProtection)
			end
		end
		if Player.movement_speed < 75 and BlessingOfFreedom:Usable() and not Player:Dazed() then
			UseExtra(BlessingOfFreedom)
		elseif ShieldOfVengeance:Usable() and ShieldOfVengeance:Down() and Player:UnderAttack() then
			UseExtra(ShieldOfVengeance)
		end
	end
	if Opt.auras and not Player.aura then
		if RetributionAura:Usable() and RetributionAura:Down() then
			UseExtra(RetributionAura)
		elseif DevotionAura:Usable() and DevotionAura:Down() then
			UseExtra(DevotionAura)
		elseif CrusaderAura:Usable() and CrusaderAura:Down() then
			UseExtra(CrusaderAura)
		end
	end
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/shield_of_vengeance
actions.precombat+=/variable,name=trinket_1_buffs,value=trinket.1.has_buff.strength|trinket.1.has_buff.mastery|trinket.1.has_buff.versatility|trinket.1.has_buff.haste|trinket.1.has_buff.crit
actions.precombat+=/variable,name=trinket_2_buffs,value=trinket.2.has_buff.strength|trinket.2.has_buff.mastery|trinket.2.has_buff.versatility|trinket.2.has_buff.haste|trinket.2.has_buff.crit
actions.precombat+=/variable,name=trinket_1_manual,value=trinket.1.is.manic_grieftorch
actions.precombat+=/variable,name=trinket_2_manual,value=trinket.2.is.manic_grieftorch
actions.precombat+=/variable,name=trinket_1_sync,op=setif,value=1,value_else=0.5,condition=variable.trinket_1_buffs&(trinket.1.cooldown.duration%%cooldown.crusade.duration=0|cooldown.crusade.duration%%trinket.1.cooldown.duration=0|trinket.1.cooldown.duration%%cooldown.avenging_wrath.duration=0|cooldown.avenging_wrath.duration%%trinket.1.cooldown.duration=0)
actions.precombat+=/variable,name=trinket_2_sync,op=setif,value=1,value_else=0.5,condition=variable.trinket_2_buffs&(trinket.2.cooldown.duration%%cooldown.crusade.duration=0|cooldown.crusade.duration%%trinket.2.cooldown.duration=0|trinket.2.cooldown.duration%%cooldown.avenging_wrath.duration=0|cooldown.avenging_wrath.duration%%trinket.2.cooldown.duration=0)
actions.precombat+=/variable,name=trinket_priority,op=setif,value=2,value_else=1,condition=!variable.trinket_1_buffs&variable.trinket_2_buffs|variable.trinket_2_buffs&((trinket.2.cooldown.duration%trinket.2.proc.any_dps.duration)*(1.5+trinket.2.has_buff.strength)*(variable.trinket_2_sync))>((trinket.1.cooldown.duration%trinket.1.proc.any_dps.duration)*(1.5+trinket.1.has_buff.strength)*(variable.trinket_1_sync))
]]
		if not Player:InArenaOrBattleground() then

		end
	else

	end
--[[
actions=auto_attack
actions+=/rebuke
actions+=/call_action_list,name=cooldowns
actions+=/call_action_list,name=generators
]]
	self.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)) or (AvengingWrath.known and AvengingWrath:Remains() > 8) or (Crusade.known and Crusade:Remains() > 8)
	self.dp_ending = DivinePurpose.known and DivinePurpose:Up() and DivinePurpose:Remains() < (Player.gcd * 2)
	self.finish_condition = Player.holy_power.current >= 5 or self.dp_ending or Target.timeToDie < Player.gcd or (EchoesOfWrath.known and CrusadingStrikes.known and EchoesOfWrath:Up()) or (not WrathfulSanction.known and DivineResonance:Up() and (Judgment:Up() or Player.holy_power.current >= 4))
	if self.use_cds then
		self:cooldowns()
	end
	return self:generators()
end

APL[SPEC.RETRIBUTION].cooldowns = function(self)
--[[
actions.cooldowns=potion,if=buff.avenging_wrath.up|buff.crusade.up&buff.crusade.stack=10|fight_remains<25
actions.cooldowns+=/invoke_external_buff,name=power_infusion,if=buff.avenging_wrath.up|buff.crusade.up
actions.cooldowns+=/lights_judgment,if=spell_targets.lights_judgment>=2|!raid_event.adds.exists|raid_event.adds.in>75|raid_event.adds.up
actions.cooldowns+=/fireblood,if=buff.avenging_wrath.up|buff.crusade.up&buff.crusade.stack=10
actions.cooldowns+=/use_item,name=algethar_puzzle_box,if=(cooldown.avenging_wrath.remains<5&!talent.crusade|cooldown.crusade.remains<5&talent.crusade)&(holy_power>=4&time<5|holy_power>=3&time>5)
actions.cooldowns+=/use_item,slot=trinket1,if=(buff.avenging_wrath.up&cooldown.avenging_wrath.remains>40|buff.crusade.up&buff.crusade.stack=10)&(!trinket.2.has_cooldown|trinket.2.cooldown.remains|variable.trinket_priority=1)|trinket.1.proc.any_dps.duration>=fight_remains
actions.cooldowns+=/use_item,slot=trinket2,if=(buff.avenging_wrath.up&cooldown.avenging_wrath.remains>40|buff.crusade.up&buff.crusade.stack=10)&(!trinket.1.has_cooldown|trinket.1.cooldown.remains|variable.trinket_priority=2)|trinket.2.proc.any_dps.duration>=fight_remains
actions.cooldowns+=/use_item,slot=trinket1,if=!variable.trinket_1_buffs&(trinket.2.cooldown.remains|!variable.trinket_2_buffs|!buff.crusade.up&cooldown.crusade.remains>20|!buff.avenging_wrath.up&cooldown.avenging_wrath.remains>20)
actions.cooldowns+=/use_item,slot=trinket2,if=!variable.trinket_2_buffs&(trinket.1.cooldown.remains|!variable.trinket_1_buffs|!buff.crusade.up&cooldown.crusade.remains>20|!buff.avenging_wrath.up&cooldown.avenging_wrath.remains>20)
actions.cooldowns+=/use_item,name=shadowed_razing_annihilator,if=(trinket.2.cooldown.remains|!variable.trinket_2_buffs)&(trinket.2.cooldown.remains|!variable.trinket_2_buffs)
actions.cooldowns+=/use_item,name=fyralath_the_dreamrender,if=dot.mark_of_fyralath.ticking&!buff.avenging_wrath.up&!buff.crusade.up
actions.cooldowns+=/shield_of_vengeance,if=fight_remains>15&(!talent.execution_sentence|!debuff.execution_sentence.up)
actions.cooldowns+=/execution_sentence,if=(!buff.crusade.up&cooldown.crusade.remains>15|buff.crusade.stack=10|cooldown.avenging_wrath.remains<0.75|cooldown.avenging_wrath.remains>15)&(holy_power>=3|holy_power>=2&talent.divine_auxiliary)&(target.time_to_die>8|target.time_to_die>12&talent.executioners_will)
actions.cooldowns+=/avenging_wrath,if=holy_power>=4&time<5|holy_power>=3&time>5|holy_power>=2&talent.divine_auxiliary&(cooldown.execution_sentence.remains=0|cooldown.final_reckoning.remains=0)
actions.cooldowns+=/crusade,if=holy_power>=5&time<5|holy_power>=3&time>5
actions.cooldowns+=/final_reckoning,if=(holy_power>=4&time<8|holy_power>=3&time>=8|holy_power>=2&talent.divine_auxiliary)&(cooldown.avenging_wrath.remains>10|cooldown.crusade.remains&(!buff.crusade.up|buff.crusade.stack>=10))&(time_to_hpg>0|holy_power=5|holy_power>=2&talent.divine_auxiliary)&(!raid_event.adds.exists|raid_event.adds.up|raid_event.adds.in>40)
]]
	if FyralathTheDreamrender:Usable() and Player.major_cd_remains == 0 and MarkOfFyralath:Up() then
		return UseCooldown(FyralathTheDreamrender)
	end
	if ExecutionSentence:Usable() and Target.timeToDie > (ExecutionersWill.known and 12 or 8) and Player.holy_power.current >= (DivineAuxiliary.known and 2 or 3) and (
		(AvengingWrath.known and (AvengingWrath:Ready(0.75) or not AvengingWrath:Ready(15) or AvengingWrath:Remains() > 8 or (AvengingWrath:Up() and AvengingWrath:Ready(AvengingWrath:Remains())))) or
		(Crusade.known and ((Crusade:Down() and not Crusade:Ready(10)) or Crusade:Stack() >= 10))
	) then
		return UseCooldown(ExecutionSentence)
	end
	if AvengingWrath:Usable() and AvengingWrath:Down() and (
		Player.holy_power.current >= 4 or
		(self.finish_condition and Player.holy_power.current >= 3) or
		(DivineAuxiliary.known and Player.holy_power.current >= 2 and ((ExecutionSentence.known and ExecutionSentence:Ready()) or (FinalReckoning.known and FinalReckoning:Ready())))
	) then
		return UseCooldown(AvengingWrath)
	end
	if Crusade:Usable() and Crusade:Down() and (
		(Player:TimeInCombat() < 5 and Player.holy_power.current >= 5) or
		((self.finish_condition or Player:TimeInCombat() > 5) and Player.holy_power.current >= 3)
	) then
		return UseCooldown(Crusade)
	end
	if FinalReckoning:Usable() and (
		Player.holy_power.current >= 4 or
		(self.finish_condition and Player.holy_power.current >= 3) or
		(DivineAuxiliary.known and Player.holy_power.current >= 2)
	) and (
		((Target.boss or Player.enemies >= 3) and Target.timeToDie < 10) or
		(AvengingWrath.known and (AvengingWrath:Remains() > 8 or (AvengingWrath:Up() and AvengingWrath:Ready(AvengingWrath:Remains())))) or
		(Crusade.known and (Crusade:Stack() >= 10 or (not Crusade:Ready() and Crusade:Down())))
	) then
		return UseCooldown(FinalReckoning)
	end
end

APL[SPEC.RETRIBUTION].finishers = function(self)
--[[
actions.finishers=variable,name=ds_castable,value=(spell_targets.divine_storm>=3|spell_targets.divine_storm>=2&!talent.divine_arbiter|buff.empyrean_power.up)&!buff.empyrean_legacy.up&!(buff.divine_arbiter.up&buff.divine_arbiter.stack>24)
actions.finishers+=/divine_storm,if=variable.ds_castable&(!talent.crusade|cooldown.crusade.remains>gcd*3|buff.crusade.up&buff.crusade.stack<10)
actions.finishers+=/justicars_vengeance,if=!talent.crusade|cooldown.crusade.remains>gcd*3|buff.crusade.up&buff.crusade.stack<10
actions.finishers+=/templars_verdict,if=!talent.crusade|cooldown.crusade.remains>gcd*3|buff.crusade.up&buff.crusade.stack<10
]]
	if (
		not self.use_cds or
		self.dp_ending or
		Target.timeToDie < Player.gcd or
		(not Crusade.known or not Crusade:Ready(Player.gcd * 3) or (Crusade:Up() and Crusade:Stack() < 10))
	) then
		if DivineStorm:Usable() and (
			(Player.enemies >= (DivineArbiter.known and 3 or 2) or (EmpyreanPower.known and EmpyreanPower:Up())) and
			(not EmpyreanLegacy.known or EmpyreanLegacy:Down()) and
			(not DivineArbiter.known or DivineArbiter:Stack() <= 24)
		) then
			return DivineStorm
		end
		if JusticarsVengeance:Usable() then
			return JusticarsVengeance
		end
		if FinalVerdict:Usable() then
			return FinalVerdict
		end
		if TemplarsVerdict:Usable() then
			return TemplarsVerdict
		end
	end
end

APL[SPEC.RETRIBUTION].generators = function(self)
--[[
actions.generators=call_action_list,name=finishers,if=holy_power=5|buff.echoes_of_wrath.up&set_bonus.tier31_4pc&talent.crusading_strikes|(debuff.judgment.up|holy_power=4)&buff.divine_resonance.up&!set_bonus.tier31_2pc
actions.generators+=/wake_of_ashes,if=holy_power<=2&(cooldown.avenging_wrath.remains|cooldown.crusade.remains)&(!talent.execution_sentence|cooldown.execution_sentence.remains>4|target.time_to_die<8)&(!talent.final_reckoning|cooldown.final_reckoning.remains>4|target.time_to_die<8)&(!raid_event.adds.exists|raid_event.adds.in>20|raid_event.adds.up)
actions.generators+=/blade_of_justice,if=!dot.expurgation.ticking&set_bonus.tier31_2pc
actions.generators+=/divine_toll,if=holy_power<=2&!debuff.judgment.up&(!raid_event.adds.exists|raid_event.adds.in>30|raid_event.adds.up)&(cooldown.avenging_wrath.remains>15|cooldown.crusade.remains>15|fight_remains<8)
actions.generators+=/judgment,if=dot.expurgation.ticking&!buff.echoes_of_wrath.up&set_bonus.tier31_2pc
actions.generators+=/call_action_list,name=finishers,if=holy_power>=3&buff.crusade.up&buff.crusade.stack<10
actions.generators+=/templar_slash,if=buff.templar_strikes.remains<gcd&spell_targets.divine_storm>=2
actions.generators+=/blade_of_justice,if=(holy_power<=3|!talent.holy_blade)&(spell_targets.divine_storm>=2&!talent.crusading_strikes|spell_targets.divine_storm>=4)
actions.generators+=/hammer_of_wrath,if=(spell_targets.divine_storm<2|!talent.blessed_champion|set_bonus.tier30_4pc)&(holy_power<=3|target.health.pct>20|!talent.vanguards_momentum)
actions.generators+=/templar_slash,if=buff.templar_strikes.remains<gcd
actions.generators+=/judgment,if=!buff.avenging_wrath.up&(holy_power<=3|!talent.boundless_judgment)&talent.crusading_strikes
actions.generators+=/blade_of_justice,if=holy_power<=3|!talent.holy_blade
actions.generators+=/judgment,if=!debuff.judgment.up&(holy_power<=3|!talent.boundless_judgment)
actions.generators+=/call_action_list,name=finishers,if=(target.health.pct<=20|buff.avenging_wrath.up|buff.crusade.up|buff.empyrean_power.up)
actions.generators+=/consecration,if=!consecration.up&spell_targets.divine_storm>=2
actions.generators+=/divine_hammer,if=spell_targets.divine_storm>=2
actions.generators+=/crusader_strike,if=cooldown.crusader_strike.charges_fractional>=1.75&(holy_power<=2|holy_power<=3&cooldown.blade_of_justice.remains>gcd*2|holy_power=4&cooldown.blade_of_justice.remains>gcd*2&cooldown.judgment.remains>gcd*2)
actions.generators+=/call_action_list,name=finishers
actions.generators+=/templar_slash
actions.generators+=/templar_strike
actions.generators+=/judgment,if=holy_power<=3|!talent.boundless_judgment
actions.generators+=/hammer_of_wrath,if=holy_power<=3|target.health.pct>20|!talent.vanguards_momentum
actions.generators+=/crusader_strike
actions.generators+=/arcane_torrent
actions.generators+=/consecration
actions.generators+=/divine_hammer
]]
	if self.finish_condition then
		local apl = self:finishers()
		if apl then return apl end
	end
	if WakeOfAshes:Usable() and Player.holy_power.current <= 2 and (not ExecutionSentence.known or not ExecutionSentence:Ready(4) or Target.timeToDie < 8) and (not FinalReckoning.known or not FinalReckoning:Ready(4) or not self.use_cds) and (
		not self.use_cds or
		Player.major_cd_remains > 0 or
		(Target.boss and Target.timeToDie < 10) or
		(AvengingWrath.known and not AvengingWrath:Ready(15)) or
		(Crusade.known and not Crusade:Ready(5))
	) then
		UseCooldown(WakeOfAshes)
	end
	if WrathfulSanction.known and BladeOfJustice:Usable() and Expurgation:Down() then
		return BladeOfJustice
	end
	if self.use_cds and DivineToll:Usable() and Player.holy_power.current <= 2 and Judgment:Down() and ((AvengingWrath.known and not AvengingWrath:Ready(15)) or (Crusade.known and not Crusade:Ready(15)) or Target.timeToDie < 8) then
		UseCooldown(DivineToll)
	end
	if WrathfulSanction.known and Judgment:Usable() and Expurgation:Up() and EchoesOfWrath:Down() then
		return Judgment
	end
	if Crusade.known and Player.holy_power.current >= 3 and Crusade:Up() and Crusade:Stack() < 10 then
		local apl = self:finishers()
		if apl then return apl end
	end
	if TemplarSlash:Usable() and Player.enemies >= 2 and TemplarStrikes:Remains() < Player.gcd then
		return TemplarSlash
	end
	if BladeOfJustice:Usable() and (Player.holy_power.current <= 3 or not HolyBlade.known) and (Player.enemies >= (CrusadingStrikes.known and 4 or 2)) then
		return BladeOfJustice
	end
	if HammerOfWrath:Usable() and (Player.enemies < 2 or not BlessedChampion.known or Player.set_bonus.t30 >= 4) and (Player.holy_power.current <= 3 or Target.health.pct > 20 or not VanguardsMomentum.known) then
		return HammerOfWrath
	end
	if TemplarSlash:Usable() and TemplarStrikes:Remains() < Player.gcd then
		return TemplarSlash
	end
	if CrusadingStrikes.known and Judgment:Usable() and AvengingWrath:Down() and (Player.holy_power.current <= 3 or not BoundlessJudgment.known) then
		return Judgment
	end
	if BladeOfJustice:Usable() and (Player.holy_power.current <= 3 or not HolyBlade.known) then
		return BladeOfJustice
	end
	if Judgment:Usable() and Judgment:Down() and (Player.holy_power.current <= 3 or not BoundlessJudgment.known) then
		return Judgment
	end
	if Target.health.pct <= 20 or Player.major_cd_remains > 0 or EmpyreanPower:Up() then
		local apl = self:finishers()
		if apl then return apl end
	end
	if Player.enemies >= 2 then
		if Consecration:Usable() and Consecration:Down() then
			return Consecration
		end
		if DivineHammer:Usable() then
			return DivineHammer
		end
	end
	if CrusaderStrike:Usable() and CrusaderStrike:ChargesFractional() >= 1.75 and (Player.holy_power.current <= 2 or (Player.holy_power.current <= 3 and not BladeOfJustice:Ready(Player.gcd * 2)) or (Player.holy_power.current <= 4 and not BladeOfJustice:Ready(Player.gcd * 2) and not Judgment:Ready(Player.gcd * 2))) then
		return CrusaderStrike
	end
	local apl = self:finishers()
	if apl then return apl end
	if TemplarSlash:Usable() then
		return TemplarSlash
	end
	if Judgment:Usable() and (Player.holy_power.current <= 3 or not BoundlessJudgment.known) then
		return Judgment
	end
	if TemplarStrike:Usable() then
		return TemplarStrike
	end
	if HammerOfWrath:Usable() and (Player.holy_power.current <= 3 or Target.health.pct > 20 or not VanguardsMomentum.known) then
		return HammerOfWrath
	end
	if CrusaderStrike:Usable() then
		return CrusaderStrike
	end
	if Consecration:Usable() then
		return Consecration
	end
	if DivineHammer:Usable() then
		return DivineHammer
	end
end

APL.Interrupt = function(self)
	if Rebuke:Usable() then
		return Rebuke
	end
	if Target.stunnable then
		if HammerOfJustice:Usable() then
			return HammerOfJustice
		end
		if Repentance:Usable() then
			return Repentance
		end
		if BlindingLight:Usable() then
			return BlindingLight
		end
	end
end

-- End Action Priority Lists

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if LibStub and LibStub.GetLibrary and not Opt.glow.blizzard then
		local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
		if lib then
			lib.ShowOverlayGlow = function(self)
				return
			end
		end
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
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
	local glow, icon
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
				glow:Show()
				if Opt.glow.animation then
					glow.ProcStartAnim:Play()
				else
					glow.ProcLoop:Play()
				end
			end
		elseif glow:IsVisible() then
			if glow.ProcStartAnim:IsPlaying() then
				glow.ProcStartAnim:Stop()
			end
			if glow.ProcLoop:IsPlaying() then
				glow.ProcLoop:Stop()
			end
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	retardedPanel:EnableMouse(draggable or Opt.aoe)
	retardedPanel.button:SetShown(Opt.aoe)
	retardedPreviousPanel:EnableMouse(draggable)
	retardedCooldownPanel:EnableMouse(draggable)
	retardedInterruptPanel:EnableMouse(draggable)
	retardedExtraPanel:EnableMouse(draggable)
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
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -32 },
		},
		[SPEC.PROTECTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -32 },
		},
		[SPEC.RETRIBUTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -32 },
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.HOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.PROTECTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.RETRIBUTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
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
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateManaBar()
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
	Timer.display = 0
	local border, dim, dim_cd, border, text_center, text_tr, text_cd
	local channel = Player.channel

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Player.main_freecast then
			border = 'freecast'
		end
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd = format('%.1f', react)
			end
		end
	end
	if Player.wait_time then
		local deficit = Player.wait_time - GetTime()
		if deficit > 0 then
			text_center = format('WAIT\n%.1fs', deficit)
			dim = Opt.dimmer
		end
	end
	if channel.ability and not channel.ability.ignore_channel and channel.tick_count > 0 then
		dim = Opt.dimmer
		if channel.tick_count > 1 then
			local ctime = GetTime()
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = '|cFF00FF00CHAIN'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if Player.major_cd_remains > 0 then
		text_tr = format('%.1fs', Player.major_cd_remains)
	end
	if border ~= retardedPanel.border.overlay then
		retardedPanel.border.overlay = border
		retardedPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	retardedPanel.dimmer:SetShown(dim)
	retardedPanel.text.center:SetText(text_center)
	retardedPanel.text.tr:SetText(text_tr)
	--retardedPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	retardedCooldownPanel.text:SetText(text_cd)
	retardedCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		retardedPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.mana_cost > 0 and Player.main:ManaCost() == 0) or (Player.main.holy_power_cost > 0 and Player.main:HolyPowerCost() == 0) or (Player.main.Free and Player.main:Free())
	end
	if Player.cd then
		retardedCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local start, duration = GetSpellCooldown(Player.cd.spellId)
			retardedCooldownPanel.swipe:SetCooldown(start, duration)
		end
	end
	if Player.extra then
		retardedExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			retardedInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			retardedInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		retardedInterruptPanel.icon:SetShown(Player.interrupt)
		retardedInterruptPanel.border:SetShown(Player.interrupt)
		retardedInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and retardedPreviousPanel.ability then
		if (Player.time - retardedPreviousPanel.ability.last_used) > 10 then
			retardedPreviousPanel.ability = nil
			retardedPreviousPanel:Hide()
		end
	end

	retardedPanel.icon:SetShown(Player.main)
	retardedPanel.border:SetShown(Player.main)
	retardedCooldownPanel:SetShown(Player.cd)
	retardedExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Retarded
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Retarded1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ABSORBED' or
	   e == 'SPELL_ENERGIZE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	trackAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if dstGUID == Player.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		return -- ignore buffs beyond here
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth('player')
		Player.health.max = UnitHealthMax('player')
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function Events:UNIT_POWER_UPDATE(unitId, powerType)
	if unitId == 'player' and powerType == 'HOLY_POWER' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function Events:UNIT_SPELLCAST_CHANNEL_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateChannelInfo()
	end
end
Events.UNIT_SPELLCAST_CHANNEL_START = Events.UNIT_SPELLCAST_CHANNEL_UPDATE
Events.UNIT_SPELLCAST_CHANNEL_STOP = Events.UNIT_SPELLCAST_CHANNEL_UPDATE

function Events:UPDATE_SHAPESHIFT_FORM()
	Player:UpdateTime()
	if CrusaderAura:Up() then
		Player.aura = CrusaderAura
	elseif DevotionAura:Up() then
		Player.aura = DevotionAura
	elseif RetributionAura:Up() then
		Player.aura = RetributionAura
	else
		Player.aura = nil
	end
end

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		retardedPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		AutoAoe:Clear()
	end
	if APL[Player.spec].precombat_variables then
		APL[Player.spec]:precombat_variables()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
	local _, equipType, hasCooldown
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

	Player.set_bonus.t29 = (Player:Equipped(200414) and 1 or 0) + (Player:Equipped(200416) and 1 or 0) + (Player:Equipped(200417) and 1 or 0) + (Player:Equipped(200418) and 1 or 0) + (Player:Equipped(200419) and 1 or 0)
	Player.set_bonus.t30 = (Player:Equipped(202450) and 1 or 0) + (Player:Equipped(202451) and 1 or 0) + (Player:Equipped(202452) and 1 or 0) + (Player:Equipped(202453) and 1 or 0) + (Player:Equipped(202455) and 1 or 0)
	Player.set_bonus.t31 = (Player:Equipped(207189) and 1 or 0) + (Player:Equipped(207190) and 1 or 0) + (Player:Equipped(207191) and 1 or 0) + (Player:Equipped(207192) and 1 or 0) + (Player:Equipped(207194) and 1 or 0)

	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	retardedPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:UPDATE_SHAPESHIFT_FORM()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
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

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
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
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

retardedPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
	retardedPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
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
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				retardedPanel:ClearAllPoints()
			end
			UI:UpdateDraggable()
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
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
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
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
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
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'h') then
				Opt.hide.holy = not Opt.hide.holy
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Holy specialization', not Opt.hide.holy)
			end
			if startsWith(msg[2], 'p') then
				Opt.hide.protection = not Opt.hide.protection
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Protection specialization', not Opt.hide.protection)
			end
			if startsWith(msg[2], 'r') then
				Opt.hide.retribution = not Opt.hide.retribution
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
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
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 10
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
	if startsWith(msg[1], 'he') then
		if msg[2] then
			Opt.heal_threshold = clamp(tonumber(msg[2]) or 60, 0, 100)
		end
		return Status('Health percentage threshold to recommend self healing spells', Opt.heal_threshold .. '%')
	end
	if startsWith(msg[1], 'de') then
		if msg[2] then
			Opt.defensives = msg[2] == 'on'
		end
		return Status('Show defensives/emergency heals in extra UI', Opt.defensives)
	end
	if startsWith(msg[1], 'au') then
		if msg[2] then
			Opt.auras = msg[2] == 'on'
		end
		return Status('Show aura reminders in extra UI', Opt.auras)
	end
	if msg[1] == 'reset' then
		retardedPanel:ClearAllPoints()
		retardedPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000holy|r/|cFFFFD000protection|r/|cFFFFD000retribution|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'heal |cFFFFD000[percent]|r - health percentage threshold to recommend self healing spells (default is 60%, 0 to disable)',
		'defensives |cFF00C000on|r/|cFFC00000off|r - show defensives/emergency heals in extra UI',
		'auras |cFF00C000on|r/|cFFC00000off|r - show aura reminders in extra UI',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Retarded1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
