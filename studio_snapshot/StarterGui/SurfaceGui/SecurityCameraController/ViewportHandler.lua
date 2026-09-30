--local RS, HTTP = game:GetService("RunService"), game:GetService("HttpService")

----Prefab stateless humanoid (used to wrap clothes)
--local StatelessHumanoid = Instance.new("Humanoid")
--	StatelessHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
--	StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics,true);StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown,false)
--	StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.Running,false);StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing,false)
--	StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,false);StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp,false)
--	StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,false);StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.Landed,false)
--	StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.Flying,false);StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall,false)
--	StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.Seated,false);StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding,false)
--	StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.Dead,false);StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming,false)
--	StatelessHumanoid:SetStateEnabled(Enum.HumanoidStateType.Physics,false)

----Define valids
--local ValidChildren		= {
--	Decal = true; Texture = true; SpecialMesh = true;
--}
--local ValidProperties	= {
--	Color = true; Material = true; Reflectance = true; Transparency = true; Shape = true; Size = true;
--	BackSurface = true; BottomSurface = true; FrontSurface = true; LeftSurface = true; RightSurface = true; TopSurface = true;
--}

----Don't want scripts or welds in our clone object
--local function ClearInvalidChildren(Object)
--	local Children = Object:GetChildren()
	
--	for i=1, #Children do
--		local c = Children[i]
		
--		if not ValidChildren[c.ClassName] then
--			c:Destroy()
--		end
--	end
	
--	return Object
--end

--local ObjectHandler = {}
--ObjectHandler.__index = ObjectHandler

--function ObjectHandler.new(Handler, Object,ObjectClone,FPS)
	
--	local objHandler = {}
	
--	objHandler.Enabled		= FPS and true or false
--	objHandler.Handler		= Handler
--	objHandler.Object		= Object
--	objHandler.ObjectClone	= ObjectClone
--	objHandler.WaitTime		= FPS and 1/math.clamp(FPS,0,9999) or 0.033333333333333
--	objHandler.LastUpdate	= 0
--	objHandler.ObjectID		= HTTP:GenerateGUID(false)
--	objHandler.Showing		= true
--	objHandler.Running		= true
	
	
--	setmetatable(objHandler, ObjectHandler)
	
--	if FPS and FPS>0 then
--		Handler.ObjectsRenderQueue[objHandler.ObjectID] = objHandler
--	end
	
--	return objHandler
--end

--function ObjectHandler:Destroy()
--	self.Handler.ObjectsRenderQueue[self.ObjectID] = nil
--	self.ObjectClone:Destroy()
--end

--function ObjectHandler:SetFPS(NewFPS)
--	if NewFPS and type(NewFPS) == "number" then		
--		self.WaitTime = 1/math.clamp(NewFPS,0,9999)
		
--		if NewFPS>0 then
--			self.Handler.ObjectsRenderQueue[self.ObjectID] = self
--		else
--			self.Handler.ObjectsRenderQueue[self.ObjectID] = nil
--		end
--	end
--end

--function ObjectHandler:Pause()
--	self.Enabled = false
--	self.Running = false
--end

--function ObjectHandler:Resume()
--	self.Enabled = self.Showing
--	self.Running = true
--end

--function ObjectHandler:Hide()
--	self.Enabled = false
--	self.ObjectClone.Transparency =1
--	self.Showing = false
--end

--function ObjectHandler:Show()	
--	self.Enabled = self.Running
--	self.ObjectClone.Transparency = self.Object.Transparency
--	self.Showing = true
--end

--function ObjectHandler:Refresh()
--	if self.Enabled then return end
	
--	self.ObjectClone.CFrame = self.Object.CFrame
	
--	for prop,_ in pairs(ValidProperties) do
--		self.ObjectClone[prop] = self.Object[prop]
--	end
	
--end



--local ViewportHandler = {}
--ViewportHandler.__index = ViewportHandler

--function ViewportHandler.new(Frame)
	
--	--Sanity checks
--	if not Frame or not (typeof(Frame) == "Instance" and Frame:IsA("ViewportFrame")) then warn("Invalid ViewportFrame") return end
	
--	local Handler = {
--		HandlerID = HTTP:GenerateGUID(false);
--		Frame = Frame;
--		ObjectsRenderQueue = {};
--	}
	
--	setmetatable(Handler, ViewportHandler)
	
--	RS:BindToRenderStep("VH-"..Handler.HandlerID, Enum.RenderPriority.Camera.Value+1, function(Delta)
--		for ObjectID, ObjectInfo in pairs(Handler.ObjectsRenderQueue) do
--			local Object,ObjectClone,WaitTime = ObjectInfo.Object,ObjectInfo.ObjectClone,ObjectInfo.WaitTime
			
--			if Object and Object.Parent then
				
--				ObjectInfo.LastUpdate = ObjectInfo.LastUpdate + Delta
							
--				if ObjectInfo.Enabled and Object.CFrame ~= ObjectClone.CFrame and ObjectInfo.LastUpdate >= WaitTime then
--					--If it has moved and FPS time has passed, then update
--					ObjectInfo.LastUpdate = 0
--					ObjectClone.CFrame = Object.CFrame
--				end
--			else
--				ObjectInfo:Destroy()
--			end
--		end
--	end)
	
--	return Handler
--end


--function ViewportHandler:RenderObject(Object, FPS, Parent)
	
--	--Sanity checks
--	if not Object or not (typeof(Object) == "Instance" and Object:IsA("BasePart")) then warn("Invalid Object") return end
	
--	--Create clone for viewport
--	local ObjectClone = ClearInvalidChildren(Object:Clone())
	
--	--Create handler
--	local objHandler = ObjectHandler.new(self, Object,ObjectClone,FPS)
	
--	--Auto update visual properties
--	Object.Changed:Connect(function(Property)
--		if objHandler.Enabled and ValidProperties[Property] then
--			ObjectClone[Property] = Object[Property]
--		end
--	end)
	
	
	
--	--Display
--	ObjectClone.Parent = Parent or self.Frame
	
--	return objHandler
--end


--function ViewportHandler:RenderHumanoid(Character, Parent)
	
--	--Sanity checks
--	if not Character or not (typeof(Character) == "Instance" and Character:IsA("Model")) then warn("Invalid Humanoid") return end
--	if not Character:FindFirstChildOfClass("Humanoid",true) then warn("Invalid Humanoid") return end
	
	
--	local humHandler = {
--		ObjHandlers = {}
--	}
	
--	local CharacterClone = Instance.new("Model")
--		CharacterClone.Name = Character.Name
		
--	local Descendants	= Character:GetDescendants()
--	for i=1, #Descendants do
--		local d = Descendants[i]
		
--		if d:IsA("BasePart") then
--			humHandler.ObjHandlers[#humHandler.ObjHandlers+1] = self:RenderObject(d,99,CharacterClone)
--		end
--	end
	
--	local Shirt,Pants = Character:FindFirstChildOfClass("Shirt"),Character:FindFirstChildOfClass("Pants")
	
--	if Shirt then Shirt:Clone().Parent = CharacterClone end
--	if Pants then Pants:Clone().Parent = CharacterClone end
	
	
--	local Humanoid = StatelessHumanoid:Clone()
--		Humanoid.RigType = Character:FindFirstChildOfClass("Humanoid",true).RigType
--		Humanoid.Parent = CharacterClone
	
--	CharacterClone.Parent = Parent or self.Frame
	
	
	
--	function humHandler:Destroy()
--		for i=1, #self.ObjHandlers do
--			self.ObjHandlers[i]:Destroy()
--		end
--		CharacterClone:Destroy()
--	end
	
--	return humHandler
--end

--function ViewportHandler:Destroy()
--	RS:UnbindFromRenderStep("VH-"..self.HandlerID)
	
--	for ObjectID, ObjectInfo in pairs(self.ObjectsRenderQueue) do
--		if ObjectInfo.ObjectClone then
--			ObjectInfo.ObjectClone:Destroy()
--		end
--	end
	
--	self.ObjectsRenderQueue = nil
--	self.Frame = nil
--end

--return ViewportHandler
