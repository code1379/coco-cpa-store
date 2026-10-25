package main

/*
#include <stdint.h>
#include <stdlib.h>
typedef struct { void* ptr; size_t len; } cliproxy_buffer;
typedef int (*cliproxy_plugin_call_fn)(char*, uint8_t*, size_t, cliproxy_buffer*);
typedef void (*cliproxy_plugin_free_fn)(void*, size_t);
typedef void (*cliproxy_plugin_shutdown_fn)(void);
typedef struct { uint32_t abi_version; void* host_ctx; void* call; void* free_buffer; } cliproxy_host_api;
typedef struct { uint32_t abi_version; cliproxy_plugin_call_fn call; cliproxy_plugin_free_fn free_buffer; cliproxy_plugin_shutdown_fn shutdown; } cliproxy_plugin_api;
extern int cliproxyPluginCall(char*, uint8_t*, size_t, cliproxy_buffer*);
extern void cliproxyPluginFree(void*, size_t);
extern void cliproxyPluginShutdown(void);
*/
import "C"

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"unsafe"
)

const (
	pluginVersion = "0.3.0"
	abiVersion    = 1
	schemaVersion = 6
	pluginID      = "cli-playground"
	resourcePath  = "/playground"
)

//go:embed web/index.html
var playgroundHTML []byte

type envelope struct {
	OK     bool            `json:"ok"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *rpcError       `json:"error,omitempty"`
}
type rpcError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}
type pluginMetadata struct {
	Name             string
	Version          string
	Author           string
	GitHubRepository string
	Logo             string
	ConfigFields     []any
}
type registration struct {
	SchemaVersion uint32         `json:"schema_version"`
	Metadata      pluginMetadata `json:"metadata"`
	Capabilities  struct {
		ManagementAPI bool `json:"management_api"`
	} `json:"capabilities"`
}
type managementResource struct {
	Path        string
	Menu        string
	Description string
}
type managementRegistration struct{ Resources []managementResource }
type managementRequest struct {
	Method  string
	Path    string
	Headers http.Header
	Body    []byte
}
type managementResponse struct {
	StatusCode int
	Headers    http.Header
	Body       []byte
}

func main() {}

//export cliproxy_plugin_init
func cliproxy_plugin_init(_ *C.cliproxy_host_api, plugin *C.cliproxy_plugin_api) C.int {
	if plugin == nil {
		return 1
	}
	plugin.abi_version = C.uint32_t(abiVersion)
	plugin.call = C.cliproxy_plugin_call_fn(C.cliproxyPluginCall)
	plugin.free_buffer = C.cliproxy_plugin_free_fn(C.cliproxyPluginFree)
	plugin.shutdown = C.cliproxy_plugin_shutdown_fn(C.cliproxyPluginShutdown)
	return 0
}

//export cliproxyPluginCall
func cliproxyPluginCall(method *C.char, request *C.uint8_t, requestLen C.size_t, response *C.cliproxy_buffer) C.int {
	if response != nil {
		response.ptr = nil
		response.len = 0
	}
	if method == nil {
		writeResponse(response, errorEnvelope("invalid_method", "method is required"))
		return 1
	}
	var requestBytes []byte
	if request != nil && requestLen > 0 {
		requestBytes = C.GoBytes(unsafe.Pointer(request), C.int(requestLen))
	}
	raw, err := handleMethod(C.GoString(method), requestBytes)
	if err != nil {
		writeResponse(response, errorEnvelope("plugin_error", err.Error()))
		return 1
	}
	writeResponse(response, raw)
	return 0
}

//export cliproxyPluginFree
func cliproxyPluginFree(ptr unsafe.Pointer, _ C.size_t) {
	if ptr != nil {
		C.free(ptr)
	}
}

//export cliproxyPluginShutdown
func cliproxyPluginShutdown() {}

func handleMethod(method string, request []byte) ([]byte, error) {
	switch method {
	case "plugin.register", "plugin.reconfigure":
		return okEnvelope(pluginRegistration())
	case "management.register":
		return okEnvelope(managementRegistration{Resources: []managementResource{{Path: resourcePath, Menu: "模型 Playground", Description: "Test chat, image generation, and model-group routing."}}})
	case "management.handle":
		return handleManagement(request)
	case "plugin.shutdown", "plugin.quiesce":
		return okEnvelope(map[string]any{"status": "ok"})
	default:
		return errorEnvelope("unknown_method", "unknown method: "+method), nil
	}
}
func pluginRegistration() registration {
	r := registration{SchemaVersion: schemaVersion, Metadata: pluginMetadata{Name: "CLIProxyAPI Playground", Version: pluginVersion, Author: "code1379", GitHubRepository: "https://github.com/code1379/coco-cpa-store", ConfigFields: []any{}}}
	r.Capabilities.ManagementAPI = true
	return r
}
func handleManagement(raw []byte) ([]byte, error) {
	var req managementRequest
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &req); err != nil {
			return nil, fmt.Errorf("decode management request: %w", err)
		}
	}
	path := strings.TrimRight(req.Path, "/")
	if path != "" && path != resourcePath && !strings.HasSuffix(path, resourcePath) {
		return okEnvelope(managementResponse{StatusCode: http.StatusNotFound, Headers: http.Header{"content-type": []string{"text/plain; charset=utf-8"}}, Body: []byte("Not found")})
	}
	return okEnvelope(managementResponse{StatusCode: http.StatusOK, Headers: http.Header{"content-type": []string{"text/html; charset=utf-8"}, "cache-control": []string{"no-store"}, "x-content-type-options": []string{"nosniff"}}, Body: append([]byte(nil), playgroundHTML...)})
}
func okEnvelope(v any) ([]byte, error) {
	result, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	return json.Marshal(envelope{OK: true, Result: result})
}
func errorEnvelope(code, message string) []byte {
	raw, _ := json.Marshal(envelope{OK: false, Error: &rpcError{Code: code, Message: message}})
	return raw
}
func writeResponse(response *C.cliproxy_buffer, raw []byte) {
	if response == nil || len(raw) == 0 {
		return
	}
	ptr := C.CBytes(raw)
	if ptr == nil {
		return
	}
	response.ptr = ptr
	response.len = C.size_t(len(raw))
}
