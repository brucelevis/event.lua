
#include "common/thread_pool.h"


typedef struct thread_ctx {
	int index;
	pthread_t pid;
	int fd;
	struct pipe_message* first;
	struct pipe_message* last;
	lua_State* L;
} thread_ctx_t;

typedef lthread_pool {
	struct thread_pool* core;

	const char* boot;

	sem_t sem;

	thread_ctx_t* thr_mgr;
} lthread_pool_t;

void task_consumer(int index, int session, void* data, size_t size) {
	
}

void 
tp_init(struct thread_pool* pool, int index, pthread_t pid, void* ud) {
	lthread_pool_t* ltp = ud;
	sem_post(&ltp->sem);

	thread_ctx_t* ctx = &ltp->thr_mgr[index];
	ctx->pid = pid;
	ctx->index = index;
}

void 
tp_fina(struct thread_pool* pool, int index, pthread_t pid, void* ud) {

}


static int
lcreate(lua_State* L) {
	int fd = lua_tointeger(L, 1);
	const char* boot = lua_tostring(L, 2);
	int count = lua_tointeger(L, 3);

	lthread_pool_t* ltp = malloc(sizeof(*ltp));
	ltp->core = thread_pool_create(tp_init, tp_fina, ltp);
	ltp->boot = strdup(boot);
	ltp->thr_mgr = malloc(count * sizeof(thread_ctx_t));
	pthread_mutex_init(&ltp->mutex, NULL);

	sem_init(&ltp->sem, 0, -count);

	thread_pool_start(ltp->core, count);

	sem_wait(&ltp->sem);

	lua_createtable(L, 0, 0);

	int i;
	for(i = 0;i < count;++i) {
		thread_ctx_t* ctx = &ltp->thr_mgr[i];
		lua_pushinteger(L, ctx->pid);
		lua_seti(L, -2, i+1);
	}
	return 1;
}

int
lpush(lua_State* L) {
	int session = lua_tointeger(L, 1);

	void* data = NULL;
	size_t size = 0;

	switch(lua_type(L,3)) {
		case LUA_TSTRING: {
			const char* str = lua_tolstring(L, 3, &size);
			data = malloc(size);
			memcpy(data,str,size);
			break;
		}
		case LUA_TLIGHTUSERDATA:{
			data = lua_touserdata(L, 3);
			size = lua_tointeger(L, 4);
			break;
		}
		default: {
			luaL_error(L,"unkown type:%s",lua_typename(L,lua_type(L,3)));
		}
	}

	if (worker_push(target,-1,session,data,size) < 0) {
		lua_pushboolean(L,0);
		return 1;
	}
	lua_pushboolean(L,1);
	return 1;
}