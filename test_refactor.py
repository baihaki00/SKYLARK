with open(r'C:\Users\User\.gemini\antigravity\scratch\AnimationLabController.lua', 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Wrap Freecam internals in do ... end
old_fc_start = '''--------------------------------------------------------------------------------
-- 1. BLENDER-STYLE FREECAM SYSTEM (CANONICAL CAS CONTROLLER & SEAMLESS FLYING)
--------------------------------------------------------------------------------
local CAS = game:GetService("ContextActionService")'''

new_fc_start = '''--------------------------------------------------------------------------------
-- 1. BLENDER-STYLE FREECAM SYSTEM (CANONICAL CAS CONTROLLER & SEAMLESS FLYING)
--------------------------------------------------------------------------------
local startFreecam, stopFreecam, toggleFreelookLock
do
\tlocal CAS = game:GetService("ContextActionService")'''

old_fc_end = '''-- Default to Character / SmoothCamera mode on game load
task.defer(function()
\tstopFreecam()
end)'''

new_fc_end = '''-- Default to Character / SmoothCamera mode on game load
\ttask.defer(function()
\t\tstopFreecam()
\tend)
end'''

assert old_fc_start in text, 'old_fc_start not found'
assert old_fc_end in text, 'old_fc_end not found'
text = text.replace(old_fc_start, new_fc_start)
text = text.replace(old_fc_end, new_fc_end)

text = text.replace('local function startFreecam()', 'startFreecam = function()')
text = text.replace('local function stopFreecam()', 'stopFreecam = function()')
text = text.replace('local function toggleFreelookLock()', 'toggleFreelookLock = function()')

# 2. Wrap Speed controls in do ... end
old_speed = '''-- ============================================================
-- EMBEDDED BATTLE SPEED CONTROLLER (Inside Quin Manager Menu)
-- ============================================================
local speedEvent = ReplicatedStorage:FindFirstChild("GameSpeedEvent")'''

new_speed = '''-- ============================================================
-- EMBEDDED BATTLE SPEED CONTROLLER (Inside Quin Manager Menu)
-- ============================================================
do
\tlocal speedEvent = ReplicatedStorage:FindFirstChild("GameSpeedEvent")'''

old_speed_end = '''Workspace:GetAttributeChangedSignal("GameSpeedMultiplier"):Connect(function()
\tlocal cur = Workspace:GetAttribute("GameSpeedMultiplier") or DEFAULT_SPEED
\tupdateSpeedUI(cur)
end)'''

new_speed_end = '''Workspace:GetAttributeChangedSignal("GameSpeedMultiplier"):Connect(function()
\tlocal cur = Workspace:GetAttribute("GameSpeedMultiplier") or DEFAULT_SPEED
\tupdateSpeedUI(cur)
\tend)
end'''

assert old_speed in text, 'old_speed not found'
assert old_speed_end in text, 'old_speed_end not found'
text = text.replace(old_speed, new_speed)
text = text.replace(old_speed_end, new_speed_end)

# 3. Wrap Window Dragging in do ... end
old_drag = '''-- Window Dragging Logic
local isDragging = false'''

new_drag = '''-- Window Dragging Logic
do
\tlocal isDragging = false'''

old_drag_end = '''UserInputService.InputEnded:Connect(function(input)
\tif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
\t\tisDragging = false
\tend
end)'''

new_drag_end = '''UserInputService.InputEnded:Connect(function(input)
\tif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
\t\tisDragging = false
\tend
\tend)
end'''

assert old_drag in text, 'old_drag not found'
assert old_drag_end in text, 'old_drag_end not found'
text = text.replace(old_drag, new_drag)
text = text.replace(old_drag_end, new_drag_end)

# 4. Wrap Export Modal in do ... end
old_modal = '''--------------------------------------------------------------------------------
-- 5. POPUP MODAL FOR EXPORTED CODE
--------------------------------------------------------------------------------
local modalBackdrop = Instance.new("Frame")'''

new_modal = '''--------------------------------------------------------------------------------
-- 5. POPUP MODAL FOR EXPORTED CODE
--------------------------------------------------------------------------------
do
\tlocal modalBackdrop = Instance.new("Frame")'''

old_modal_end = '''copyNotifyBtn.MouseButton1Click:Connect(function()
\tlocal luauCode = AnimationConfig.exportLuau()
\tprint("========================================")
\tprint("QUIN ANIMATION CONFIG EXPORT:")
\tprint(luauCode)
\tprint("========================================")
\tmodalTextBox:CaptureFocus()
\tcopyNotifyBtn.Text = "✓ Printed to Console Output!"
\ttask.delay(1.5, function() copyNotifyBtn.Text = "Print to Studio Output & Select All" end)
end)'''

new_modal_end = '''copyNotifyBtn.MouseButton1Click:Connect(function()
\tlocal luauCode = AnimationConfig.exportLuau()
\tprint("========================================")
\tprint("QUIN ANIMATION CONFIG EXPORT:")
\tprint(luauCode)
\tprint("========================================")
\tmodalTextBox:CaptureFocus()
\tcopyNotifyBtn.Text = "✓ Printed to Console Output!"
\ttask.delay(1.5, function() copyNotifyBtn.Text = "Print to Studio Output & Select All" end)
\tend)
end'''

assert old_modal in text, 'old_modal not found'
assert old_modal_end in text, 'old_modal_end not found'
text = text.replace(old_modal, new_modal)
text = text.replace(old_modal_end, new_modal_end)

# 5. Pre-declarations for 4B, 4C and do blocks
old_4b = '''--------------------------------------------------------------------------------
-- 4B. SUB-TAB 2: CONTINUOUS LOCOMOTION & PROCEDURAL FOOT IK
--------------------------------------------------------------------------------'''

new_4b = '''-- Forward declarations for controls referenced across tabs & Section 9 event listeners
local walkStrideSlider, runStrideSlider, maxRollSlider, bankRespSlider
local isFootIKActive = false
local ikToggleBtn
local rayDistSlider, heightOffsetSlider, maxStepDownSlider, hipsDipSlider
local isAnkleAlign = true
local ankleBtn
local isLedgeGrip = true
local ledgeBtn
local muscleStiffSlider, dampingSlider, tumbleScaleSlider, groundFrictionSlider, recoveryDelaySlider
local isContinuousRagdoll = false
local toggleContinuousRagBtn
local createModeCard

--------------------------------------------------------------------------------
-- 4B. SUB-TAB 2: CONTINUOUS LOCOMOTION & PROCEDURAL FOOT IK
--------------------------------------------------------------------------------
do'''

assert old_4b in text, 'old_4b not found'
text = text.replace(old_4b, new_4b)

text = text.replace('local walkStrideSlider = createPrecisionSlider', 'walkStrideSlider = createPrecisionSlider')
text = text.replace('local runStrideSlider = createPrecisionSlider', 'runStrideSlider = createPrecisionSlider')
text = text.replace('local maxRollSlider = createPrecisionSlider', 'maxRollSlider = createPrecisionSlider')
text = text.replace('local bankRespSlider = createPrecisionSlider', 'bankRespSlider = createPrecisionSlider')
text = text.replace('local isFootIKActive = (CombatConfig.FootIK_Enabled ~= false)', 'isFootIKActive = (CombatConfig.FootIK_Enabled ~= false)')
text = text.replace('local ikToggleBtn = Instance.new("TextButton")', 'ikToggleBtn = Instance.new("TextButton")')
text = text.replace('local rayDistSlider = createPrecisionSlider', 'rayDistSlider = createPrecisionSlider')
text = text.replace('local heightOffsetSlider = createPrecisionSlider', 'heightOffsetSlider = createPrecisionSlider')
text = text.replace('local maxStepDownSlider = createPrecisionSlider', 'maxStepDownSlider = createPrecisionSlider')
text = text.replace('local hipsDipSlider = createPrecisionSlider', 'hipsDipSlider = createPrecisionSlider')
text = text.replace('local isAnkleAlign = (CombatConfig.FootIK_AnkleAlignment ~= false)', 'isAnkleAlign = (CombatConfig.FootIK_AnkleAlignment ~= false)')
text = text.replace('local ankleBtn = Instance.new("TextButton")', 'ankleBtn = Instance.new("TextButton")')
text = text.replace('local isLedgeGrip = (CombatConfig.FootIK_LedgeGrip ~= false)', 'isLedgeGrip = (CombatConfig.FootIK_LedgeGrip ~= false)')
text = text.replace('local ledgeBtn = Instance.new("TextButton")', 'ledgeBtn = Instance.new("TextButton")')

# End 4B, begin 4C
old_4c = '''--------------------------------------------------------------------------------
-- 4C. SUB-TAB 3: ACTIVE MUSCLE RAGDOLL & SPECTACLE KNOCKBACK SANDBOX
--------------------------------------------------------------------------------'''

new_4c = '''end

--------------------------------------------------------------------------------
-- 4C. SUB-TAB 3: ACTIVE MUSCLE RAGDOLL & SPECTACLE KNOCKBACK SANDBOX
--------------------------------------------------------------------------------
do'''

assert old_4c in text, 'old_4c not found'
text = text.replace(old_4c, new_4c)

text = text.replace('local muscleStiffSlider = createPrecisionSlider', 'muscleStiffSlider = createPrecisionSlider')
text = text.replace('local dampingSlider = createPrecisionSlider', 'dampingSlider = createPrecisionSlider')
text = text.replace('local tumbleScaleSlider = createPrecisionSlider', 'tumbleScaleSlider = createPrecisionSlider')
text = text.replace('local groundFrictionSlider = createPrecisionSlider', 'groundFrictionSlider = createPrecisionSlider')
text = text.replace('local recoveryDelaySlider = createPrecisionSlider', 'recoveryDelaySlider = createPrecisionSlider')
text = text.replace('local isContinuousRagdoll = false', 'isContinuousRagdoll = false')
text = text.replace('local toggleContinuousRagBtn = Instance.new("TextButton")', 'toggleContinuousRagBtn = Instance.new("TextButton")')

# End 4C, begin 4D
old_4d = '''--------------------------------------------------------------------------------
-- 4D. SUB-TAB 4: AUTONOMOUS LOCOMOTION MANEUVER SUITE
--------------------------------------------------------------------------------'''

new_4d = '''end

--------------------------------------------------------------------------------
-- 4D. SUB-TAB 4: AUTONOMOUS LOCOMOTION MANEUVER SUITE
--------------------------------------------------------------------------------
do'''

assert old_4d in text, 'old_4d not found'
text = text.replace(old_4d, new_4d)

# End 4D, begin createModeCard and Section 7
old_sec7 = '''--------------------------------------------------------------------------------
-- 7. GAME MODES VIEW (1v1, 2v2, FFA, CLEAN)
--------------------------------------------------------------------------------'''

new_sec7 = '''end

function createModeCard(parent, xPos, title, badge, desc, accentCol, onClick)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 220, 0, 420)
	card.Position = UDim2.new(0, xPos, 0, 0)
	card.BackgroundColor3 = C_CARD
	card.Parent = parent
	applyCorner(card, 8)
	applyStroke(card, C_BORDER, 1)

	local cardBadge = Instance.new("TextLabel")
	cardBadge.Size = UDim2.new(1, -20, 0, 20)
	cardBadge.Position = UDim2.new(0, 10, 0, 14)
	cardBadge.BackgroundTransparency = 1
	cardBadge.TextColor3 = accentCol
	cardBadge.Font = Enum.Font.GothamBold
	cardBadge.TextSize = 10
	cardBadge.TextXAlignment = Enum.TextXAlignment.Left
	cardBadge.Text = string.upper(badge)
	cardBadge.Parent = card

	local cardTitle = Instance.new("TextLabel")
	cardTitle.Size = UDim2.new(1, -20, 0, 26)
	cardTitle.Position = UDim2.new(0, 10, 0, 36)
	cardTitle.BackgroundTransparency = 1
	cardTitle.TextColor3 = C_TEXT
	cardTitle.Font = Enum.Font.GothamBold
	cardTitle.TextSize = 15
	cardTitle.TextXAlignment = Enum.TextXAlignment.Left
	cardTitle.Text = title
	cardTitle.Parent = card

	local cardDesc = Instance.new("TextLabel")
	cardDesc.Size = UDim2.new(1, -20, 0, 240)
	cardDesc.Position = UDim2.new(0, 10, 0, 68)
	cardDesc.BackgroundTransparency = 1
	cardDesc.TextColor3 = C_TEXT_MUTED
	cardDesc.Font = Enum.Font.Gotham
	cardDesc.TextSize = 12
	cardDesc.TextXAlignment = Enum.TextXAlignment.Left
	cardDesc.TextYAlignment = Enum.TextYAlignment.Top
	cardDesc.TextWrapped = true
	cardDesc.Text = desc
	cardDesc.Parent = card

	local launchBtn = Instance.new("TextButton")
	launchBtn.Size = UDim2.new(1, -20, 0, 40)
	launchBtn.Position = UDim2.new(0, 10, 1, -52)
	launchBtn.BackgroundColor3 = accentCol
	launchBtn.TextColor3 = Color3.new(0, 0, 0)
	launchBtn.Font = Enum.Font.GothamBold
	launchBtn.TextSize = 12
	launchBtn.Text = "Launch Mode ▶"
	launchBtn.Parent = card
	applyCorner(launchBtn, 6)

	launchBtn.MouseButton1Click:Connect(function()
		onClick(launchBtn)
	end)

	return card
end

--------------------------------------------------------------------------------
-- 7. GAME MODES VIEW (1v1, 2v2, FFA, CLEAN)
--------------------------------------------------------------------------------
do'''

assert old_sec7 in text, 'old_sec7 not found'
text = text.replace(old_sec7, new_sec7)

# Remove the original inner createModeCard definition from section 7
old_inner_card = '''local function createModeCard(parent, xPos, title, badge, desc, accentCol, onClick)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 220, 0, 420)
	card.Position = UDim2.new(0, xPos, 0, 0)
	card.BackgroundColor3 = C_CARD
	card.Parent = parent
	applyCorner(card, 8)
	applyStroke(card, C_BORDER, 1)

	local cardBadge = Instance.new("TextLabel")
	cardBadge.Size = UDim2.new(1, -20, 0, 20)
	cardBadge.Position = UDim2.new(0, 10, 0, 14)
	cardBadge.BackgroundTransparency = 1
	cardBadge.TextColor3 = accentCol
	cardBadge.Font = Enum.Font.GothamBold
	cardBadge.TextSize = 10
	cardBadge.TextXAlignment = Enum.TextXAlignment.Left
	cardBadge.Text = string.upper(badge)
	cardBadge.Parent = card

	local cardTitle = Instance.new("TextLabel")
	cardTitle.Size = UDim2.new(1, -20, 0, 26)
	cardTitle.Position = UDim2.new(0, 10, 0, 36)
	cardTitle.BackgroundTransparency = 1
	cardTitle.TextColor3 = C_TEXT
	cardTitle.Font = Enum.Font.GothamBold
	cardTitle.TextSize = 15
	cardTitle.TextXAlignment = Enum.TextXAlignment.Left
	cardTitle.Text = title
	cardTitle.Parent = card

	local cardDesc = Instance.new("TextLabel")
	cardDesc.Size = UDim2.new(1, -20, 0, 240)
	cardDesc.Position = UDim2.new(0, 10, 0, 68)
	cardDesc.BackgroundTransparency = 1
	cardDesc.TextColor3 = C_TEXT_MUTED
	cardDesc.Font = Enum.Font.Gotham
	cardDesc.TextSize = 12
	cardDesc.TextXAlignment = Enum.TextXAlignment.Left
	cardDesc.TextYAlignment = Enum.TextYAlignment.Top
	cardDesc.TextWrapped = true
	cardDesc.Text = desc
	cardDesc.Parent = card

	local launchBtn = Instance.new("TextButton")
	launchBtn.Size = UDim2.new(1, -20, 0, 40)
	launchBtn.Position = UDim2.new(0, 10, 1, -52)
	launchBtn.BackgroundColor3 = accentCol
	launchBtn.TextColor3 = Color3.new(0, 0, 0)
	launchBtn.Font = Enum.Font.GothamBold
	launchBtn.TextSize = 12
	launchBtn.Text = "Launch Mode ▶"
	launchBtn.Parent = card
	applyCorner(launchBtn, 6)

	launchBtn.MouseButton1Click:Connect(function()
		onClick(launchBtn)
	end)

	return card
end'''

assert old_inner_card in text, 'old_inner_card not found'
text = text.replace(old_inner_card, '')

# End Section 7, begin Section 8
old_sec8 = '''--------------------------------------------------------------------------------
-- 8. TEST MODES VIEW (SPARRING LAB | INFINITE STRAFE | PROJECTILE JUMP)
--------------------------------------------------------------------------------'''

new_sec8 = '''end

--------------------------------------------------------------------------------
-- 8. TEST MODES VIEW (SPARRING LAB | INFINITE STRAFE | PROJECTILE JUMP)
--------------------------------------------------------------------------------
do'''

assert old_sec8 in text, 'old_sec8 not found'
text = text.replace(old_sec8, new_sec8)

# End Section 8, begin Section 9
old_sec9 = '''--------------------------------------------------------------------------------
-- 9. EVENT LISTENERS & PRODUCTION SYNCHRONIZATION
--------------------------------------------------------------------------------'''

new_sec9 = '''end

--------------------------------------------------------------------------------
-- 9. EVENT LISTENERS & PRODUCTION SYNCHRONIZATION
--------------------------------------------------------------------------------'''

assert old_sec9 in text, 'old_sec9 not found'
text = text.replace(old_sec9, new_sec9)

with open(r'C:\Users\User\.gemini\antigravity\scratch\AnimationLabController.lua', 'w', encoding='utf-8') as f:
    f.write(text)

print('Updated AnimationLabController.lua successfully')

lines = text.splitlines()
root_locals = [l.strip() for l in lines if l.startswith('local ')]
print(f'Total root-level locals now: {len(root_locals)}')
