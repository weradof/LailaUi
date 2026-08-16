-- ═══════════════════════════════════════════════════════════════
-- MODERN HUD — Fixed Edition v2
-- Coexists with default Roblox UI. No top bar. No CoreGui tampering.
-- "/" opens this HUD's own chatbox. "/w <player> <message>" whispers.
-- ═══════════════════════════════════════════════════════════════
 
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
 
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local SettingsFile = "ModernHUD_Settings.json"
local SavedSettings = {}
local function LoadSettings()
	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(SettingsFile)) end)
	if ok and type(data) == "table" then SavedSettings = data end
end
local function SaveSettings()
	pcall(function() writefile(SettingsFile, HttpService:JSONEncode(SavedSettings)) end)
end
LoadSettings()
 
-- ─── DISABLE DEFAULT ROBLOX CHAT + PLAYERLIST COREGUI ───
-- This is what was actually causing the conflicts: the built-in
-- Chat window and PlayerList were still active underneath our
-- custom GUI and fighting it for "/" and Tab. Turning them off
-- here means our custom panels are the only thing left standing.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
end)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)
 
-- FIXED (root cause of the "/" and whisper bugs): SetCoreGuiEnabled(Chat, ...)
-- only touches the OLD legacy chat GUI. It does NOT disable the modern
-- TextChatService default UI (chat window, input bar, bubble chat). That
-- default input bar was still fully alive the whole time, also listening
-- for "/" and Enter, and its own whisper handling lived in ITS box —
-- not ours. Two chat systems fighting for the same keys is exactly what
-- produced the stray "/" behavior and the "whisper doesn't work" symptom.
-- These three lines are the actual fix for that:
pcall(function() TextChatService.ChatWindowConfiguration.Enabled = false end)
pcall(function() TextChatService.ChatInputBarConfiguration.Enabled = false end)
-- Custom bubble chat enabled below

-- ─── ENABLE THE REAL "VIEW PROFILE" API ───
-- FIXED (the actual bug behind the "Profile Unavailable Here" toast):
-- "PromptViewProfile" was never a real, registered SetCore key — it's not
-- in Roblox's SetCore list anywhere, so that call always failed and always
-- fell into the warning-toast fallback branch, 100% of the time, for
-- everyone. The real, documented API for showing a player's profile from
-- inside an experience is the Avatar Context Menu (ACM): it has to be
-- switched on once here, then opened per-target later (see
-- APProfileBtn's click handler further down). ACM's default "View" option
-- is the actual native profile/appearance inspector.
pcall(function()
	StarterGui:SetCore("AvatarContextMenuEnabled", true)
end)
 
-- ─── CONFIG ───
local Config = {
	ToggleKey = Enum.KeyCode.Tab,
	SettingsKey = Enum.KeyCode.Comma,
	Theme = {
		Background = Color3.fromRGB(10, 10, 16),
		Panel = Color3.fromRGB(20, 20, 32),
		Surface = Color3.fromRGB(32, 34, 50),
		SurfaceHover = Color3.fromRGB(45, 47, 68),
		Accent = Color3.fromRGB(108, 140, 255),
		AccentDeep = Color3.fromRGB(130, 90, 255), -- gradient partner for Accent, used on headers/buttons
		Success = Color3.fromRGB(82, 210, 128),
		Warning = Color3.fromRGB(255, 188, 82),
		Error = Color3.fromRGB(255, 86, 86),
		Info = Color3.fromRGB(86, 160, 255),
		TextPrimary = Color3.fromRGB(250, 250, 254),
		TextSecondary = Color3.fromRGB(178, 178, 200),
		TextMuted = Color3.fromRGB(112, 114, 138),
		Border = Color3.fromRGB(40, 42, 60),
		BorderLight = Color3.fromRGB(64, 66, 90),
	},
	Chat = { MaxMessages = 100, ShowTimestamps = SavedSettings.ShowTimestamps ~= false, Position = SavedSettings.ChatPosition or {X = 15, Y = 52} },
	PlayerList = { ShowPing = true, ShowTeam = true, EntryHeight = 52 },
	UIAnimations = SavedSettings.UIAnimations ~= false,
	Shadows = SavedSettings.Shadows ~= false,
	MasterVolume = SavedSettings.MasterVolume or 100,
	KeyBinds = SavedSettings.KeyBinds or {PlayerList = "Tab", Settings = "Comma", Chat = "Slash"},
}
 
-- ─── ANIMATION UTIL ───
local Animation = {}
Animation._activeTweens = {}
Animation._connections = {}
 
function Animation:_cancelTween(instance)
	local existing = self._activeTweens[instance]
	if existing then
		existing:Cancel()
		self._activeTweens[instance] = nil
	end
end
 
function Animation:_playTween(instance, tweenInfo, properties)
	if not instance or not instance.Parent then return nil end
	self:_cancelTween(instance)
	local tween = TweenService:Create(instance, tweenInfo, properties)
	self._activeTweens[instance] = tween
	tween:Play()
 
	local conn = tween.Completed:Connect(function()
		if self._activeTweens[instance] == tween then
			self._activeTweens[instance] = nil
		end
	end)
 
	if not self._connections[instance] then
		self._connections[instance] = {}
	end
	table.insert(self._connections[instance], conn)
	return tween
end
 
function Animation:Open(panel)
	if not panel or not panel.Parent then return end
	if not panel:GetAttribute("_origPos") then
		panel:SetAttribute("_origPos", panel.Position)
	end
	if not panel:GetAttribute("_origTrans") then
		panel:SetAttribute("_origTrans", panel.BackgroundTransparency)
	end
 
	local origPos = panel:GetAttribute("_origPos")
	local origTrans = panel:GetAttribute("_origTrans")
 
	panel.Visible = true
	panel.BackgroundTransparency = 1
	panel.Position = origPos + UDim2.fromOffset(0, 12)
 
	self:_playTween(panel, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		BackgroundTransparency = origTrans,
		Position = origPos,
	})
end
 
function Animation:Close(panel, onComplete)
	if not panel or not panel.Parent then
		if onComplete then onComplete() end
		return
	end
 
	local origPos = panel:GetAttribute("_origPos")
	local origTrans = panel:GetAttribute("_origTrans")
 
	if not origPos or not origTrans then
		panel.Visible = false
		if onComplete then onComplete() end
		return
	end
 
	local tween = self:_playTween(panel, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
		Position = origPos + UDim2.fromOffset(0, 12),
	})
 
	if tween then
		local conn = tween.Completed:Connect(function()
			if panel and panel.Parent then
				panel.Visible = false
				panel.Position = origPos
				panel.BackgroundTransparency = origTrans
			end
			if onComplete then onComplete() end
		end)
		if not self._connections[panel] then self._connections[panel] = {} end
		table.insert(self._connections[panel], conn)
	else
		panel.Visible = false
		if onComplete then onComplete() end
	end
end
 
function Animation:Hover(instance, isHovering, baseColor)
	if not instance or not instance.Parent then return end
	local base = baseColor or Config.Theme.Surface
	local target = isHovering and base:Lerp(Config.Theme.Accent, 0.06) or base
	if Config.UIAnimations then
		self:_playTween(instance, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = target})
	else
		instance.BackgroundColor3 = target
	end
end
 
function Animation:Fade(instance, targetTransparency, duration)
	if not instance or not instance.Parent then return end
	if Config.UIAnimations then
		self:_playTween(instance, TweenInfo.new(duration or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = targetTransparency})
	else
		instance.BackgroundTransparency = targetTransparency
	end
end
 
function Animation:FadeText(instance, targetTransparency, duration)
	if not instance or not instance.Parent then return end
	if Config.UIAnimations then
		self:_playTween(instance, TweenInfo.new(duration or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = targetTransparency})
	else
		instance.TextTransparency = targetTransparency
	end
end
 
function Animation:Scale(instance, targetSize, duration)
	if not instance or not instance.Parent then return end
	if Config.UIAnimations then
		self:_playTween(instance, TweenInfo.new(duration or 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = targetSize})
	else
		instance.Size = targetSize
	end
end
 
function Animation:Clean(instance)
	self:_cancelTween(instance)
	local conns = self._connections[instance]
	if conns then
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		self._connections[instance] = nil
	end
end
 
-- ─── UI COMPONENTS ───
local UI = {}
 
function UI.Corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = parent
	return c
end

-- Diagonal accent gradient (Accent -> AccentDeep). Used sparingly on
-- headers, active states, and primary buttons to give the flat theme
-- some depth instead of everything being one solid slab of color.
function UI.AccentGradient(parent, rotation)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Config.Theme.Accent),
		ColorSequenceKeypoint.new(1, Config.Theme.AccentDeep),
	})
	g.Rotation = rotation or 100
	g.Parent = parent
	return g
end

-- Subtle vertical panel gradient (Panel -> Background) so big flat
-- frames read as slightly lit from the top rather than one flat fill.
function UI.PanelGradient(parent, rotation)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.new(0.82, 0.82, 0.86)),
	})
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end
 
function UI.Stroke(parent, col, thick)
	local s = Instance.new("UIStroke")
	s.Color = col or Config.Theme.Border
	s.Thickness = thick or 1
	s.Transparency = 0.3
	s.Parent = parent
	return s
end
 
function UI.Shadow(parent, off)
	local sh = Instance.new("ImageLabel")
	sh.Name = "Shadow"
	sh.AnchorPoint = Vector2.new(0.5, 0.5)
	sh.BackgroundTransparency = 1
	sh.Position = UDim2.fromScale(0.5, 0.5)
	sh.Size = UDim2.new(1, off or 24, 1, off or 24)
	sh.Image = "rbxassetid://6015897843"
	sh.ImageColor3 = Color3.new(0, 0, 0)
	sh.ImageTransparency = 0.7
	sh.ScaleType = Enum.ScaleType.Slice
	sh.SliceCenter = Rect.new(49, 49, 450, 450)
	sh.ZIndex = parent.ZIndex - 1
	sh.Parent = parent
	sh.Visible = Config.Shadows
	return sh
end
 
function UI.CreateButton(props)
	local button = Instance.new("TextButton")
	button.Size = props.Size
	button.Position = props.Position
	button.BackgroundColor3 = Config.Theme.Surface
	button.BackgroundTransparency = 0.2
	button.Text = props.Text or ""
	button.TextColor3 = Config.Theme.TextPrimary
	button.TextSize = 15
	button.Font = Enum.Font.GothamMedium
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Parent = props.Parent
 
	UI.Corner(button, 8)
	UI.Stroke(button)
 
	local conns = {}
	table.insert(conns, button.MouseEnter:Connect(function()
		Animation:Hover(button, true, Config.Theme.Surface)
	end))
	table.insert(conns, button.MouseLeave:Connect(function()
		Animation:Hover(button, false, Config.Theme.Surface)
	end))
	table.insert(conns, button.MouseButton1Down:Connect(function()
		local base = button.BackgroundColor3
		Animation:_playTween(button, TweenInfo.new(0.04), {BackgroundColor3 = base:Lerp(Color3.new(0.35,0.35,0.45), 0.4)})
		task.delay(0.06, function()
			if button and button.Parent then
				Animation:_playTween(button, TweenInfo.new(0.1), {BackgroundColor3 = base})
			end
		end)
	end))
 
	if props.OnClick then
		table.insert(conns, button.MouseButton1Click:Connect(function()
			if button.Active ~= false then props.OnClick() end
		end))
	end
 
	return {
		Instance = button,
		SetEnabled = function(_, enabled)
			button.Active = enabled
			button.TextColor3 = enabled and Config.Theme.TextPrimary or Config.Theme.TextMuted
		end,
		SetText = function(_, text) button.Text = text end,
		Destroy = function()
			for _, c in ipairs(conns) do c:Disconnect() end
			Animation:Clean(button)
			button:Destroy()
		end,
	}
end
 
function UI.CreateLabel(props)
	local label = Instance.new("TextLabel")
	label.Size = props.Size
	label.Position = props.Position
	label.BackgroundTransparency = 1
	label.Text = props.Text
	label.TextColor3 = Config.Theme.TextPrimary
	label.TextSize = 14
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = props.Parent
	return {
		Instance = label,
		Destroy = function() label:Destroy() end,
	}
end
 
function UI.CreateToggle(props)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 34)
	container.BackgroundTransparency = 1
	container.Parent = props.Parent
 
	local label = Instance.new("TextLabel", container)
	label.Size = UDim2.new(1, -60, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = props.Text
	label.TextColor3 = Config.Theme.TextPrimary
	label.TextSize = 14
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
 
	local track = Instance.new("Frame", container)
	track.Size = UDim2.fromOffset(46, 24)
	track.Position = UDim2.new(1, -46, 0.5, -12)
	track.BackgroundColor3 = Config.Theme.Surface
	track.BorderSizePixel = 0
	UI.Corner(track, 12)
 
	local knob = Instance.new("Frame", track)
	knob.Size = UDim2.fromOffset(20, 20)
	knob.Position = UDim2.fromOffset(2, 2)
	knob.BackgroundColor3 = Config.Theme.TextPrimary
	knob.BorderSizePixel = 0
	UI.Corner(knob, 10)
 
	local value = props.DefaultValue or false
	local conns = {}
 
	local function updateVisual()
		if value then
			track.BackgroundColor3 = Config.Theme.Accent
			Animation:_playTween(knob, TweenInfo.new(0.1), {Position = UDim2.new(1, -22, 0, 2)})
		else
			track.BackgroundColor3 = Config.Theme.Surface
			Animation:_playTween(knob, TweenInfo.new(0.1), {Position = UDim2.fromOffset(2, 2)})
		end
	end
 
	updateVisual()
 
	local obj = {
		Instance = container,
		SetValue = function(_, newValue)
			value = newValue
			updateVisual()
			if props.OnChanged then props.OnChanged(value) end
		end,
		Destroy = function()
			for _, c in ipairs(conns) do c:Disconnect() end
			container:Destroy()
		end,
	}
 
	table.insert(conns, container.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			obj:SetValue(not value)
		end
	end))
 
	return obj
end
 
function UI.CreateSlider(props)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 50)
	container.BackgroundTransparency = 1
	container.Parent = props.Parent
 
	local label = Instance.new("TextLabel", container)
	label.Size = UDim2.new(1, -50, 0, 20)
	label.BackgroundTransparency = 1
	label.Text = props.Text
	label.TextColor3 = Config.Theme.TextPrimary
	label.TextSize = 14
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
 
	local valueLabel = Instance.new("TextLabel", container)
	valueLabel.Size = UDim2.fromOffset(50, 20)
	valueLabel.Position = UDim2.new(1, -50, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = tostring(props.DefaultValue)
	valueLabel.TextColor3 = Config.Theme.TextSecondary
	valueLabel.TextSize = 14
	valueLabel.Font = Enum.Font.GothamMedium
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
 
	local track = Instance.new("Frame", container)
	track.Size = UDim2.new(1, 0, 0, 6)
	track.Position = UDim2.fromOffset(0, 34)
	track.BackgroundColor3 = Config.Theme.Surface
	track.BorderSizePixel = 0
	UI.Corner(track, 3)
 
	local fill = Instance.new("Frame", track)
	fill.Size = UDim2.fromScale(0.5, 1)
	fill.BackgroundColor3 = Config.Theme.Accent
	fill.BorderSizePixel = 0
	UI.Corner(fill, 3)
 
	local knob = Instance.new("Frame", track)
	knob.Size = UDim2.fromOffset(16, 16)
	knob.Position = UDim2.new(0.5, -8, 0.5, -8)
	knob.BackgroundColor3 = Config.Theme.TextPrimary
	knob.BorderSizePixel = 0
	UI.Corner(knob, 8)
 
	local min, max = props.Min, props.Max
	local currentValue = math.clamp(props.DefaultValue, min, max)
	local dragging = false
	local conns = {}
 
	local function setFromX(x)
		local abs = track.AbsolutePosition.X
		local size = track.AbsoluteSize.X
		local ratio = math.clamp((x - abs) / size, 0, 1)
		currentValue = min + (max - min) * ratio
		fill.Size = UDim2.fromScale(ratio, 1)
		knob.Position = UDim2.new(ratio, -8, 0.5, -8)
		valueLabel.Text = string.format("%.0f", currentValue)
		if props.OnChanged then props.OnChanged(currentValue) end
	end
 
	local function updateVisual()
		local ratio = (currentValue - min) / (max - min)
		fill.Size = UDim2.fromScale(ratio, 1)
		knob.Position = UDim2.new(ratio, -8, 0.5, -8)
		valueLabel.Text = string.format("%.0f", currentValue)
	end
 
	updateVisual()
 
	-- FIXED: was UserInputService.InputBegan with an `if gp then return end`
	-- guard. Once SetFrame.Active was turned on (to stop background clicks
	-- closing the modal), every click inside the modal got marked as "game
	-- processed", so that guard silently ate every slider click. Using the
	-- container's own InputBegan instead isn't affected by that flag, and
	-- it already only fires when the input actually lands on this container.
	table.insert(conns, container.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			local pos = UserInputService:GetMouseLocation()
			setFromX(pos.X)
		end
	end))
 
	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(UserInputService:GetMouseLocation().X)
		end
	end))
 
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
 
	return {
		Instance = container,
		SetValue = function(_, val)
			currentValue = math.clamp(val, min, max)
			updateVisual()
			if props.OnChanged then props.OnChanged(currentValue) end
		end,
		Destroy = function()
			for _, c in ipairs(conns) do c:Disconnect() end
			container:Destroy()
		end,
	}
end
 
function UI.CreatePlayerEntry(props)
	local entry = Instance.new("Frame")
	entry.Size = UDim2.new(1, -6, 0, Config.PlayerList.EntryHeight)
	entry.BackgroundColor3 = Config.Theme.Surface
	entry.BackgroundTransparency = 0.5
	entry.BorderSizePixel = 0
	entry.Parent = props.Parent
	UI.Corner(entry, 10)

	-- Left accent strip, hidden until hover — gives clicking a row a
	-- clearer "this is interactive" affordance than a flat color shift alone.
	local accentStrip = Instance.new("Frame", entry)
	accentStrip.Size = UDim2.new(0, 3, 1, -12)
	accentStrip.Position = UDim2.new(0, 0, 0, 6)
	accentStrip.BackgroundColor3 = Color3.new(1, 1, 1)
	accentStrip.BackgroundTransparency = 1
	accentStrip.BorderSizePixel = 0
	UI.Corner(accentStrip, 2)
	UI.AccentGradient(accentStrip, 90)
 
	local thumb = Instance.new("ImageLabel", entry)
	thumb.Size = UDim2.fromOffset(34, 34)
	thumb.Position = UDim2.fromOffset(8, 6)
	thumb.BackgroundColor3 = Config.Theme.Background
	thumb.BorderSizePixel = 0
	UI.Corner(thumb, 17)
 
	local name = Instance.new("TextLabel", entry)
	name.Size = UDim2.new(0, 120, 0, 20)
	name.Position = UDim2.fromOffset(50, 4)
	name.BackgroundTransparency = 1
	name.TextColor3 = Config.Theme.TextPrimary
	name.TextSize = 14
	name.Font = Enum.Font.GothamBold
	name.TextXAlignment = Enum.TextXAlignment.Left
 
	local user = Instance.new("TextLabel", entry)
	user.Size = UDim2.new(0, 120, 0, 16)
	user.Position = UDim2.fromOffset(50, 25)
	user.BackgroundTransparency = 1
	user.TextColor3 = Config.Theme.TextMuted
	user.TextSize = 12
	user.Font = Enum.Font.Gotham
	user.TextXAlignment = Enum.TextXAlignment.Left
 
	local statsF = Instance.new("Frame", entry)
	statsF.Size = UDim2.new(0, 150, 1, 0)
	statsF.Position = UDim2.new(1, -156, 0, 0)
	statsF.BackgroundTransparency = 1
	local sl = Instance.new("UIListLayout", statsF)
	sl.FillDirection = Enum.FillDirection.Horizontal
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	sl.VerticalAlignment = Enum.VerticalAlignment.Center
	sl.Padding = UDim.new(0, 8)
 
	local conns = {}
	local baseColor = Config.Theme.Surface
 
	table.insert(conns, entry.MouseEnter:Connect(function()
		Animation:Hover(entry, true, baseColor)
		Animation:Fade(accentStrip, 0, 0.12)
	end))
	table.insert(conns, entry.MouseLeave:Connect(function()
		Animation:Hover(entry, false, baseColor)
		Animation:Fade(accentStrip, 1, 0.12)
	end))
 
	local obj = {
		Instance = entry,
		Update = function(_, data)
			name.Text = data.DisplayName
			user.Text = "@" .. data.Username
			if data.Thumbnail and data.Thumbnail ~= "" then
				thumb.Image = data.Thumbnail
			end
 
			for _, c in ipairs(statsF:GetChildren()) do
				if c:IsA("TextLabel") then c:Destroy() end
			end
 
			if data.Leaderstats and next(data.Leaderstats) then
				for statName, v in pairs(data.Leaderstats) do
					local l = Instance.new("TextLabel", statsF)
					l.Size = UDim2.fromOffset(80, 18)
					l.BackgroundTransparency = 1
					l.Text = statName .. ": " .. tostring(v)
					l.TextColor3 = Config.Theme.TextSecondary
					l.TextSize = 12
					l.Font = Enum.Font.GothamMedium
					l.TextXAlignment = Enum.TextXAlignment.Right
				end
			elseif data.Team and Config.PlayerList.ShowTeam then
				local l = Instance.new("TextLabel", statsF)
				l.Size = UDim2.fromOffset(80, 18)
				l.BackgroundTransparency = 1
				l.Text = data.Team.Name
				l.TextColor3 = data.Team.TeamColor.Color
				l.TextSize = 12
				l.Font = Enum.Font.GothamBold
				l.TextXAlignment = Enum.TextXAlignment.Right
			end
 

		end,
		Destroy = function()
			for _, c in ipairs(conns) do c:Disconnect() end
			Animation:Clean(entry)
			entry:Destroy()
		end,
	}
 
	return obj
end
 
function UI.CreateNotification(props)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 340, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Config.Theme.Panel
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Parent = props.Parent
	UI.Corner(frame, 10)
	UI.Stroke(frame, Config.Theme.BorderLight, 1)
	UI.Shadow(frame, 24)
 
	local accent = Instance.new("Frame", frame)
	accent.Size = UDim2.new(0, 3, 1, 0)
	accent.BorderSizePixel = 0
 
	local colors = {Info = Config.Theme.Info, Success = Config.Theme.Success, Warning = Config.Theme.Warning, Error = Config.Theme.Error}
	accent.BackgroundColor3 = colors[props.Type] or Config.Theme.Info
 
	local pad = Instance.new("UIPadding", frame)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
 
	local title = Instance.new("TextLabel", frame)
	title.Size = UDim2.new(1, -28, 0, 20)
	title.BackgroundTransparency = 1
	title.Text = props.Title
	title.TextColor3 = Config.Theme.TextPrimary
	title.TextSize = 15
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
 
	local desc = Instance.new("TextLabel", frame)
	desc.Size = UDim2.new(1, -28, 0, 0)
	desc.Position = UDim2.fromOffset(16, 36)
	desc.BackgroundTransparency = 1
	desc.Text = props.Description
	desc.TextColor3 = Config.Theme.TextSecondary
	desc.TextSize = 13
	desc.Font = Enum.Font.Gotham
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextWrapped = true
	desc.AutomaticSize = Enum.AutomaticSize.Y
 
	local close = Instance.new("TextButton", frame)
	close.Size = UDim2.fromOffset(22, 22)
	close.Position = UDim2.new(1, -30, 0, 10)
	close.BackgroundTransparency = 1
	close.Text = "×"
	close.TextColor3 = Config.Theme.TextMuted
	close.TextSize = 20
	close.Font = Enum.Font.GothamBold
 
	local obj = {
		Instance = frame,
		Dismiss = function() frame:Destroy() end,
		Destroy = function() frame:Destroy() end,
	}
 
	close.MouseButton1Click:Connect(function() obj:Dismiss() end)
	return obj
end
 
function UI.CreateWipBadge(props)
	local badge = Instance.new("Frame")
	badge.Size = UDim2.fromOffset(36, 18)
	badge.BackgroundColor3 = Config.Theme.Warning
	badge.BorderSizePixel = 0
	badge.Parent = props.Parent
	UI.Corner(badge, 4)
 
	local label = Instance.new("TextLabel", badge)
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "WIP"
	label.TextColor3 = Config.Theme.Background
	label.TextSize = 10
	label.Font = Enum.Font.GothamBold
	return badge
end
 
-- ─── SCREEN GUI ───
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ModernHUD"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 10
ScreenGui.ScreenInsets = Enum.ScreenInsets.None
ScreenGui.Parent = PlayerGui
 
-- ═══════════════════════════════════════════════════════════════
-- PLAYER LIST (Bottom Right — avoids default top-right player list)
-- ═══════════════════════════════════════════════════════════════
local PLFrame = Instance.new("Frame")
PLFrame.Name = "PlayerList"
PLFrame.Size = UDim2.new(0, 280, 0, 320)
PLFrame.Position = UDim2.new(1, -300, 1, -340)
PLFrame.BackgroundColor3 = Config.Theme.Background
PLFrame.BackgroundTransparency = 0.12
PLFrame.BorderSizePixel = 0
PLFrame.Visible = false
PLFrame.ZIndex = 5
PLFrame:SetAttribute("origTrans", 0.12)
PLFrame.Parent = ScreenGui
UI.Corner(PLFrame, 12)
UI.Stroke(PLFrame, Config.Theme.BorderLight, 1)
UI.Shadow(PLFrame, 28)
UI.PanelGradient(PLFrame, 90)
 
local PLHeader = Instance.new("Frame", PLFrame)
PLHeader.Size = UDim2.new(1, 0, 0, 44)
PLHeader.BackgroundColor3 = Config.Theme.Panel
PLHeader.BackgroundTransparency = 0.3
PLHeader.BorderSizePixel = 0
UI.Corner(PLHeader, 12)

-- Slim accent-gradient underline so the header reads as a distinct,
-- branded strip instead of just a slightly-lighter grey block.
local PLHeaderAccent = Instance.new("Frame", PLHeader)
PLHeaderAccent.Size = UDim2.new(1, 0, 0, 2)
PLHeaderAccent.Position = UDim2.new(0, 0, 1, -2)
PLHeaderAccent.BackgroundColor3 = Color3.new(1, 1, 1)
PLHeaderAccent.BorderSizePixel = 0
UI.AccentGradient(PLHeaderAccent, 0)
 
local PLTitle = Instance.new("TextLabel", PLHeader)
PLTitle.Size = UDim2.new(1, -70, 1, 0)
PLTitle.Position = UDim2.fromOffset(14, 0)
PLTitle.BackgroundTransparency = 1
PLTitle.Text = "Players"
PLTitle.TextColor3 = Config.Theme.TextPrimary
PLTitle.TextSize = 15
PLTitle.Font = Enum.Font.GothamBold
PLTitle.TextXAlignment = Enum.TextXAlignment.Left
 
local PLCount = Instance.new("TextLabel", PLHeader)
PLCount.Size = UDim2.fromOffset(50, 44)
PLCount.Position = UDim2.new(1, -60, 0, 0)
PLCount.BackgroundTransparency = 1
PLCount.Text = "0"
PLCount.TextColor3 = Config.Theme.TextMuted
PLCount.TextSize = 13
PLCount.Font = Enum.Font.Gotham
PLCount.TextXAlignment = Enum.TextXAlignment.Right
 
local PLScroll = Instance.new("ScrollingFrame", PLFrame)
PLScroll.Size = UDim2.new(1, -10, 1, -54)
PLScroll.Position = UDim2.fromOffset(5, 50)
PLScroll.BackgroundTransparency = 1
PLScroll.BorderSizePixel = 0
PLScroll.ScrollBarThickness = 3
PLScroll.ScrollBarImageColor3 = Config.Theme.Border
PLScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
PLScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UIListLayout", PLScroll).Padding = UDim.new(0, 5)
 
-- Player list logic
local PlayerEntries = {}
local ThumbCache = {}

-- Forward declarations: the player-list click handler (inside AddPlayer,
-- defined further below) needs to reference the avatar/friend panel, but
-- that panel is built further down the file (after the Notifications
-- section, since it reuses ShowNotification). Declaring the locals here
-- and assigning them later lets AddPlayer's closures capture the right
-- upvalue instead of silently falling through to a nil global.
local OpenAvatarPanel
local CloseAvatarPanel
 
local function GetPing(plr)
	if plr ~= LocalPlayer then return nil end
	local ok, p = pcall(function() return plr:GetNetworkPing() end)
	return ok and p and math.floor(p * 1000) or nil
end
 
local function GetThumb(id, cb)
	if ThumbCache[id] then cb(ThumbCache[id]) return end
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(id, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		if ok and url then ThumbCache[id] = url cb(url) else cb("") end
	end)
end
 
local function AddPlayer(plr)
	if PlayerEntries[plr] then return end
	local entry = UI.CreatePlayerEntry({Parent = PLScroll})
	PlayerEntries[plr] = entry
 
	local conns = {}

	-- Click anywhere on this player's row to open the avatar/friend panel.
	table.insert(conns, entry.Instance.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if OpenAvatarPanel then OpenAvatarPanel(plr) end
		end
	end))

	local function Refresh()
		if not entry.Instance or not entry.Instance.Parent then return end
 
		local stats = {}
		local ls = plr:FindFirstChild("leaderstats")
		if ls then
			for _, c in ipairs(ls:GetChildren()) do
				if c:IsA("IntValue") or c:IsA("NumberValue") then stats[c.Name] = c.Value end
			end
		end
 
		entry:Update({
			DisplayName = plr.DisplayName,
			Username = plr.Name,
			Leaderstats = next(stats) and stats or nil,
			Team = plr.Team,
		})
	end
 
	GetThumb(plr.UserId, function(url)
		if entry.Instance and entry.Instance.Parent then
			entry:Update({DisplayName = plr.DisplayName, Username = plr.Name, Thumbnail = url})
		end
	end)
 
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		for _, c in ipairs(ls:GetChildren()) do
			if c:IsA("IntValue") or c:IsA("NumberValue") then
				table.insert(conns, c:GetPropertyChangedSignal("Value"):Connect(Refresh))
			end
		end
		table.insert(conns, ls.ChildAdded:Connect(function(c)
			if c:IsA("IntValue") or c:IsA("NumberValue") then
				table.insert(conns, c:GetPropertyChangedSignal("Value"):Connect(Refresh))
				Refresh()
			end
		end))
		table.insert(conns, ls.ChildRemoved:Connect(Refresh))
	end
 
	-- LATE LEADERSTATS DETECTION
	table.insert(conns, plr.ChildAdded:Connect(function(child)
		if child.Name == "leaderstats" and child:IsA("Folder") then
			for _, c in ipairs(child:GetChildren()) do
				if c:IsA("IntValue") or c:IsA("NumberValue") then
					table.insert(conns, c:GetPropertyChangedSignal("Value"):Connect(Refresh))
				end
			end
			table.insert(conns, child.ChildAdded:Connect(function(c)
				if c:IsA("IntValue") or c:IsA("NumberValue") then
					table.insert(conns, c:GetPropertyChangedSignal("Value"):Connect(Refresh))
					Refresh()
				end
			end))
			table.insert(conns, child.ChildRemoved:Connect(Refresh))
			Refresh()
		end
	end))
 
	table.insert(conns, plr:GetPropertyChangedSignal("Team"):Connect(Refresh))
	Refresh()

	-- Click to open detail panel
	PlayerEntries[plr] = {Frame = entry, Connections = conns}
end
 
local function RemovePlayer(plr)
	local d = PlayerEntries[plr]
	if not d then return end
	if d.Frame then d.Frame:Destroy() end
	if d.Connections then
		for _, c in ipairs(d.Connections) do c:Disconnect() end
	end
	PlayerEntries[plr] = nil
	if CloseAvatarPanel then CloseAvatarPanel(plr) end
end
 
for _, p in ipairs(Players:GetPlayers()) do AddPlayer(p) end
Players.PlayerAdded:Connect(function(p)
	AddPlayer(p)
	PLCount.Text = tostring(#Players:GetPlayers())
end)
Players.PlayerRemoving:Connect(function(p)
	RemovePlayer(p)
	PLCount.Text = tostring(#Players:GetPlayers() - 1)
end)
PLCount.Text = tostring(#Players:GetPlayers())
 
local PLVisible = false
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Config.ToggleKey then
		PLVisible = not PLVisible
		if PLVisible then Animation:Open(PLFrame) else Animation:Close(PLFrame) end
	end
end)

-- ═══════════════════════════════════════════════════════════════
-- ═══════════════════════════════════════════════════════════════
-- CHAT (Top Left — the ONLY chat now that CoreGui Chat + TextChatService's
-- default UI are both disabled)
-- ═══════════════════════════════════════════════════════════════
local ChatFrame = Instance.new("Frame")
ChatFrame.Name = "Chat"
ChatFrame.Size = UDim2.new(0, 400, 0, 260)
ChatFrame.Position = UDim2.new(0, Config.Chat.Position.X, 0, Config.Chat.Position.Y)
ChatFrame.BackgroundColor3 = Config.Theme.Background
ChatFrame.BackgroundTransparency = 0.12
ChatFrame.BorderSizePixel = 0
ChatFrame.ZIndex = 5
ChatFrame:SetAttribute("origTrans", 0.12)
ChatFrame.Parent = ScreenGui
UI.Corner(ChatFrame, 12)
UI.Stroke(ChatFrame, Config.Theme.BorderLight, 1)
UI.Shadow(ChatFrame, 28)
UI.PanelGradient(ChatFrame, 90)
 
local ChatHeader = Instance.new("Frame", ChatFrame)
ChatHeader.Name = "Header"
ChatHeader.Size = UDim2.new(1, 0, 0, 28)
ChatHeader.BackgroundColor3 = Config.Theme.Panel
ChatHeader.BackgroundTransparency = 0.3
ChatHeader.BorderSizePixel = 0
UI.Corner(ChatHeader, 12)

local ChatHeaderAccent = Instance.new("Frame", ChatHeader)
ChatHeaderAccent.Size = UDim2.new(1, 0, 0, 2)
ChatHeaderAccent.Position = UDim2.new(0, 0, 1, -2)
ChatHeaderAccent.BackgroundColor3 = Color3.new(1, 1, 1)
ChatHeaderAccent.BorderSizePixel = 0
UI.AccentGradient(ChatHeaderAccent, 0)

local ChatTitle = Instance.new("TextLabel", ChatHeader)
ChatTitle.Size = UDim2.new(1, -40, 1, 0)
ChatTitle.Position = UDim2.fromOffset(10, 0)
ChatTitle.BackgroundTransparency = 1
ChatTitle.Text = "Chat"
ChatTitle.TextColor3 = Config.Theme.TextPrimary
ChatTitle.TextSize = 13
ChatTitle.Font = Enum.Font.GothamBold
ChatTitle.TextXAlignment = Enum.TextXAlignment.Left

local ChatMinBtn = Instance.new("TextButton", ChatHeader)
ChatMinBtn.Name = "Minimize"
ChatMinBtn.Size = UDim2.fromOffset(22, 22)
ChatMinBtn.Position = UDim2.new(1, -28, 0, 3)
ChatMinBtn.BackgroundTransparency = 1
ChatMinBtn.Text = "−"
ChatMinBtn.TextColor3 = Config.Theme.TextMuted
ChatMinBtn.TextSize = 18
ChatMinBtn.Font = Enum.Font.GothamBold

-- Drag-to-move chat
local ChatDragging = false
local ChatDragOffset = Vector2.new(0, 0)

ChatHeader.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		ChatDragging = true
		ChatDragOffset = Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(ChatFrame.AbsolutePosition.X, ChatFrame.AbsolutePosition.Y)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if ChatDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local newX = input.Position.X - ChatDragOffset.X
		local newY = input.Position.Y - ChatDragOffset.Y
		newX = math.clamp(newX, 0, workspace.CurrentCamera.ViewportSize.X - ChatFrame.AbsoluteSize.X)
		newY = math.clamp(newY, 36, workspace.CurrentCamera.ViewportSize.Y - ChatFrame.AbsoluteSize.Y)
		ChatFrame.Position = UDim2.fromOffset(newX, newY)
		ChatToggleBtn.Position = UDim2.fromOffset(newX, newY)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if ChatDragging then
			ChatDragging = false
			Config.Chat.Position.X = ChatFrame.AbsolutePosition.X
			Config.Chat.Position.Y = ChatFrame.AbsolutePosition.Y
			SavedSettings.ChatPosition = {X = Config.Chat.Position.X, Y = Config.Chat.Position.Y}
			SaveSettings()
		end
	end
end)

local ChatScroll = Instance.new("ScrollingFrame", ChatFrame)
ChatScroll.Size = UDim2.new(1, -10, 1, -82)
ChatScroll.Position = UDim2.fromOffset(5, 33)
ChatScroll.BackgroundTransparency = 1
ChatScroll.BorderSizePixel = 0
ChatScroll.ScrollBarThickness = 3
ChatScroll.ScrollBarImageColor3 = Config.Theme.Border
ChatScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
ChatScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UIListLayout", ChatScroll).Padding = UDim.new(0, 5)
 
local ChatInputFrame = Instance.new("Frame", ChatFrame)
ChatInputFrame.Size = UDim2.new(1, -10, 0, 38)
ChatInputFrame.Position = UDim2.new(0, 5, 1, -46)
ChatInputFrame.BackgroundColor3 = Config.Theme.Surface
ChatInputFrame.BackgroundTransparency = 0.3
ChatInputFrame.BorderSizePixel = 0
UI.Corner(ChatInputFrame, 8)
 
local ChatInput = Instance.new("TextBox", ChatInputFrame)
ChatInput.Size = UDim2.new(1, -14, 1, 0)
ChatInput.Position = UDim2.fromOffset(7, 0)
ChatInput.BackgroundTransparency = 1
ChatInput.Text = ""
ChatInput.PlaceholderText = "Enter to chat, /w <player> <msg> to whisper..."
ChatInput.TextColor3 = Config.Theme.TextPrimary
ChatInput.PlaceholderColor3 = Config.Theme.TextMuted
ChatInput.TextSize = 13
ChatInput.Font = Enum.Font.Gotham
ChatInput.ClearTextOnFocus = false
 
-- Chat toggle button
local ChatToggleBtn = Instance.new("TextButton")
ChatToggleBtn.Name = "ChatToggle"
ChatToggleBtn.Size = UDim2.fromOffset(70, 28)
ChatToggleBtn.Position = UDim2.new(0, Config.Chat.Position.X, 0, Config.Chat.Position.Y)
ChatToggleBtn.BackgroundColor3 = Config.Theme.Background
ChatToggleBtn.BackgroundTransparency = 0.15
ChatToggleBtn.Text = "💬 Chat"
ChatToggleBtn.TextColor3 = Config.Theme.TextPrimary
ChatToggleBtn.TextSize = 12
ChatToggleBtn.Font = Enum.Font.GothamBold
ChatToggleBtn.BorderSizePixel = 0
ChatToggleBtn.ZIndex = 5
ChatToggleBtn.Visible = false
ChatToggleBtn.Parent = ScreenGui
UI.Corner(ChatToggleBtn, 8)
UI.Stroke(ChatToggleBtn, Config.Theme.BorderLight, 1)

ChatToggleBtn.MouseEnter:Connect(function()
	TweenService:Create(ChatToggleBtn, TweenInfo.new(0.1), {BackgroundColor3 = Config.Theme.Surface}):Play()
end)
ChatToggleBtn.MouseLeave:Connect(function()
	TweenService:Create(ChatToggleBtn, TweenInfo.new(0.1), {BackgroundColor3 = Config.Theme.Background}):Play()
end)

local ChatVisible = true
local function ToggleChat()
	ChatVisible = not ChatVisible
	if ChatVisible then
		ChatFrame.Visible = true
		ChatToggleBtn.Visible = false
		Animation:Open(ChatFrame)
	else
		Animation:Close(ChatFrame, function()
			ChatToggleBtn.Visible = true
			ChatToggleBtn.Position = UDim2.new(0, Config.Chat.Position.X, 0, Config.Chat.Position.Y)
		end)
	end
end

ChatMinBtn.MouseButton1Click:Connect(ToggleChat)
ChatToggleBtn.MouseButton1Click:Connect(ToggleChat)

local ChatEnabled = (TextChatService.ChatVersion == Enum.ChatVersion.TextChatService)
local Messages = {}
 
-- ─── CHAT HELPERS ───
local function ColorToHex(c)
	return string.format("%02X%02X%02X",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5))
end
 
-- FIXED/ADDED: raw player/message text was being dropped straight into a
-- RichText label. Anything containing "<", ">" or "&" (a name someone
-- managed to sneak past the filter, a message that happens to contain
-- those characters, etc.) would either break the label's formatting or,
-- worse, let someone forge fake colored/bold text. Everything user-supplied
-- now goes through this before it touches a RichText label.
local function EscapeRichText(s)
	s = tostring(s or "")
	s = s:gsub("&", "&amp;")
	s = s:gsub("<", "&lt;")
	s = s:gsub(">", "&gt;")
	s = s:gsub('"', "&quot;")
	return s
end
 
-- ADDED: pulled the "make a line, fade it in, trim history, autoscroll"
-- logic out of the MessageReceived handler so whispers/system messages
-- can reuse it instead of duplicating (and risking drifting out of sync
-- with) that logic.
--
-- FIXED (chat "delay"): this used to set TextTransparency = 1 and then
-- tween it to 0 over 0.15s, and separately used a single task.defer to
-- move the scrollbar. Two problems stacked on top of each other:
--  1) AutomaticSize needs a layout pass to know the label's real height
--     before AutomaticCanvasSize on the ScrollingFrame can grow to fit
--     it — a single task.defer (one frame) isn't reliably enough time
--     for that chain to settle, so the frame would sometimes snap/scroll
--     late, reading as "lag".
--  2) On top of that, the 0.15s opacity tween itself is a real, visible
--     delay before the text is fully readable — which is why it felt
--     laggy here but not in the bubble chat above characters' heads
--     (bubbles pop in over the same-ish duration, but there's no dense
--     block of scrollback shifting underneath them at the same time).
-- Fix: show text at full opacity immediately (no fade-in) and wait an
-- extra frame before snapping the scrollbar so AutomaticCanvasSize has
-- actually caught up.
local function AppendChatLine(richText)
	local row = Instance.new("Frame", ChatScroll)
	row.BackgroundColor3 = Config.Theme.Surface
	row.BackgroundTransparency = 0.82
	row.Size = UDim2.new(1, -6, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BorderSizePixel = 0
	UI.Corner(row, 6)

	local pad = Instance.new("UIPadding", row)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)

	local lbl = Instance.new("TextLabel", row)
	lbl.Size = UDim2.new(1, 0, 0, 16)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Config.Theme.TextPrimary
	lbl.TextSize = 14
	lbl.Font = Enum.Font.Gotham
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextWrapped = true
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.RichText = true
	lbl.Text = richText
	-- No fade — text appears instantly, matching a normal chat feed.

	table.insert(Messages, row)
	while #Messages > Config.Chat.MaxMessages do
		local old = table.remove(Messages, 1)
		if old then old:Destroy() end
	end

	-- Wait two frames: one for this label's AutomaticSize to resolve,
	-- one more for the ScrollingFrame's AutomaticCanvasSize to catch up
	-- to that new content height — then snap to bottom.
	task.defer(function()
		task.defer(function()
			if ChatScroll and ChatScroll.Parent then
				ChatScroll.CanvasPosition = Vector2.new(0, math.max(0, ChatScroll.AbsoluteCanvasSize.Y - ChatScroll.AbsoluteWindowSize.Y))
			end
		end)
	end)
end
 
-- ─── WHISPER ───
-- Roblox's "/w" and "/whisper" are handled by RBXWhisperCommand, which is
-- hardcoded into TextChatService — it can't even be turned off, and it
-- works purely off ch:SendAsync(text), with no custom command handling
-- and no server script needed on our end. Sending "/w Bob hey" through
-- SendAsync (below, in FocusLost) is all that's required to trigger it.
-- The one thing left for us to do client-side is recognize the private
-- "RBXWhisper:<id1>_<id2>" channel it creates and render those messages
-- with a "To/From" label instead of the normal sender-name format.
local function GetWhisperInfo(msg)
	local channel = msg.TextChannel
	if not channel then return nil end
 
	local id1, id2 = channel.Name:match("^RBXWhisper:(%d+)_(%d+)$")
	if not id1 then return nil end
 
	local src = msg.TextSource
	local outgoing = src ~= nil and src.UserId == LocalPlayer.UserId
	local otherId = tonumber((tostring(LocalPlayer.UserId) == id1) and id2 or id1)
	local otherPlr = otherId and Players:GetPlayerByUserId(otherId)
 
	return {
		Outgoing = outgoing,
		OtherName = otherPlr and otherPlr.DisplayName or "Unknown",
	}
end
 
if not ChatEnabled then
	local fb = Instance.new("TextLabel", ChatFrame)
	fb.Size = UDim2.new(1, -20, 0, 50)
	fb.Position = UDim2.fromOffset(10, 20)
	fb.BackgroundTransparency = 1
	fb.Text = "TextChatService not enabled.\nChat features unavailable."
	fb.TextColor3 = Config.Theme.Warning
	fb.TextSize = 13
	fb.Font = Enum.Font.Gotham
	fb.TextWrapped = true
else
	TextChatService.MessageReceived:Connect(function(msg)
		local status = msg.Status
		if status ~= Enum.TextChatMessageStatus.Success and status ~= Enum.TextChatMessageStatus.Sending then return end
 
		local whisper = GetWhisperInfo(msg)
		if whisper then
			local accent = ColorToHex(Config.Theme.Accent)
			local otherName = EscapeRichText(whisper.OtherName)
			local text = EscapeRichText(msg.Text)
			if whisper.Outgoing then
				AppendChatLine(string.format('<font color="#%s"><b>To %s:</b></font> <font color="#F0F0F8">%s</font>', accent, otherName, text))
			else
				AppendChatLine(string.format('<font color="#%s"><b>From %s:</b></font> <font color="#F0F0F8">%s</font>', accent, otherName, text))
			end
			return
		end

		if not msg.TextSource then
			AppendChatLine(msg.Text)
			return
		end

		local parts = {}
		if Config.Chat.ShowTimestamps then
			table.insert(parts, string.format('<font color="#6E6E87">[%s]</font>', os.date("%H:%M")))
		end

		local src = msg.TextSource
		local plr = Players:GetPlayerByUserId(src.UserId)
		local name = EscapeRichText(plr and plr.DisplayName or src.Name)
		local color = plr and "6096FF" or "A0A0B8"

		table.insert(parts, string.format('<font color="#%s"><b>%s</b></font>', color, name))
		table.insert(parts, '<font color="#F0F0F8">' .. EscapeRichText(msg.Text) .. '</font>')
		AppendChatLine(table.concat(parts, " "))
	end)
 
	ChatInput.FocusLost:Connect(function(enter)
		if not enter or ChatInput.Text == "" then return end
 
		local text = ChatInput.Text
		ChatInput.Text = ""
 
		-- Just send it as-is. "/w Bob hi" and "/whisper Bob hi" are handled
		-- automatically by RBXWhisperCommand once it's actually the only
		-- thing listening (see the ChatWindowConfiguration/ChatInputBarConfiguration
		-- fix near the top) — no manual command parsing needed here.
		local ch = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
		if ch then pcall(function() ch:SendAsync(text) end) end
	end)
end
 
-- Since the native Chat CoreGui AND the TextChatService default UI are
-- both disabled, our TextBox is now the only place "/" and Enter can
-- meaningfully open chat — no more competing listener underneath it, so
-- no more fighting over focus.
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Minus then return end
	if input.KeyCode == Enum.KeyCode.Slash and ChatEnabled then
		if not ChatInput:IsFocused() then
			ChatInput:CaptureFocus()
		end
	elseif (input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter) and ChatEnabled then
		if not ChatInput:IsFocused() then
			ChatInput:CaptureFocus()
			task.defer(function()
				ChatInput.CursorPosition = #ChatInput.Text + 1
			end)
		end
	end
	if input.KeyCode == Enum.KeyCode.Escape and ChatInput:IsFocused() then
		ChatInput:ReleaseFocus()
	end
end)
 
-- ═══════════════════════════════════════════════════════════════
-- SETTINGS MODAL (Comma key)
-- ═══════════════════════════════════════════════════════════════
local Overlay = Instance.new("Frame", ScreenGui)
Overlay.Size = UDim2.fromScale(1, 1)
Overlay.Position = UDim2.fromScale(0, 0)
Overlay.BackgroundColor3 = Color3.new(0, 0, 0)
Overlay.BackgroundTransparency = 1
Overlay.Visible = false
Overlay.ZIndex = 20
Overlay.Active = true
 
local SetFrame = Instance.new("Frame")
SetFrame.Name = "Settings"
SetFrame.Size = UDim2.fromOffset(600, 420)
SetFrame.Position = UDim2.new(0.5, -300, 0.5, -210)
SetFrame.BackgroundColor3 = Config.Theme.Background
SetFrame.BackgroundTransparency = 0.08
SetFrame.BorderSizePixel = 0
SetFrame.Visible = false
SetFrame.ZIndex = 25
SetFrame.Parent = ScreenGui
SetFrame.Active = true -- CRITICAL: without this, Frames don't block input, so clicks
-- on sliders/toggles/empty space fall through to the Overlay behind and close the modal
SetFrame:SetAttribute("origTrans", 0.08)
UI.Corner(SetFrame, 14)
UI.Stroke(SetFrame, Config.Theme.BorderLight, 1)
UI.Shadow(SetFrame, 36)
UI.PanelGradient(SetFrame, 90)
 
-- Inner clip layer: holds Sidebar/Content/CloseBtn and clips them to a
-- rounded rect, WITHOUT clipping the Shadow image above (which needs to
-- bleed outside SetFrame's bounds for the glow effect).
local SetInner = Instance.new("Frame", SetFrame)
SetInner.Size = UDim2.fromScale(1, 1)
SetInner.BackgroundTransparency = 1
SetInner.BorderSizePixel = 0
SetInner.ClipsDescendants = true
UI.Corner(SetInner, 14)
 
local Sidebar = Instance.new("Frame", SetInner)
Sidebar.Size = UDim2.new(0, 160, 1, 0)
Sidebar.BackgroundColor3 = Config.Theme.Panel
Sidebar.BackgroundTransparency = 0.4
Sidebar.BorderSizePixel = 0
-- (no UICorner here on purpose — a rounded right edge here would show as a
-- gap against Content's straight left edge; SetInner's rounded clip above
-- is what gives the whole modal its rounded look)
 
local SidebarPadding = Instance.new("UIPadding", Sidebar)
SidebarPadding.PaddingTop = UDim.new(0, 14)
SidebarPadding.PaddingLeft = UDim.new(0, 14)
SidebarPadding.PaddingRight = UDim.new(0, 14)
SidebarPadding.PaddingBottom = UDim.new(0, 14)
local SidebarLayout = Instance.new("UIListLayout", Sidebar)
SidebarLayout.Padding = UDim.new(0, 6)
SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
 
local SetTitle = Instance.new("TextLabel", Sidebar)
SetTitle.Name = "Title"
SetTitle.LayoutOrder = -2 -- always first, regardless of alphabetical Name sorting
SetTitle.Size = UDim2.new(1, 0, 0, 26)
SetTitle.BackgroundTransparency = 1
SetTitle.Text = "Settings"
SetTitle.TextColor3 = Config.Theme.TextPrimary
SetTitle.TextSize = 16
SetTitle.Font = Enum.Font.GothamBold
SetTitle.TextXAlignment = Enum.TextXAlignment.Left

local SetTitleAccent = Instance.new("Frame", Sidebar)
SetTitleAccent.LayoutOrder = -1
SetTitleAccent.Size = UDim2.new(0, 32, 0, 3)
SetTitleAccent.BackgroundColor3 = Color3.new(1, 1, 1)
SetTitleAccent.BorderSizePixel = 0
UI.Corner(SetTitleAccent, 2)
UI.AccentGradient(SetTitleAccent, 0)
 
local Content = Instance.new("Frame", SetInner)
Content.Size = UDim2.new(1, -160, 1, 0)
Content.Position = UDim2.fromOffset(160, 0)
Content.BackgroundTransparency = 1
local ContentPadding = Instance.new("UIPadding", Content)
ContentPadding.PaddingTop = UDim.new(0, 52) -- was 16 — cleared so content starts below the × button instead of behind it
ContentPadding.PaddingLeft = UDim.new(0, 16)
ContentPadding.PaddingRight = UDim.new(0, 16)
ContentPadding.PaddingBottom = UDim.new(0, 16)
Instance.new("UIListLayout", Content).Padding = UDim.new(0, 8)
 
local CloseBtn = Instance.new("TextButton", SetFrame)
CloseBtn.Size = UDim2.fromOffset(34, 34) -- was 30x30 with no visible background — bigger + a real background makes it far easier to hit
CloseBtn.Position = UDim2.new(1, -44, 0, 8)
CloseBtn.ZIndex = 30 -- guarantees it renders above the FOV slider's value label, which sat in the same corner
CloseBtn.BackgroundColor3 = Config.Theme.Surface
CloseBtn.BackgroundTransparency = 0.25
CloseBtn.AutoButtonColor = false
CloseBtn.Text = "×"
CloseBtn.TextColor3 = Config.Theme.TextMuted
CloseBtn.TextSize = 22
CloseBtn.Font = Enum.Font.GothamBold
UI.Corner(CloseBtn, 8)
 
-- FIXED: Close button hover feedback (background + text color, so it reads as a real button)
CloseBtn.MouseEnter:Connect(function()
	TweenService:Create(CloseBtn, TweenInfo.new(0.1), {
		TextColor3 = Config.Theme.TextPrimary,
		BackgroundColor3 = Config.Theme.SurfaceHover,
		BackgroundTransparency = 0.1,
	}):Play()
end)
CloseBtn.MouseLeave:Connect(function()
	TweenService:Create(CloseBtn, TweenInfo.new(0.1), {
		TextColor3 = Config.Theme.TextMuted,
		BackgroundColor3 = Config.Theme.Surface,
		BackgroundTransparency = 0.25,
	}):Play()
end)
 
-- Background click no longer closes the modal — only the Settings key
-- (,) or the × button do. (Overlay still dims the background, it just
-- doesn't listen for clicks anymore.)
 
local SettingsOpen = false
local function ToggleSettings()
	SettingsOpen = not SettingsOpen
	if SettingsOpen then
		Overlay.Visible = true
		SetFrame.Visible = true
		TweenService:Create(Overlay, TweenInfo.new(0.2), {BackgroundTransparency = 0.6}):Play()
		Animation:Open(SetFrame)
	else
		Animation:Close(SetFrame)
		local t = TweenService:Create(Overlay, TweenInfo.new(0.2), {BackgroundTransparency = 1})
		t:Play()
		t.Completed:Connect(function() Overlay.Visible = false end)
	end
end
 
CloseBtn.MouseButton1Click:Connect(ToggleSettings)
 
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Config.SettingsKey then ToggleSettings() end
end)
 
-- Settings builder
local Categories = {}
local CurrentCat = ""
local SidebarButtons = {}
 
local function SelectCat(name)
	CurrentCat = name
	for n, f in pairs(Categories) do f.Visible = (n == name) end
	for _, btn in ipairs(SidebarButtons) do
		local isActive = (btn.Name == name)
		btn.BackgroundColor3 = isActive and Config.Theme.SurfaceHover or Config.Theme.Surface
		btn.BackgroundTransparency = isActive and 0.2 or 0.4
	end
end
 
local function AddSection(name)
	local btn = Instance.new("TextButton", Sidebar)
	btn.Name = name
	btn.LayoutOrder = #SidebarButtons -- preserves call order instead of alphabetical Name sort
	btn.Size = UDim2.new(1, 0, 0, 36)
	btn.BackgroundColor3 = Config.Theme.Surface
	btn.BackgroundTransparency = 0.4
	btn.Text = name
	btn.TextColor3 = Config.Theme.TextPrimary
	btn.TextSize = 14
	btn.Font = Enum.Font.GothamMedium
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	UI.Corner(btn, 8)
 
	-- FIXED: Custom hover that respects active state (no flicker)
	btn.MouseEnter:Connect(function()
		if CurrentCat ~= name then
			TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = Config.Theme.SurfaceHover}):Play()
		end
	end)
	btn.MouseLeave:Connect(function()
		if CurrentCat ~= name then
			TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3 = Config.Theme.Surface}):Play()
		end
	end)
	btn.MouseButton1Click:Connect(function() SelectCat(name) end)
 
	table.insert(SidebarButtons, btn)
 
	local frame = Instance.new("Frame", Content)
	frame.Name = name
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	Instance.new("UIListLayout", frame).Padding = UDim.new(0, 8)
 
	Categories[name] = frame
	if CurrentCat == "" then SelectCat(name) end
end
 
local function AddToggle(section, text, default, callback)
	local parent = Categories[section]
	if not parent then return end
	UI.CreateToggle({
		Parent = parent,
		Text = text,
		DefaultValue = default,
		OnChanged = callback,
	})
end
 
local function AddSlider(section, text, min, max, default, callback)
	local parent = Categories[section]
	if not parent then return end
	UI.CreateSlider({
		Parent = parent,
		Text = text,
		Min = min,
		Max = max,
		DefaultValue = default,
		OnChanged = callback,
	})
end
 
AddSection("General")
AddToggle("General", "UI Animations", Config.UIAnimations, function(v)
	Config.UIAnimations = v
	SavedSettings.UIAnimations = v
	SaveSettings()
end)
AddToggle("General", "Shadows", Config.Shadows, function(v)
	Config.Shadows = v
	SavedSettings.Shadows = v
	SaveSettings()
	for _, obj in ipairs(ScreenGui:GetDescendants()) do
		if obj.Name == "Shadow" and obj:IsA("ImageLabel") then
			obj.Visible = v
		end
	end
end)
AddToggle("General", "Chat Timestamps", Config.Chat.ShowTimestamps, function(v)
	Config.Chat.ShowTimestamps = v
	SavedSettings.ShowTimestamps = v
	SaveSettings()
end)

-- Reset Chat Position button
local resetRow = Instance.new("Frame", Categories["General"])
resetRow.Size = UDim2.new(1, 0, 0, 36)
resetRow.BackgroundTransparency = 1
local resetLbl = Instance.new("TextLabel", resetRow)
resetLbl.Size = UDim2.new(1, -110, 1, 0)
resetLbl.BackgroundTransparency = 1
resetLbl.Text = "Chat Position"
resetLbl.TextColor3 = Config.Theme.TextPrimary
resetLbl.TextSize = 14
resetLbl.Font = Enum.Font.Gotham
resetLbl.TextXAlignment = Enum.TextXAlignment.Left
local resetBtn = UI.CreateButton({
	Parent = resetRow,
	Size = UDim2.fromOffset(100, 28),
	Position = UDim2.new(1, -100, 0.5, -14),
	Text = "Reset",
	OnClick = function()
		Config.Chat.Position = {X = 15, Y = 52}
		SavedSettings.ChatPosition = {X = 15, Y = 52}
		SaveSettings()
		ChatFrame.Position = UDim2.new(0, 15, 0, 52)
		ChatToggleBtn.Position = UDim2.new(0, 15, 0, 52)
	end,
})
 
AddSection("Audio")
AddToggle("Audio", "Music", true, function(v) end)
AddSlider("Audio", "Master Volume", 0, 100, Config.MasterVolume, function(v)
	Config.MasterVolume = v
	SavedSettings.MasterVolume = v
	SaveSettings()
end)
 
AddSection("Video")
AddSlider("Video", "FOV", 60, 120, 70, function(v)
	local cam = Workspace.CurrentCamera
	if cam then cam.FieldOfView = v end
end)
 
AddSection("Controls")
local controlsFrame = Categories["Controls"]
if controlsFrame then
	local row = Instance.new("Frame", controlsFrame)
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundTransparency = 1
 
	local lbl = Instance.new("TextLabel", row)
	lbl.Size = UDim2.new(1, -50, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = "Key remapping coming in a future update."
	lbl.TextColor3 = Config.Theme.TextPrimary
	lbl.TextSize = 13
	lbl.Font = Enum.Font.Gotham
	lbl.TextXAlignment = Enum.TextXAlignment.Left
 
	local badge = UI.CreateWipBadge({Parent = row})
	badge.Position = UDim2.new(1, -42, 0, 3)
	badge.AnchorPoint = Vector2.new(0, 0)
end
 
-- ═══════════════════════════════════════════════════════════════
-- NOTIFICATIONS (Top Right, below topbar area)
-- ═══════════════════════════════════════════════════════════════
local NotifContainer = Instance.new("Frame")
NotifContainer.Name = "Notifications"
NotifContainer.Size = UDim2.new(0, 360, 1, -60)
NotifContainer.Position = UDim2.new(1, -380, 0, 10)
NotifContainer.BackgroundTransparency = 1
NotifContainer.Active = false
NotifContainer.ZIndex = 50
NotifContainer.Parent = ScreenGui
 
Instance.new("UIListLayout", NotifContainer).Padding = UDim.new(0, 10)
NotifContainer.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
NotifContainer.UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
NotifContainer.UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
 
local function ShowNotification(props)
	local notif = UI.CreateNotification({
		Parent = NotifContainer,
		Title = props.Title,
		Description = props.Description,
		Type = props.Type,
		Duration = props.Duration,
	})
 
	notif.Instance.LayoutOrder = -tick()
	notif.Instance.BackgroundTransparency = 1
	notif.Instance.Position = notif.Instance.Position + UDim2.fromOffset(20, 0)
 
	-- FIXED: Safer animation without race-condition height read
	Animation:Fade(notif.Instance, 0.05, 0.22)
	local targetPos = UDim2.new(0, 0, 0, 0) -- relative to parent list layout
	Animation:_playTween(notif.Instance, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {
		Position = targetPos
	})
 
	local dismissed = false
	local origDismiss = notif.Dismiss
	notif.Dismiss = function()
		if dismissed then return end
		dismissed = true
		Animation:Fade(notif.Instance, 1, 0.15)
		task.delay(0.2, function() origDismiss(notif) end)
	end
 
	task.delay(props.Duration, function()
		notif:Dismiss()
	end)
end
 
-- ═══════════════════════════════════════════════════════════════
-- PLAYER ACTION PANEL — click a row in the Players list to add-friend
-- or view a bigger avatar shot. Sits to the left of the player list.
-- ═══════════════════════════════════════════════════════════════
local AvatarPanel = Instance.new("Frame")
AvatarPanel.Name = "PlayerActionPanel"
AvatarPanel.Size = UDim2.fromOffset(240, 340)
AvatarPanel.Position = UDim2.new(1, -560, 1, -360)
AvatarPanel.BackgroundColor3 = Config.Theme.Background
AvatarPanel.BackgroundTransparency = 0.08
AvatarPanel.BorderSizePixel = 0
AvatarPanel.Visible = false
AvatarPanel.ZIndex = 15
AvatarPanel.Active = true -- blocks clicks from falling through to whatever's behind it
AvatarPanel:SetAttribute("origTrans", 0.08)
AvatarPanel.Parent = ScreenGui
UI.Corner(AvatarPanel, 12)
UI.Stroke(AvatarPanel, Config.Theme.BorderLight, 1)
UI.Shadow(AvatarPanel, 28)
UI.PanelGradient(AvatarPanel, 90)

local APClose = Instance.new("TextButton", AvatarPanel)
APClose.Size = UDim2.fromOffset(26, 26)
APClose.Position = UDim2.new(1, -34, 0, 8)
APClose.ZIndex = 17
APClose.BackgroundColor3 = Config.Theme.Surface
APClose.BackgroundTransparency = 0.25
APClose.AutoButtonColor = false
APClose.Text = "×"
APClose.TextColor3 = Config.Theme.TextMuted
APClose.TextSize = 18
APClose.Font = Enum.Font.GothamBold
UI.Corner(APClose, 8)

APClose.MouseEnter:Connect(function()
	TweenService:Create(APClose, TweenInfo.new(0.1), {TextColor3 = Config.Theme.TextPrimary, BackgroundColor3 = Config.Theme.SurfaceHover}):Play()
end)
APClose.MouseLeave:Connect(function()
	TweenService:Create(APClose, TweenInfo.new(0.1), {TextColor3 = Config.Theme.TextMuted, BackgroundColor3 = Config.Theme.Surface}):Play()
end)

local APAvatarRing = Instance.new("Frame", AvatarPanel)
APAvatarRing.Size = UDim2.fromOffset(164, 164)
APAvatarRing.Position = UDim2.new(0.5, -82, 0, 18)
APAvatarRing.BackgroundColor3 = Config.Theme.Surface
APAvatarRing.BackgroundTransparency = 0.35
APAvatarRing.BorderSizePixel = 0
APAvatarRing.ZIndex = 16
UI.Corner(APAvatarRing, 82)
UI.Stroke(APAvatarRing, Config.Theme.BorderLight, 1)

local APAvatarImg = Instance.new("ImageLabel", APAvatarRing)
APAvatarImg.Size = UDim2.fromOffset(156, 156)
APAvatarImg.Position = UDim2.fromOffset(4, 4)
APAvatarImg.BackgroundTransparency = 1
APAvatarImg.ZIndex = 17
APAvatarImg.Image = ""
UI.Corner(APAvatarImg, 78)

local APName = Instance.new("TextLabel", AvatarPanel)
APName.Size = UDim2.new(1, -20, 0, 22)
APName.Position = UDim2.fromOffset(10, 190)
APName.BackgroundTransparency = 1
APName.Text = ""
APName.TextColor3 = Config.Theme.TextPrimary
APName.TextSize = 16
APName.Font = Enum.Font.GothamBold
APName.TextXAlignment = Enum.TextXAlignment.Center
APName.ZIndex = 16

local APUser = Instance.new("TextLabel", AvatarPanel)
APUser.Size = UDim2.new(1, -20, 0, 18)
APUser.Position = UDim2.fromOffset(10, 212)
APUser.BackgroundTransparency = 1
APUser.Text = ""
APUser.TextColor3 = Config.Theme.TextMuted
APUser.TextSize = 13
APUser.Font = Enum.Font.Gotham
APUser.TextXAlignment = Enum.TextXAlignment.Center
APUser.ZIndex = 16

local APFriendBtn = UI.CreateButton({
	Parent = AvatarPanel,
	Size = UDim2.new(1, -20, 0, 36),
	Position = UDim2.fromOffset(10, 244),
	Text = "➕ Add Friend",
})
APFriendBtn.Instance.ZIndex = 16

local APProfileBtn = UI.CreateButton({
	Parent = AvatarPanel,
	Size = UDim2.new(1, -20, 0, 36),
	Position = UDim2.fromOffset(10, 286),
	Text = "👤 View Profile",
})
APProfileBtn.Instance.ZIndex = 16

local AvatarPanelVisible = false
local CurrentTargetPlayer = nil

-- Bigger, closer-cropped thumbnail than the 48x48 one used in the list row.
local FullThumbCache = {}
local function GetFullThumbnail(userId, cb)
	if FullThumbCache[userId] then cb(FullThumbCache[userId]) return end
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size420x420)
		end)
		if ok and url then
			FullThumbCache[userId] = url
			cb(url)
		else
			cb("")
		end
	end)
end

CloseAvatarPanel = function(onlyIfPlayer)
	if onlyIfPlayer and CurrentTargetPlayer ~= onlyIfPlayer then return end
	if not AvatarPanelVisible then return end
	AvatarPanelVisible = false
	Animation:Close(AvatarPanel)
	CurrentTargetPlayer = nil
end

OpenAvatarPanel = function(plr)
	if not plr or plr == LocalPlayer then return end
	CurrentTargetPlayer = plr
	APName.Text = plr.DisplayName
	APUser.Text = "@" .. plr.Name
	APAvatarImg.Image = ""

	GetFullThumbnail(plr.UserId, function(url)
		if CurrentTargetPlayer == plr then
			APAvatarImg.Image = url
		end
	end)

	-- Reflect current friend status on the button, when the platform lets us ask.
	local label, enabled = "➕ Add Friend", true
	local ok, status = pcall(function() return LocalPlayer:GetFriendStatus(plr) end)
	if ok then
		if status == Enum.FriendStatus.Friend then
			label, enabled = "✓ Already Friends", false
		elseif status == Enum.FriendStatus.FriendRequestSent then
			label, enabled = "Request Sent", false
		elseif status == Enum.FriendStatus.FriendRequestReceived then
			label, enabled = "➕ Accept Request", true
		end
	end
	APFriendBtn:SetText(label)
	APFriendBtn:SetEnabled(enabled)

	AvatarPanelVisible = true
	AvatarPanel.Visible = true
	Animation:Open(AvatarPanel)
end

APClose.MouseButton1Click:Connect(function() CloseAvatarPanel() end)

APFriendBtn.Instance.MouseButton1Click:Connect(function()
	if not CurrentTargetPlayer then return end
	-- Native Roblox "send/accept friend request" prompt. Wrapped in pcall
	-- since the SetCore key isn't guaranteed to exist on every platform
	-- (e.g. some console/embedded clients), and we don't want a missing
	-- key to error out the rest of the script.
	local target = CurrentTargetPlayer
	local ok = pcall(function()
		StarterGui:SetCore("PromptSendFriendRequest", target)
	end)
	if not ok then
		ShowNotification({Title = "Unavailable", Description = "Friend requests aren't available on this platform.", Type = "Warning", Duration = 4})
	end
end)

APProfileBtn.Instance.MouseButton1Click:Connect(function()
	if not CurrentTargetPlayer then return end
	local target = CurrentTargetPlayer

	-- FIXED (correct API): "PromptViewProfile" isn't a real SetCore key —
	-- it doesn't exist in Roblox's SetCore list, so it always failed and
	-- always hit the fallback toast, regardless of platform. The real API
	-- for this is the Avatar Context Menu, enabled once at startup above.
	-- Opening it here targets this specific player and gives them the
	-- native Friend / Chat / View (appearance) / Wave menu — "View" is
	-- the actual built-in profile/appearance inspector.
	local ok = pcall(function()
		StarterGui:SetCore("AvatarContextMenuTarget", target)
	end)

	if ok then
		CloseAvatarPanel() -- hand off to the native ACM overlay instead of stacking two panels
	else
		-- Only reachable if ACM itself isn't available on this platform.
		local profileUrl = string.format("https://www.roblox.com/users/%d/profile", target.UserId)
		ShowNotification({
			Title = "Profile Unavailable Here",
			Description = "Player profiles aren't supported on this platform. Profile link: " .. profileUrl,
			Type = "Warning",
			Duration = 6,
		})
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if input.KeyCode == Enum.KeyCode.Escape and AvatarPanelVisible then
		CloseAvatarPanel()
	end
end)

Players.PlayerRemoving:Connect(function(p)
	CloseAvatarPanel(p)
end)

-- ═══════════════════════════════════════════════════════════════
-- FPS & PING COUNTER (Bottom Left)
-- ═══════════════════════════════════════════════════════════════

local StatsFrame = Instance.new("Frame")
StatsFrame.Name = "Stats"
StatsFrame.Size = UDim2.fromOffset(120, 50)
StatsFrame.Position = UDim2.new(0, 12, 1, -62)
StatsFrame.BackgroundColor3 = Config.Theme.Background
StatsFrame.BackgroundTransparency = 0.15
StatsFrame.BorderSizePixel = 0
StatsFrame.ZIndex = 5
StatsFrame.Parent = ScreenGui
UI.Corner(StatsFrame, 8)
UI.Stroke(StatsFrame, Config.Theme.BorderLight, 1)

local StatsLayout = Instance.new("UIListLayout", StatsFrame)
StatsLayout.FillDirection = Enum.FillDirection.Vertical
StatsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
StatsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
StatsLayout.Padding = UDim.new(0, 2)

local FPSText = Instance.new("TextLabel", StatsFrame)
FPSText.Size = UDim2.new(1, -8, 0, 18)
FPSText.BackgroundTransparency = 1
FPSText.Text = "FPS: --"
FPSText.TextColor3 = Config.Theme.TextPrimary
FPSText.TextSize = 12
FPSText.Font = Enum.Font.GothamBold
FPSText.TextXAlignment = Enum.TextXAlignment.Center

local PingText = Instance.new("TextLabel", StatsFrame)
PingText.Size = UDim2.new(1, -8, 0, 16)
PingText.BackgroundTransparency = 1
PingText.Text = "Ping: --ms"
PingText.TextColor3 = Config.Theme.TextSecondary
PingText.TextSize = 11
PingText.Font = Enum.Font.GothamMedium
PingText.TextXAlignment = Enum.TextXAlignment.Center

local frameCount = 0
local lastUpdate = tick()
RunService.Heartbeat:Connect(function()
	frameCount += 1
	local now = tick()
	if now - lastUpdate >= 1 then
		local fps = math.round(frameCount / (now - lastUpdate))
		frameCount = 0
		lastUpdate = now
		FPSText.Text = "FPS: " .. fps
		if fps >= 55 then
			FPSText.TextColor3 = Config.Theme.Success
		elseif fps >= 30 then
			FPSText.TextColor3 = Config.Theme.Warning
		else
			FPSText.TextColor3 = Config.Theme.Error
		end
	end
end)

local function UpdatePing()
	local ok, ping = pcall(function() return LocalPlayer:GetNetworkPing() end)
	if ok and ping then
		local ms = math.floor(ping * 1000)
		PingText.Text = "Ping: " .. ms .. "ms"
		PingText.TextColor3 = ms < 80 and Config.Theme.Success or (ms < 160 and Config.Theme.Warning or Config.Theme.Error)
	else
		PingText.Text = "Ping: --ms"
		PingText.TextColor3 = Config.Theme.TextMuted
	end
end

task.spawn(function()
	while true do
		UpdatePing()
		task.wait(3)
	end
end)

-- ═══════════════════════════════════════════════════════════════
-- CUSTOM BUBBLE CHAT v3 — Sleek Black + Ultra Round
-- ═══════════════════════════════════════════════════════════════

local BubbleContainer = Instance.new("Folder")
BubbleContainer.Name = "Bubbles"
BubbleContainer.Parent = ScreenGui

local ActiveBubbles = {}

local BubbleBlack = Color3.fromRGB(5, 5, 8)
local BubbleGlow = Color3.fromRGB(40, 40, 55)

local function CreateBubble(msg, senderPlr)
	if not senderPlr or senderPlr == LocalPlayer then return end
	local char = senderPlr.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end

	-- Remove old bubble from this player
	if ActiveBubbles[senderPlr] then
		local old = ActiveBubbles[senderPlr]
		if old and old.Parent then
			Animation:Fade(old, 1, 0.1)
			Animation:FadeText(old:FindFirstChild("MsgText"), 1, 0.1)
			Animation:FadeText(old:FindFirstChild("NameLabel"), 1, 0.1)
			task.delay(0.12, function()
				if old and old.Parent then old:Destroy() end
			end)
		end
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "Bubble"
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(240, 0)
	bb.StudsOffset = Vector3.new(0, 3.4, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 80
	bb.LightInfluence = 0
	bb.Parent = BubbleContainer

	-- Shadow / glow behind bubble
	local shadow = Instance.new("ImageLabel", bb)
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.BackgroundTransparency = 1
	shadow.Position = UDim2.fromScale(0.5, 0.5)
	shadow.Size = UDim2.new(1, 30, 1, 30)
	shadow.Image = "rbxassetid://6015897843"
	shadow.ImageColor3 = Color3.new(0, 0, 0)
	shadow.ImageTransparency = 0.5
	shadow.ScaleType = Enum.ScaleType.Slice
	shadow.SliceCenter = Rect.new(49, 49, 450, 450)
	shadow.ZIndex = 0

	-- Main black bubble
	local bubbleFrame = Instance.new("Frame", bb)
	bubbleFrame.Name = "BubbleFrame"
	bubbleFrame.Size = UDim2.new(1, 0, 0, 0)
	bubbleFrame.AutomaticSize = Enum.AutomaticSize.Y
	bubbleFrame.BackgroundColor3 = BubbleBlack
	bubbleFrame.BackgroundTransparency = 0.05
	bubbleFrame.BorderSizePixel = 0
	bubbleFrame.ZIndex = 2

	local corner = Instance.new("UICorner", bubbleFrame)
	corner.CornerRadius = UDim.new(0, 20)

	-- Soft white border
	local border = Instance.new("UIStroke", bubbleFrame)
	border.Color = BubbleGlow
	border.Thickness = 1.5
	border.Transparency = 0.4
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	-- Padding
	local pad = Instance.new("UIPadding", bubbleFrame)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 12)

	-- Name label
	local nameLabel = Instance.new("TextLabel", bubbleFrame)
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = senderPlr.DisplayName
	nameLabel.TextColor3 = Config.Theme.Accent
	nameLabel.TextSize = 11
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 3

	-- Message text
	local msgText = Instance.new("TextLabel", bubbleFrame)
	msgText.Name = "MsgText"
	msgText.Size = UDim2.new(1, 0, 0, 0)
	msgText.Position = UDim2.fromOffset(0, 18)
	msgText.BackgroundTransparency = 1
	msgText.Text = msg.Text
	msgText.TextColor3 = Color3.fromRGB(230, 230, 240)
	msgText.TextSize = 14
	msgText.Font = Enum.Font.Gotham
	msgText.TextWrapped = true
	msgText.TextXAlignment = Enum.TextXAlignment.Left
	msgText.AutomaticSize = Enum.AutomaticSize.Y
	msgText.ZIndex = 3

	-- Round tail pointing down
	local tail = Instance.new("Frame", bb)
	tail.Name = "Tail"
	tail.Size = UDim2.fromOffset(18, 14)
	tail.Position = UDim2.new(0.5, -9, 1, -6)
	tail.BackgroundColor3 = BubbleBlack
	tail.BackgroundTransparency = 0.05
	tail.BorderSizePixel = 0
	tail.ZIndex = 1
	tail.Rotation = 45

	local tailCorner = Instance.new("UICorner", tail)
	tailCorner.CornerRadius = UDim.new(0, 6)

	-- Whisper styling
	local whisper = GetWhisperInfo(msg)
	if whisper then
		border.Color = Config.Theme.Warning
		border.Transparency = 0.15
		nameLabel.TextColor3 = Config.Theme.Warning
		nameLabel.Text = "🔒 " .. senderPlr.DisplayName
	end

	-- Animate in
	bubbleFrame.Size = UDim2.new(1, 0, 0, 0)
	bubbleFrame.BackgroundTransparency = 1
	msgText.TextTransparency = 1
	nameLabel.TextTransparency = 1
	shadow.ImageTransparency = 1
	tail.BackgroundTransparency = 1

	if Config.UIAnimations then
		Animation:Scale(bubbleFrame, UDim2.new(1, 0, 0, bubbleFrame.AbsoluteSize.Y), 0.22)
		Animation:Fade(bubbleFrame, 0.05, 0.18)
		Animation:FadeText(msgText, 0, 0.18)
		Animation:FadeText(nameLabel, 0, 0.18)
		Animation:Fade(shadow, 0.5, 0.25)
		Animation:Fade(tail, 0.05, 0.18)
	else
		bubbleFrame.BackgroundTransparency = 0.05
		msgText.TextTransparency = 0
		nameLabel.TextTransparency = 0
		shadow.ImageTransparency = 0.5
		tail.BackgroundTransparency = 0.05
	end

	ActiveBubbles[senderPlr] = bubbleFrame

	-- Auto destroy
	task.delay(6, function()
		if bubbleFrame and bubbleFrame.Parent then
			if Config.UIAnimations then
				Animation:Fade(bubbleFrame, 1, 0.2)
				Animation:FadeText(msgText, 1, 0.15)
				Animation:FadeText(nameLabel, 1, 0.15)
				Animation:Fade(shadow, 1, 0.2)
				Animation:Fade(tail, 1, 0.2)
				task.delay(0.25, function()
					if bb and bb.Parent then bb:Destroy() end
					if ActiveBubbles[senderPlr] == bubbleFrame then
						ActiveBubbles[senderPlr] = nil
					end
				end)
			else
				bb:Destroy()
				ActiveBubbles[senderPlr] = nil
			end
		end
	end)
end

-- Hook into message received for bubbles
if ChatEnabled then
	TextChatService.MessageReceived:Connect(function(msg)
		local status = msg.Status
		if status ~= Enum.TextChatMessageStatus.Success and status ~= Enum.TextChatMessageStatus.Sending then return end
		local src = msg.TextSource
		local plr = src and Players:GetPlayerByUserId(src.UserId)
		if plr and plr ~= LocalPlayer then
			CreateBubble(msg, plr)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════
-- (Welcome/"Modern HUD Active" popup removed per request)
-- ═══════════════════════════════════════════════════════════════