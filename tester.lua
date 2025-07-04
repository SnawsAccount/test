if getgenv().KeepAmount == nil then
	getgenv().KeepAmount = 1000
end
if getgenv().ResetCharacter == nil then
	getgenv().ResetCharacter = true
end
getgenv().TargetLocation1 = Vector3.new(-628.5126342773438, 276.837890625, -1479.9002685546875)
getgenv().TargetLocation2 = Vector3.new(-450.40960693359375, 310.3192138671875, -1456.2130126953125)
if getgenv().JobId == nil then
	getgenv().JobId = game.JobId
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end

print("Waiting 3 seconds")
task.wait(3)

function filter<T>(arr: { T }, func: (T) -> boolean): { T }
	local new_arr = {}
	for _, v in pairs(arr) do
		if func(v) then
			table.insert(new_arr, v)
		end
	end
	return new_arr
end

function map<T, U>(arr: { T }, func: (T) -> U): { U }
	local new_arr = {}
	for i, v in pairs(arr) do
		new_arr[i] = func(v)
	end
	return new_arr
end

--- Constants ---
local Players = game:GetService("Players")
local VIM = Instance.new("VirtualInputManager")
local PathfindingService = game:GetService("PathfindingService")
local TeleportService = game:GetService("TeleportService")

local Player = Players.LocalPlayer

if game.JobId ~= getgenv().JobId then
	while task.wait(5) do
		TeleportService:TeleportToPlaceInstance(game.PlaceId, getgenv().JobId, Player)
	end
end

local Gui = Player.PlayerGui
local Map = workspace:WaitForChild("Map")
local Props = Map:WaitForChild("Props")
local ATMFolder = Props:WaitForChild("ATMs")

local ATMs = ATMFolder:GetChildren()
assert(#ATMs > 0, "ATMs not found (they probably changed where ATMs are)")

local function findNewATMs()
	local newATMs = ATMFolder:GetChildren()
	for _, new in pairs(newATMs) do
		local already = false
		for _, old in pairs(ATMs) do
			if new == old then
				already = true
				break
			end
		end
		if not already then
			table.insert(ATMs, new)
		end
	end
end

if Player.DisplayName == getgenv().TargetPlayer then
	return
end

local poses = {}
for _, atm in ipairs(ATMs) do
	local pos = atm:GetPivot().Position
	table.insert(poses, { pos.X, pos.Y, pos.Z })
end

setclipboard(game:GetService("HttpService"):JSONEncode(poses))

local RespawnButton = Gui.DeathScreen.DeathScreenHolder.Frame.RespawnButtonFrame.RespawnButton

local Tutorial = Gui:WaitForChild("Slideshow"):WaitForChild("SlideshowHolder")
local TutorialCloseButton = Tutorial:WaitForChild("SlideshowCloseButton")

local ATMActionPageOptions = Gui:FindFirstChild("ATMActionAmount", true).Parent
local ATMGui = ATMActionPageOptions.Parent.Parent
local ATMWithdrawButton = ATMGui:FindFirstChild("ATMWithdrawButton", true)
local ATMMainPageOptions = ATMWithdrawButton.Parent
local ATMAmount = ATMActionPageOptions:FindFirstChild("Frame"):FindFirstChildOfClass("TextBox")

local ATMConfirmButton
for _, v in pairs(ATMActionPageOptions:GetChildren()) do
	if v:IsA("TextButton") and v.ZIndex == 1 then
		ATMConfirmButton = v
	end
end

--- Utility Functions ---
local function notify(text: string, duration: number?)
	print(text)
	game:GetService("StarterGui"):SetCore("SendNotification", {
		Title = "AutoDrop",
		Text = text,
		Duration = duration or 3,
	})
end

local function rejoin()
	while task.wait(5) do
		TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, Player)
	end
end

local function keypress(key: Enum.KeyCode)
	VIM:SendKeyEvent(true, key, false, game)
	task.wait()
	VIM:SendKeyEvent(false, key, false, game)
	task.wait()
end

local function clickOnUi(element: TextButton)
	task.spawn(function()
		setthreadidentity(2)
		firesignal(element.MouseButton1Click)
	end)
	task.wait()
end

local function isCombatLogging()
	return Gui.Hotbar.HotbarHolder.List.HotbarCombatLogging.Visible
end

local function Character()
	return Player.Character or Player.CharacterAdded:Wait()
end

local function Humanoid()
	return Character():WaitForChild("Humanoid")
end

local function HRP()
	return Character():WaitForChild("HumanoidRootPart")
end

local function closest(parts)
	local closest, closest_distance = nil, math.huge
	for _, part in pairs(parts) do
		local pos = part:IsA("BasePart") and part.Position or part:GetPivot().Position
		local dist = (pos - HRP().Position).Magnitude
		if dist < closest_distance then
			closest, closest_distance = part, dist
		end
	end
	return closest
end

local function isAtmWorking(atm)
	local screen = atm:FindFirstChild("Screen", true)
	return screen and not screen.Enabled
end

local function withdraw(amount)
	clickOnUi(ATMWithdrawButton)
	ATMAmount.Text = amount or 999999999
	clickOnUi(ATMConfirmButton)
end

local function glideTo(pos: Vector3, speed: number)
	local root = HRP()
	local dist = (root.Position - pos).Magnitude
	local duration = dist / speed
	local steps = math.ceil(duration / 0.03)

	for i = 1, steps do
		local alpha = i / steps
		local newPos = root.Position:Lerp(pos, alpha)
		root.CFrame = CFrame.new(Vector3.new(newPos.X, pos.Y + 6, newPos.Z))
		task.wait(0.03)
	end
end

local function moveTo(target, checkATM)
	for _, part in pairs(workspace:GetChildren()) do
		if part:IsA("Part") and part.Name == "Waypoint" then
			part:Destroy()
		end
	end

	local position, targetModel
	if typeof(target) == "Vector3" then
		position = target
	elseif typeof(target) == "CFrame" then
		position = target.Position
	elseif target:IsA("BasePart") then
		position = target.Position
	else
		position = target:GetPivot().Position
		targetModel = target
		for _, v in pairs(target:GetChildren()) do
			if v:IsA("BasePart") and v.CanCollide then
				v.CanCollide = false
			end
		end
	end

	local path = PathfindingService:CreatePath({
		AgentCanJump = false,
		AgentCanClimb = true,
		WaypointSpacing = 5
	})

	local success, err = pcall(function()
		path:ComputeAsync(HRP().Position, position)
	end)

	if not success or path.Status ~= Enum.PathStatus.Success then
		notify("Path failed: " .. (err or tostring(path.Status)))
		rejoin()
		error("Path failed: " .. (err or tostring(path.Status)))
	end

	for _, waypoint in ipairs(path:GetWaypoints()) do
		local p = Instance.new("Part", workspace)
		p.Position = waypoint.Position
		p.Name = "Waypoint"
		p.Anchored = true
		p.CanCollide = false
		p.Color = Color3.new(1, 0, 0)
		p.Size = Vector3.new(0.2, 0.2, 0.2)
	end

	for _, waypoint in ipairs(path:GetWaypoints()) do
		if (position - HRP().Position).Magnitude <= 6 then break end
		if checkATM and targetModel and not isAtmWorking(targetModel) then
			notify("ATM stopped working, finding another one")
			return false
		end
		glideTo(waypoint.Position, 20)
	end
	return true
end

local function bank()
	for _, v in pairs(ATMMainPageOptions:GetChildren()) do
		if v:IsA("TextLabel") and v.Text:find("Bank") then
			local bank = tonumber(v.Text:sub(16))
			if not bank then error("Couldn't get bank balance " .. v.Text) end
			return bank
		end
	end
	error("Couldn't get bank balance")
end

local function resetCharacter()
	keypress(Enum.KeyCode.Escape)
	task.wait(0.1)
	keypress(Enum.KeyCode.R)
	task.wait(0.1)
	keypress(Enum.KeyCode.Return)
	task.wait(1)
	rejoin()
end

print("Waiting for loading screen")
while Gui:FindFirstChild("LoadingScreen", true) do task.wait() end

print("Entering game")
if Gui:FindFirstChild("SplashScreenGui") then
	clickOnUi(Gui.SplashScreenGui.Frame.PlayButton)
	task.wait(5)
end

print("Skipping character creator")
if Gui.CharacterCreator.Enabled then
	clickOnUi(Gui.CharacterCreator.MenuFrame.AvatarMenuSkipButton)
	task.wait(5)
end

print("Skipping tutorial")
if Tutorial.Visible then
	clickOnUi(TutorialCloseButton)
end

print("Disabling door collision")
for _, v in pairs(workspace:GetDescendants()) do
	if v:IsA("Model") and v.Name == "DoorSystem" then
		for _, p in pairs(v:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CanCollide = false
			end
		end
	end
end

--- Main Loop ---
if bank() > getgenv().KeepAmount then
	notify("Moving to ATM")
	while task.wait(0.1) do
		findNewATMs()
		local workingATMs = filter(ATMs, isAtmWorking)
		local atm = closest(workingATMs)
		if not atm or not isAtmWorking(atm) then
			notify("ATM is nil or not working")
			continue
		end
		if moveTo(atm, true) and isAtmWorking(atm) then
			notify("Moved to ATM")
			break
		end
	end

	notify("Withdrawing 1")
	withdraw(bank() - getgenv().KeepAmount)
	task.wait(0.1)
	notify("Withdrawing 2")
	withdraw(bank() - getgenv().KeepAmount)
	task.wait(0.1)
	notify("Withdrawing 3")
	withdraw(bank() - getgenv().KeepAmount)
	task.wait(0.1)
end

notify("Moving to target location 1")
moveTo(getgenv().TargetLocation1)

notify("Now moving to target location 2")
moveTo(getgenv().TargetLocation2)

while not isCombatLogging() do task.wait() end

if getgenv().ResetCharacter then
	resetCharacter()
else
	while not Gui.DeathScreen.DeathScreenHolder.Visible do task.wait() end
	task.wait(1)
	rejoin()
end
