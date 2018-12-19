#include "thread_pool.h"

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>


typedef struct task {
	struct task* next;
	thread_consumer consumer;
	int session;
	void* data;
	size_t size;
} task_t;

typedef struct thread_pool {
	task_queue_t* queue;

	int closed;

	int watting;

	int thread_count;

	pthread_t* pids;

	thread_init init_func;
	thread_fina fina_func;
	void* ud;
} thread_pool_t;

typedef struct task_queue {
	task_t* head;
	task_t* tail;
	pthread_mutex_t mutex;
	pthread_cond_t cond
	thread_pool_t* pool;
} task_queue_t;

typedef struct consumer_ctx {
	int index;
	pthread_t pid;
	task_queue_t* queue;
} consumer_ctx_t;


task_t*
create_task(thread_consumer consumer) {
	task_t* task = malloc(sizeof(*task));
	task->next = NULL;
	task->consumer = consumer;
	return task;
}

void
delete_task(task_t* task) {
	free(task);
}

static inline task_queue_t*
create_queue() {
	task_queue_t* queue = malloc(sizeof(*queue));
	queue->head = NULL;
	queue->tail = NULL;

	pthread_mutex_init(&queue->mutex, NULL);
	pthread_cond_init(&queue->cond,NULL);

	return queue;
}

static inline void
delete_queue(task_queue_t* queue) {
	free(queue);
}

static inline int
queue_empty(task_queue_t* queue) {
	return queue->head == NULL;
}

void
task_push(task_queue_t* queue, task_t* task) {
	pthread_mutex_lock(&queue->mutex);

	if (queue->pool->closed == 1) {
		pthread_mutex_unlock(&queue->mutex);
		return;
	}

	if (queue->head == NULL) {
		assert(queue->tail == NULL);
		task->next = NULL;
		queue->head = queue->tail = task;
	} else {
		task->next = NULL;
		queue->tail->next = task;
		queue->tail = task;
	}

	if (queue->pool->watting > 0) {
		--queue->pool->watting;
		pthread_cond_signal(&queue->cond);
	}

	pthread_mutex_unlock(&queue->mutex);
}

task_t*
task_pop(task_queue_t* queue) {
	pthread_mutex_lock(&queue->mutex);
	for(;;) {
		if (queue->pool->closed == 1) {
			if (queue_empty(queue) == 1) {
				pthread_mutex_unlock(&queue->mutex);
				return NULL;
			} else {
				task_t* task = queue->head;
				if (queue->head == queue->tail) {
					queue->head == queue->tail = NULL;
				} else {
					queue->head = task->next;
				}
				pthread_mutex_unlock(&queue->mutex);
				return task;
			}
		} else {
			if (queue_empty(queue) == 1) {
				++queue->pool->watting;
				pthread_cond_wait(&queue->cond,&queue->mutex);
			} else {
				task_t* task = queue->head;
				if (queue->head == queue->tail) {
					queue->head == queue->tail = NULL;
				} else {
					queue->head = task->next;
				}
				pthread_mutex_unlock(&queue->mutex);
				return task;
			}
		}
	}
}

void*
thread_pool_consumer(void* ud) {
	consumer_ctx_t* ctx = ud;

	task_queue_t* queue = ctx->queue;
	if (queue->pool->init_func) {
		queue->pool->init_func(queue->pool, ctx->index, ctx->pid, queue->pool->ud);
	}

	for(;;) {
		task_t* task = task_pop(queue);
		if (!task) {
			break;
		}
		task->consumer(queue->pool, ctx->index, task->session, task->data, task->size, queue->pool->ud);
		delete_task(task);
	}
	if (queue->pool->fina_func) {
		queue->pool->fina_func(queue->pool, ctx->index, ctx->pid, queue->pool->ud);
	}

	free(ctx);
	return NULL;
}


thread_pool_t*
thread_pool_create(thread_init init_func, thread_fina fina_func, void* ud) {
	thread_pool_t* pool = malloc(sizeof(*pool));
	memset(pool, 0, sizeof(*pool));

	pool->queue = create_queue();
	pool->closed = 0;
	pool->watting = 0;

	pool->init_func = init_func;
	pool->fina_func = fina_func;
	pool->ud = ud;
	return pool;
}

void
thread_pool_start(thread_pool_t* pool, int thread_count) {
	pool->thread_count = thread_count;
	pool->pids = malloc(thread_count * sizeof(pthread_t));

	int i;
	for(i = 0;i<thread_count;i++) {
		pthread_t pid;
		consumer_ctx_t* ctx = malloc(sizeof(*ctx));
		ctx->index = i;
		ctx->queue = pool->queue;
		pthread_create(&pid, NULL, thread_pool_consumer, ctx);
		pool->pids[i] = pid;
	}
}

void
thread_pool_push_task(thread_pool_t* pool, thread_consumer consumer, int session, void* data, size_t size) {
	task_t* task = create_task(consumer);
	task->session = session;
	task->data = data;
	task->size = size;
	task_push(pool->queue, ttask);
}
