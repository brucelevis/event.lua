#include "socket_http.h"

#include "common/string.h"
#include "curl/curl.h"
#include <assert.h>

typedef struct http_multi {
	CURLM* ctx;
	int still_running;
	struct ev_timer io;
	struct ev_loop_ctx* ev_loop;
} http_multi_t;

typedef struct http_request {
	http_multi_t* multi;
	CURL* ctx;
	int fd;
	struct ev_io rio;
	struct ev_io wio;
	string_t header;
	string_t content;
	char error[CURL_ERROR_SIZE];
	void* callback_ud;
	request_callback callback;
} http_request_t;

static void 
check_multi_info(http_multi_t *multi) {
	CURLMsg *msg;
	int msgs_left;
	CURL *easy;
	http_request_t * request = NULL;

	while ((msg = curl_multi_info_read(multi->ctx, &msgs_left))) {
		if (msg->msg == CURLMSG_DONE) {
			easy = msg->easy_handle;
			curl_easy_getinfo(easy, CURLINFO_PRIVATE, &request);
			curl_multi_remove_handle(multi->ctx, easy);
			request->callback(request, request->callback_ud);
			http_request_delete(request); //BUG,FIXME
		}
	}
}

static void
timeout(struct ev_loop* loop,struct ev_timer* io,int revents) {
	http_multi_t* multi = io->data;
	curl_multi_socket_action(multi->ctx, CURL_SOCKET_TIMEOUT, 0, &multi->still_running);
	check_multi_info(multi);
}

static void
read_cb(struct ev_loop* loop,struct ev_io* io,int revents) {
	http_request_t* request = io->data;
	http_multi_t* multi = request->multi;
	curl_multi_socket_action(multi->ctx, request->fd, CURL_POLL_IN, &multi->still_running);
	check_multi_info(multi);

	//BUG,FIXME
	if (multi->still_running <= 0) {
		if (ev_is_active(&multi->io)) {
			ev_timer_stop(loop_ctx_get(multi->ev_loop),(struct ev_timer*)&multi->io);
		}
	}
}

static void
write_cb(struct ev_loop* loop,struct ev_io* io,int revents) {
	http_request_t* request = io->data;
	http_multi_t* multi = request->multi;
	curl_multi_socket_action(multi->ctx, request->fd, CURL_POLL_OUT, &multi->still_running);
	check_multi_info(multi);
	if (multi->still_running <= 0) {
		if (ev_is_active(&multi->io)) {
			ev_timer_stop(loop_ctx_get(multi->ev_loop),(struct ev_timer*)&multi->io);
		}
	}
}

static int 
multi_sock_cb(CURL* e, curl_socket_t s, int what, void* cbp, void* ud) {
	http_multi_t* multi = cbp;
	http_request_t* request = ud;
	if (what == CURL_POLL_REMOVE) {
		if (ev_is_active(&request->rio)) {
			ev_io_stop(loop_ctx_get(multi->ev_loop), &request->rio);
		}
		if (ev_is_active(&request->wio)) {
			ev_io_stop(loop_ctx_get(multi->ev_loop), &request->wio);
		}
	} else {
		if (!request) {
			curl_easy_getinfo(e, CURLINFO_PRIVATE, &request);
			request->fd = s;

			curl_multi_assign(request->multi->ctx, s, request);

			request->rio.data = request;
			ev_io_init(&request->rio,read_cb,s,EV_READ);

			request->wio.data = request;
			ev_io_init(&request->wio,write_cb,s,EV_WRITE);
		}
	
		if ( what == CURL_POLL_IN ) {
			if (!ev_is_active(&request->rio)) {
				ev_io_start(loop_ctx_get(multi->ev_loop), &request->rio);
			}
		} else if ( what == CURL_POLL_OUT ){
			if (!ev_is_active(&request->wio)) {
				ev_io_start(loop_ctx_get(multi->ev_loop), &request->wio);
			}
		} else if ( what == CURL_POLL_INOUT ){
			if (!ev_is_active(&request->rio)) {
				ev_io_start(loop_ctx_get(multi->ev_loop), &request->rio);
			}
			if (!ev_is_active(&request->wio)) {
				ev_io_start(loop_ctx_get(multi->ev_loop), &request->wio);
			}
		}
	}
	return 0;
}

static int 
multi_timer_cb(CURLM* ctx, long timeout_ms,void* ud) {
	http_multi_t* multi = ud;

	if (timeout_ms == 0) {
		curl_multi_socket_action(multi->ctx, CURL_SOCKET_TIMEOUT, 0, &multi->still_running);
	} else if (timeout_ms > 0) {
		multi->io.data = multi;
		ev_timer_init((struct ev_timer*)&multi->io,timeout,timeout_ms,0);
		ev_timer_start(loop_ctx_get(multi->ev_loop),(struct ev_timer*)&multi->io);
	}

	return 0;
}


void http_multi_init(http_multi_t* multi, struct ev_loop_ctx* ev_loop) {
	multi->ctx = curl_multi_init();
	multi->ev_loop = ev_loop;
	multi->still_running = 0;
	curl_multi_setopt(multi->ctx, CURLMOPT_SOCKETFUNCTION, multi_sock_cb);
	curl_multi_setopt(multi->ctx, CURLMOPT_SOCKETDATA, multi);
	curl_multi_setopt(multi->ctx, CURLMOPT_TIMERFUNCTION, multi_timer_cb);
	curl_multi_setopt(multi->ctx, CURLMOPT_TIMERDATA, multi);
}

http_multi_t* http_multi_new(struct ev_loop_ctx* ev_loop) {
	http_multi_t* multi = malloc(sizeof( *multi ));
	http_multi_init(multi, ev_loop);
	return multi;
}

size_t 
receive_data(char *buffer, size_t size, size_t nitems, void *userdata) {
	string_t* data = (string_t*)userdata;
	string_append_lstr(data, buffer, nitems * size);
	return nitems * size;
}

void http_request_init(http_request_t* request) {
	request->error[0] = '\0';
	string_init(&request->header, NULL, 64);
	string_init(&request->content, NULL, 64);
	request->multi = NULL;
	request->callback = NULL;
	request->ctx = curl_easy_init();

	curl_easy_setopt(request->ctx, CURLOPT_PRIVATE, request);

	curl_easy_setopt(request->ctx, CURLOPT_HEADERFUNCTION, receive_data);
	curl_easy_setopt(request->ctx, CURLOPT_HEADERDATA, &request->header);

	curl_easy_setopt(request->ctx, CURLOPT_WRITEFUNCTION, receive_data);
	curl_easy_setopt(request->ctx, CURLOPT_WRITEDATA, &request->content);

	curl_easy_setopt(request->ctx, CURLOPT_NOPROGRESS, 1);
	curl_easy_setopt(request->ctx, CURLOPT_NOSIGNAL, 1);

	curl_easy_setopt(request->ctx, CURLOPT_CONNECTTIMEOUT_MS, 0);

	curl_easy_setopt(request->ctx, CURLOPT_ERRORBUFFER, request->error);

	/* abort if slower than 30 bytes/sec during 5 seconds */
	curl_easy_setopt(request->ctx, CURLOPT_LOW_SPEED_TIME, 5L);
	curl_easy_setopt(request->ctx, CURLOPT_LOW_SPEED_LIMIT, 30L);
}

void http_request_release(http_request_t* request) {
	curl_easy_cleanup(request->ctx);
	string_release(&request->header);
	string_release(&request->content);
}

http_request_t* http_request_new() {
	http_request_t* request = malloc(sizeof( *request ));
	http_request_init(request);
	return request;
}

void http_request_delete(http_request_t* request) {
	http_request_release(request);
	free(request);
}

int set_url(http_request_t* request, const char* url) {
	return curl_easy_setopt(request->ctx, CURLOPT_URL, url);
}

const char* get_headers(http_request_t* request) {
	return string_str(&request->header);
}

const char* get_content(http_request_t* request) {
	return string_str(&request->content);
}

void set_callback(http_request_t* request, request_callback callback, void* ud) {
	request->callback = callback;
	request->callback_ud = ud;
}

int http_multi_perform(http_multi_t* multi, http_request_t* request) {
	request->multi = multi;
	CURLMcode rc = curl_multi_add_handle(multi->ctx, request->ctx);

	if (rc != CURLM_OK)
		http_request_delete(request);

	return rc;
}