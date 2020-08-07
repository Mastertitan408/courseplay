
TriggerHandler = CpObject()

TriggerHandler.myLoadingStates = {
	IS_LOADING = {},
	NOTHING = {},
	APPROACH_TRIGGER = {},
	APPROACH_AUGER_TRIGGER = {},
	IS_UNLOADING = {},
	DRIVE_NOW = {},
	STOPPED = {}
}
TriggerHandler.APPROACH_AUGER_TRIGGER_SPEED = 3

function TriggerHandler:init(vehicle,...)
	self.vehicle = vehicle
	self.driver = vehicle.cp.driver
	self.siloSelectedFillTypeSetting=SiloSelectedFillTypeSetting
	self.allwaysSearchFuel = vehicle.cp.settings.allwaysSearchFuel
	self.validFillTypeLoading = false
	self.validFillTypeUnloading = false
	self.validFuelLoading = false
	self.loadingState = self.states.NOTHING
	self.triggers = {}
	self.isInAugerWagonTrigger = false
	self.fillableObject = nil
end 

function TriggerHandler:onStart()
	
end 

function TriggerHandler:onStop()
	
end 

function TriggerHandler:onUpdate()
	if self.validFillTypeLoading or self.validFuelLoading and self:checkFuel() then
		self:updateLoadingTriggers()
	end
	if self.validFillTypeUnloading then 
		self:updateUnloadingTriggers()
	end
end 

function TriggerHandler:updateLoadingTriggers()
	self:activateLoadingTriggerWhenAvailable()
	self:activateFillTriggersWhenAvailable(self.vehicle)
	if self:isLoading() then
		self:disableFillingIfFull()
	end
end 

function TriggerHandler:updateUnloadingTriggers()
	self:activateUnloadingTriggerWhenAvailable(self.vehicle)
end 

function TriggerHandler:disableFillingIfFull()
	if self:isFilledUntilPercantageX() then 
		self:forceStopLoading()
	end
end

function TriggerHandler:setLoadingText(fillType,fillLevel,capacity)
	self.loadingText = {}
	self.loadingText.fillLevel = fillLevel
	self.loadingText.capacity = capacity
end

function TriggerHandler:setUnloadingText(fillType,fillLevel,capacity)	
	self.unloadingText = {}
	self.unloadingText.fillLevel = fillLevel
	self.unloadingText.capacity = capacity
end

function TriggerAIDriver:isFilledUntilPercantageX(maxFillLevelPercentage)
	if self.fillableObject then 
		local object = self.fillableObject.object
		local fillUnitIndex = self.fillableObject.fillUnitIndex
		if object:getFillUnitFillLevelPercentage*100 > 	maxFillLevelPercentage then 
			return true
		end
	end
end

function TriggerAIDriver:checkFilledUnitFillPercantage()
	local fillTypeData, fillTypeDataSize= self:getSiloSelectedFillTypeData()
	if fillTypeData == nil then
		return
	end
	local fillLevelInfo = {}
	local okFillTypes = 0
	self:getAllFillLevels(self.vehicle, fillLevelInfo)
	for fillType, info in pairs(fillLevelInfo) do	
		if fillTypeData then 
			for _,data in ipairs(fillTypeData) do
				if data.fillType == fillType then
					local fillLevelPercentage = info.fillLevel/info.capacity*100
					if data.maxFillLevel and fillLevelPercentage >= data.maxFillLevel then 
						if self.fillableObject and self.fillableObject.fillType == fillType then
							self:forceStopLoading()
						end
						okFillTypes=okFillTypes+1
					end
				end
			end
		end
	end
	if okFillTypes == #fillTypeData then 
		return true
	end
end

--TODO might change this one 
function TriggerAIDriver:levelDidNotChange(fillLevelPercent)
	--fillLevel changed in last loop-> start timer
	if self.prevFillLevelPct == nil or self.prevFillLevelPct ~= fillLevelPercent then
		self.prevFillLevelPct = fillLevelPercent
		courseplay:setCustomTimer(self.vehicle, "fillLevelChange", 3)
	end
	--if time is up and no fillLevel change happend, return true
	if courseplay:timerIsThrough(self.vehicle, "fillLevelChange",false) then
		if self.prevFillLevelPct == fillLevelPercent then
			return true
		end
		courseplay:resetCustomTimer(self.vehicle, "fillLevelChange",nil)
	end
end

function TriggerAIDriver:getSiloSelectedFillTypeSetting()
	--override
end

function TriggerAIDriver:getSiloSelectedFillTypeData()
	local siloSelectedFillTypeSetting = self:getSiloSelectedFillTypeSetting()
	if siloSelectedFillTypeSetting then
		local fillTypeData = siloSelectedFillTypeSetting:getData()
		local size = siloSelectedFillTypeSetting:getSize()
		return fillTypeData,size
	end
end

----

--Driver set to wait while loading
function TriggerHandler:setLoadingState(object,fillUnitIndex,fillType,trigger)
	self.fillableObject = {}
	self.fillableObject.object = object
	self.fillableObject.fillUnitIndex = fillUnitIndex
	self.fillableObject.fillType = fillType
	self.fillableObject.trigger = trigger
	if not self:isDriveNowActivated() and not self:isLoading() then
		self.loadingState=self.states.IS_LOADING
		self:refreshHUD()
	end
end


function TriggerHandler:isLoading()
	if self.loadingState == self.states.IS_LOADING then
		return true
	end
end

function TriggerHandler:isUnloading()
	if self.loadingState == self.states.IS_UNLOADING then
		return true
	end
end

--Driver stops loading
function TriggerAIDriver:resetLoadingState()
	if not self:ignoreTrigger() then 
		if not self.activeTriggers then
			self.loadingState=self.states.NOTHING
		else
			self.loadingState=self.states.APPROACH_TRIGGER
		end
	end
	self.augerTriggerSpeed=nil
	self.fillableObject = nil
end

--Driver set to wait while unloading
function TriggerAIDriver:setUnloadingState(object)
	if object then 
		self.fillableObject = {} 
		self.fillableObject.object = object --used to enable self:forceStopLoading()
	else
		self.fillableObject = nil
	end
	if not self:ignoreTrigger() then
		self.loadingState=self.states.IS_UNLOADING
		self:refreshHUD()
	end
end

--Driver stops unloading 
function TriggerAIDriver:resetUnloadingState()
	if not self:ignoreTrigger() then
		self.loadingState=self.states.NOTHING
	end
	self.fillableObject = nil
end

--countTriggerUp/countTriggerDown used to check current Triggers
function TriggerHandler:countTriggerUp(triggerId,object)
	if object and triggerId then
		if self.triggers[triggerId] == nil then
			self.triggers[triggerId] = {}
		end
		self.triggers[triggerId][object]=true
	end
end

function TriggerHandler:countTriggerDown(triggerId,object)
	if object and triggerId then
		if self.triggers[triggerId] and self.triggers[triggerId][object] then
			self.triggers[triggerId][object]=nil
			for triggerId,data in pairs(self.triggers) do 
				local hasObject = false
				for object,bool in pairs(data) do 
					if bool then
						hasObject = true
						break
					end
				end
				if not hasObject then
					self.triggers[triggerId] = nil
				end
			end
		end
		if not self:isInTrigger() then 
			self:disableTriggerSpeed()
		end
	end 
end

function TriggerHandler:enableTriggerSpeed()
	if not self:isDriveNowActivated() then 
		self.loadingState = self.isInAugerWagonTrigger and self.states.APPROACH_AUGER_TRIGGER or self.states.APPROACH_TRIGGER
	end
end

function TriggerHandler:disableTriggerSpeed()
	if not self:isDriveNowActivated() then 
		self.loadingState = self.states.NOTHING
	end
end

function TriggerHandler:isInTrigger()
	return #self.triggers > 0
end

function TriggerHandler:isDriveNowActivated()
	return self.loadingState == self.states.DRIVE_NOW
end

--force stop loading/ unloading if "continue" or stop is pressed
function TriggerAIDriver:forceStopLoading()
	if self.fillableObject then 
		if self.fillableObject.trigger then 
			if self.fillableObject.trigger:isa(Vehicle) then --disable filling at Augerwagons
				--TODO!!
			else --disable filling at LoadingTriggers
				self.fillableObject.trigger:setIsLoading(false)
			end
		else 
			if self:isLoading() then -- disable filling at fillTriggers
				self.fillableObject.object:setFillUnitIsFilling(false)
			else -- disable unloading
				self.fillableObject.object:setDischargeState(Dischargeable.DISCHARGE_STATE_OFF)
			end
		end
	end
end

--- Check if need to refill/unload anything
function TriggerAIDriver:allFillLevelsOk()
	if not self.vehicle.cp.workTools then return false end
	-- what here comes is basically what Giants' getFillLevelInformation() does but this returns the real fillType,
	-- not the fillTypeToDisplay as this latter is different for each type of seed
	local fillLevelInfo = {}
	self:getAllFillLevels(self.vehicle, fillLevelInfo)
	return self:areFillLevelsOk(fillLevelInfo)
end

function TriggerAIDriver:getAllFillLevels(object, fillLevelInfo)
	-- get own fill levels
	if object.getFillUnits then
		for _, fillUnit in pairs(object:getFillUnits()) do
			local fillType = self:getFillTypeFromFillUnit(fillUnit)
			local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillType)
			self:debugSparse('%s: Fill levels: %s: %.1f/%.1f', object:getName(), fillTypeName, fillUnit.fillLevel, fillUnit.capacity)
			if not fillLevelInfo[fillType] then fillLevelInfo[fillType] = {fillLevel=0, capacity=0} end
			fillLevelInfo[fillType].fillLevel = fillLevelInfo[fillType].fillLevel + fillUnit.fillLevel
			fillLevelInfo[fillType].capacity = fillLevelInfo[fillType].capacity + fillUnit.capacity
		end
	end
 	-- collect fill levels from all attached implements recursively
	for _,impl in pairs(object:getAttachedImplements()) do
		self:getAllFillLevels(impl.object, fillLevelInfo)
	end
end

function TriggerAIDriver:getFillTypeFromFillUnit(fillUnit)
	local fillType = fillUnit.lastValidFillType or fillUnit.fillType
	-- TODO: do we need to check more supported fill types? This will probably cover 99.9% of the cases
	if fillType == FillType.UNKNOWN then
		-- just get the first valid supported fill type
		for ft, valid in pairs(fillUnit.supportedFillTypes) do
			if valid then return ft end
		end
	else
		return fillType
	end
end

function TriggerAIDriver:areFillLevelsOk(fillLevelInfo)
	return true
end

function TriggerAIDriver:checkTriggerMinStartFillLevel(minFillPercentage,objectFillCapacity,triggerFillLevel)
	return true
end

function TriggerAIDriver:checkRunCounterAllowed(runCounter)
	return true
end

function TriggerHandler:needsFuel()
	local dieselIndex = self.vehicle:getConsumerFillUnitIndex(FillType.DIESEL)
	local currentFuelPercentage = self.vehicle:getFillUnitFillLevelPercentage(dieselIndex) * 100
	local searchForFuel = self.allwaysSearchFuel:is(true) and currentFuelPercentage < 99 or currentFuelPercentage < 20
	if searchForFuel then 
		return true
	end
end

function TriggerAIDriver:checkFuel()
	self:activateLoadingTriggerWhenAvailable()
	self:activateFillTriggersWhenAvailable(self.vehicle)
end

--Trigger stuff


--scanning for LoadingTriggers and FillTriggers(checkFillTriggers)
function TriggerHandler:activateLoadingTriggerWhenAvailable()
	for key, object in pairs(g_currentMission.activatableObjects) do
		if object:getIsActivatable(self.vehicle) then
			local callback = {}		
			if object:isa(LoadTrigger) then 
				self:activateTriggerForVehicle(object, self.vehicle)
				return
			end
        end
    end
    return
end

--check recusively if fillTriggers are enableable 
function TriggerHandler:activateFillTriggersWhenAvailable(object)
	if object.spec_fillUnit then
		local spec = object.spec_fillUnit
		local coverSpec = object.spec_cover	
		if spec.fillTrigger and #spec.fillTrigger.triggers>0 then
			if not self.driver:ignoreTrigger() and not spec.fillTrigger.isFilling then	
				if coverSpec and coverSpec.isDirty then 
					courseplay.debugFormat(2,"cover is still opening wait!")
					self.driver:setLoadingState()
				else
					object:setFillUnitIsFilling(true)
				end
			end
		end
	end
	-- get all attached implements recursively
	for _,impl in pairs(object:getAttachedImplements()) do
		self:activateFillTriggersWhenAvailable(impl.object)
	end
end

--check for standart object unloading Triggers
function TriggerHandler:activateUnloadingTriggerWhenAvailable(object)    
	local spec = object.spec_dischargeable
	local rootVehicle = object:getRootVehicle()
	if rootVehicle and spec then 
		if spec:getCanToggleDischargeToObject() then 
			local currentDischargeNode = spec.currentDischargeNode
			if currentDischargeNode then
				if currentDischargeNode.dischargeObject then 
					self.driver:countTriggerUp(object)
					self.driver:setInTriggerRange()
					if not self.driver:isUnloading() then
						courseplay:setInfoText(rootVehicle,"COURSEPLAY_TIPTRIGGER_REACHED")
					end
				else
					self.driver:countTriggerDown(object)
				end
				if currentDischargeNode.dischargeFailedReason == Dischargeable.DISCHARGE_REASON_NO_FREE_CAPACITY then 
					CpManager:setGlobalInfoText(rootVehicle, 'FARM_SILO_IS_FULL');
					self.driver:setUnloadingState()
				elseif currentDischargeNode.dischargeFailedReason == Dischargeable.DISCHARGE_REASON_FILLTYPE_NOT_SUPPORTED then
				--	CpManager:setGlobalInfoText(rootVehicle, 'WRONG_FILLTYPE_FOR_TRIGGER');
				end
				if spec.currentDischargeState == Dischargeable.DISCHARGE_STATE_OFF then
					if not spec:getCanDischargeToObject(currentDischargeNode) then
						for i=1,#spec.dischargeNodes do
							if spec:getCanDischargeToObject(spec.dischargeNodes[i])then
								spec:setCurrentDischargeNodeIndex(spec.dischargeNodes[i]);
								currentDischargeNode = spec:getCurrentDischargeNode()
								break
							end
						end
					end
					if spec:getCanDischargeToObject(currentDischargeNode) and not self.driver:isNearFillPoint() then
						if not object:getFillUnitFillType(currentDischargeNode.fillUnitIndex) or self.driver:ignoreTrigger() then 
							return
						end
						spec:setDischargeState(Dischargeable.DISCHARGE_STATE_OBJECT)				
						self.driver:setUnloadingState(object)
					end
				end
			end
		else
			self.driver:countTriggerDown(object)
		end
	end
	for _,impl in pairs(object:getAttachedImplements()) do
		TriggerAIDriver:activateUnloadingTriggerWhenAvailable(impl.object)
	end
end

function TriggerHandler:onStop()
	
end 

function TriggerHandler:enableFillTypeLoading()
	self.validFillTypeLoading = true
end 

function TriggerHandler:enableFillTypeUnloading()
	self.validFillTypeUnloading = true
end

function TriggerHandler:enableFuelLoading()
	self.validFuelLoading = true
end

function TriggerHandler:disableFillTypeLoading()
	self.validFillTypeLoading = false
end 

function TriggerHandler:disableFillTypeUnloading()
	self.validFillTypeUnloading = false
end

function TriggerHandler:disableFuelLoading()
	self.validFuelLoading = false
end

function TriggerHandler:isAllowedToLoadFillType()
	
end 

function TriggerHandler:isAllowedToLoadFuel()
	if self.validFuelLoading and self:needsFuel() then
		return true
	end
end 

function TriggerHandler:canLoadFillType(object,fillUnitIndex,maxFillLevelPercentage,minFillLevelPercentage,triggerFillLevel)  
	local objectFillCapacity = object:getFillUnitFillLevelPercentage(fillUnitIndex)
	local objectFillLevelPercentage = object:getFillLevelPercentage(fillUnitIndex)
	if objectFillLevelPercentage*100 < maxFillLevelPercentage then 
		if minFillLevelPercentage and triggerFillLevel then 
			if minFillLevelPercentage
		end
		return true
	end
end


-- Custom version of trigger:onActivateObject to allow activating for a non-controlled vehicle
function TriggerHandler:activateTriggerForVehicle(trigger, vehicle)
	--Cache giant values to restore later
	local defaultGetFarmIdFunction = g_currentMission.getFarmId;
	local oldControlledVehicle = g_currentMission.controlledVehicle;

	--Override farm id to match the calling vehicle (fixes issue when obtaining fill levels)
	local overriddenFarmIdFunc = function()
		local ownerFarmId = vehicle:getOwnerFarmId()
		courseplay.debugVehicle(19, vehicle, 'Overriding farm id during trigger activation to %d', ownerFarmId);
		return ownerFarmId;
	end
	g_currentMission.getFarmId = overriddenFarmIdFunc;

	--Override controlled vehicle if I'm not in it
	if g_currentMission.controlledVehicle ~= vehicle then
		g_currentMission.controlledVehicle = vehicle;
	end

	--Call giant method with new params set
	--trigger:onActivateObject(vehicle,callback);
	trigger:onActivateObject(vehicle)
	--Restore previous values
	g_currentMission.getFarmId = defaultGetFarmIdFunction;
	g_currentMission.controlledVehicle = oldControlledVehicle;
end

-- LoadTrigger doesn't allow filling non controlled tools
function TriggerHandler:getIsActivatable(superFunc,objectToFill)
	--when the trigger is filling, it uses this function without objectToFill
	if objectToFill ~= nil then
		local vehicle = objectToFill:getRootVehicle()
		if objectToFill:getIsCourseplayDriving() or (vehicle~= nil and vehicle:getIsCourseplayDriving()) then
			--if i'm in the vehicle, all is good and I can use the normal function, if not, i have to cheat:
			if g_currentMission.controlledVehicle ~= vehicle then
				local oldControlledVehicle = g_currentMission.controlledVehicle;
				g_currentMission.controlledVehicle = vehicle or objectToFill;
				local result = superFunc(self,objectToFill);
				g_currentMission.controlledVehicle = oldControlledVehicle;
				return result;
			end
		end
	end
	return superFunc(self,objectToFill);
end
LoadTrigger.getIsActivatable = Utils.overwrittenFunction(LoadTrigger.getIsActivatable,TriggerHandler.getIsActivatable)

--LoadTrigger activate, if fillType is right and fillLevel ok 
function TriggerHandler:onActivateObject(superFunc,vehicle,callback)
	if courseplay:isAIDriverActive(vehicle) then 
		local triggerHandler = vehicle.cp.driver.triggerHandler
		if not triggerHandler:isAllowedToLoadFuel() and not triggerHandler:isAllowedToLoadFillType() then 
			return superFunc(self)
		end
		
		if not self.isLoading then
			local fillLevels, capacity
			--normal fillLevels of silo
			if self.source.getAllFillLevels then 
				fillLevels, capacity = self.source:getAllFillLevels(g_currentMission:getFarmId())
			--g_company fillLevels of silo
			elseif self.source.getAllProvidedFillLevels then --g_company fillLevels
				--self.managerId should be self.extraParameter!!!
				fillLevels, capacity = self.source:getAllProvidedFillLevels(g_currentMission:getFarmId(), self.managerId)
			else
				return superFunc(self)
			end
			local fillableObject = self.validFillableObject
			local fillUnitIndex = self.validFillableFillUnitIndex
			local firstFillType = nil
			local validFillTypIndexes = {}
			local emptyOnes = 0
			local lastCounter
			for fillTypeIndex, fillLevel in pairs(fillLevels) do
				if fillTypeIndex == FillType.DIESEL  then 
					if self:needsFuel() then
						if fillableObject:getFillUnitAllowsFillType(fillUnitIndex, fillTypeIndex) then
							self:onFillTypeSelection(fillTypeIndex)
							if callback then callback.ok = true end
						end
					end
					return
				end
			end
			if triggerHandler:isAllowedToLoadFillType() then
				for _,data in ipairs(fillTypeData) do
					for fillTypeIndex, fillLevel in pairs(fillLevels) do
						if self.fillTypes == nil or self.fillTypes[fillTypeIndex] then
							if fillableObject:getFillUnitAllowsFillType(fillUnitIndex, fillTypeIndex) then
								
								
								
								--check silo fillLevel
								if fillLevel > 0 and vehicle.cp.driver:checkTriggerMinStartFillLevel(data.minFillLevel,fillableObject:getFillUnitCapacity(fillUnitIndex),fillLevel) and fillTypeIndex == data.fillType then 
									--cover is open, wait till it's open to start load
									if vehicle.cp.driver:checkRunCounterAllowed(data.runCounter) then
										if fillableObject.spec_cover and fillableObject.spec_cover.isDirty then 
											vehicle.cp.driver:setLoadingState(fillableObject,fillUnitIndex,fillTypeIndex,self)
											courseplay.debugFormat(2, 'Cover is still opening!')
											return
										end
										--fixes giants bug for Lemken Solitaer with has fillunit that keeps on filling to infinity
										if fillableObject:getFillUnitCapacity(fillUnitIndex) <=0 then 
											vehicle.cp.driver:resetLoadingState()
											return
										else
										--start loading everthing is ok
											self:onFillTypeSelection(fillTypeIndex)
											g_currentMission.activatableObjects[self] = nil
											return								
										end
									else
										courseplay.debugFormat(2, 'runCounter = 0!')
									end
								else
									courseplay.debugFormat(2, 'FillType is empty or minFillLevel not reached!')
									emptyOnes = emptyOnes+1
								end
							else 
								courseplay.debugFormat(2, 'FillLevel reached!')
								g_currentMission.activatableObjects[self] = nil
								vehicle.cp.driver:resetLoadingState()
								break
							end
						end
					end
					lastCounter=data.runCounter
				end
			end
			if triggerHandler:isAllowedToLoadFuel() then 
				for fillTypeIndex, fillLevel in pairs(fillLevels) do
					if fillTypeIndex == FillType.DIESEL  then 
						if fillableObject:getFillUnitAllowsFillType(fillUnitIndex, fillTypeIndex) then
							if triggerHandler:canLoadFillType(object,fillunit,99) then 
								self:onFillTypeSelection(fillTypeIndex)
								g_currentMission.activatableObjects[self] = nil
							end
						end
					end
				end
			end
			--if all selected fillTypes are empty in the trigger and no fillLevel reached => wait for more
			if emptyOnes == fillTypeDataSize and not callback.ok and emptyOnes>0 then 
				vehicle.cp.driver:setLoadingState()
				CpManager:setGlobalInfoText(vehicle, 'FARM_SILO_IS_EMPTY');
				courseplay.debugFormat(2, 'Silo empty, emptyOnes: '..emptyOnes)
				return
			elseif lastCounter === 0 then 
				vehicle.cp.driver:setLoadingState()
				CpManager:setGlobalInfoText(vehicle, 'RUNCOUNTER_ERROR_FOR_TRIGGER');
				courseplay.debugFormat(2, 'last runCounter=0 ')
				return
			end
		end
	else 
		return superFunc(self)
	end
end
LoadTrigger.onActivateObject = Utils.overwrittenFunction(LoadTrigger.onActivateObject,TriggerHandler.onActivateObject)

--LoadTrigger => start/stop driver and close cover once free from trigger
function TriggerHandler:setIsLoading(superFunc,isLoading, targetObject, fillUnitIndex, fillType, noEventSend)
	local rootVehicle = self.validFillableObject:getRootVehicle()
	if courseplay:isAIDriverActive(rootVehicle) then
		local triggerHandler = rootVehicle.cp.driver.triggerHandler
		if not triggerHandler.validFillTypeLoading and not triggerHandler.validFuelLoading then
			return superFunc(self,isLoading, targetObject, fillUnitIndex, fillType, noEventSend)
		end
		if isLoading then 
			triggerHandler:setLoadingState(self.validFillableObject,fillUnitIndex, fillType,self)
			courseplay.debugFormat(2, 'LoadTrigger setLoading, FillType: '..g_fillTypeManager:getFillTypeByIndex(fillType).title)
		else 
			triggerHandler:resetLoadingState()
			courseplay.debugFormat(2, 'LoadTrigger resetLoading and close Cover')
			SpecializationUtil.raiseEvent(self.validFillableObject, "onRemovedFillUnitTrigger",#self.validFillableObject.spec_fillUnit.fillTrigger.triggers)
			g_currentMission:addActivatableObject(self)
		end
	end
	return superFunc(self,isLoading, targetObject, fillUnitIndex, fillType, noEventSend)
end
LoadTrigger.setIsLoading = Utils.overwrittenFunction(LoadTrigger.setIsLoading,TriggerHandler.setIsLoading)

--close cover after tipping for trailer if not closed already
function TriggerHandler:endTipping(superFunc,noEventSend)
	local rootVehicle = self:getRootVehicle()
	if courseplay:isAIDriverActive(rootVehicle) then
		if rootVehicle.cp.settings.automaticCoverHandling:is(true) and self.spec_cover then
			self:setCoverState(0, true)
		end
		rootVehicle.cp.driver:resetUnloadingState()
	end
	return superFunc(self,noEventSend)
end
Trailer.endTipping = Utils.overwrittenFunction(Trailer.endTipping,TriggerHandler.endTipping)

function TriggerHandler:setFillUnitIsFilling(superFunc,isFilling, noEventSend)
	local rootVehicle = self:getRootVehicle()
	if courseplay:isAIDriverActive(rootVehicle) then 
		if not rootVehicle.cp.driver:isLoadingTriggerCallbackEnabled() then 
			return superFunc(self,isFilling, noEventSend)
		end
		if not self:isAllowedToLoadFillType(trigger:getCurrentFillType(),self) or not self.validFuelLoading then
			return superFunc(self,isFilling, noEventSend)
		end
		local spec = self.spec_fillUnit
		if isFilling ~= spec.fillTrigger.isFilling then
			if noEventSend == nil or noEventSend == false then
				if g_server ~= nil then
					g_server:broadcastEvent(SetFillUnitIsFillingEvent:new(self, isFilling), nil, nil, self)
				else
					g_client:getServerConnection():sendEvent(SetFillUnitIsFillingEvent:new(self, isFilling))
				end
			end
			if isFilling then
				-- find the first trigger which is activable
				spec.fillTrigger.currentTrigger = nil
				for _, trigger in ipairs(spec.fillTrigger.triggers) do
					if trigger:getIsActivatable(self) then
						local fillType = trigger:getCurrentFillType()
						local fillUnitIndex = nil
						local dieselFound = fillType == FillType.DIESEL
						if fillType and (fillType == data.fillType or dieselFound) then
							fillUnitIndex = self:getFirstValidFillUnitToFill(fillType)
						end
						if fillUnitIndex then
							rootVehicle = self:getRootVehicle()
							rootVehicle.cp.driver:setLoadingState(self,fillUnitIndex,fillType)
							spec.fillTrigger.currentTrigger = trigger
							courseplay.debugFormat(2,"FillUnit setLoading, FillType: "..g_fillTypeManager:getFillTypeByIndex(fillType).title)
							break
						end
					end
				end
			end
			spec.fillTrigger.isFilling = isFilling
			if self.isClient then
				self:setFillSoundIsPlaying(isFilling)
				if spec.fillTrigger.currentTrigger ~= nil then
					spec.fillTrigger.currentTrigger:setFillSoundIsPlaying(isFilling)
				end
			end
			SpecializationUtil.raiseEvent(self, "onFillUnitIsFillingStateChanged", isFilling)
			if not isFilling then
				self:updateFillUnitTriggers()
				rootVehicle.cp.driver:resetLoadingState()
				courseplay.debugFormat(2,"FillUnit resetLoading")
			end
		end
		return
	end
	return superFunc(self,isFilling, noEventSend)
end
FillUnit.setFillUnitIsFilling = Utils.overwrittenFunction(FillUnit.setFillUnitIsFilling,TriggerHandler.setFillUnitIsFilling)


--LoadTrigger callback used to open correct cover for loading 
function TriggerHandler:loadTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
	--legancy code!!!
	courseplay:SiloTrigger_TriggerCallback(self, triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)
	
	local fillableObject = g_currentMission:getNodeObject(otherId)
	local rootVehicle
	if fillableObject and fillableObject:isa(Vehicle) then 
		rootVehicle = fillableObject:getRootVehicle()
	end
	if courseplay:isAIDriverActive(rootVehicle) then
		if rootVehicle.cp.driver.triggerHandler.validFillTypeLoading then
			TriggerHandler:handleLoadTriggerCallback(self,triggerId, otherId, onEnter, onLeave, onStay, otherShapeId,rootVehicle,fillableObject)
		end
	end
end
LoadTrigger.loadTriggerCallback = Utils.appendedFunction(LoadTrigger.loadTriggerCallback,TriggerHandler.loadTriggerCallback)

function TriggerHandler:handleLoadTriggerCallback(self,triggerId, otherId, onEnter, onLeave, onStay, otherShapeId,rootVehicle,fillableObject)
	local triggerHandler = rootVehicle.cp.driver.triggerHandler
	triggerHandler:countTriggerUp(otherId)
	if onEnter then 
		courseplay.debugFormat(2, 'LoadTrigger onEnter')
		if fillableObject.getFillUnitIndexFromNode ~= nil then
			local fillLevels, capacity
			if self.source.getAllFillLevels then
				fillLevels, capacity = self.source:getAllFillLevels(g_currentMission:getFarmId())
			elseif self.source.getAllProvidedFillLevels then
				fillLevels, capacity = self.source:getAllProvidedFillLevels(g_currentMission:getFarmId(), self.managerId)
			end
			if fillLevels then
				local foundFillUnitIndex = fillableObject:getFillUnitIndexFromNode(otherId)
				for fillTypeIndex, fillLevel in pairs(fillLevels) do
					if fillableObject:getFillUnitSupportsFillType(foundFillUnitIndex, fillTypeIndex) then
						if fillableObject:getFillUnitAllowsFillType(foundFillUnitIndex, fillTypeIndex) and fillableObject.spec_cover then
							SpecializationUtil.raiseEvent(fillableObject, "onAddedFillUnitTrigger",fillTypeIndex,foundFillUnitIndex,1)
							courseplay.debugFormat(2, 'open Cover for loading')
						end
					end
				end
			end
		end
	end
	if onLeave then 
		triggerHandler:countTriggerDown(otherId)
		spec = fillableObject.spec_fillUnit
		if spec then
			SpecializationUtil.raiseEvent(fillableObject, "onRemovedFillUnitTrigger",#spec.fillTrigger.triggers)
		end
		courseplay.debugFormat(2,"LoadTrigger onLeave")
	end
end

--FillTrigger callback used to set approach speed for Cp driver
function TriggerHandler:fillTriggerCallback(superFunc, triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)
	local fillableObject = g_currentMission:getNodeObject(otherId)
	local rootVehicle
	if fillableObject and fillableObject:isa(Vehicle) then 
		rootVehicle = fillableObject:getRootVehicle()
	end
	if courseplay:isAIDriverActive(rootVehicle) then
		local triggerHandler = rootVehicle.cp.driver.triggerHandler
		if not triggerHandler.validFillTypeLoading then
			return superFunc(self,triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)
		end		
		if onEnter then
			courseplay.debugFormat(2, 'fillTrigger onEnter')
		end
		if onLeave then
			triggerHandler:countTriggerDown(otherActorId)
			courseplay.debugFormat(2, 'fillTrigger onLeave')
		else
			triggerHandler:countTriggerUp(otherActorId)
		end
	end
	return superFunc(self,triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)
end
FillTrigger.fillTriggerCallback = Utils.overwrittenFunction(FillTrigger.fillTriggerCallback, TriggerHandler.fillTriggerCallback)

--check if the vehicle is controlled by courseplay
function TriggerHandler:isAIDriverActive(rootVehicle) 
	if rootVehicle and rootVehicle.cp and rootVehicle.cp.driver and rootVehicle:getIsCourseplayDriving() and rootVehicle.cp.driver:isActive() and not rootVehicle.cp.driver:isAutoDriveDriving() then
		return true
	end
end

