local event = require "event"
local model = require "model"
local route = require "route"
local timer = require "timer"

local serverMgr = import "module.server_manager"
local clientMgr = import "module.client_manager"

_loginCtx = _loginCtx or {}
_agentAccountMgr = _agentAccountMgr or {}

_nameAccount = _nameAccount or {}
_uidAccount = _uidAccount or {}

local eUSER_PHASE = {
	LOADING = 1,
	DONE = 2,
	LEAVE = 3
}

function start(self)
	timer.callout(1,self,"timeout")
	local dbChannel = model.get_dbChannel()
	local result = dbChannel:findAll("event","accountInfo")
	for _,info in pairs(result) do
		for _,detail in pairs(info.list) do
			_nameAccount[detail.name] = info.account
			_uidAccount[detail.uid] = info.account
		end
	end

	serverMgr:registerEvent("AGENT_DOWN",self,"agentDown")
	import "handler.login_handler"
	import "handler.cmd_handler"
end

function timeout(self)

end

function userEnterAgent(self,account,userUid,agentId)
	local info = {userUid = userUid,agentId = agentId,time = os.time()}
	_agentAccountMgr[account] = info
end

function agentDown(self,listener,agentId)
	for account,info in pairs(_agentAccountMgr) do
		if info.agent_server == agentId then
			_agentAccountMgr[account] = nil
		end
	end
end

function enter(self,cid,addr)
	event.error(string.format("cid:%d addr:%s enter",cid,addr))
	local info = {cid = cid,addr = addr}
	_loginCtx[cid] = info
end

function leave(self,cid)
	event.error(string.format("cid:%d leave",cid))
	local info = _loginCtx[cid]
	if not info then
		return
	end
	_loginCtx[cid] = nil

	if info.account then
		local user = model.fetch_login_user_with_account(info.account)
		if user and user.cid == cid then
			if user.phase == eUSER_PHASE.DONE then
				user:save()
			end
			user.phase = eUSER_PHASE.LEAVE
			user:leave()
			model.unbind_login_user_with_account(info.account)
		end
	end
end

function dispatch_client(self,cid,message_id,data,size)
	local user = model.fetch_login_user_with_cid(cid)
	if not user then
		route.dispatch_client(cid,message_id,data,size)
	else
		route.dispatch_client(user,message_id,data,size)
	end
end

local function _userDoAuth(self,cid,account)
	local info = _loginCtx[cid]
	info.account = account
	local user = model.fetch_login_user_with_account(info.account)
	if user then
		if _loginCtx[user.cid] then
			clientMgr:close(user.cid)
			_loginCtx[user.cid] = nil
		end
		if user.phase == eUSER_PHASE.DONE then
			user.cid = cid
			user:auth()
			return
		elseif user.phase == eUSER_PHASE.LOADING then
			user.cid = cid
		end

	end
	local loginUser = import "module.login.login_user"
	user = loginUser.cLoginUser:new()
	model.bind_login_user_with_account(account,user)
	user:onCreate(cid,account)
	user.phase = eUSER_PHASE.LOADING
	user:load()
	if user.phase == eUSER_PHASE.LEAVE then
		return
	end
	user.phase = eUSER_PHASE.DONE
	user:auth()
end

function userAuth(self,cid,account)
	local info = _loginCtx[cid]
	assert(info ~= nil,cid)
	assert(info.account == nil,info.account)

	local accountInfo = _agentAccountMgr[account]
	if accountInfo then
		local queue = accountInfo.queue
		if not queue then
			queue = {}
			accountInfo.queue = queue
		end
		table.insert(queue,cid)

		serverMgr:sendAgent(accountInfo.agentId,"handler.agent_handler","userKick",{uid = accountInfo.uid},function (ok)
			_agentAccountMgr[account] = nil
			local count = #queue
			for i = 1,count-1 do
				local cid = queue[i]
				if _loginCtx[cid] then
					clientMgr:close(cid)
					_loginCtx[cid] = nil
				end
			end
			local lastCid = queue[count]
			if not _loginCtx[lastCid] then 
				return
			end
			event.fork(_userDoAuth,self,lastCid,account)
		end)
		return
	end

	event.fork(_userDoAuth,self,cid,account)
end


function server_stop(self)
	local client_manager = model.get_client_manager()
	client_manager:stop()

	local all = model.fetch_login_user()
	for _,user in pairs(all) do
		user:leave()
	end

	local db_channel = model.get_dbChannel()
	
	local updater = {}
	updater["$inc"] = {version = 1}
	updater["$set"] = {time = os.time()}
	db_channel:findAndModify("common","login_version",{query = {uid = env.distId},update = updater,upsert = true})

	local agent_set = server_manager:how_many_agent()
	for _,agent_id in pairs(agent_set) do
		server_manager:sendAgent(agent_id,"handler.agent_handler","server_stop")
	end
end
