DBMAbilityColorsDB = DBMAbilityColorsDB or {}

local floor = math.floor

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

local function GetModKey(mod)
	return (mod and (mod.id or mod.name)) or "unknown"
end

local function GetModDisplayName(mod)
	if not mod then return "Unknown" end
	if mod.combatInfo and mod.combatInfo.name and mod.combatInfo.name ~= "" then
		return mod.combatInfo.name
	end
	if mod.name and mod.name ~= "" then
		return mod.name
	end
	if mod.modId then
		return mod.modId
	end
	return tostring(GetModKey(mod))
end

local zoneNameCache = {}

local function GetZoneName(zoneId)
	if not zoneId then return nil end
	if zoneNameCache[zoneId] then return zoneNameCache[zoneId] end
	local name = GetRealZoneText and GetRealZoneText(zoneId)
	if name then name = name:trim() end
	if not name or name == "" then
		if C_Map and C_Map.GetMapInfo then
			local info = C_Map.GetMapInfo(zoneId)
			name = info and info.name
		end
	end
	if not name or name == "" then return nil end
	zoneNameCache[zoneId] = name
	return name
end

local instanceNameCache = {}

local function GetInstanceName(instanceId)
	if not instanceId then return "Other" end
	if instanceNameCache[instanceId] then return instanceNameCache[instanceId] end
	local name
	if C_EncounterJournal and C_EncounterJournal.GetInstanceInfo then
		name = C_EncounterJournal.GetInstanceInfo(instanceId)
	elseif EJ_GetInstanceInfo then
		name = EJ_GetInstanceInfo(instanceId)
	end
	name = name or ("Instance " .. tostring(instanceId))
	instanceNameCache[instanceId] = name
	return name
end

local function GetModZoneGroup(mod)
	if type(mod.zones) == "table" then
		local lowest
		for zoneId in pairs(mod.zones) do
			if type(zoneId) == "number" and (not lowest or zoneId < lowest) then
				lowest = zoneId
			end
		end
		if lowest then
			local name = GetZoneName(lowest)
			if name then
				return lowest, name
			end
		end
	end
	if mod.instanceId then
		return "ej" .. mod.instanceId, GetInstanceName(mod.instanceId)
	end
	return 0, "Other"
end

local QUESTION_MARK_ICON = 134400

local function GetSpellNameAndIcon(spellId)
	spellId = tonumber(spellId)
	if not spellId then return nil, nil end
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spellId)
		if info and info.name and info.name ~= "" then
			return info.name, info.iconID
		end
	end
	if GetSpellInfo then
		local name, _, icon = GetSpellInfo(spellId)
		if name and name ~= "" then
			return name, icon
		end
	end
	return nil, nil
end

local function ResolveSpellTokens(text, wantIcon)
	if type(text) ~= "string" then return text, nil end
	local icon
	local resolved = text:gsub("%$spell:(%d+)", function(id)
		local name, spellIcon = GetSpellNameAndIcon(id)
		if wantIcon and not icon and spellIcon then icon = spellIcon end
		return name or ("Spell " .. id)
	end)
	return resolved, icon
end

local function FindSpellIdInObj(obj)
	if type(obj.spellId) == "number" then
		return obj.spellId
	end
	local id = tonumber(obj.option)
	if id then return id end
	if type(obj.option) == "string" then
		id = obj.option:match("%$spell:(%d+)")
		if id then return tonumber(id) end
	end
	if type(obj.text) == "string" then
		id = obj.text:match("%$spell:(%d+)")
		if id then return tonumber(id) end
	end
	return nil
end

local function BuildAbilityDisplay(mod, obj)
	local candidate, icon

	if mod.localization and mod.localization.options and type(obj.option) == "string" then
		local loc = mod.localization.options[obj.option]
		if type(loc) == "string" and loc ~= "" then
			candidate = loc
		end
	end
	if not candidate and type(obj.text) == "string" and obj.text ~= "" then
		candidate = obj.text
	end
	if not candidate and type(obj.option) == "string" then
		candidate = obj.option
	end

	local spellId = FindSpellIdInObj(obj)

	local label
	if candidate and not tonumber(candidate) then
		local resolved, tokenIcon = ResolveSpellTokens(candidate, true)
		icon = icon or tokenIcon
		label = (resolved or candidate):gsub("%%s", "?")
	end

	if not label or label == "" then
		if spellId then
			local spellName, spellIcon = GetSpellNameAndIcon(spellId)
			label = spellName
			icon = icon or spellIcon
		end
	end

	label = label or tostring(obj.option)

	if spellId and not icon then
		local _, spellIcon = GetSpellNameAndIcon(spellId)
		icon = spellIcon
	end

	if spellId then
		label = ("%s (ID: %d)"):format(label, spellId)
	end

	if not icon then
		if type(obj.icon) == "number" or (type(obj.icon) == "string" and obj.icon ~= "") then
			icon = obj.icon
		else
			icon = QUESTION_MARK_ICON
		end
	end

	return label, icon, spellId
end

-- Cheap check used when grouping mods: does this mod have anything we can customize?
local function ModHasWarnings(mod)
	local function has(tbl)
		if type(tbl) ~= "table" then return false end
		for _, obj in pairs(tbl) do
			if obj.option then return true end
		end
		return false
	end
	return has(mod.announces) or has(mod.specwarns)
end

-- The full list (labels, icons, spell lookups) is only built for mods the user actually
-- expands, and cached for as long as the window stays open. It's cleared every time the
-- window is opened so spell names that weren't cached by the client yet get picked up.
local warningListCache = {}

local function GetWarningList(mod)
	local cached = warningListCache[mod]
	if cached then return cached end
	local list = {}
	local function addFrom(tbl, kind)
		if type(tbl) ~= "table" then return end
		for _, obj in pairs(tbl) do
			if obj.option then
				local label, icon, spellId = BuildAbilityDisplay(mod, obj)
				table.insert(list, { option = obj.option, label = label, icon = icon, spellId = spellId, kind = kind, obj = obj })
			end
		end
	end
	addFrom(mod.announces, "Announce")
	addFrom(mod.specwarns, "Special Warning")
	table.sort(list, function(a, b) return a.label < b.label end)
	warningListCache[mod] = list
	return list
end

local function GetEntry(modKey, optionKey, create)
	local modTbl = DBMAbilityColorsDB[modKey]
	if not modTbl then
		if not create then return nil end
		modTbl = {}
		DBMAbilityColorsDB[modKey] = modTbl
	end
	local entry = modTbl[optionKey]
	if not entry and create then
		entry = {}
		modTbl[optionKey] = entry
	end
	return entry
end

local function EntryIsEmpty(e)
	if not e then return true end
	if e.color then return false end
	if e.text and e.text ~= "" then return false end
	if e.sound and e.sound ~= "" then return false end
	if e.tts and e.tts ~= "" then return false end
	if e.hideDefaultSound then return false end
	if e.displayAs then return false end
	return true
end

-- Removes an entry (and its boss table) from the saved variables once nothing is customized.
local function PruneEntry(modKey, optionKey)
	local modTbl = DBMAbilityColorsDB[modKey]
	if not modTbl then return end
	if EntryIsEmpty(modTbl[optionKey]) then
		modTbl[optionKey] = nil
	end
	if next(modTbl) == nil then
		DBMAbilityColorsDB[modKey] = nil
	end
end

local function PruneAll()
	for modKey, modTbl in pairs(DBMAbilityColorsDB) do
		if type(modTbl) == "table" then
			for optionKey in pairs(modTbl) do
				PruneEntry(modKey, optionKey)
			end
		end
	end
end

local function SpeakText(text)
	if not (C_VoiceChat and C_VoiceChat.SpeakText) then
		print("|cffff5555DBM Alert Customizer:|r Text-to-speech isn't available on this client.")
		return
	end
	local voiceID = 0
	if C_TTSSettings and C_TTSSettings.GetVoiceOptionID and Enum.TtsVoiceType then
		local ok, id = pcall(C_TTSSettings.GetVoiceOptionID, Enum.TtsVoiceType.Narration)
		if ok and id then voiceID = id end
	end
	if Enum.VoiceTtsDestination then
		C_VoiceChat.SpeakText(voiceID, text, Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
	else
		C_VoiceChat.SpeakText(voiceID, text, 0, 100, false)
	end
end

----------------------------------------------------------------------
-- Custom message text
----------------------------------------------------------------------

-- DBM formats warning text with string.format. %s is filled with names (player names, or
-- several names joined together when DBM combines targets), and >%s< makes DBM class-color
-- the name. A few DBM defaults also use %d for numbers (stacks, interrupt counts).
-- Everything else with a % sign is escaped so it's shown literally (e.g. "100%").
local sanitizeCache = {}

local function SanitizeCustomText(text)
	if type(text) ~= "string" then return text end
	local cached = sanitizeCache[text]
	if cached then return cached end
	local result = text:gsub("%%(.?)", function(nextChar)
		if nextChar == "s" or nextChar == "d" then
			return "%" .. nextChar
		elseif nextChar == "%" then
			return "%%"
		end
		return "%%" .. nextChar
	end)
	sanitizeCache[text] = result
	return result
end

local function CountPlaceholders(text)
	if type(text) ~= "string" then return 0 end
	local stripped = text:gsub("%%%%", "")
	local _, count = stripped:gsub("%%[sd]", "")
	return count
end

----------------------------------------------------------------------
-- Colors
----------------------------------------------------------------------

local function ColorHex(r, g, b)
	return ("%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-- Same math DBM uses when it builds its "back to the normal special warning color" code
-- after a class-colored name, so we can find and replace it.
local function DBMSpecialWarningHex()
	local col = DBM.Options and DBM.Options.SpecialWarningFontCol
	if not col then return nil end
	return ("%02x%02x%02x"):format(floor(col[1] * 255), floor(col[2] * 255), floor(col[3] * 255))
end

-- Colors one special warning line by putting the color inside the text itself, so each
-- line on screen keeps its own color (instead of recoloring both DBM font strings).
local function ColorizeSpecialWarningText(text, c)
	local customCode = "|cff" .. ColorHex(c[1], c[2], c[3])
	local defaultHex = DBMSpecialWarningHex()
	if defaultHex then
		-- After a class-colored >name<, DBM switches back to its default color; switch back
		-- to the custom color instead.
		text = text:gsub("|cff" .. defaultHex, customCode)
	end
	return customCode .. text .. "|r"
end

-- One reusable color table per announce object. DBM caches its name-coloring function per
-- color table, so reusing the same table avoids building a new cache entry on every change.
local function GetCustomColorTable(obj, c)
	local t = obj.__acColor
	if not t then
		t = {}
		obj.__acColor = t
	end
	t.r, t.g, t.b = c[1], c[2], c[3]
	return t
end

local function GetDefaultColor(row)
	if row.kind == "Special Warning" then
		local col = DBM.Options and DBM.Options.SpecialWarningFontCol
		if col then return col[1], col[2], col[3] end
	elseif row.obj and type(row.obj.color) == "table" and row.obj.color.r then
		return row.obj.color.r, row.obj.color.g, row.obj.color.b
	end
	return 1, 1, 1
end

----------------------------------------------------------------------
-- Hooks
----------------------------------------------------------------------

local noop = function() end
local pendingSWColor    -- color for the next special warning line DBM puts on screen
local queuedDuringShow  -- true when DBM only queued a Midnight warning instead of showing it

local function InstallGlobalHooks()
	if not DBM or DBM.__acGlobalHooks then return end
	DBM.__acGlobalHooks = true

	if type(DBM.AddSpecialWarning) == "function" then
		local origAdd = DBM.AddSpecialWarning
		DBM.AddSpecialWarning = function(self, text, ...)
			local c = pendingSWColor
			-- Clear before calling: DBM calls this function again for itself when both lines
			-- are busy, and that inner call must not color the text a second time.
			pendingSWColor = nil
			if c and not IsSecret(text) and type(text) == "string" then
				text = ColorizeSpecialWarningText(text, c)
			end
			return origAdd(self, text, ...)
		end
	end

	-- On Midnight, some warnings call Show() twice: first DBM only queues them, then Shows
	-- them for real once Blizzard provides the target. We note the queue call so the custom
	-- sound/TTS plays once, when the warning actually appears.
	for _, fname in ipairs({ "QueueBlizzTargetAnnounce", "QueueBlizzTargetSpecialWarning", "QueueBlizzYouSpecialWarning" }) do
		local orig = DBM[fname]
		if type(orig) == "function" then
			DBM[fname] = function(...)
				queuedDuringShow = true
				return orig(...)
			end
		end
	end
end

----------------------------------------------------------------------
-- Switching a warning between normal announce and special warning
----------------------------------------------------------------------

-- DBM still builds the whole message (names, class colors, icons, custom text). We only
-- change where the finished text is drawn, and swap which kind of sound/flash goes with it.
-- Sounds follow DBM's own decision: the other type's sound only plays if DBM wanted to
-- play a sound for this warning, so DBM's mute/voice pack settings keep working.

local promoteState = { shown = false, soundWanted = false }
local demoteState = { shown = false, soundWanted = false, color = nil }
local promoteNextPlaySoundFile

-- Normal announce -> drawn in the special warning frame
local function PromoteAddWarning(self, text, force, announceObject, useSound, prefix, overrideDuration, customIcon)
	promoteState.shown = true
	return self:AddSpecialWarning(text, nil, nil, nil, customIcon, true)
end

-- Catches only the normal announce sound; everything else plays as usual.
local function PromotePlaySoundFile(self, path, ...)
	if path == (DBM.Options and DBM.Options.RaidWarningSound) then
		promoteState.soundWanted = true
		return
	end
	return promoteNextPlaySoundFile(self, path, ...)
end

-- Special warning -> drawn in the normal announce area
local function DemoteAddSpecialWarning(self, text, force, specWarnObject, number, customIcon, noSound)
	demoteState.shown = true
	if demoteState.color and not IsSecret(text) and type(text) == "string" then
		text = ColorizeSpecialWarningText(text, demoteState.color)
	end
	return self:AddWarning(text, nil, nil, false, nil, nil, customIcon)
end

local function DemotePlaySpecialWarningSound()
	demoteState.soundWanted = true
end

local function SpecialWarningStyleEffects(style)
	if UnitIsDeadOrGhost("player") then return end
	local o = DBM.Options
	if not o then return end
	if o["SpecialWarningFlash" .. style] and not o.DontShowSpecialWarningFlash and DBM.Flash then
		local c = o["SpecialWarningFlashCol" .. style]
		if c then
			DBM.Flash:Show(c[1], c[2], c[3], o["SpecialWarningFlashDura" .. style], o["SpecialWarningFlashAlph" .. style], (o["SpecialWarningFlashCount" .. style] or 1) - 1)
		end
	end
	if not o.DontDoSpecialWarningVibrate and o["SpecialWarningVibrate" .. style] and DBM.VibrateController then
		DBM:VibrateController()
	end
end

-- Color for a special warning shown as a normal announce: the custom color if one is set,
-- otherwise DBM's first announce color so it looks like any other normal announce.
local function DemoteColor(entry)
	if entry.color then return entry.color end
	local wc = DBM.Options and DBM.Options.WarningColors and DBM.Options.WarningColors[1]
	if wc and wc.r then return { wc.r, wc.g, wc.b } end
	return nil
end

local function HookWarningObject(mod, obj, isSpecialWarning)
	if not obj or obj.__acHooked or type(obj.Show) ~= "function" or not obj.option then
		return
	end
	obj.__acHooked = true
	local modKey = GetModKey(mod)

	local origShow = obj.Show
	obj.Show = function(self, ...)
		local entry = GetEntry(modKey, self.option, false)
		if not entry then
			-- Nothing customized for this ability: no extra work at all.
			return origShow(self, ...)
		end

		-- Custom text is only swapped in for the duration of this call. DBM's own text stays
		-- untouched, so boss mods that change text mid-fight and DBM's spell renaming keep working.
		local savedText, customText
		if entry.text and entry.text ~= "" and type(self.text) == "string" then
			customText = SanitizeCustomText(entry.text)
			if (self.announceType == "blizztarget" or self.announceType == "blizzyou")
				and CountPlaceholders(customText) ~= CountPlaceholders(self.text) then
				-- These Midnight warnings are formatted without DBM's error protection, so a
				-- mismatched number of %s would cause a Lua error. Use DBM's text instead.
				customText = nil
			end
			if customText then
				savedText = self.text
				self.text = customText
			end
		end

		local savedColor
		if entry.color then
			if isSpecialWarning then
				pendingSWColor = entry.color -- (cleared again below if the warning is shown as normal)
			elseif type(self.color) == "table" then
				savedColor = self.color
				self.color = GetCustomColorTable(self, entry.color)
			end
		end

		local suppressDefault = entry.hideDefaultSound
		local origDBMPlaySoundFile
		if suppressDefault then
			origDBMPlaySoundFile = DBM.PlaySoundFile
			DBM.PlaySoundFile = noop
		end

		-- Switched type (set from the "Type" button in the GUI)
		local promote = not isSpecialWarning and entry.displayAs == "special"
		local demote = isSpecialWarning and entry.displayAs == "normal"
		local savedAddWarning, savedAddSW, savedPSF, savedSWSound, savedFlashShow, savedVibrate
		if promote then
			promoteState.shown, promoteState.soundWanted = false, false
			savedAddWarning = DBM.AddWarning
			DBM.AddWarning = PromoteAddWarning
			savedPSF = DBM.PlaySoundFile
			promoteNextPlaySoundFile = savedPSF
			DBM.PlaySoundFile = PromotePlaySoundFile
		elseif demote then
			pendingSWColor = nil
			demoteState.shown, demoteState.soundWanted = false, false
			demoteState.color = DemoteColor(entry)
			savedAddSW = DBM.AddSpecialWarning
			DBM.AddSpecialWarning = DemoteAddSpecialWarning
			savedSWSound = DBM.PlaySpecialWarningSound
			DBM.PlaySpecialWarningSound = DemotePlaySpecialWarningSound
			if DBM.Flash then
				savedFlashShow = rawget(DBM.Flash, "Show")
				DBM.Flash.Show = noop
			end
			savedVibrate = DBM.VibrateController
			DBM.VibrateController = noop
		end

		local prevQueued = queuedDuringShow
		queuedDuringShow = false

		local ok, r1, r2, r3 = pcall(origShow, self, ...)

		local wasQueued = queuedDuringShow
		queuedDuringShow = prevQueued
		pendingSWColor = nil

		-- Put everything back in reverse order
		if promote then
			DBM.PlaySoundFile = savedPSF
			DBM.AddWarning = savedAddWarning
		elseif demote then
			DBM.VibrateController = savedVibrate
			if DBM.Flash then DBM.Flash.Show = savedFlashShow end
			DBM.PlaySpecialWarningSound = savedSWSound
			DBM.AddSpecialWarning = savedAddSW
			demoteState.color = nil
		end
		if suppressDefault then
			DBM.PlaySoundFile = origDBMPlaySoundFile
		end
		if savedColor then
			self.color = savedColor
		end
		if customText and self.text == customText then
			self.text = savedText
		end

		if not ok then
			error(r1, 0)
		end

		-- Give the warning the sound and flash of its new type
		if promote and promoteState.shown then
			if promoteState.soundWanted and not suppressDefault and DBM.PlaySpecialWarningSound then
				DBM:PlaySpecialWarningSound(entry.swStyle or 1)
			end
			SpecialWarningStyleEffects(entry.swStyle or 1)
		elseif demote and demoteState.shown then
			if demoteState.soundWanted and not suppressDefault and DBM.Options then
				DBM:PlaySoundFile(DBM.Options.RaidWarningSound, nil, true)
			end
		end

		if not wasQueued then
			if entry.sound and entry.sound ~= "" then
				PlaySoundFile(entry.sound, "Master")
			end
			if entry.tts and entry.tts ~= "" then
				SpeakText(entry.tts)
			end
		end
		return r1, r2, r3
	end

	-- DBM voice-pack callouts are played from a separate Play() method (often scheduled a
	-- moment after Show), outside of Show()'s window. Both announces and special warnings
	-- have one, so both are hooked so "hide DBM sound" also covers the voice line.
	if type(obj.Play) == "function" then
		local origPlay = obj.Play
		obj.Play = function(self, ...)
			local entry = GetEntry(modKey, self.option, false)
			if entry and entry.hideDefaultSound then
				return
			end
			return origPlay(self, ...)
		end
	end
end

local function CountObjects(mod)
	local n = 0
	if type(mod.announces) == "table" then n = n + #mod.announces end
	if type(mod.specwarns) == "table" then n = n + #mod.specwarns end
	return n
end

local function HookMod(mod)
	if not mod then return end
	local n = CountObjects(mod)
	if mod.__acHookedCount == n then return end -- already fully hooked
	if type(mod.announces) == "table" then
		for _, obj in pairs(mod.announces) do
			HookWarningObject(mod, obj, false)
		end
	end
	if type(mod.specwarns) == "table" then
		for _, obj in pairs(mod.specwarns) do
			HookWarningObject(mod, obj, true)
		end
	end
	mod.__acHookedCount = n
end

local function HookAllLoadedMods()
	if not DBM or not DBM.Mods then return end
	InstallGlobalHooks()
	for _, mod in ipairs(DBM.Mods) do
		HookMod(mod)
	end
end

local hookDriver = CreateFrame("Frame")
hookDriver:RegisterEvent("ADDON_LOADED")
hookDriver:RegisterEvent("PLAYER_LOGIN")
hookDriver:RegisterEvent("ENCOUNTER_START")
hookDriver:RegisterEvent("PLAYER_LOGOUT")
hookDriver:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == "DBM-AlertCustomizer" then
			DBMAbilityColorsDB = DBMAbilityColorsDB or {}
			return
		end
		-- Only DBM's own boss mod addons matter. Hook right away (before a pull can schedule
		-- anything), plus once more shortly after in case a mod finishes setting up late.
		if type(arg1) == "string" and arg1:find("^DBM") then
			HookAllLoadedMods()
			C_Timer.After(0.5, HookAllLoadedMods)
		end
	elseif event == "PLAYER_LOGOUT" then
		PruneAll()
	else
		HookAllLoadedMods()
	end
end)

InstallGlobalHooks()

----------------------------------------------------------------------
-- Slash command helpers
----------------------------------------------------------------------

local function PrintDebug()
	if not DBM or not DBM.Mods then
		print("|cffff5555DBM Alert Customizer:|r DBM not loaded.")
		return
	end
	print(("|cff33ff99DBM Alert Customizer:|r %d mod(s) currently loaded in DBM.Mods:"):format(#DBM.Mods))
	for _, mod in ipairs(DBM.Mods) do
		local aCount = type(mod.announces) == "table" and #mod.announces or 0
		local sCount = type(mod.specwarns) == "table" and #mod.specwarns or 0
		print(("  - %s (id=%s)  announces=%d  specwarns=%d"):format(
			GetModDisplayName(mod), tostring(GetModKey(mod)), aCount, sCount))
	end
end

local function PrintInspect(searchTerm)
	if not DBM or not DBM.Mods or not searchTerm or searchTerm == "" then
		print("|cffff5555DBM Alert Customizer:|r Usage: /dbmalerts inspect <part of ability name>")
		return
	end
	searchTerm = searchTerm:lower()
	local found = 0
	for _, mod in ipairs(DBM.Mods) do
		local function scan(tbl, kind)
			if type(tbl) ~= "table" then return end
			for _, obj in pairs(tbl) do
				if obj.option then
					local label = BuildAbilityDisplay(mod, obj)
					if label:lower():find(searchTerm, 1, true) then
						found = found + 1
						print(("|cff33ff99[%s]|r %s -> %s"):format(kind, GetModDisplayName(mod), label))
						local keys = {}
						for k in pairs(obj) do table.insert(keys, tostring(k)) end
						table.sort(keys)
						print("  fields: " .. table.concat(keys, ", "))
					end
				end
			end
		end
		scan(mod.announces, "Announce")
		scan(mod.specwarns, "Special Warning")
	end
	if found == 0 then
		print("|cffff5555DBM Alert Customizer:|r No loaded ability matched '" .. searchTerm .. "'.")
	end
end

----------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------

local function ShowColorPicker(startR, startG, startB, applyColor, onCancel)
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = startR, g = startG, b = startB,
			swatchFunc = function()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				applyColor(r, g, b)
			end,
			cancelFunc = function()
				onCancel()
			end,
		})
	else
		ColorPickerFrame:SetColorRGB(startR, startG, startB)
		ColorPickerFrame.previousValues = { r = startR, g = startG, b = startB }
		ColorPickerFrame.func = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			applyColor(r, g, b)
		end
		ColorPickerFrame.cancelFunc = function()
			onCancel()
		end
		ColorPickerFrame.opacityFunc = nil
		ColorPickerFrame.hasOpacity = false
		ShowUIPanel(ColorPickerFrame)
	end
end

-- Tiny frame pool. WoW never frees frames, so the GUI reuses the ones it already made
-- instead of creating new ones on every refresh.
local function NewPool(createFn)
	return { items = {}, used = 0, create = createFn }
end

local function PoolAcquire(pool)
	pool.used = pool.used + 1
	local f = pool.items[pool.used]
	if not f then
		f = pool.create()
		pool.items[pool.used] = f
	end
	f:Show()
	return f
end

local function PoolReleaseAll(pool)
	for i = 1, #pool.items do
		pool.items[i]:Hide()
	end
	pool.used = 0
end

local mainFrame, scrollChild, mainScrollFrame
local expandedRaids, expandedMods = {}, {}
local RefreshTree

local function OpenTextPopup(row, modKey)
	local option, label, obj = row.option, row.label, row.obj
	local popup = _G["DBMAbilityColorsTextPopup"]
	if not popup then
		popup = CreateFrame("Frame", "DBMAbilityColorsTextPopup", UIParent, "BasicFrameTemplateWithInset")
		popup:SetSize(400, 180)
		popup:SetPoint("CENTER")
		popup:SetMovable(true)
		popup:EnableMouse(true)
		popup:RegisterForDrag("LeftButton")
		popup:SetScript("OnDragStart", popup.StartMoving)
		popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
		popup:SetFrameStrata("DIALOG")

		popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		popup.title:SetPoint("TOPLEFT", 40, -8)
		popup.title:SetPoint("TOPRIGHT", -40, -8)
		popup.title:SetJustifyH("CENTER")
		popup.title:SetWordWrap(true)

		popup.hint = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		popup.hint:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", -20, -12)
		popup.hint:SetPoint("TOPRIGHT", popup.title, "BOTTOMRIGHT", 20, -12)
		popup.hint:SetJustifyH("LEFT")
		popup.hint:SetWordWrap(true)

		local editBox = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
		editBox:SetSize(360, 20)
		editBox:SetPoint("TOP", popup.hint, "BOTTOM", 0, -16)
		editBox:SetAutoFocus(true)
		popup.editBox = editBox

		local saveBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		saveBtn:SetSize(80, 22)
		saveBtn:SetPoint("BOTTOMLEFT", 20, 16)
		saveBtn:SetText("Save")
		popup.saveBtn = saveBtn

		local clearBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		clearBtn:SetSize(80, 22)
		clearBtn:SetPoint("BOTTOM", 0, 16)
		clearBtn:SetText("Clear")
		popup.clearBtn = clearBtn

		local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		cancelBtn:SetSize(80, 22)
		cancelBtn:SetPoint("BOTTOMRIGHT", -20, 16)
		cancelBtn:SetText("Cancel")
		cancelBtn:SetScript("OnClick", function() popup:Hide() end)

		editBox:SetScript("OnEscapePressed", function() popup:Hide() end)
		editBox:SetScript("OnEnterPressed", function() popup.saveBtn:Click() end)
	end

	popup.title:SetText("Custom message for " .. label)

	-- obj.text is always DBM's own text now (custom text is only swapped in during Show).
	local defaultText = obj and obj.text
	local placeholderCount = 0
	if type(defaultText) == "string" then
		placeholderCount = CountPlaceholders(defaultText)
		defaultText = (ResolveSpellTokens(defaultText))
	else
		defaultText = nil
	end
	if defaultText then
		if placeholderCount > 0 then
			popup.hint:SetText(("Default: \"%s\"\nThis message has %d dynamic value(s): %%s is filled with the affected player name(s), %%d with a number. Keep the same ones in the same order. Write a name as >%%s< to keep DBM's class colors."):format(defaultText, placeholderCount))
		else
			popup.hint:SetText(("Default: \"%s\"\nThis message has no dynamic values."):format(defaultText))
		end
	else
		popup.hint:SetText("")
	end

	local titleHeight = popup.title:GetStringHeight() or 20
	local hintHeight = popup.hint:GetStringHeight() or 14
	local contentTop = 8 + titleHeight + 12 + hintHeight + 16
	popup:SetHeight(math.max(180, contentTop + 20 + 16 + 22 + 16))

	local entry = GetEntry(modKey, option, false)
	popup.editBox:SetText((entry and entry.text) or "")
	popup.editBox:HighlightText()

	popup.saveBtn:SetScript("OnClick", function()
		local text = popup.editBox:GetText()
		if text == "" then
			local e = GetEntry(modKey, option, false)
			if e then e.text = nil end
			PruneEntry(modKey, option)
		else
			local e = GetEntry(modKey, option, true)
			e.text = text
			local customCount = CountPlaceholders(SanitizeCustomText(text))
			if customCount ~= placeholderCount then
				print(("|cffffcc00DBM Alert Customizer:|r Saved, but your message has %d dynamic value(s) and DBM's default has %d. Names may not appear the way you expect."):format(customCount, placeholderCount))
			end
		end
		popup:Hide()
		RefreshTree()
	end)

	popup.clearBtn:SetScript("OnClick", function()
		local e = GetEntry(modKey, option, false)
		if e then e.text = nil end
		PruneEntry(modKey, option)
		popup:Hide()
		RefreshTree()
	end)

	popup:Show()
	popup.editBox:SetFocus()
end

local function OpenSoundPopup(modKey, option, label)
	local popup = _G["DBMAbilityColorsSoundTextPopup"]
	if not popup then
		popup = CreateFrame("Frame", "DBMAbilityColorsSoundTextPopup", UIParent, "BasicFrameTemplateWithInset")
		popup:SetSize(380, 150)
		popup:SetPoint("CENTER")
		popup:SetMovable(true)
		popup:EnableMouse(true)
		popup:RegisterForDrag("LeftButton")
		popup:SetScript("OnDragStart", popup.StartMoving)
		popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
		popup:SetFrameStrata("DIALOG")

		popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		popup.title:SetPoint("TOPLEFT", 40, -8)
		popup.title:SetPoint("TOPRIGHT", -40, -8)
		popup.title:SetJustifyH("CENTER")
		popup.title:SetWordWrap(true)

		popup.hint = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		popup.hint:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", -20, -10)
		popup.hint:SetPoint("TOPRIGHT", popup.title, "BOTTOMRIGHT", 20, -10)
		popup.hint:SetJustifyH("CENTER")
		popup.hint:SetWordWrap(true)
		popup.hint:SetText("Leave blank to use the default DBM sound")

		local editBox = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
		editBox:SetSize(340, 20)
		editBox:SetPoint("TOP", popup.hint, "BOTTOM", 0, -14)
		editBox:SetAutoFocus(true)
		popup.editBox = editBox

		local ttsLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		ttsLabel:SetPoint("TOP", editBox, "BOTTOM", 0, -14)
		ttsLabel:SetText("Text-to-Speech (spoken in addition to the sound above):")

		local ttsBox = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
		ttsBox:SetSize(280, 20)
		ttsBox:SetPoint("TOP", ttsLabel, "BOTTOM", -35, -4)
		ttsBox:SetAutoFocus(false)
		popup.ttsBox = ttsBox

		local speakBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		speakBtn:SetSize(60, 20)
		speakBtn:SetPoint("LEFT", ttsBox, "RIGHT", 6, 0)
		speakBtn:SetText("Speak")
		popup.speakBtn = speakBtn

		local hideDefaultCheck = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
		hideDefaultCheck:SetSize(20, 20)
		hideDefaultCheck:SetPoint("TOP", ttsBox, "BOTTOM", -50, -8)
		popup.hideDefaultCheck = hideDefaultCheck

		local hideDefaultLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		hideDefaultLabel:SetPoint("LEFT", hideDefaultCheck, "RIGHT", 2, 0)
		hideDefaultLabel:SetText("Hide DBM's default sound for this ability")
		popup.hideDefaultLabel = hideDefaultLabel

		local saveBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		saveBtn:SetSize(80, 22)
		saveBtn:SetPoint("BOTTOMLEFT", 20, 16)
		saveBtn:SetText("Save")
		popup.saveBtn = saveBtn

		local clearBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		clearBtn:SetSize(80, 22)
		clearBtn:SetPoint("BOTTOM", 0, 16)
		clearBtn:SetText("Clear")
		popup.clearBtn = clearBtn

		local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		cancelBtn:SetSize(80, 22)
		cancelBtn:SetPoint("BOTTOMRIGHT", -20, 16)
		cancelBtn:SetText("Cancel")
		cancelBtn:SetScript("OnClick", function() popup:Hide() end)

		editBox:SetScript("OnEscapePressed", function() popup:Hide() end)
		editBox:SetScript("OnEnterPressed", function() popup.saveBtn:Click() end)
	end

	popup.title:SetText("Custom sound for " .. label)

	local titleHeight = popup.title:GetStringHeight() or 20
	local hintHeight = popup.hint:GetStringHeight() or 14
	local contentTop = 8 + titleHeight + 10 + hintHeight + 14
	popup:SetHeight(math.max(230, contentTop + 20 + 14 + 20 + 4 + 20 + 8 + 16 + 22 + 16))

	local entry = GetEntry(modKey, option, false)
	popup.editBox:SetText((entry and entry.sound) or "")
	popup.editBox:HighlightText()

	popup.ttsBox:SetText((entry and entry.tts) or "")
	local function saveTts()
		local text = popup.ttsBox:GetText()
		if text == "" then
			local e = GetEntry(modKey, option, false)
			if e then e.tts = nil end
			PruneEntry(modKey, option)
		else
			GetEntry(modKey, option, true).tts = text
		end
	end
	popup.ttsBox:SetScript("OnEnterPressed", function(self)
		saveTts()
		SpeakText(self:GetText())
		self:ClearFocus()
	end)
	popup.speakBtn:SetScript("OnClick", function()
		saveTts()
		SpeakText(popup.ttsBox:GetText())
	end)

	popup.hideDefaultCheck:SetChecked(entry and entry.hideDefaultSound or false)

	popup.saveBtn:SetScript("OnClick", function()
		local sound = popup.editBox:GetText()
		local e = GetEntry(modKey, option, true)
		e.sound = (sound ~= "" and sound) or nil
		local tts = popup.ttsBox:GetText()
		e.tts = (tts ~= "" and tts) or nil
		e.hideDefaultSound = popup.hideDefaultCheck:GetChecked() and true or nil
		if e.sound then
			PlaySoundFile(e.sound, "Master")
		end
		PruneEntry(modKey, option)
		popup:Hide()
		RefreshTree()
	end)

	popup.clearBtn:SetScript("OnClick", function()
		local e = GetEntry(modKey, option, false)
		if e then
			e.sound = nil
			e.tts = nil
			e.hideDefaultSound = nil
		end
		PruneEntry(modKey, option)
		popup:Hide()
		RefreshTree()
	end)

	popup:Show()
	popup.editBox:SetFocus()
end

local soundRowPool

local function CreateSoundRow()
	local picker = _G["DBMAbilityColorsSoundPicker"]
	local row = CreateFrame("Button", nil, picker.child)
	row:SetSize(230, 18)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.text:SetPoint("LEFT", 2, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 0) end)
	row:SetScript("OnLeave", function(self)
		if self.isSelected then
			self.text:SetTextColor(0.3, 1, 0.5)
		else
			self.text:SetTextColor(1, 1, 1)
		end
	end)
	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			PlaySoundFile(self.path, "Master")
		else
			local ctx = picker.ctx
			GetEntry(ctx.modKey, ctx.option, true).sound = self.path
			PlaySoundFile(self.path, "Master")
			picker:Hide()
			RefreshTree()
		end
	end)
	return row
end

local function OpenSharedMediaPicker(modKey, option, label)
	local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if not LSM then
		OpenSoundPopup(modKey, option, label)
		return
	end

	local list = LSM:HashTable("sound")
	local names = {}
	for name in pairs(list) do table.insert(names, name) end
	table.sort(names)

	local picker = _G["DBMAbilityColorsSoundPicker"]
	if not picker then
		picker = CreateFrame("Frame", "DBMAbilityColorsSoundPicker", UIParent, "BasicFrameTemplateWithInset")
		picker:SetSize(300, 400)
		picker:SetPoint("CENTER")
		picker:SetMovable(true)
		picker:EnableMouse(true)
		picker:RegisterForDrag("LeftButton")
		picker:SetScript("OnDragStart", picker.StartMoving)
		picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
		picker:SetFrameStrata("DIALOG")
		picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		picker.title:SetPoint("TOPLEFT", 40, -8)
		picker.title:SetPoint("TOPRIGHT", -40, -8)
		picker.title:SetJustifyH("CENTER")
		picker.title:SetWordWrap(true)

		picker.current = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		picker.current:SetPoint("TOPLEFT", picker.title, "BOTTOMLEFT", -40, -6)
		picker.current:SetPoint("TOPRIGHT", picker.title, "BOTTOMRIGHT", 40, -6)
		picker.current:SetJustifyH("CENTER")
		picker.current:SetWordWrap(true)
		picker.current:SetTextColor(0.3, 1, 0.5)

		local clearBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
		clearBtn:SetSize(80, 20)
		clearBtn:SetPoint("TOP", picker.current, "BOTTOM", 0, -10)
		clearBtn:SetText("Clear Sound")
		picker.clearBtn = clearBtn

		local ttsLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		ttsLabel:SetPoint("TOP", picker.clearBtn, "BOTTOM", 0, -12)
		ttsLabel:SetText("Text-to-Speech:")

		local ttsBox = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
		ttsBox:SetSize(220, 20)
		ttsBox:SetPoint("TOP", ttsLabel, "BOTTOM", 0, -4)
		ttsBox:SetAutoFocus(false)
		picker.ttsBox = ttsBox

		local speakBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
		speakBtn:SetSize(60, 18)
		speakBtn:SetPoint("TOP", ttsBox, "BOTTOM", -70, -6)
		speakBtn:SetText("Speak")
		picker.speakBtn = speakBtn

		local ttsSaveBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
		ttsSaveBtn:SetSize(60, 18)
		ttsSaveBtn:SetPoint("LEFT", speakBtn, "RIGHT", 4, 0)
		ttsSaveBtn:SetText("Save")
		picker.ttsSaveBtn = ttsSaveBtn

		local ttsClearBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
		ttsClearBtn:SetSize(60, 18)
		ttsClearBtn:SetPoint("LEFT", ttsSaveBtn, "RIGHT", 4, 0)
		ttsClearBtn:SetText("Clear")
		picker.ttsClearBtn = ttsClearBtn

		local hideDefaultCheck = CreateFrame("CheckButton", nil, picker, "UICheckButtonTemplate")
		hideDefaultCheck:SetSize(20, 20)
		hideDefaultCheck:SetPoint("TOP", speakBtn, "BOTTOM", -20, -8)
		picker.hideDefaultCheck = hideDefaultCheck

		local hideDefaultLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		hideDefaultLabel:SetPoint("LEFT", hideDefaultCheck, "RIGHT", 2, 0)
		hideDefaultLabel:SetText("Hide DBM's default sound for this ability")

		local scrollFrame = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
		scrollFrame:SetPoint("TOPLEFT", hideDefaultCheck, "BOTTOMLEFT", -28, -14)
		scrollFrame:SetPoint("BOTTOMRIGHT", -30, 12)
		local child = CreateFrame("Frame", nil, scrollFrame)
		child:SetSize(240, 1)
		scrollFrame:SetScrollChild(child)
		picker.child = child

		soundRowPool = NewPool(CreateSoundRow)

		-- These buttons read the current ability from picker.ctx, so their scripts are set once.
		local function ctxSaveTts()
			local ctx = picker.ctx
			local text = picker.ttsBox:GetText()
			if text == "" then
				local e = GetEntry(ctx.modKey, ctx.option, false)
				if e then e.tts = nil end
				PruneEntry(ctx.modKey, ctx.option)
			else
				GetEntry(ctx.modKey, ctx.option, true).tts = text
			end
			RefreshTree()
		end
		picker.ttsBox:SetScript("OnEnterPressed", function(self)
			ctxSaveTts()
			SpeakText(self:GetText())
			self:ClearFocus()
		end)
		picker.speakBtn:SetScript("OnClick", function()
			ctxSaveTts()
			SpeakText(picker.ttsBox:GetText())
		end)
		picker.ttsSaveBtn:SetScript("OnClick", ctxSaveTts)
		picker.ttsClearBtn:SetScript("OnClick", function()
			local ctx = picker.ctx
			picker.ttsBox:SetText("")
			local e = GetEntry(ctx.modKey, ctx.option, false)
			if e then e.tts = nil end
			PruneEntry(ctx.modKey, ctx.option)
			RefreshTree()
		end)
		picker.hideDefaultCheck:SetScript("OnClick", function(self)
			local ctx = picker.ctx
			GetEntry(ctx.modKey, ctx.option, true).hideDefaultSound = self:GetChecked() and true or nil
			PruneEntry(ctx.modKey, ctx.option)
			RefreshTree()
		end)
		picker.clearBtn:SetScript("OnClick", function()
			local ctx = picker.ctx
			local e = GetEntry(ctx.modKey, ctx.option, false)
			if e then e.sound = nil end
			PruneEntry(ctx.modKey, ctx.option)
			picker:Hide()
			RefreshTree()
		end)
	end

	picker.ctx = { modKey = modKey, option = option }
	picker.title:SetText(label)

	local currentEntry = GetEntry(modKey, option, false)
	local currentSound = currentEntry and currentEntry.sound
	local currentName
	if currentSound and currentSound ~= "" then
		for name, path in pairs(list) do
			if path == currentSound then
				currentName = name
				break
			end
		end
		picker.current:SetText("Currently set: " .. (currentName or currentSound))
	else
		picker.current:SetText("Currently set: (default DBM sound)")
	end

	local titleHeight = picker.title:GetStringHeight() or 20
	local currentHeight = picker.current:GetStringHeight() or 14
	picker:SetHeight(math.max(460, 8 + titleHeight + 6 + currentHeight + 10 + 20 + 12 + 20 + 24 + 20 + 300))

	picker.ttsBox:SetText((currentEntry and currentEntry.tts) or "")
	picker.hideDefaultCheck:SetChecked(currentEntry and currentEntry.hideDefaultSound or false)

	PoolReleaseAll(soundRowPool)
	local y = -2
	for _, name in ipairs(names) do
		local path = list[name]
		local row = PoolAcquire(soundRowPool)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, y)
		row.path = path
		row.isSelected = currentSound and path == currentSound or false
		row.text:SetText((row.isSelected and "* " or "") .. name)
		if row.isSelected then
			row.text:SetTextColor(0.3, 1, 0.5)
		else
			row.text:SetTextColor(1, 1, 1)
		end
		y = y - 20
	end
	picker.child:SetHeight(math.max(1, -y))
	picker:Show()
end

local function GetRaidGroups()
	local groups = {}
	if not DBM or not DBM.Mods then return groups end
	local byId = {}
	for _, mod in ipairs(DBM.Mods) do
		if ModHasWarnings(mod) then
			local groupId, groupName = GetModZoneGroup(mod)
			byId[groupId] = byId[groupId] or { groupId = groupId, name = groupName, mods = {} }
			table.insert(byId[groupId].mods, mod)
		end
	end
	for _, g in pairs(byId) do
		table.sort(g.mods, function(a, b) return GetModDisplayName(a) < GetModDisplayName(b) end)
		table.insert(groups, g)
	end
	table.sort(groups, function(a, b) return a.name < b.name end)
	return groups
end

local headerPool, bossPool, abilityPool

local function CreateHeaderButton(parent, fontObject)
	local btn = CreateFrame("Button", nil, parent)
	btn.text = btn:CreateFontString(nil, "OVERLAY", fontObject)
	btn.text:SetPoint("LEFT", 4, 0)
	return btn
end

local function UpdateSwatch(rowFrame)
	local d = rowFrame.data
	local entry = GetEntry(d.modKey, d.row.option, false)
	if entry and entry.color then
		rowFrame.swatch:SetBackdropColor(entry.color[1], entry.color[2], entry.color[3], 1)
		rowFrame.swatch:SetBackdropBorderColor(1, 0.82, 0, 1) -- gold border = custom color
	else
		local r, g, b = GetDefaultColor(d.row)
		rowFrame.swatch:SetBackdropColor(r, g, b, 1)
		rowFrame.swatch:SetBackdropBorderColor(0, 0, 0, 1)
	end
end

-- Short description of how a row is currently displayed, e.g. "Announce -> Special 2"
local function DisplayKindText(row, entry)
	if row.kind == "Announce" and entry and entry.displayAs == "special" then
		return ("Announce -> Special %d"):format(entry.swStyle or 1)
	elseif row.kind == "Special Warning" and entry and entry.displayAs == "normal" then
		return "Special Warning -> Normal"
	end
	return row.kind
end

local function OpenTypePopup(row, modKey)
	local option = row.option
	local popup = _G["DBMAbilityColorsTypePopup"]
	if not popup then
		popup = CreateFrame("Frame", "DBMAbilityColorsTypePopup", UIParent, "BasicFrameTemplateWithInset")
		popup:SetSize(380, 200)
		popup:SetPoint("CENTER")
		popup:SetMovable(true)
		popup:EnableMouse(true)
		popup:RegisterForDrag("LeftButton")
		popup:SetScript("OnDragStart", popup.StartMoving)
		popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
		popup:SetFrameStrata("DIALOG")
		tinsert(UISpecialFrames, "DBMAbilityColorsTypePopup")

		popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		popup.title:SetPoint("TOPLEFT", 40, -8)
		popup.title:SetPoint("TOPRIGHT", -40, -8)
		popup.title:SetJustifyH("CENTER")
		popup.title:SetWordWrap(true)

		popup.current = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		popup.current:SetPoint("TOP", popup.title, "BOTTOM", 0, -14)

		popup.hint = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		popup.hint:SetPoint("TOPLEFT", 16, -70)
		popup.hint:SetPoint("TOPRIGHT", -16, -70)
		popup.hint:SetJustifyH("LEFT")
		popup.hint:SetWordWrap(true)

		popup.defaultBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		popup.defaultBtn:SetSize(160, 22)

		popup.styleBtns = {}
		for i = 1, 5 do
			local b = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
			b:SetSize(62, 22)
			b:SetText("Special " .. i)
			b.style = i
			popup.styleBtns[i] = b
		end

		popup.normalBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		popup.normalBtn:SetSize(160, 22)
		popup.normalBtn:SetText("Show as Normal")
	end

	local entry = GetEntry(modKey, option, false)
	popup.title:SetText("Display type for " .. row.label)
	popup.current:SetText("Currently: " .. DisplayKindText(row, entry))

	local function choose(displayAs, style)
		if displayAs then
			local e = GetEntry(modKey, option, true)
			e.displayAs = displayAs
			e.swStyle = style
		else
			local e = GetEntry(modKey, option, false)
			if e then
				e.displayAs = nil
				e.swStyle = nil
			end
			PruneEntry(modKey, option)
		end
		popup:Hide()
		RefreshTree()
	end

	popup.defaultBtn:ClearAllPoints()
	popup.normalBtn:ClearAllPoints()
	for _, b in ipairs(popup.styleBtns) do b:ClearAllPoints() end

	if row.kind == "Announce" then
		popup.hint:SetText("DBM shows this as a normal announce. Pick a special warning style to show it in the big center frame instead. Styles 1-5 use the sound and screen flash you set for them in DBM's Special Warnings options.")
		popup.defaultBtn:SetText("Keep Normal (default)")
		popup.defaultBtn:SetPoint("BOTTOM", 0, 48)
		popup.defaultBtn:SetScript("OnClick", function() choose(nil) end)
		for i, b in ipairs(popup.styleBtns) do
			b:SetPoint("BOTTOMLEFT", 18 + (i - 1) * 69, 16)
			b:SetScript("OnClick", function() choose("special", i) end)
			b:Show()
		end
		popup.normalBtn:Hide()
	else
		popup.hint:SetText("DBM shows this as a special warning. Choose \"Show as Normal\" to show it in the normal announce area instead, with the normal announce sound and no screen flash.")
		popup.defaultBtn:SetText("Keep Special (default)")
		popup.defaultBtn:SetPoint("BOTTOMLEFT", 20, 16)
		popup.defaultBtn:SetScript("OnClick", function() choose(nil) end)
		popup.normalBtn:SetPoint("BOTTOMRIGHT", -20, 16)
		popup.normalBtn:SetScript("OnClick", function() choose("normal") end)
		popup.normalBtn:Show()
		for _, b in ipairs(popup.styleBtns) do b:Hide() end
	end

	local hintHeight = popup.hint:GetStringHeight() or 40
	popup:SetHeight(math.max(200, 70 + hintHeight + 16 + 22 + 10 + 22 + 16))
	popup:Show()
end

local function CreateAbilityRow()
	local rowFrame = CreateFrame("Frame", nil, scrollChild)

	rowFrame.icon = rowFrame:CreateTexture(nil, "ARTWORK")
	rowFrame.icon:SetSize(16, 16)
	rowFrame.icon:SetPoint("TOPLEFT", 2, -3)

	rowFrame.text = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	rowFrame.text:SetPoint("TOPLEFT", rowFrame.icon, "TOPRIGHT", 4, 0)
	rowFrame.text:SetJustifyH("LEFT")
	rowFrame.text:SetJustifyV("TOP")
	rowFrame.text:SetWordWrap(true)

	local swatch = CreateFrame("Button", nil, rowFrame, "BackdropTemplate")
	swatch:SetSize(18, 18)
	swatch:SetPoint("TOPRIGHT", -216, -2)
	swatch:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8", edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
	rowFrame.swatch = swatch
	swatch:SetScript("OnClick", function()
		-- Capture this ability now; the row frame may be reused for another ability later.
		local d = rowFrame.data
		local modKey, option = d.modKey, d.row.option
		local existing = GetEntry(modKey, option, false)
		local prevColor = existing and existing.color and { existing.color[1], existing.color[2], existing.color[3] }
		local startR, startG, startB
		if prevColor then
			startR, startG, startB = prevColor[1], prevColor[2], prevColor[3]
		else
			startR, startG, startB = GetDefaultColor(d.row)
		end
		local function refreshIfSame()
			if rowFrame.data == d and rowFrame:IsShown() then UpdateSwatch(rowFrame) end
		end
		ShowColorPicker(startR, startG, startB, function(r, g, b)
			GetEntry(modKey, option, true).color = { r, g, b }
			refreshIfSame()
		end, function()
			-- Cancel puts things back exactly as they were, including "no custom color".
			local e = GetEntry(modKey, option, false)
			if e then e.color = prevColor end
			PruneEntry(modKey, option)
			refreshIfSame()
		end)
	end)

	local msgBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
	msgBtn:SetSize(40, 18)
	msgBtn:SetPoint("TOPRIGHT", -168, -2)
	rowFrame.msgBtn = msgBtn
	msgBtn:SetScript("OnClick", function()
		local d = rowFrame.data
		OpenTextPopup(d.row, d.modKey)
	end)

	local soundBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
	soundBtn:SetSize(50, 18)
	soundBtn:SetPoint("TOPRIGHT", -110, -2)
	rowFrame.soundBtn = soundBtn
	soundBtn:SetScript("OnClick", function()
		local d = rowFrame.data
		OpenSharedMediaPicker(d.modKey, d.row.option, d.row.label)
	end)

	local typeBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
	typeBtn:SetSize(56, 18)
	typeBtn:SetPoint("TOPRIGHT", -50, -2)
	rowFrame.typeBtn = typeBtn
	typeBtn:SetScript("OnClick", function()
		local d = rowFrame.data
		OpenTypePopup(d.row, d.modKey)
	end)

	local resetBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
	resetBtn:SetSize(45, 18)
	resetBtn:SetPoint("TOPRIGHT", 0, -2)
	resetBtn:SetText("Reset")
	resetBtn:SetScript("OnClick", function()
		local d = rowFrame.data
		local modTbl = DBMAbilityColorsDB[d.modKey]
		if modTbl then
			modTbl[d.row.option] = nil
			if next(modTbl) == nil then DBMAbilityColorsDB[d.modKey] = nil end
		end
		RefreshTree()
	end)

	return rowFrame
end

RefreshTree = function()
	if not scrollChild then return end
	PoolReleaseAll(headerPool)
	PoolReleaseAll(bossPool)
	PoolReleaseAll(abilityPool)

	local availWidth = (mainScrollFrame and mainScrollFrame:GetWidth()) or 620
	if availWidth < 300 then availWidth = 300 end
	scrollChild:SetWidth(availWidth)

	local headerWidth = availWidth
	local bossWidth = availWidth - 16
	local rowWidth = availWidth - 32
	local controlsWidth = 240
	local textWidth = math.max(120, rowWidth - 20 - controlsWidth - 10)

	local y = -4
	local groups = GetRaidGroups()
	for _, group in ipairs(groups) do
		local raidKey = group.groupId

		local headerBtn = PoolAcquire(headerPool)
		headerBtn:ClearAllPoints()
		headerBtn:SetSize(headerWidth, 22)
		headerBtn:SetPoint("TOPLEFT", 0, y)
		headerBtn.text:SetText((expandedRaids[raidKey] and "- " or "+ ") .. group.name)
		headerBtn.key = raidKey
		y = y - 24

		if expandedRaids[raidKey] then
			for _, mod in ipairs(group.mods) do
				local modKey = GetModKey(mod)

				local bossBtn = PoolAcquire(bossPool)
				bossBtn:ClearAllPoints()
				bossBtn:SetSize(bossWidth, 20)
				bossBtn:SetPoint("TOPLEFT", 16, y)
				bossBtn.text:SetText((expandedMods[modKey] and "- " or "+ ") .. GetModDisplayName(mod))
				bossBtn.key = modKey
				y = y - 22

				if expandedMods[modKey] then
					for _, row in ipairs(GetWarningList(mod)) do
						local rowFrame = PoolAcquire(abilityPool)
						rowFrame.data = { modKey = modKey, row = row }
						rowFrame:ClearAllPoints()
						rowFrame:SetPoint("TOPLEFT", 32, y)

						rowFrame.icon:SetTexture(row.icon)
						rowFrame.text:SetWidth(textWidth)
						local entry = GetEntry(modKey, row.option, false)
						rowFrame.text:SetText(("[%s] %s"):format(DisplayKindText(row, entry), row.label))

						local textHeight = rowFrame.text:GetStringHeight() or 14
						local rowHeight = math.max(22, textHeight + 8)
						rowFrame:SetSize(rowWidth, rowHeight)

						UpdateSwatch(rowFrame)
						rowFrame.msgBtn:SetText((entry and entry.text and entry.text ~= "") and "Msg*" or "Msg")
						local hasSound = entry and ((entry.sound and entry.sound ~= "") or (entry.tts and entry.tts ~= "") or entry.hideDefaultSound)
						rowFrame.soundBtn:SetText(hasSound and "Sound*" or "Sound")
						rowFrame.typeBtn:SetText((entry and entry.displayAs) and "Type*" or "Type")

						y = y - rowHeight - 2
					end
				end
			end
		end
	end
	scrollChild:SetHeight(math.max(1, -y))
end

local function CreateMainFrame()
	if mainFrame then return mainFrame end

	local f = CreateFrame("Frame", "DBMAbilityColorsFrame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(740, 520)
	f:SetPoint("CENTER")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetFrameStrata("HIGH")
	f:Hide()
	tinsert(UISpecialFrames, "DBMAbilityColorsFrame")

	f:SetResizable(true)
	if f.SetResizeBounds then
		f:SetResizeBounds(560, 350, 1400, 1000)
	else
		f:SetMinResize(560, 350)
		f:SetMaxResize(1400, 1000)
	end

	local resizeGrip = CreateFrame("Button", nil, f)
	resizeGrip:SetSize(16, 16)
	resizeGrip:SetPoint("BOTTOMRIGHT", -4, 4)
	resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resizeGrip:SetScript("OnMouseDown", function()
		f:StartSizing("BOTTOMRIGHT")
	end)
	resizeGrip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		RefreshTree()
	end)

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.title:SetPoint("TOP", 0, -6)
	f.title:SetText("DBM Alert Customizer")

	local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 16, -34)
	scrollFrame:SetPoint("BOTTOMRIGHT", -34, 16)
	mainScrollFrame = scrollFrame

	scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetSize(620, 1)
	scrollFrame:SetScrollChild(scrollChild)

	headerPool = NewPool(function()
		local btn = CreateHeaderButton(scrollChild, "GameFontNormal")
		btn:SetScript("OnClick", function(self)
			expandedRaids[self.key] = not expandedRaids[self.key]
			RefreshTree()
		end)
		return btn
	end)
	bossPool = NewPool(function()
		local btn = CreateHeaderButton(scrollChild, "GameFontNormalSmall")
		btn:SetScript("OnClick", function(self)
			expandedMods[self.key] = not expandedMods[self.key]
			RefreshTree()
		end)
		return btn
	end)
	abilityPool = NewPool(CreateAbilityRow)

	mainFrame = f
	return f
end

SLASH_DBMABILITYCOLORS1 = "/dbmalerts"
SLASH_DBMABILITYCOLORS2 = "/dbmalert"
SLASH_DBMABILITYCOLORS3 = "/dbmcolor"
SlashCmdList["DBMABILITYCOLORS"] = function(msg)
	msg = (msg or ""):trim()
	local lower = msg:lower()
	if lower == "debug" then
		PrintDebug()
		return
	end
	local inspectTerm = lower:match("^inspect%s+(.+)$")
	if inspectTerm then
		PrintInspect(inspectTerm)
		return
	end
	local f = CreateMainFrame()
	if f:IsShown() then
		f:Hide()
	else
		HookAllLoadedMods()
		wipe(warningListCache)
		RefreshTree()
		f:Show()
	end
end
