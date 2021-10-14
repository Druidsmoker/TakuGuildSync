--[[-----------------------------------------------------------------------------
Close Button Widget
Graphical Button.
-------------------------------------------------------------------------------]]
local Type, Version = "TakuGuildSyncCloseButton", 1
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

-- Lua APIs
local pairs = pairs

-- WoW APIs
local _G = _G
local PlaySound, CreateFrame, UIParent = PlaySound, CreateFrame, UIParent

--[[-----------------------------------------------------------------------------
Scripts
-------------------------------------------------------------------------------]]
local function Button_OnClick(frame, ...)
	AceGUI:ClearFocus()
	PlaySound(852) -- SOUNDKIT.IG_MAINMENU_OPTION
	frame.obj:Fire("OnClick", ...)
end

--[[-----------------------------------------------------------------------------
Methods
-------------------------------------------------------------------------------]]
local methods = {
	["OnAcquire"] = function(self)
		-- restore default values
		self:SetDisabled(false)
	end,

	-- ["OnRelease"] = nil,

	["SetDisabled"] = function(self, disabled)
		self.disabled = disabled
		if disabled then
			self.frame:Disable()
		else
			self.frame:Enable()
		end
	end
}

--[[-----------------------------------------------------------------------------
Constructor
-------------------------------------------------------------------------------]]
local function Constructor()
	local name = "AceGUI30CloseButton" .. AceGUI:GetNextWidgetNum(Type)
	local frame = CreateFrame("Button", name, UIParent, "UIPanelCloseButton")
	frame:Hide()

	frame:EnableMouse(true)
	frame:SetScript("OnClick", Button_OnClick)

	local widget = {
		frame = frame,
		type  = Type
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end

	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
