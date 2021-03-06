local timer = require "timer"
local worker = require "worker"
local tp = require "tp"
local model = require "model"

_dirtyUser = _dirtyUser or {}
_userLru = _userLru or nil

MODEL_BINDER("dbUser","uid")

local lru = {}

function lru:new(name,max,timeout,unload)
	local ctx = setmetatable({},{__index = self})
	ctx.head = nil
	ctx.tail = nil
	ctx.nodeCtx = {}
	ctx.count = 0
	ctx.max = max or 100
	ctx.timeout = timeout or 3600 * 10
	ctx.unload = unload
	ctx.name = name
	return ctx
end

function lru:insert(id)
	print("update",id)
	local node = self.nodeCtx[id]
	if not node then
		self.count = self.count + 1
		node = {prev = nil,next = nil,id = id,time = os.time()}

		if self.head == nil then
			self.head = node
			self.tail = node
		else
			self.head.prev = node
			node.next = self.head
			self.head = node
		end

		self.nodeCtx[id] = node

		if self.count > self.max then
			local node = self.tail
			self.unload(self.name,node.id)
			self.tail = node.prev
			self.tail.next = nil
			self.count = self.count - 1
		end
	else
		node.time = os.time()

		if not node.prev then
			return
		end
		local prevNode = node.prev
		local nextNode = node.next
		prevNode.next = nextNode
		if nextNode then
			nextNode.prev = prevNode
		end
		node.prev = nil
		node.next = self.head
		self.head = node
	end
end

function lru:update(now)
	local node = self.tail
	while node do
		if now - node.time >= self.timeout then
			if node.next then
				node.next.prev = node.prev
			end

			if node.prev then
				node.prev.next = node.next
			end

			if node == self.tail then
				self.tail = node.prev
			end

			if node == self.head then
				self.head = node.next
			end

			self.unload(self.name,node.id)
		else
			break
		end
		node = node.prev
	end
end

function updateUserLru()
	_userLru:update(os.time())
end

function doSaveUser(self,userUid,dirtyData)
	local dbUser = model.fetch_dbUser_with_uid(userUid)

	for tbName,updateField in pairs(dirtyData) do
		local dbUserTb = dbUser[tbName]
		local sql = string.format("update %s set %%s where userUid=%d",tbName,userUid)
		local sub = {}
		for field in pairs(updateField) do
			table.insert(sub,string.format("%s='%s'",field,tostring(dbUserTb[field])))
		end
		sql = string.format(sql,table.concat(sub,","))
		tp.send("handler.data_mysql","executeSql",sql)
	end
end

function start(self,workerCount)
	_userLru = lru:new("user",1000,10,function (name,userUid)
		print("unload",userUid)
		if _dirtyUser[userUid] then
			self:doSaveUser(userUid,_dirtyUser[userUid])
			_dirtyUser[userUid] = nil
		end
		model.unbind_dbUser_with_uid(userUid)
	end)

	tp.create(workerCount,"server/tp_data_worker")
	timer.callout(10,self,"saveUser")
	timer.callout(1,self,"updateUserLru")
end


function loadUser(_,args)
	local user = model.fetch_dbUser_with_uid(args.userUid)
	if user then
		return user
	end

	local dbUserInfo = tp.call("handler.data_mysql","loadUser",args.userUid)

	model.bind_dbUser_with_uid(args.userUid,dbUserInfo)

	_userLru:insert(args.userUid)

	return dbUserInfo
end

function saveUser(self,args)
	for userUid,dirtyData in pairs(_dirtyUser) do
		self:doSaveUser(userUid,dirtyData)
	end
	_dirtyUser = {}
end

function updateUser(_,args)
	local userUid = args.userUid
	local dbUser = model.fetch_dbUser_with_uid(userUid)
	if not dbUser then
		return
	end

	local dirtyData = _dirtyUser[userUid]
	if not dirtyData then
		dirtyData = {}
		_dirtyUser[userUid] = dirtyData
	end

	local dirtyField = dirtyData[args.tbName]
	if not dirtyField then
		dirtyField = {}
		dirtyData[args.tbName] = dirtyField
	end

	local tb = dbUser[args.tbName]
	local updater = args.updater
	for field,value in pairs(updater) do
		tb[field] = value
		dirtyField[field] = true
	end

	_userLru:insert(args.userUid)
end