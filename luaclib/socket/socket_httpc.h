#ifndef SOCKET_HTTPC_H
#define SOCKET_HTTPC_H

#include "socket_tcp.h"

struct http_request;
struct http_multi;
typedef void(*request_callback)( struct http_request* request, void* ud );

struct http_multi* http_multi_new(struct ev_loop_ctx* ev_loop);
void http_multi_delete(struct http_multi* multi);

struct http_request* http_request_new();
void http_request_delete(struct http_request* request);

int set_url(struct http_request* request, const char* url);
int set_header(struct http_request* request, const char* data, size_t size);
int set_post_data(struct http_request* request, const char* data, size_t size);
int set_timeout(struct http_request* request, uint32_t secs);
int set_unix_socket_path(struct http_request* request, const char* path);

const char* get_headers(struct http_request* request);
const char* get_content(struct http_request* request);
int get_http_code(struct http_request* request);

int http_multi_perform(struct http_multi* multi, struct http_request* request, request_callback callback, void* ud);



#endif