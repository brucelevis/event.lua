local event = require "event"
local cjson = require "cjson"
local model = require "model"
local util = require "util"
local protocol = require "protocol"

local id_builder = import "module.id_builder"
local dbObject = import "module.database_object"
local serverMgr = import "module.server_manager"
local agentMgr = import "module.login.agent_manager"
local clientMgr = import "module.client_manager"
local loginServer = import "module.login.login_server"

cLoginUser = dbObject.cDatabase:inherit("login_user","account","cid")

function __init__(self)
	self.cLoginUser:saveField("accountInfo")
	self.cLoginUser:saveField("forbidInfo")
end

function cLoginUser:onCreate(cid,account)
	self.cid = cid
	self.account = account
	
end

function cLoginUser:dbIndex()
	return {account = self.account}
end

function cLoginUser:auth()
	if not self.accountInfo then
		self.accountInfo = {list = {}}
		self:dirtyField("accountInfo")
	end

	local result = {}
	for _,role in pairs(self.accountInfo.list) do
		table.insert(result,{uid = role.uid,name = role.name})
	end

	sendClient(self.cid,"sLoginAuth",{list = result})
end

function cLoginUser:createRole(career,name)
	local role = {career = career,name = "mrq",uid = id_builder:alloc_user_uid()}
	table.insert(self.accountInfo.list,role)
	self:dirtyField("accountInfo")

	local result = {}
	for _,role in pairs(self.accountInfo.list) do
		table.insert(result,{uid = role.uid,name = role.name})
	end

	sendClient(self.cid,"sCreateRole",{list = result})
end

function cLoginUser:delete_role(uid)

end

function cLoginUser:create_name(name)

end

function cLoginUser:random_name()

end

function cLoginUser:onDestroy()
	model.unbind_login_user_with_account(self.account)
	model.unbind_login_user_with_cid(self.cid)
end

function cLoginUser:leave()
	self:save()
	self:release()
end

function cLoginUser:enterAgent(uid)
	local agentId,agentAddr = agentMgr:selectAgent()
	local time = util.time()
	local json = cjson.encode({account = self.account,uid = uid})
	local token = util.authcode(json,tostring(time),1)

	serverMgr:sendAgent(agentId,"handler.agent_handler","userRegister",{token = token,time = time,uid = uid,account = self.account},function ()
		local user = model.fetch_login_user_with_cid(info.cid)
		if not user then
			return
		end
		loginServer:userEnterAgent(user.account,user.uid,agentId)
		sendClient(user.cid,"s2c_login_enter",{token = token,ip = agentAddr.ip,port = agentAddr.port})
		clientMgr:close(user.cid)
	end)

end

