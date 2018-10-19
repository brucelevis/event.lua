local util = require "util"
local model = require "model"

local aiState = import "module.scene.ai.ai_state"

cAIGohome = aiState.cAIState:inherit("aiGohome")


function cAIGohome:ctor(fsm,charactor,...)
	self.fsm = fsm
	self.charactor = charactor
end

function cAIGohome:onEnter()
	if not self.charactor:moveToPos(self.charactor.owner.bornPos) then
		return false
	end
	return true
end

function cAIGohome:onUpdate(now)
	local owner = self.charactor.owner
	local stateMgr = owner.stateMgr
	if not stateMgr:hasState("MOVE") then
		self.charactor:moveToPos(self.charactor.owner.bornPos)
		return true
	end

	local dt = util.dot2dot(owner.pos[1],owner.pos[2],owner.bornPos[1],owner.bornPos[2])
	if dt <= 0.1 then
		self.fsm:switchState("IDLE")
		return false
	end

	return true
end
