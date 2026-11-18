--[[
	Controller Seal Timer
	WoW Forever. Times a paladin seal from UNIT_SPELLCAST_SUCCEEDED (30s) and
	draws the seconds left on the controller button that currently shows it.
	Does not read auras. Judgement does not cancel the timer.
]]

local ADDON = ...

local DEFAULT_DURATION = 30
local WARN_SECONDS = 5

-- Lowercased prefixes. A cast whose name starts with one of these is a seal.
local PREFIXES = {
	"seal of ",
	"siegel ",
	"sceau ",
	"sello ",
	"selo ",
	"sigillo ",
	"печать",
	"pieczęć",
	"pecsét",
}

-- Substrings that stay in the original spelling (no useful lowercase form).
local CONTAINS = {
	"圣印",
	"聖印",
}

local active
local buttons = {}
local seenButtons = {}
local overlayHooked = false
local foundSlotButtons = false
local deepScans = 0
local elapsedSinceScan = 0

local core = CreateFrame("Frame")

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffd597ffController Seal Timer|r: " .. msg)
end

local function Secret(value)
	if issecretvalue and issecretvalue(value) then
		return true
	end
	return false
end

local function Normalize(name)
	if type(name) ~= "string" or Secret(name) then
		return nil
	end
	name = name:gsub("%s*%([^%)]*%)%s*$", "")
	name = name:gsub("%s+", " ")
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return nil
	end
	return name:lower()
end

local function SpellName(spellID)
	if type(spellID) ~= "number" or Secret(spellID) then
		return nil
	end
	if C_Spell and C_Spell.GetSpellName then
		local name = C_Spell.GetSpellName(spellID)
		if type(name) == "string" and not Secret(name) then
			return name
		end
	end
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spellID)
		if type(info) == "table" and type(info.name) == "string" and not Secret(info.name) then
			return info.name
		end
	end
	return nil
end

local function IsTrackedName(name)
	local key = Normalize(name)
	if not key then
		return false
	end
	if ControllerSealTimerDB and ControllerSealTimerDB.extra then
		if ControllerSealTimerDB.extra[key] then
			return true, key
		end
	end
	for i = 1, #PREFIXES do
		local prefix = PREFIXES[i]
		if key:sub(1, #prefix) == prefix then
			return true, key
		end
	end
	for i = 1, #CONTAINS do
		if name:find(CONTAINS[i], 1, true) then
			return true, key
		end
	end
	return false
end

local function Duration()
	local seconds = ControllerSealTimerDB and ControllerSealTimerDB.duration
	if type(seconds) ~= "number" or seconds < 1 or seconds > 600 then
		return DEFAULT_DURATION
	end
	return seconds
end

local function EnsureDB()
	if type(ControllerSealTimerDB) ~= "table" then
		ControllerSealTimerDB = {}
	end
	if type(ControllerSealTimerDB.extra) ~= "table" then
		ControllerSealTimerDB.extra = {}
	end
	if type(ControllerSealTimerDB.duration) ~= "number" then
		ControllerSealTimerDB.duration = DEFAULT_DURATION
	end
end

local function StartTimer(spellID, name)
	local key = Normalize(name)
	if not key then
		return
	end
	local now = GetTime()
	active = {
		spellID = spellID,
		name = name,
		key = key,
		castAt = now,
		expiresAt = now + Duration(),
	}
	core:Refresh()
end

local function ClearTimer(reason)
	if not active then
		return
	end
	active = nil
	core:Refresh()
	if reason then
		Print(reason)
	end
end

local function Remaining()
	if not active then
		return nil
	end
	local left = active.expiresAt - GetTime()
	if left <= 0 then
		active = nil
		return nil
	end
	return left
end

local function RememberButton(button)
	if not button or seenButtons[button] then
		return
	end
	if not button.GetObjectType or button:GetObjectType() ~= "CheckButton" then
		return
	end
	seenButtons[button] = true
	buttons[#buttons + 1] = button
end

local function CollectSide(side)
	if not side then
		return
	end
	for i = 1, 8 do
		RememberButton(side["ActionButton" .. i])
	end
end

local function CollectBar(bar)
	if type(bar) ~= "table" then
		return
	end
	CollectSide(bar.Left)
	CollectSide(bar.Right)
	for i = 1, 12 do
		RememberButton(bar["ActionButton" .. i])
	end
	if type(bar.actionButtons) == "table" then
		for i = 1, #bar.actionButtons do
			RememberButton(bar.actionButtons[i])
		end
	end
end

local EnsureOverlay

local function ScanButtons()
	local main = _G.GamepadMainActionBarFrame
	local page = main and main.PageUnit
	local bars = page and page.actionBars
	if type(bars) == "table" then
		for _, bar in pairs(bars) do
			CollectBar(bar)
		end
	end
	if page then
		RememberButton(page.LeftClassAction)
		RememberButton(page.RightClassAction)
	end

	-- Face and D-pad buttons are not always global names. Walk once we have
	-- seen a real gamepad slot, and keep trying for a while at login if the
	-- controller UI has not been built yet.
	if not foundSlotButtons and deepScans < 30 and EnumerateFrames then
		deepScans = deepScans + 1
		local frame = EnumerateFrames()
		while frame do
			if frame.pageUnitSlotID and frame.cooldown then
				RememberButton(frame)
				foundSlotButtons = true
			end
			frame = EnumerateFrames(frame)
		end
	end

	if not (InCombatLockdown and InCombatLockdown()) then
		for i = 1, #buttons do
			EnsureOverlay(buttons[i])
		end
	end
end

local function ButtonAction(button)
	local action = button.action
	if type(action) == "number" and action > 0 and not Secret(action) then
		return action
	end
	if button.CalculateAction then
		local ok, calculated = pcall(button.CalculateAction, button)
		if ok and type(calculated) == "number" and calculated > 0 and not Secret(calculated) then
			return calculated
		end
	end
	return nil
end

local function ButtonSpellID(button)
	local direct = button.spellID
	if button.isFlyoutAction and type(direct) == "number" and direct > 0 and not Secret(direct) then
		return direct
	end

	local action = ButtonAction(button)
	if not action or not GetActionInfo then
		return nil
	end
	local actionType, id = GetActionInfo(action)
	if Secret(actionType) or Secret(id) then
		return nil
	end
	if actionType == "spell" and type(id) == "number" then
		return id
	end
	if actionType == "macro" and type(id) == "number" and GetMacroSpell then
		local spellID = GetMacroSpell(id)
		if type(spellID) == "number" and not Secret(spellID) then
			return spellID
		end
	end
	return nil
end

local function ButtonMatches(button)
	if not active then
		return false
	end
	local spellID = ButtonSpellID(button)
	if not spellID then
		return false
	end
	if spellID == active.spellID then
		return true
	end
	local name = SpellName(spellID)
	local key = Normalize(name)
	return key ~= nil and key == active.key
end

function EnsureOverlay(button)
	if button.ControllerSealTimer then
		return button.ControllerSealTimer
	end
	if InCombatLockdown and InCombatLockdown() then
		return nil
	end

	local holder = CreateFrame("Frame", nil, button)
	holder:SetAllPoints(button.icon or button.Icon or button)
	holder:EnableMouse(false)
	if holder.SetPropagateMouseClicks then
		holder:SetPropagateMouseClicks(true)
	end

	local text = holder:CreateFontString(nil, "OVERLAY")
	local font = (GameFontNormal and select(1, GameFontNormal:GetFont())) or "Fonts\\FRIZQT__.TTF"
	text:SetFont(font, 16, "OUTLINE")
	text:SetPoint("CENTER", holder, "CENTER", 0, 0)
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	holder.text = text
	holder:Hide()
	button.ControllerSealTimer = holder
	return holder
end

local function PlaceOverlay(button, holder)
	local cooldown = button.cooldown
	local level = (button.GetFrameLevel and button:GetFrameLevel() or 1) + 6
	if cooldown and cooldown.GetFrameLevel then
		level = cooldown:GetFrameLevel() + 3
	end
	holder:SetFrameLevel(level)

	local width = button.GetWidth and button:GetWidth() or 40
	if not width or width < 8 then
		width = 40
	end
	local size = math.floor(width * 0.45)
	if size < 12 then
		size = 12
	elseif size > 28 then
		size = 28
	end
	local font = select(1, holder.text:GetFont()) or "Fonts\\FRIZQT__.TTF"
	holder.text:SetFont(font, size, "OUTLINE")
end

local function PaintButton(button)
	local holder = button.ControllerSealTimer
	local left = Remaining()
	local show = left and ButtonMatches(button) and button:IsVisible()

	if not show then
		if holder then
			holder:Hide()
		end
		return
	end

	holder = holder or EnsureOverlay(button)
	if not holder then
		return
	end
	PlaceOverlay(button, holder)
	holder.text:SetText(tostring(math.ceil(left)))
	if left <= WARN_SECONDS then
		holder.text:SetTextColor(1, 0.25, 0.25, 1)
	else
		holder.text:SetTextColor(1, 0.95, 0.7, 1)
	end
	holder:Show()
end

function core:Refresh()
	for i = 1, #buttons do
		PaintButton(buttons[i])
	end
end

local function OnCast(unit, spellID)
	if unit and unit ~= "player" then
		return
	end
	if Secret(spellID) or type(spellID) ~= "number" then
		return
	end
	local name = SpellName(spellID)
	if not name then
		return
	end
	if not IsTrackedName(name) then
		return
	end
	StartTimer(spellID, name)
end

local function HookMixin()
	if overlayHooked then
		return
	end
	if type(hooksecurefunc) ~= "function" then
		return
	end
	if type(GamepadActionBarStandardButtonMixin) == "table" and GamepadActionBarStandardButtonMixin.UpdateAction then
		hooksecurefunc(GamepadActionBarStandardButtonMixin, "UpdateAction", function()
			core:Refresh()
		end)
		overlayHooked = true
	end
end

local function StatusText()
	local left = Remaining()
	local count = #buttons
	if left and active then
		return string.format("%s, %ds left, %d controller button(s) found.", active.name, math.ceil(left), count)
	end
	return string.format("No seal running. %d controller button(s) found. Cast a seal, or /cst test.", count)
end

local function DumpButtons()
	ScanButtons()
	Print(StatusText())
	local shown = 0
	for i = 1, #buttons do
		local button = buttons[i]
		if button:IsVisible() then
			shown = shown + 1
			local spellID = ButtonSpellID(button)
			local name = spellID and SpellName(spellID) or "empty"
			local frameName = button.GetName and button:GetName() or "(unnamed)"
			Print(string.format("  %s = %s", tostring(frameName), tostring(name)))
		end
	end
	if shown == 0 then
		Print("No visible controller buttons. Enable the controller layout, then /cst debug again.")
	end
end

local function Command(msg)
	EnsureDB()
	msg = msg or ""
	msg = msg:gsub("^%s+", ""):gsub("%s+$", "")
	local command, rest = msg:match("^(%S+)%s*(.*)$")
	command = command and command:lower() or ""

	if command == "" or command == "status" then
		ScanButtons()
		Print(StatusText())
	elseif command == "debug" then
		DumpButtons()
	elseif command == "clear" then
		ClearTimer("Timer cleared.")
	elseif command == "duration" then
		local seconds = tonumber(rest)
		if not seconds or seconds < 1 or seconds > 600 then
			Print("Usage: /cst duration 30")
			return
		end
		ControllerSealTimerDB.duration = seconds
		Print(string.format("Seal duration set to %d seconds. The next cast uses it.", seconds))
	elseif command == "add" then
		local key = Normalize(rest)
		if not key then
			Print("Usage: /cst add Seal of Righteousness")
			return
		end
		ControllerSealTimerDB.extra[key] = true
		Print(string.format("Tracking \"%s\". Casting it starts the timer.", rest))
	elseif command == "remove" then
		local key = Normalize(rest)
		if not key or not ControllerSealTimerDB.extra[key] then
			Print("That name is not in the extra list.")
			return
		end
		ControllerSealTimerDB.extra[key] = nil
		Print("Removed.")
	elseif command == "test" then
		ScanButtons()
		local spellID, name
		if rest ~= "" then
			name = rest
			if C_Spell and C_Spell.GetSpellInfo then
				local info = C_Spell.GetSpellInfo(rest)
				if type(info) == "table" then
					spellID = info.spellID
					name = info.name or rest
				end
			end
		else
			for i = 1, #buttons do
				local button = buttons[i]
				if button:IsVisible() then
					local id = ButtonSpellID(button)
					local buttonName = id and SpellName(id)
					if buttonName then
						spellID = id
						name = buttonName
						break
					end
				end
			end
		end
		if not name then
			Print("No spell found to test. Put a spell on a controller button, or /cst test Seal of Righteousness.")
			return
		end
		StartTimer(spellID or 0, name)
		Print(string.format("Test timer on %s for %d seconds.", name, Duration()))
	else
		Print("Commands: /cst status, debug, test, clear, duration <seconds>, add <spell name>, remove <spell name>")
	end
end

core:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name == ADDON then
			EnsureDB()
			HookMixin()
			ScanButtons()
		elseif name == "Blizzard_GamepadActionBars" then
			HookMixin()
			ScanButtons()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		local isLogin, isReload = ...
		HookMixin()
		ScanButtons()
		if isLogin or isReload then
			active = nil
			core:Refresh()
		end
	elseif event == "PLAYER_DEAD" then
		ClearTimer(nil)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, _, spellID = ...
		OnCast(unit, spellID)
	end
end)

core:SetScript("OnUpdate", function(_, delta)
	elapsedSinceScan = elapsedSinceScan + delta
	if elapsedSinceScan >= 1 then
		elapsedSinceScan = 0
		if #buttons == 0 or not (InCombatLockdown and InCombatLockdown()) then
			ScanButtons()
			HookMixin()
		end
	end
	if active or core.dirty then
		core:Refresh()
		core.dirty = nil
	end
end)

core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_ENTERING_WORLD")
core:RegisterEvent("PLAYER_DEAD")
if core.RegisterUnitEvent then
	core:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
else
	core:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end

SLASH_CONTROLLERSEALTIMER1 = "/cst"
SLASH_CONTROLLERSEALTIMER2 = "/controllersealtimer"
SlashCmdList.CONTROLLERSEALTIMER = Command
