local event = require "event"
local cjson = require "cjson"
local model = require "model"
local util = require "util"
local chatMgr = import "module.world.chat_manager"
local serverMgr = import "module.server_manager"
local dbObject = import "module.database_object"
local sceneMgr = import "module.world.scene_manager"

cFighterProxy = dbObject.cCollection:inherit("fighter")

local eTRANSFER_STATUS = {
	TRANSFER = 1,
	ENTER = 2,
	LEAVE = 3	
}

function __init__(self)
	
end


function cFighterProxy:onCreate(agentFighterInfo)
	self.__user = user
	self.__mutex = event.mutex()
end

function cFighterProxy:onDestroy()
end

function cFighterProxy:onEnter()
	local locationInfo = self.locationInfo
	self:enterScene(locationInfo.sceneId,locationInfo.sceneUid)
end

function cFighterProxy:onLeave()
	event.fork(function ()
		self.__mutex(sceneMgr.leaveScene,sceneMgr,self)
	end)
end

function cFighterProxy:enterScene(sceneId,sceneUid)
	event.fork(function ()
		self.__mutex(sceneMgr.enterScene,sceneMgr,self,sceneId,sceneUid)
	end)
end

function cFighterProxy:onEnterScene(sceneId,sceneUid)
	self.sceneId = sceneId
	self.sceneUid = sceneUid
end

