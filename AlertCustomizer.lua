DBMAbilityColorsDB = DBMAbilityColorsDB or {}

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

local function GetWarningList(mod)
	local list = {}
	local function addFrom(tbl, kind)
		if type(tbl) ~= "table" then return end
		for _, obj in pairs(tbl) do
			if obj.option then
				local label, icon, spellId = BuildAbilityDisplay(mod, obj)
				table.insert(list, { option = obj.option, label = label, icon = icon, spellId = spellId, kind = kind })
			end
		end
	end
	addFrom(mod.announces, "Announce")
	addFrom(mod.specwarns, "Special Warning")
	table.sort(list, function(a, b) return a.label < b.label end)
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

local function GetSpecialWarningFontStrings()
	return _G["DBMSpecialWarning1"], _G["DBMSpecialWarning2"]
end

local function SanitizeCustomText(text)
	if type(text) ~= "string" then return text end
	text = text:gsub("%%([^s])", "%%%%%1")
	text = text:gsub("%%$", "%%%%")
	return text
end

local function HookWarningObject(mod, obj, isSpecialWarning)
	if not obj or obj.__acHooked or type(obj.Show) ~= "function" or not obj.option then
		return
	end
	obj.__acHooked = true
	local origShow = obj.Show
	obj.Show = function(self, ...)
		local entry = GetEntry(GetModKey(mod), self.option, false)

		if isSpecialWarning then
			local c = entry and entry.color
			if c then
				local f1, f2 = GetSpecialWarningFontStrings()
				if f1 then f1:SetTextColor(c[1], c[2], c[3]) end
				if f2 then f2:SetTextColor(c[1], c[2], c[3]) end
			else
				local col = DBM.Options and DBM.Options.SpecialWarningFontCol
				if col then
					local f1, f2 = GetSpecialWarningFontStrings()
					if f1 then f1:SetTextColor(col[1], col[2], col[3]) end
					if f2 then f2:SetTextColor(col[1], col[2], col[3]) end
				end
			end
		end

		local suppressDefault = entry and entry.hideDefaultSound
		local origDBMPlaySoundFile
		if suppressDefault then
			origDBMPlaySoundFile = DBM.PlaySoundFile
			DBM.PlaySoundFile = function() end
		end

		if entry and entry.sound and entry.sound ~= "" then
			PlaySoundFile(entry.sound, "Master")
		end
		if entry and entry.tts and entry.tts ~= "" then
			SpeakText(entry.tts)
		end

		local ok, r1, r2, r3 = pcall(origShow, self, ...)

		if suppressDefault then
			DBM.PlaySoundFile = origDBMPlaySoundFile
		end

		if not ok then
			error(r1, 0)
		end
		return r1, r2, r3
	end

	-- DBM voice-pack spoken alerts (recorded ability call-outs) are NOT played from
	-- inside Show(). They're played from a separate "Play" method on special warning
	-- objects, either called directly or scheduled for a few tenths of a second later
	-- (so the beep and the voice line don't overlap). Because that happens outside of
	-- Show()'s pcall window, muting DBM.PlaySoundFile only during Show() never catches
	-- it. Hook Play() too so "hide DBM sound" also hides DBM's own spoken alert.
	if isSpecialWarning and type(obj.Play) == "function" then
		local origPlay = obj.Play
		obj.Play = function(self, ...)
			local entry = GetEntry(GetModKey(mod), self.option, false)
			if entry and entry.hideDefaultSound then
				-- Swallow DBM's own voice line entirely; our custom sound/TTS already
				-- played from the Show() hook above.
				return
			end
			return origPlay(self, ...)
		end
	end
end

local function ApplyAnnounceColors(mod)
	local modKey = GetModKey(mod)
	if type(mod.announces) ~= "table" then return end
	for _, obj in pairs(mod.announces) do
		if obj.option and obj.color and not obj.__acDefaultColor then
			obj.__acDefaultColor = { r = obj.color.r, g = obj.color.g, b = obj.color.b }
		end
		local entry = GetEntry(modKey, obj.option, false)
		if entry and entry.color then
			obj.color = { r = entry.color[1], g = entry.color[2], b = entry.color[3] }
		end
	end
end

local function ApplyCustomTexts(mod)
	local modKey = GetModKey(mod)
	local function apply(tbl)
		if type(tbl) ~= "table" then return end
		for _, obj in pairs(tbl) do
			if obj.option and obj.__acDefaultText == nil then
				obj.__acDefaultText = obj.text or false
			end
			local entry = GetEntry(modKey, obj.option, false)
			if entry and entry.text and entry.text ~= "" then
				obj.text = SanitizeCustomText(entry.text)
			elseif obj.__acDefaultText ~= nil then
				obj.text = obj.__acDefaultText or obj.text
			end
		end
	end
	apply(mod.announces)
	apply(mod.specwarns)
end

local function RestoreDefaultsForOption(tbl, option)
	if type(tbl) ~= "table" then return end
	for _, obj in pairs(tbl) do
		if obj.option == option then
			if obj.__acDefaultColor then
				obj.color = { r = obj.__acDefaultColor.r, g = obj.__acDefaultColor.g, b = obj.__acDefaultColor.b }
			end
			if obj.__acDefaultText ~= nil then
				obj.text = obj.__acDefaultText or obj.text
			end
		end
	end
end

local function HookMod(mod)
	if not mod then return end
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
	ApplyAnnounceColors(mod)
	ApplyCustomTexts(mod)
end

local function HookAllLoadedMods()
	if not DBM or not DBM.Mods then return end
	for _, mod in ipairs(DBM.Mods) do
		HookMod(mod)
	end
end

local hookDriver = CreateFrame("Frame")
hookDriver:RegisterEvent("ADDON_LOADED")
hookDriver:RegisterEvent("PLAYER_LOGIN")
hookDriver:RegisterEvent("ENCOUNTER_START")
hookDriver:SetScript("OnEvent", function()
	C_Timer.After(0.5, HookAllLoadedMods)
end)

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

local function ShowColorPicker(startR, startG, startB, applyColor)
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = startR, g = startG, b = startB,
			swatchFunc = function()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				applyColor(r, g, b)
			end,
			cancelFunc = function(previousValues)
				if previousValues then
					applyColor(previousValues.r, previousValues.g, previousValues.b)
				end
			end,
		})
	else
		ColorPickerFrame:SetColorRGB(startR, startG, startB)
		ColorPickerFrame.previousValues = { r = startR, g = startG, b = startB }
		ColorPickerFrame.func = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			applyColor(r, g, b)
		end
		ColorPickerFrame.cancelFunc = function(previousValues)
			if previousValues then
				applyColor(previousValues.r, previousValues.g, previousValues.b)
			end
		end
		ColorPickerFrame.opacityFunc = nil
		ColorPickerFrame.hasOpacity = false
		ShowUIPanel(ColorPickerFrame)
	end
end

local mainFrame, scrollChild, mainScrollFrame
local expandedRaids, expandedMods = {}, {}
local RefreshTree

local function FindDefaultText(mod, option)
	local function scan(tbl)
		if type(tbl) ~= "table" then return nil end
		for _, obj in pairs(tbl) do
			if obj.option == option then
				if obj.__acDefaultText ~= nil then
					return obj.__acDefaultText or obj.text
				end
				return obj.text
			end
		end
		return nil
	end
	return scan(mod.announces) or scan(mod.specwarns)
end

local function OpenTextPopup(mod, option, label)
	local modKey = GetModKey(mod)
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
	end

	popup.title:SetText("Custom message for " .. label)

	local defaultText = FindDefaultText(mod, option)
	local placeholderCount = 0
	if type(defaultText) == "string" then
		local _, count = defaultText:gsub("%%s", "")
		placeholderCount = count
		defaultText = (ResolveSpellTokens(defaultText))
	end
	if defaultText then
		if placeholderCount > 0 then
			popup.hint:SetText(("Default: \"%s\"\nThis message uses %d dynamic value(s) (%%s) -- e.g. a player name. Keep the same number of %%s in your custom text, in the same order, to have them filled in the same way."):format(defaultText, placeholderCount))
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

	popup.editBox:SetText("")
	local entry = GetEntry(modKey, option, false)
	if entry and entry.text then
		popup.editBox:SetText(entry.text)
	end
	popup.editBox:HighlightText()

	popup.saveBtn:SetScript("OnClick", function()
		local text = popup.editBox:GetText()
		local e = GetEntry(modKey, option, true)
		e.text = text
		ApplyCustomTexts(mod)
		popup:Hide()
		RefreshTree()
	end)
	popup.editBox:SetScript("OnEnterPressed", function()
		popup.saveBtn:Click()
	end)

	popup.clearBtn:SetScript("OnClick", function()
		local e = GetEntry(modKey, option, false)
		if e then e.text = nil end
		ApplyCustomTexts(mod)
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
	end

	popup.title:SetText("Custom sound for " .. label)

	local titleHeight = popup.title:GetStringHeight() or 20
	local hintHeight = popup.hint:GetStringHeight() or 14
	local contentTop = 8 + titleHeight + 10 + hintHeight + 14
	popup:SetHeight(math.max(230, contentTop + 20 + 14 + 20 + 4 + 20 + 8 + 16 + 22 + 16))

	popup.editBox:SetText("")
	local entry = GetEntry(modKey, option, false)
	if entry and entry.sound then
		popup.editBox:SetText(entry.sound)
	end
	popup.editBox:HighlightText()

	popup.ttsBox:SetText((entry and entry.tts) or "")
	local function saveTts()
		local e = GetEntry(modKey, option, true)
		e.tts = popup.ttsBox:GetText()
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
		e.sound = sound
		e.tts = popup.ttsBox:GetText()
		e.hideDefaultSound = popup.hideDefaultCheck:GetChecked() and true or false
		if sound and sound ~= "" then
			PlaySoundFile(sound, "Master")
		end
		popup:Hide()
		RefreshTree()
	end)
	popup.editBox:SetScript("OnEnterPressed", function()
		popup.saveBtn:Click()
	end)

	popup.clearBtn:SetScript("OnClick", function()
		local e = GetEntry(modKey, option, false)
		if e then
			e.sound = nil
			e.tts = nil
			e.hideDefaultSound = nil
		end
		popup:Hide()
		RefreshTree()
	end)

	popup:Show()
	popup.editBox:SetFocus()
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
	end

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
	local function saveTts()
		local e = GetEntry(modKey, option, true)
		e.tts = picker.ttsBox:GetText()
		RefreshTree()
	end
	picker.ttsBox:SetScript("OnEnterPressed", function(self)
		saveTts()
		SpeakText(self:GetText())
		self:ClearFocus()
	end)
	picker.speakBtn:SetScript("OnClick", function()
		saveTts()
		SpeakText(picker.ttsBox:GetText())
	end)
	picker.ttsSaveBtn:SetScript("OnClick", function()
		saveTts()
	end)
	picker.ttsClearBtn:SetScript("OnClick", function()
		picker.ttsBox:SetText("")
		local e = GetEntry(modKey, option, false)
		if e then e.tts = nil end
		RefreshTree()
	end)

	picker.hideDefaultCheck:SetChecked(currentEntry and currentEntry.hideDefaultSound or false)
	picker.hideDefaultCheck:SetScript("OnClick", function(self)
		local e = GetEntry(modKey, option, true)
		e.hideDefaultSound = self:GetChecked() and true or false
		RefreshTree()
	end)

	picker.clearBtn:SetScript("OnClick", function()
		local entry = GetEntry(modKey, option, true)
		entry.sound = nil
		picker:Hide()
		RefreshTree()
	end)

	for _, c in ipairs({ picker.child:GetChildren() }) do
		c:Hide()
		c:SetParent(nil)
	end

	local y = -2
	for _, name in ipairs(names) do
		local path = list[name]
		local isSelected = currentSound and path == currentSound
		local row = CreateFrame("Button", nil, picker.child)
		row:SetSize(230, 18)
		row:SetPoint("TOPLEFT", 0, y)
		local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		text:SetPoint("LEFT", 2, 0)
		text:SetText((isSelected and "* " or "") .. name)
		row:SetScript("OnEnter", function() text:SetTextColor(1, 1, 0) end)
		row:SetScript("OnLeave", function()
			if isSelected then
				text:SetTextColor(0.3, 1, 0.5)
			else
				text:SetTextColor(1, 1, 1)
			end
		end)
		if isSelected then
			text:SetTextColor(0.3, 1, 0.5)
		end
		row:SetScript("OnClick", function(_, button)
			if button == "RightButton" then
				PlaySoundFile(path, "Master")
			else
				local entry = GetEntry(modKey, option, true)
				entry.sound = path
				PlaySoundFile(path, "Master")
				picker:Hide()
				RefreshTree()
			end
		end)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
		local rows = GetWarningList(mod)
		if #rows > 0 then
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

RefreshTree = function()
	if not scrollChild then return end
	for _, child in ipairs({ scrollChild:GetChildren() }) do
		child:Hide()
		child:SetParent(nil)
	end

	local availWidth = (mainScrollFrame and mainScrollFrame:GetWidth()) or 620
	if availWidth < 300 then availWidth = 300 end
	scrollChild:SetWidth(availWidth)

	local headerWidth = availWidth
	local bossWidth = availWidth - 16
	local rowWidth = availWidth - 32
	local controlsWidth = 180
	local textWidth = math.max(120, rowWidth - 20 - controlsWidth - 10)

	local y = -4
	local groups = GetRaidGroups()
	for _, group in ipairs(groups) do
		local raidKey = group.groupId

		local headerBtn = CreateFrame("Button", nil, scrollChild)
		headerBtn:SetSize(headerWidth, 22)
		headerBtn:SetPoint("TOPLEFT", 0, y)
		local headerText = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		headerText:SetPoint("LEFT", 4, 0)
		headerText:SetText((expandedRaids[raidKey] and "- " or "+ ") .. group.name)
		headerBtn:SetScript("OnClick", function()
			expandedRaids[raidKey] = not expandedRaids[raidKey]
			RefreshTree()
		end)
		y = y - 24

		if expandedRaids[raidKey] then
			for _, mod in ipairs(group.mods) do
				local modKey = GetModKey(mod)

				local bossBtn = CreateFrame("Button", nil, scrollChild)
				bossBtn:SetSize(bossWidth, 20)
				bossBtn:SetPoint("TOPLEFT", 16, y)
				local bossText = bossBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				bossText:SetPoint("LEFT", 4, 0)
				bossText:SetText((expandedMods[modKey] and "- " or "+ ") .. GetModDisplayName(mod))
				bossBtn:SetScript("OnClick", function()
					expandedMods[modKey] = not expandedMods[modKey]
					RefreshTree()
				end)
				y = y - 22

				if expandedMods[modKey] then
					local rows = GetWarningList(mod)
					for _, row in ipairs(rows) do
						local rowFrame = CreateFrame("Frame", nil, scrollChild)
						rowFrame:SetPoint("TOPLEFT", 32, y)

						local icon = rowFrame:CreateTexture(nil, "ARTWORK")
						icon:SetSize(16, 16)
						icon:SetPoint("TOPLEFT", 2, -3)
						icon:SetTexture(row.icon)

						local text = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
						text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 4, 0)
						text:SetWidth(textWidth)
						text:SetJustifyH("LEFT")
						text:SetJustifyV("TOP")
						text:SetWordWrap(true)
						text:SetText(("[%s] %s"):format(row.kind, row.label))

						local textHeight = text:GetStringHeight() or 14
						local rowHeight = math.max(22, textHeight + 8)
						rowFrame:SetSize(rowWidth, rowHeight)

						local swatch = CreateFrame("Button", nil, rowFrame, "BackdropTemplate")
						swatch:SetSize(18, 18)
						swatch:SetPoint("TOPRIGHT", -156, -2)
						swatch:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8", edgeFile = "Interface/Buttons/WHITE8x8", edgeSize = 1 })
						swatch:SetBackdropBorderColor(0, 0, 0, 1)

						local entry = GetEntry(modKey, row.option, false)
						local savedColor = entry and entry.color
						if savedColor then
							swatch:SetBackdropColor(savedColor[1], savedColor[2], savedColor[3], 1)
						else
							swatch:SetBackdropColor(0.2, 0.55, 1, 1)
						end

						swatch:SetScript("OnClick", function()
							local function applyColor(r, g, b)
								local e = GetEntry(modKey, row.option, true)
								e.color = { r, g, b }
								swatch:SetBackdropColor(r, g, b, 1)
								ApplyAnnounceColors(mod)
							end
							local startR, startG, startB = 0.2, 0.55, 1
							if savedColor then startR, startG, startB = savedColor[1], savedColor[2], savedColor[3] end
							ShowColorPicker(startR, startG, startB, applyColor)
						end)

						local msgBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
						msgBtn:SetSize(40, 18)
						msgBtn:SetPoint("TOPRIGHT", -108, -2)
						msgBtn:SetText("Msg")
						if entry and entry.text and entry.text ~= "" then
							msgBtn:SetText("Msg*")
						end
						msgBtn:SetScript("OnClick", function()
							OpenTextPopup(mod, row.option, row.label)
						end)

						local soundBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
						soundBtn:SetSize(50, 18)
						soundBtn:SetPoint("TOPRIGHT", -50, -2)
						soundBtn:SetText("Sound")
						if entry and ((entry.sound and entry.sound ~= "") or (entry.tts and entry.tts ~= "") or entry.hideDefaultSound) then
							soundBtn:SetText("Sound*")
						end
						soundBtn:SetScript("OnClick", function()
							OpenSharedMediaPicker(modKey, row.option, row.label)
						end)

						local resetBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
						resetBtn:SetSize(45, 18)
						resetBtn:SetPoint("TOPRIGHT", 0, -2)
						resetBtn:SetText("Reset")
						resetBtn:SetScript("OnClick", function()
							if DBMAbilityColorsDB[modKey] then
								DBMAbilityColorsDB[modKey][row.option] = nil
							end
							RestoreDefaultsForOption(mod.announces, row.option)
							RestoreDefaultsForOption(mod.specwarns, row.option)
							RefreshTree()
						end)

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
	f:SetSize(680, 520)
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
		f:SetResizeBounds(500, 350, 1400, 1000)
	else
		f:SetMinResize(500, 350)
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
		RefreshTree()
		f:Show()
	end
end
