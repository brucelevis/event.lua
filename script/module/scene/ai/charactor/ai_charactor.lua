local util = require "util"
local model = require "model"
local b3 = import "module.scene.ai.bt.bt_const"
local object = import "module.object"
local sceneConst = import "module.scene.scene_const"

cAICharactor = object.cObject:inherit("aiCharactor")


function cAICharactor:ctor(sceneObj)
	self.owner = sceneObj
	self.userAmount = 0
end

function cAICharactor:onCreate()
end

function cAICharactor:onDestroy()
end

function cAICharactor:searchEnemy()
	local enemyList = self.owner:getViewer(sceneConst.eSCENE_OBJ_TYPE.FIGHTER)
	if not next(enemyList) then
		return
	end

	local pos = self.owner.pos
	local minDt
	local enemyUid
	for _,enemy in pairs(enemyList) do
		local dt = util.dot2dot(pos[1],pos[2],enemy.pos)
		if not minDt or minDt > dt then
			minDt = dt
			enemyUid = enemy.uid
		end
	end

	return enemyUid
end

function cAICharactor:haveEnemy()
	return self.userAmount ~= 0
end

function cAICharactor:randomPatrolPos()
	local bornPos = self.owner.bornPos
	return util.random_in_circle(bornPos[1],bornPos[2], self.owner.patrolRange)
end

function cAICharactor:moveToTarget(targetUid)
	if not targetUid then
		targetUid = self:searchEnemy()
	end
	local targetObj = model.fetch_fighter_with_uid(targetUid)

	local angle = targetObj:getAngleFrom(self.owner)

	local fx, fz = util.move_torward(targetObj.pos[1], targetObj.pos[2], angle, 1)

	local path = {}
	table.insert(path,{self.owner.pos[1],self.owner.pos[2]})
	table.insert(path,{fx,fz})

	local moveCtrl = self.owner.moveCtrl
	if not moveCtrl:onServerMoveStart(path) then
		return false
	end
	return true
end

function cAICharactor:moveToPos(pos)
	local path = {}
	table.insert(path,{self.owner.pos[1],self.owner.pos[2]})
	table.insert(path,{pos[1],pos[2]})

	local moveCtrl = self.owner.moveCtrl
	if not moveCtrl:onServerMoveStart(path) then
		return false
	end
	return true
end

function cAICharactor:canAttack(targetObj)
	if util.dot2dot(self.owner.pos[1],self.owner.pos[2],targetObj.pos[1],targetObj.pos[2]) <= 2 then
		return true
	end
	return false
end

function cAICharactor:isOutOfRange()
	if util.dot2dot(self.owner.pos[1],self.owner.pos[2],self.owner.bornPos[1],self.owner.bornPos[2]) >= 100 then
		return true
	end
	return false
end

function cAICharactor:onUserEnter(sceneObj)
	self.userAmount = self.userAmount + 1
end

function cAICharactor:onUserLeave(sceneObj)
	self.userAmount = self.userAmount - 1
end

function cAICharactor:isNeedGoHome()
	if self:isOutOfRange() then
		return b3.SUCCESS
	end
	return b3.FAILURE
end

function cAICharactor:noTarget()
	if not self:haveEnemy() then
		return b3.SUCCESS 
	end
	return b3.FAILURE
end

function cAICharactor:findTarget()
	if self:haveEnemy() then
		return b3.SUCCESS
	end
	return b3.FAILURE
end

function cAICharactor:goHome()
	local stateMgr = self.owner.stateMgr

	if not stateMgr:hasState("MOVE") then
		self:moveToPos(self.owner.bornPos)
	end

	if self:haveEnemy() then
		return b3.FAILURE
	end

	return b3.RUNNING
end

function cAICharactor:randomSpeak()
	print("randomSpeak")
	return b3.SUCCESS
end

function cAICharactor:randomMove()
	print("randomMove 1")
	local stateMgr = self.owner.stateMgr
	if stateMgr:hasState("MOVE") then
		print("randomMove 2")
		return b3.RUNNING
	end

	if self:haveEnemy() then
		print("randomMove 3")
		return b3.FAILURE
	end

	self.patrolPos = {self:randomPatrolPos()}

	local moveCtrl = self.owner.moveCtrl

	moveCtrl:onServerMoveStart({{self.owner.pos[1],self.owner.pos[2]}, self.patrolPos})
	print("randomMove 4")
	return b3.RUNNING
end

function cAICharactor:attack()
	return b3.RUNNING
end
