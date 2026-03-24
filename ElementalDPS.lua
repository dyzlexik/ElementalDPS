ElementalDPS = {}

ElementalDPS.defaults = {
	enabled = true,
	debug = false,
	autoTarget = true,
	maintainShield = true,
	shieldSpell = "Earth Shield",
	useChainLightningSecondClearcasting = true,
	useFlameShock = true,
	useMoltenBlast = true,
	flameShockDuration = 15,
	flameShockRefreshBuffer = 0.4,
	proactiveRefreshLead = 1.8,
	moltenBlastEarliestAfter = 9.0,
	moltenBlastCastTime = 2.0,
	moltenBlastTravelTime = 1.5,
	moltenBlastSafetyBuffer = 0.6,
	lightningBoltDownrankEnabled = false,
	lightningBoltDownrankRank = 4,
	lightningBoltDownrankManaPercent = 25,
	minimapButtonAngle = 225,
	showMinimapButton = true,
}

ElementalDPS.spells = {
	earthShield = "Earth Shield",
	lightningShield = "Lightning Shield",
	waterShield = "Water Shield",
	chainLightning = "Chain Lightning",
	lightningBolt = "Lightning Bolt",
	flameShock = "Flame Shock",
	moltenBlast = "Molten Blast",
}

ElementalDPS.buffNames = {
	clearcasting = "Clearcasting",
	elementalFocus = "Elemental Focus",
	earthShield = "Earth Shield",
	lightningShield = "Lightning Shield",
	waterShield = "Water Shield",
	flameShock = "Flame Shock",
}

ElementalDPS.spellBook = {}
ElementalDPS.spellRanks = {}
ElementalDPS.buffTextures = {}
ElementalDPS.targetStates = {}
ElementalDPS.currentCast = nil
ElementalDPS.clearcastingCharges = 0
ElementalDPS.clearcastingAuraActive = false
ElementalDPS.superwow = false
ElementalDPS.configFrame = nil
ElementalDPS.configWidgets = {}
ElementalDPS.minimapButton = nil

local function EDPS_Print(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ElementalDPS|r: " .. msg)
	end
end

local function EDPS_CopyDefaults(src)
	local dst = {}
	for key, value in pairs(src) do
		if type(value) == "table" then
			local child = {}
			for childKey, childValue in pairs(value) do
				child[childKey] = childValue
			end
			dst[key] = child
		else
			dst[key] = value
		end
	end
	return dst
end

local function EDPS_MergeDefaults(dst, src)
	for key, value in pairs(src) do
		if dst[key] == nil then
			if type(value) == "table" then
				dst[key] = EDPS_CopyDefaults(value)
			else
				dst[key] = value
			end
		end
	end
end

local function EDPS_ParseRankNumber(rankText)
	if not rankText then
		return 0
	end
	local rankNumber = string.match(rankText, "(%d+)")
	return rankNumber and tonumber(rankNumber) or 0
end

function ElementalDPS:Debug(msg)
	if self.db and self.db.debug then
		EDPS_Print(msg)
	end
end

function ElementalDPS:Initialize()
	if self.initialized then
		return
	end

	if not EDPS_DB then
		EDPS_DB = EDPS_CopyDefaults(self.defaults)
	else
		EDPS_MergeDefaults(EDPS_DB, self.defaults)
	end

	self.db = EDPS_DB
	self.superwow = (SUPERWOW_VERSION and true) or false
	self.initialized = true
	self:RefreshSpells()
	self:EnsureMinimapButton()
	EDPS_Print("initialized")
end

function ElementalDPS:RefreshSpells()
	self.spellBook = {}
	self.spellRanks = {}

	for tab = 1, 8 do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		if not offset then
			break
		end

		for i = offset + 1, offset + numSpells do
			local spellName, rankText = GetSpellName(i, BOOKTYPE_SPELL)
			if spellName then
				local entry = {
					index = i,
					rankText = rankText,
					rankNumber = EDPS_ParseRankNumber(rankText),
					texture = GetSpellTexture(i, BOOKTYPE_SPELL),
					castName = (rankText and rankText ~= "" and (spellName .. "(" .. rankText .. ")")) or spellName,
				}

				if not self.spellBook[spellName] or entry.rankNumber >= (self.spellBook[spellName].rankNumber or 0) then
					self.spellBook[spellName] = entry
				end

				if not self.spellRanks[spellName] then
					self.spellRanks[spellName] = {}
				end
				self.spellRanks[spellName][entry.rankNumber] = entry
			end
		end
	end

	self.buffTextures.clearcasting = self:GetSpellTexture(self.buffNames.clearcasting) or self:GetSpellTexture(self.buffNames.elementalFocus)
	self.buffTextures.earthShield = self:GetSpellTexture(self.buffNames.earthShield)
	self.buffTextures.lightningShield = self:GetSpellTexture(self.buffNames.lightningShield)
	self.buffTextures.waterShield = self:GetSpellTexture(self.buffNames.waterShield)
	self.buffTextures.flameShock = self:GetSpellTexture(self.buffNames.flameShock)
end

function ElementalDPS:GetSpellEntry(spellName)
	if not spellName then
		return nil
	end
	return self.spellBook[spellName]
end

function ElementalDPS:GetSpellEntryByRank(spellName, rankNumber)
	if not spellName or not rankNumber or not self.spellRanks[spellName] then
		return nil
	end
	return self.spellRanks[spellName][rankNumber]
end

function ElementalDPS:GetSpellTexture(spellName)
	local entry = self:GetSpellEntry(spellName)
	return entry and entry.texture or nil
end

function ElementalDPS:GetSpellCooldownRemaining(spellName)
	local entry = self:GetSpellEntry(spellName)
	if not entry then
		return nil
	end
	local start, duration = GetSpellCooldown(entry.index, BOOKTYPE_SPELL)
	if not start or not duration or start == 0 or duration == 0 then
		return 0
	end
	return math.max(0, (start + duration) - GetTime())
end

function ElementalDPS:GetManaPercent()
	local mana = UnitMana and UnitMana("player") or 0
	local manaMax = UnitManaMax and UnitManaMax("player") or 0
	if manaMax <= 0 then
		return 100
	end
	return (mana / manaMax) * 100
end

function ElementalDPS:IsSpellKnown(spellName)
	return self:GetSpellEntry(spellName) ~= nil
end

function ElementalDPS:GetTargetKey()
	local unitHandle = UnitExists("target")
	if not unitHandle then
		return nil
	end
	if type(unitHandle) == "string" and unitHandle ~= "" then
		return unitHandle
	end
	local name = UnitName("target") or "unknown"
	local level = UnitLevel("target") or -1
	local hp = UnitHealthMax("target") or -1
	return name .. ":" .. level .. ":" .. hp
end

function ElementalDPS:GetTargetState()
	local key = self:GetTargetKey()
	if not key then
		return nil
	end
	if not self.targetStates[key] then
		self.targetStates[key] = {
			flameShockExpiresAt = 0,
			flameShockSeenAt = 0,
			flameShockAppliedAt = 0,
			pendingFlameShock = 0,
			pendingMoltenBlast = 0,
		}
	end
	return self.targetStates[key]
end

function ElementalDPS:GetFlameShockRemaining()
	local state = self:GetTargetState()
	if not state or not state.flameShockExpiresAt or state.flameShockExpiresAt <= 0 then
		return 0
	end
	local remaining = state.flameShockExpiresAt - GetTime()
	if remaining <= 0 then
		state.flameShockExpiresAt = 0
		return 0
	end
	return remaining
end

function ElementalDPS:HasVisibleFlameShock()
	local texture = self.buffTextures.flameShock
	if not texture then
		return false
	end
	for i = 1, 16 do
		local debuffTexture = UnitDebuff("target", i)
		if not debuffTexture then
			break
		end
		if debuffTexture == texture then
			local state = self:GetTargetState()
			if state then
				state.flameShockSeenAt = GetTime()
				if (not state.flameShockExpiresAt or state.flameShockExpiresAt <= GetTime()) and not self:IsFlameShockPending() and not self:IsMoltenBlastPending() then
					state.flameShockExpiresAt = GetTime() + (self.db.flameShockDuration or 15)
					state.flameShockAppliedAt = GetTime()
					self:Debug("reseeded Flame Shock timer from visible debuff")
				end
			end
			return true
		end
	end
	return false
end

function ElementalDPS:HasValidEnemyTarget()
	if not UnitExists("target") then
		return false
	end
	if UnitIsDead("target") then
		return false
	end
	if UnitIsFriend and UnitIsFriend("player", "target") then
		return false
	end
	if UnitCanAttack and not UnitCanAttack("player", "target") and not UnitCanAttack("target", "player") then
		return false
	end
	return true
end

function ElementalDPS:EnsureEnemyTarget()
	if self:HasValidEnemyTarget() then
		return true
	end
	if self.db.autoTarget and TargetNearestEnemy then
		TargetNearestEnemy()
	end
	return self:HasValidEnemyTarget()
end

function ElementalDPS:GetPlayerBuffState()
	local clearcasting = false
	local stacks = self.clearcastingCharges or 0
	local foundClearcasting = false
	local observedApplications = nil

	if GetPlayerBuffID and SpellInfo then
		for i = 0, 40 do
			local buffID = GetPlayerBuffID(i)
			if not buffID then
				break
			end
			local name = SpellInfo(buffID)
			local lower = name and string.lower(name)
			if lower and (string.find(lower, "clearcasting", 1, true) or string.find(lower, "elemental focus", 1, true)) then
				foundClearcasting = true
				break
			end
		end
	end

	if self.buffTextures.clearcasting then
		for i = 0, 31 do
			local buffIndex = GetPlayerBuff(i, "HELPFUL|PASSIVE")
			if buffIndex and buffIndex >= 0 then
				if GetPlayerBuffTexture(buffIndex) == self.buffTextures.clearcasting then
					foundClearcasting = true
					if GetPlayerBuffApplications then
						local applications = GetPlayerBuffApplications(buffIndex)
						if applications and applications > 0 then
							observedApplications = applications
						end
					end
					break
				end
			else
				break
			end
		end
	end

	if foundClearcasting then
		clearcasting = true

		if not self.clearcastingAuraActive then
			if observedApplications and observedApplications > 0 then
				stacks = observedApplications
			else
				stacks = 2
			end
		elseif observedApplications and observedApplications > 0 and observedApplications < stacks then
			stacks = observedApplications
		elseif stacks <= 0 then
			stacks = observedApplications or 2
		end
	else
		stacks = 0
	end

	self.clearcastingCharges = stacks
	self.clearcastingAuraActive = foundClearcasting
	return clearcasting, stacks
end

function ElementalDPS:IsDamageSpell(spellName)
	return spellName == self.spells.lightningBolt or
		spellName == self.spells.chainLightning or
		spellName == self.spells.flameShock or
		spellName == self.spells.moltenBlast
end

function ElementalDPS:ConsumeClearcastingCharge(spellName)
	if not self:IsDamageSpell(spellName) then
		return
	end
	if self.clearcastingCharges and self.clearcastingCharges > 0 then
		self.clearcastingCharges = self.clearcastingCharges - 1
		if self.clearcastingCharges < 0 then
			self.clearcastingCharges = 0
		end
	end
end

function ElementalDPS:GetShieldState(shieldName)
	local expectedTexture = nil
	local expectedName = nil

	if shieldName == self.spells.earthShield then
		expectedTexture = self.buffTextures.earthShield
		expectedName = self.buffNames.earthShield
	elseif shieldName == self.spells.lightningShield then
		expectedTexture = self.buffTextures.lightningShield
		expectedName = self.buffNames.lightningShield
	elseif shieldName == self.spells.waterShield then
		expectedTexture = self.buffTextures.waterShield
		expectedName = self.buffNames.waterShield
	end

	local found = false
	local stacks = 0

	if GetPlayerBuffID and SpellInfo and expectedName then
		for i = 0, 40 do
			local buffID = GetPlayerBuffID(i)
			if not buffID then
				break
			end
			if SpellInfo(buffID) == expectedName then
				found = true
				stacks = 1
				break
			end
		end
	end

	if expectedTexture then
		for i = 0, 31 do
			local buffIndex = GetPlayerBuff(i, "HELPFUL|PASSIVE")
			if buffIndex and buffIndex >= 0 then
				if GetPlayerBuffTexture(buffIndex) == expectedTexture then
					found = true
					stacks = GetPlayerBuffApplications and (GetPlayerBuffApplications(buffIndex) or stacks) or stacks
					if stacks == 0 then
						stacks = 1
					end
					break
				end
			else
				break
			end
		end
	end

	return found, stacks
end

function ElementalDPS:GetShieldAction()
	local shieldName = self.db.shieldSpell or self.spells.earthShield
	local hasShield = self:GetShieldState(shieldName)

	if not self.db.maintainShield or not self:IsSpellKnown(shieldName) then
		return nil
	end
	if not hasShield then
		return shieldName, "Refresh " .. shieldName
	end
	return nil
end

function ElementalDPS:GetCurrentCastRemaining()
	if not self.currentCast then
		return 0
	end
	local remaining = (self.currentCast.startedAt + self.currentCast.duration) - GetTime()
	if remaining <= 0 then
		self.currentCast = nil
		return 0
	end
	return remaining
end

function ElementalDPS:IsCastingSpell(spellName)
	if not self.currentCast or not spellName then
		return false
	end
	if self:GetCurrentCastRemaining() <= 0 then
		return false
	end
	return self.currentCast.spellName == spellName
end

function ElementalDPS:IsMoltenBlastPending()
	local state = self:GetTargetState()
	local pendingAt = state and state.pendingMoltenBlast or 0
	local pendingWindow = (self.db.moltenBlastCastTime or 2.0) + (self.db.moltenBlastTravelTime or 1.5) + 1.0

	if not pendingAt or pendingAt <= 0 then
		return false
	end

	if (GetTime() - pendingAt) > pendingWindow then
		state.pendingMoltenBlast = 0
		return false
	end

	return true
end

function ElementalDPS:IsFlameShockPending()
	local state = self:GetTargetState()
	local pendingAt = state and state.pendingFlameShock or 0
	local pendingWindow = 2.5

	if not pendingAt or pendingAt <= 0 then
		return false
	end

	if (GetTime() - pendingAt) > pendingWindow then
		state.pendingFlameShock = 0
		return false
	end

	return true
end

function ElementalDPS:GetMoltenBlastWindow()
	return self:GetCurrentCastRemaining() + (self.db.moltenBlastCastTime or 2.0) + (self.db.moltenBlastTravelTime or 1.5) + (self.db.moltenBlastSafetyBuffer or 0.2)
end

function ElementalDPS:GetElapsedSinceFlameShock()
	local state = self:GetTargetState()
	if not state or not state.flameShockAppliedAt or state.flameShockAppliedAt <= 0 then
		return nil
	end
	return GetTime() - state.flameShockAppliedAt
end

function ElementalDPS:ShouldHoldForMoltenBlast(flameShockRemaining, hasVisibleFlameShock)
	local elapsedSinceFlameShock = self:GetElapsedSinceFlameShock()
	local remainingToMoltenBlast = nil
	local proactiveLead = self.db.proactiveRefreshLead or 1.8

	if self:GetCurrentCastRemaining() > 0 then
		return false
	end
	if not hasVisibleFlameShock or flameShockRemaining <= 0 then
		return false
	end
	if not elapsedSinceFlameShock then
		return false
	end

	remainingToMoltenBlast = (self.db.moltenBlastEarliestAfter or 9.0) - elapsedSinceFlameShock
	return remainingToMoltenBlast > 0 and remainingToMoltenBlast <= proactiveLead
end

function ElementalDPS:CanCastMoltenBlast(flameShockRemaining, hasVisibleFlameShock)
	local moltenBlastCd = self:GetSpellCooldownRemaining(self.spells.moltenBlast) or 999
	local state = self:GetTargetState()
	local elapsedSinceFlameShock = 0
	local currentCastRemaining = self:GetCurrentCastRemaining()

	if moltenBlastCd > 0 then
		return false
	end

	if state and state.flameShockAppliedAt and state.flameShockAppliedAt > 0 then
		elapsedSinceFlameShock = GetTime() - state.flameShockAppliedAt
	else
		return false
	end

	if not hasVisibleFlameShock or flameShockRemaining <= 0 then
		return false
	end

	if currentCastRemaining > 0 then
		return (elapsedSinceFlameShock + currentCastRemaining) >= (self.db.moltenBlastEarliestAfter or 9.0)
	end

	return elapsedSinceFlameShock >= (self.db.moltenBlastEarliestAfter or 9.0)
end

function ElementalDPS:GetLightningBoltCastName()
	local highestEntry = self:GetSpellEntry(self.spells.lightningBolt)
	if not highestEntry then
		return nil, nil
	end

	if self.db.lightningBoltDownrankEnabled and self:GetManaPercent() <= (self.db.lightningBoltDownrankManaPercent or 0) then
		local downrankEntry = self:GetSpellEntryByRank(self.spells.lightningBolt, self.db.lightningBoltDownrankRank)
		if downrankEntry then
			return downrankEntry.castName, "Lightning Bolt (Rank " .. tostring(downrankEntry.rankNumber or self.db.lightningBoltDownrankRank) .. ")"
		end
	end

	return highestEntry.castName, "Lightning Bolt"
end

function ElementalDPS:GetNextAction()
	local shieldSpell, shieldLabel = self:GetShieldAction()
	local flameShockRemaining = self:GetFlameShockRemaining()
	local hasVisibleFlameShock = self:HasVisibleFlameShock()
	local hasClearcasting, clearcastingStacks = self:GetPlayerBuffState()
	local chainLightningCd = self:GetSpellCooldownRemaining(self.spells.chainLightning) or 999
	local flameShockRefreshPoint = math.max(self:GetCurrentCastRemaining() + (self.db.flameShockRefreshBuffer or 0), self.db.proactiveRefreshLead or 1.8)

	if not hasVisibleFlameShock and flameShockRemaining > 0 then
		self:ClearCurrentTargetFlameShock()
		flameShockRemaining = 0
	end

	if self.db.useFlameShock and flameShockRemaining <= flameShockRefreshPoint and not self:IsFlameShockPending() then
		return self.spells.flameShock, "Apply Flame Shock"
	end

	if self.db.useMoltenBlast and not self:IsCastingSpell(self.spells.moltenBlast) and not self:IsMoltenBlastPending() and self:CanCastMoltenBlast(flameShockRemaining, hasVisibleFlameShock) then
		return self.spells.moltenBlast, "Molten Blast"
	end

	if self.db.useMoltenBlast and not self:IsMoltenBlastPending() and self:ShouldHoldForMoltenBlast(flameShockRemaining, hasVisibleFlameShock) then
		return nil, "Hold for Molten Blast"
	end

	if shieldSpell then
		return shieldSpell, shieldLabel
	end

	if self.db.useChainLightningSecondClearcasting then
		if hasClearcasting and clearcastingStacks <= 1 and chainLightningCd <= 0 then
			return self.spells.chainLightning, "Chain Lightning"
		end
	elseif chainLightningCd <= 0 then
		return self.spells.chainLightning, "Chain Lightning"
	end

	local lightningBoltCastName, lightningBoltLabel = self:GetLightningBoltCastName()
	return self.spells.lightningBolt, lightningBoltLabel, lightningBoltCastName
end

function ElementalDPS:ClearCurrentTargetFlameShock()
	local state = self:GetTargetState()
	if state then
		state.flameShockExpiresAt = 0
		state.flameShockSeenAt = 0
		state.flameShockAppliedAt = 0
		state.pendingFlameShock = 0
		state.pendingMoltenBlast = 0
	end
end

function ElementalDPS:MarkFlameShockLanded()
	local state = self:GetTargetState()
	if state then
		state.flameShockExpiresAt = GetTime() + (self.db.flameShockDuration or 15)
		state.flameShockSeenAt = GetTime()
		state.flameShockAppliedAt = GetTime()
		state.pendingFlameShock = 0
		state.pendingMoltenBlast = 0
	end
end

function ElementalDPS:MarkMoltenBlastLanded()
	local state = self:GetTargetState()
	if state then
		state.flameShockExpiresAt = GetTime() + (self.db.flameShockDuration or 15)
		state.flameShockSeenAt = GetTime()
		state.flameShockAppliedAt = GetTime()
		state.pendingMoltenBlast = 0
	end
end

function ElementalDPS:HandleSelfDamageMessage(message)
	if not message or message == "" then
		return
	end

	local lower = string.lower(message)
	if string.find(lower, "your flame shock", 1, true) then
		if string.find(lower, "resist", 1, true) or string.find(lower, "immune", 1, true) or string.find(lower, "miss", 1, true) or string.find(lower, "absorb", 1, true) then
			self:ClearCurrentTargetFlameShock()
			self:Debug("cleared Flame Shock timer from combat text: " .. lower)
		elseif string.find(lower, "hit", 1, true) or string.find(lower, "hits", 1, true) or string.find(lower, "crit", 1, true) or string.find(lower, "crits", 1, true) or string.find(lower, "afflict", 1, true) then
			self:MarkFlameShockLanded()
		end
	elseif string.find(lower, "your molten blast", 1, true) then
		if string.find(lower, "resist", 1, true) or string.find(lower, "immune", 1, true) or string.find(lower, "miss", 1, true) or string.find(lower, "absorb", 1, true) then
			local state = self:GetTargetState()
			if state then
				state.pendingMoltenBlast = 0
			end
			self:Debug("Molten Blast did not land: " .. lower)
		elseif string.find(lower, "hit", 1, true) or string.find(lower, "hits", 1, true) or string.find(lower, "crit", 1, true) or string.find(lower, "crits", 1, true) then
			self:MarkMoltenBlastLanded()
		end
	end
end

function ElementalDPS:TryCastSpell(spellName, castNameOverride)
	local entry = self:GetSpellEntry(spellName)
	if not entry then
		return false
	end
	CastSpellByName(castNameOverride or entry.castName or spellName)
	return true
end

function ElementalDPS:DoAction()
	if not self.initialized then
		self:Initialize()
	end
	if not self.db.enabled then
		return false
	end
	if not self:EnsureEnemyTarget() then
		EDPS_Print("no valid target")
		return false
	end

	local spellName, label, castNameOverride = self:GetNextAction()
	if not spellName then
		if label then
			self:Debug(label)
			return false
		end
		EDPS_Print("no action selected")
		return false
	end

	self:Debug("casting " .. (label or spellName))
	if self:TryCastSpell(spellName, castNameOverride) then
		self:ConsumeClearcastingCharge(spellName)

		if spellName == self.spells.flameShock then
			local state = self:GetTargetState()
			if state then
				state.pendingFlameShock = GetTime()
			end
		elseif spellName == self.spells.moltenBlast then
			local state = self:GetTargetState()
			if state then
				state.pendingMoltenBlast = GetTime()
				self.currentCast = { startedAt = GetTime(), duration = (self.db.moltenBlastCastTime or 2.0), spellName = self.spells.moltenBlast }
			end
		elseif spellName == self.spells.lightningBolt then
			self.currentCast = { startedAt = GetTime(), duration = 2.0, spellName = self.spells.lightningBolt }
		elseif spellName == self.spells.chainLightning then
			self.currentCast = { startedAt = GetTime(), duration = 1.5, spellName = self.spells.chainLightning }
		end
		return true
	end
	return false
end

function ElementalDPS:PrintStatus()
	if not self.initialized then
		self:Initialize()
	end

	local hasTarget = UnitExists("target") and true or false
	local targetName = hasTarget and (UnitName("target") or "unknown") or "none"
	local mana = UnitMana and UnitMana("player") or 0
	local manaMax = UnitManaMax and UnitManaMax("player") or 0
	local manaPercent = self:GetManaPercent()
	local hasClearcasting, clearcastingStacks = self:GetPlayerBuffState()
	local spellName, label = self:GetNextAction()
	local flameShockRemaining = self:GetFlameShockRemaining()
	local moltenBlastWindow = self:GetMoltenBlastWindow()

	EDPS_Print("enabled=" .. tostring(self.db.enabled) ..
		" target=" .. targetName ..
		" mana=" .. tostring(mana) .. "/" .. tostring(manaMax) ..
		" manapct=" .. string.format("%.0f", manaPercent) ..
		" next=" .. tostring(label or spellName or "-") ..
		" fs=" .. string.format("%.1f", flameShockRemaining) ..
		" mbwin=" .. string.format("%.1f", moltenBlastWindow) ..
		" clearcasting=" .. tostring(hasClearcasting) .. "/" .. tostring(clearcastingStacks) ..
		" superwow=" .. tostring(self.superwow))
end

function ElementalDPS:PrintSpells()
	local orderedKeys = {
		"earthShield",
		"chainLightning",
		"lightningBolt",
		"flameShock",
		"moltenBlast",
	}

	for _, key in ipairs(orderedKeys) do
		local spellName = self.spells[key]
		local entry = self:GetSpellEntry(spellName)
		if entry then
			EDPS_Print(spellName .. ": found rank=" .. tostring(entry.rankNumber or 0) .. " index=" .. tostring(entry.index))
		else
			EDPS_Print(spellName .. ": missing")
		end
	end
end

function ElementalDPS:PrintHelp()
	EDPS_Print("commands: /edps status, /edps spells, /edps dps, /edps config, /edps debug, /edps reset")
	EDPS_Print("macro: create a macro with /edps dps and spam that button in combat")
	EDPS_Print("minimap: left-click opens config, right-click prints this help, drag moves the button")
end

function ElementalDPS:RefreshConfigUI()
	if not self.configFrame or not self.configWidgets then
		return
	end

	if self.configWidgets.shieldValue then
		self.configWidgets.shieldValue:SetText(self.db.shieldSpell or self.spells.earthShield)
	end
	if self.configWidgets.downrankCheckbox then
		self.configWidgets.downrankCheckbox:SetChecked(self.db.lightningBoltDownrankEnabled and 1 or nil)
	end
	if self.configWidgets.downrankRankValue then
		self.configWidgets.downrankRankValue:SetText(tostring(self.db.lightningBoltDownrankRank or 1))
	end
	if self.configWidgets.downrankManaValue then
		self.configWidgets.downrankManaValue:SetText(tostring(self.db.lightningBoltDownrankManaPercent or 0) .. "%")
	end
end

function ElementalDPS:SetShieldSpell(spellName)
	self.db.shieldSpell = spellName
	self:RefreshConfigUI()
end

function ElementalDPS:AdjustDownrankRank(delta)
	local nextRank = (self.db.lightningBoltDownrankRank or 1) + delta
	if nextRank < 1 then
		nextRank = 1
	elseif nextRank > 10 then
		nextRank = 10
	end
	self.db.lightningBoltDownrankRank = nextRank
	self:RefreshConfigUI()
end

function ElementalDPS:AdjustDownrankMana(delta)
	local nextThreshold = (self.db.lightningBoltDownrankManaPercent or 0) + delta
	if nextThreshold < 1 then
		nextThreshold = 1
	elseif nextThreshold > 100 then
		nextThreshold = 100
	end
	self.db.lightningBoltDownrankManaPercent = nextThreshold
	self:RefreshConfigUI()
end

function ElementalDPS:UpdateMinimapButtonPosition()
	if not self.minimapButton then
		return
	end

	local angle = math.rad(self.db.minimapButtonAngle or 225)
	local radius = 78
	local x = math.cos(angle) * radius
	local y = math.sin(angle) * radius

	self.minimapButton:ClearAllPoints()
	self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)

	if self.db.showMinimapButton then
		self.minimapButton:Show()
	else
		self.minimapButton:Hide()
	end
end

function ElementalDPS:EnsureMinimapButton()
	if self.minimapButton or not Minimap then
		return self.minimapButton
	end

	local button = CreateFrame("Button", "ElementalDPSMinimapButton", Minimap)
	button:SetWidth(32)
	button:SetHeight(32)
	button:SetFrameStrata("MEDIUM")
	button:SetMovable(true)
	button:EnableMouse(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetPoint("CENTER", button, "CENTER", 0, 0)
	icon:SetTexture(self:GetSpellTexture(self.spells.flameShock) or "Interface\\Icons\\Spell_Fire_FlameShock")

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	button:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:SetText("ElementalDPS")
		GameTooltip:AddLine("Left-click: Open config", 1, 1, 1)
		GameTooltip:AddLine("Right-click: Print help", 1, 1, 1)
		GameTooltip:AddLine("Drag: Move button", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:SetScript("OnClick", function()
		if arg1 == "RightButton" then
			ElementalDPS:PrintHelp()
		else
			ElementalDPS:ToggleConfig()
		end
	end)
	button:SetScript("OnDragStart", function()
		this:LockHighlight()
	end)
	button:SetScript("OnDragStop", function()
		local mx, my = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		local centerX, centerY = Minimap:GetCenter()
		local dx = (mx / scale) - centerX
		local dy = (my / scale) - centerY
		ElementalDPS.db.minimapButtonAngle = math.deg(math.atan2(dy, dx))
		this:UnlockHighlight()
		ElementalDPS:UpdateMinimapButtonPosition()
	end)

	self.minimapButton = button
	self:UpdateMinimapButtonPosition()
	return button
end

function ElementalDPS:EnsureConfigFrame()
	if self.configFrame then
		return self.configFrame
	end

	local frame = CreateFrame("Frame", "ElementalDPSConfigFrame", UIParent)
	frame:SetWidth(350)
	frame:SetHeight(280)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function()
		this:StartMoving()
	end)
	frame:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
	end)
	frame:Hide()

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", frame, "TOP", 0, -18)
	title:SetText("ElementalDPS")

	local subTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subTitle:SetPoint("TOP", title, "BOTTOM", 0, -6)
	subTitle:SetText("Priority + one-button settings")

	local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	closeButton:SetWidth(24)
	closeButton:SetHeight(20)
	closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -14)
	closeButton:SetText("X")
	closeButton:SetScript("OnClick", function()
		frame:Hide()
	end)

	local shieldLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	shieldLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -48)
	shieldLabel:SetText("Maintain Shield")

	local shieldValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	shieldValue:SetPoint("TOPLEFT", shieldLabel, "BOTTOMLEFT", 0, -4)

	local earthButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	earthButton:SetWidth(90)
	earthButton:SetHeight(22)
	earthButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -88)
	earthButton:SetText("Earth")
	earthButton:SetScript("OnClick", function()
		ElementalDPS:SetShieldSpell(ElementalDPS.spells.earthShield)
	end)

	local waterButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	waterButton:SetWidth(90)
	waterButton:SetHeight(22)
	waterButton:SetPoint("LEFT", earthButton, "RIGHT", 8, 0)
	waterButton:SetText("Water")
	waterButton:SetScript("OnClick", function()
		ElementalDPS:SetShieldSpell(ElementalDPS.spells.waterShield)
	end)

	local lightningButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	lightningButton:SetWidth(90)
	lightningButton:SetHeight(22)
	lightningButton:SetPoint("LEFT", waterButton, "RIGHT", 8, 0)
	lightningButton:SetText("Lightning")
	lightningButton:SetScript("OnClick", function()
		ElementalDPS:SetShieldSpell(ElementalDPS.spells.lightningShield)
	end)

	local downrankCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	downrankCheckbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -128)
	downrankCheckbox:SetScript("OnClick", function()
		ElementalDPS.db.lightningBoltDownrankEnabled = this:GetChecked() and true or false
		ElementalDPS:RefreshConfigUI()
	end)

	local downrankLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	downrankLabel:SetPoint("LEFT", downrankCheckbox, "RIGHT", 4, 0)
	downrankLabel:SetText("Enable LB downrank")

	local rankLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	rankLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -164)
	rankLabel:SetText("LB Rank")

	local rankMinus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	rankMinus:SetWidth(28)
	rankMinus:SetHeight(20)
	rankMinus:SetPoint("TOPLEFT", rankLabel, "BOTTOMLEFT", 0, -6)
	rankMinus:SetText("-")
	rankMinus:SetScript("OnClick", function()
		ElementalDPS:AdjustDownrankRank(-1)
	end)

	local rankValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	rankValue:SetPoint("LEFT", rankMinus, "RIGHT", 12, 0)

	local rankPlus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	rankPlus:SetWidth(28)
	rankPlus:SetHeight(20)
	rankPlus:SetPoint("LEFT", rankValue, "RIGHT", 12, 0)
	rankPlus:SetText("+")
	rankPlus:SetScript("OnClick", function()
		ElementalDPS:AdjustDownrankRank(1)
	end)

	local manaLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	manaLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 190, -164)
	manaLabel:SetText("Mana %")

	local manaMinus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	manaMinus:SetWidth(28)
	manaMinus:SetHeight(20)
	manaMinus:SetPoint("TOPLEFT", manaLabel, "BOTTOMLEFT", 0, -6)
	manaMinus:SetText("-")
	manaMinus:SetScript("OnClick", function()
		ElementalDPS:AdjustDownrankMana(-5)
	end)

	local manaValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	manaValue:SetPoint("LEFT", manaMinus, "RIGHT", 12, 0)

	local manaPlus = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	manaPlus:SetWidth(28)
	manaPlus:SetHeight(20)
	manaPlus:SetPoint("LEFT", manaValue, "RIGHT", 12, 0)
	manaPlus:SetText("+")
	manaPlus:SetScript("OnClick", function()
		ElementalDPS:AdjustDownrankMana(5)
	end)

	local helpText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	helpText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 18)
	helpText:SetWidth(300)
	helpText:SetJustifyH("LEFT")
	helpText:SetText("Use /edps config or the minimap button. Left-drag the frame to move it.")

	self.configFrame = frame
	self.configWidgets = {
		shieldValue = shieldValue,
		downrankCheckbox = downrankCheckbox,
		downrankRankValue = rankValue,
		downrankManaValue = manaValue,
	}
	self:RefreshConfigUI()
	return frame
end

function ElementalDPS:ToggleConfig()
	self:EnsureMinimapButton()
	local frame = self:EnsureConfigFrame()
	if frame:IsShown() then
		frame:Hide()
	else
		self:RefreshConfigUI()
		frame:Show()
	end
end

function ElementalDPS:HandleSlash(msg)
	msg = string.lower(string.gsub(msg or "", "^%s*(.-)%s*$", "%1"))

	if msg == "" or msg == "status" then
		EDPS_Print("slash works: " .. msg)
		self:PrintStatus()
	elseif msg == "spells" then
		if not self.initialized then
		self:Initialize()
		end
		self:RefreshSpells()
		EDPS_Print("full spell scan:")
		self:PrintSpells()
	elseif msg == "config" or msg == "ui" then
		if not self.initialized then
			self:Initialize()
		end
		self:ToggleConfig()
	elseif msg == "dps" then
		self:DoAction()
	elseif msg == "debug" then
		if not self.initialized then
			self:Initialize()
		end
		self.db.debug = not self.db.debug
		EDPS_Print("debug " .. (self.db.debug and "enabled" or "disabled"))
	elseif msg == "reset" then
		EDPS_DB = EDPS_CopyDefaults(self.defaults)
		self.db = EDPS_DB
		self.initialized = true
		self.currentCast = nil
		self.clearcastingCharges = 0
		self.clearcastingAuraActive = false
		self.targetStates = {}
		self:RefreshSpells()
		self:UpdateMinimapButtonPosition()
		self:RefreshConfigUI()
		EDPS_Print("settings reset")
	else
		self:PrintHelp()
	end
end

local frame = CreateFrame("Frame", "ElementalDPSFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
if SUPERWOW_VERSION then
	frame:RegisterEvent("UNIT_CASTEVENT")
	frame:RegisterEvent("RAW_COMBATLOG")
end
frame:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" and arg1 == "ElementalDPS" then
		ElementalDPS:Initialize()
		EDPS_Print("loaded ok")
	elseif event == "SPELLS_CHANGED" and ElementalDPS.initialized then
		ElementalDPS:RefreshSpells()
	elseif event == "PLAYER_TARGET_CHANGED" and ElementalDPS.initialized then
		if ElementalDPS.currentCast and ElementalDPS:GetCurrentCastRemaining() <= 0 then
			ElementalDPS.currentCast = nil
		end
	elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" and ElementalDPS.initialized then
		ElementalDPS:HandleSelfDamageMessage(arg1)
	elseif event == "RAW_COMBATLOG" and ElementalDPS.initialized then
		if type(arg1) == "string" and arg1 ~= "" then
			ElementalDPS:HandleSelfDamageMessage(arg1)
		end
		if type(arg2) == "string" and arg2 ~= "" then
			ElementalDPS:HandleSelfDamageMessage(arg2)
		end
	elseif event == "UNIT_CASTEVENT" and ElementalDPS.initialized then
		local casterGUID = arg1
		local castEvent = arg3
		local spellID = arg4
		local castDuration = arg5
		local playerGUID = UnitExists and UnitExists("player")
		local spellName = nil

		if casterGUID and playerGUID and casterGUID == playerGUID and SpellInfo and spellID then
			spellName = SpellInfo(spellID)
			if castEvent == "START" then
				if spellName == ElementalDPS.spells.lightningBolt or spellName == ElementalDPS.spells.chainLightning or spellName == ElementalDPS.spells.moltenBlast then
					ElementalDPS.currentCast = {
						startedAt = GetTime(),
						duration = (castDuration and castDuration > 0 and (castDuration / 1000)) or (spellName == ElementalDPS.spells.chainLightning and 1.5 or 2.0),
						spellName = spellName,
					}
				end
			elseif castEvent == "CAST" or castEvent == "FAIL" or castEvent == "INTERRUPTED" or castEvent == "STOP" then
				if spellName == ElementalDPS.spells.lightningBolt or spellName == ElementalDPS.spells.chainLightning or spellName == ElementalDPS.spells.moltenBlast then
					ElementalDPS.currentCast = nil
					if spellName == ElementalDPS.spells.moltenBlast and (castEvent == "FAIL" or castEvent == "INTERRUPTED") then
						local state = ElementalDPS:GetTargetState()
						if state then
							state.pendingMoltenBlast = 0
						end
					end
				end
			end
		end
	end
end)

SLASH_EDPS1 = "/edps"
SLASH_EDPS2 = "/srh"
SlashCmdList["EDPS"] = function(msg)
	ElementalDPS:HandleSlash(msg)
end
