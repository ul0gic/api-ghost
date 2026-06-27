(function() {
    'use strict';

    // ========================================
    // APIGhost Comprehensive Traffic Interceptor
    // Captures: fetch, XHR, WebSocket, SSE, Streaming
    // ========================================

    // Connection tracking for real-time connections
    const connections = new Map();

    // Unique ID generator
    function generateId() {
        return 'req_' + Date.now() + '_' + Math.random().toString(36).substring(2, 11);
    }

    // Generate connection ID for persistent connections
    function generateConnectionId(type) {
        return type + '_' + Date.now() + '_' + Math.random().toString(36).substring(2, 11);
    }

    // Post message to Swift
    function postToSwift(data) {
        try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.apiGhost) {
                window.webkit.messageHandlers.apiGhost.postMessage(data);
            }
        } catch (e) {
            console.error('[APIGhost] Failed to post to Swift:', e);
        }
    }

    // Convert relative URL to absolute
    function toAbsoluteURL(url) {
        if (!url) return url;
        if (url.startsWith('http://') || url.startsWith('https://') ||
            url.startsWith('ws://') || url.startsWith('wss://')) {
            return url;
        }
        try {
            return new URL(url, window.location.origin).href;
        } catch (e) {
            return window.location.origin + (url.startsWith('/') ? url : '/' + url);
        }
    }

    // Safe JSON stringify with circular reference handling
    // Used for complex objects that may have circular references
    function safeStringify(obj) {
        const seen = new WeakSet();
        return JSON.stringify(obj, (_key, value) => {
            if (typeof value === 'object' && value !== null) {
                if (seen.has(value)) {
                    return '[Circular]';
                }
                seen.add(value);
            }
            return value;
        });
    }

    // Extract headers from various formats
    function extractHeaders(headersInput, includeFromRequest = null) {
        const headers = {};

        try {
            if (headersInput instanceof Headers) {
                headersInput.forEach((value, key) => {
                    headers[key.toLowerCase()] = value;
                });
            } else if (Array.isArray(headersInput)) {
                headersInput.forEach(([key, value]) => {
                    headers[key.toLowerCase()] = value;
                });
            } else if (headersInput && typeof headersInput === 'object') {
                Object.entries(headersInput).forEach(([key, value]) => {
                    headers[key.toLowerCase()] = String(value);
                });
            }

            // If we have a Request object, extract its headers too
            if (includeFromRequest instanceof Request) {
                includeFromRequest.headers.forEach((value, key) => {
                    if (!headers[key.toLowerCase()]) {
                        headers[key.toLowerCase()] = value;
                    }
                });
            }
        } catch (e) {
            console.error('[APIGhost] Header extraction error:', e);
        }

        return headers;
    }

    // Read body from various formats
    async function readBody(body) {
        if (!body) return null;
        if (typeof body === 'string') return body;

        try {
            if (body instanceof FormData) {
                const obj = {};
                body.forEach((v, k) => {
                    if (v instanceof File) {
                        obj[k] = `[File: ${v.name}, ${v.size} bytes, ${v.type}]`;
                    } else {
                        obj[k] = v;
                    }
                });
                return JSON.stringify(obj);
            }
            if (body instanceof URLSearchParams) return body.toString();
            if (body instanceof Blob) {
                if (body.size > 1024 * 1024) {
                    return `[Blob: ${body.size} bytes, ${body.type}]`;
                }
                return await body.text();
            }
            if (body instanceof ArrayBuffer) {
                if (body.byteLength > 1024 * 1024) {
                    return `[ArrayBuffer: ${body.byteLength} bytes]`;
                }
                return new TextDecoder().decode(body);
            }
            if (ArrayBuffer.isView(body)) {
                if (body.byteLength > 1024 * 1024) {
                    return `[TypedArray: ${body.byteLength} bytes]`;
                }
                return new TextDecoder().decode(body);
            }
            return JSON.stringify(body);
        } catch (e) {
            return String(body);
        }
    }

    // Convert binary data to base64 for transmission
    function binaryToBase64(data) {
        try {
            if (data instanceof ArrayBuffer) {
                const bytes = new Uint8Array(data);
                let binary = '';
                for (let i = 0; i < bytes.byteLength; i++) {
                    binary += String.fromCharCode(bytes[i]);
                }
                return btoa(binary);
            }
            if (data instanceof Blob) {
                return new Promise((resolve) => {
                    const reader = new FileReader();
                    reader.onload = () => {
                        const base64 = reader.result.split(',')[1];
                        resolve(base64);
                    };
                    reader.onerror = () => resolve(null);
                    reader.readAsDataURL(data);
                });
            }
        } catch (e) {
            return null;
        }
        return null;
    }

    // ========================================
    // FETCH INTERCEPTION (with streaming support)
    // ========================================

    const originalFetch = window.fetch;

    window.fetch = async function(input, init = {}) {
        const requestId = generateId();
        const startTime = Date.now();

        // Parse request details
        const isRequest = input instanceof Request;
        const rawUrl = isRequest ? input.url : String(input);
        const url = toAbsoluteURL(rawUrl);
        const method = (init.method || (isRequest ? input.method : 'GET')).toUpperCase();

        // Extract headers comprehensively
        const headers = extractHeaders(init.headers, isRequest ? input : null);

        // Try to get request body
        let requestBody = null;
        if (init.body) {
            requestBody = await readBody(init.body);
        } else if (isRequest && input.body) {
            try {
                const clonedRequest = input.clone();
                requestBody = await clonedRequest.text();
            } catch (e) {
                requestBody = '[Could not read request body]';
            }
        }

        // Post request to Swift
        postToSwift({
            type: 'request',
            id: requestId,
            url: url,
            method: method,
            headers: headers,
            body: requestBody,
            timestamp: startTime
        });

        try {
            const response = await originalFetch(input, init);

            // Get response headers
            const responseHeaders = {};
            response.headers.forEach((value, key) => {
                responseHeaders[key.toLowerCase()] = value;
            });

            const contentType = responseHeaders['content-type'] || '';
            const isStreaming = response.body && (
                contentType.includes('text/event-stream') ||
                contentType.includes('application/x-ndjson') ||
                contentType.includes('application/stream+json') ||
                contentType.includes('text/plain') // Some APIs use text/plain for streaming
            );

            // Check if this is a streaming response
            if (isStreaming && response.body && response.body.getReader) {
                // Handle streaming response by teeing the body
                const [bodyForConsumer, bodyForCapture] = response.body.tee();

                // Process the capture body in background
                processStreamingResponse(requestId, url, responseHeaders, bodyForCapture, startTime, response.status, response.statusText);

                // Return response with the consumer body
                return new Response(bodyForConsumer, {
                    status: response.status,
                    statusText: response.statusText,
                    headers: response.headers
                });
            } else {
                // Non-streaming response - clone and read
                const cloned = response.clone();
                let responseBody = null;

                try {
                    const contentLength = parseInt(responseHeaders['content-length'] || '0', 10);
                    if (contentLength > 10 * 1024 * 1024) {
                        responseBody = `[Response too large: ${contentLength} bytes]`;
                    } else {
                        responseBody = await cloned.text();
                    }
                } catch (e) {
                    responseBody = '[Could not read response body]';
                }

                // Post response to Swift
                postToSwift({
                    type: 'response',
                    id: requestId,
                    url: url,
                    status: response.status,
                    statusText: response.statusText,
                    headers: responseHeaders,
                    body: responseBody,
                    duration: Date.now() - startTime,
                    timestamp: Date.now()
                });

                return response;
            }
        } catch (error) {
            postToSwift({
                type: 'error',
                id: requestId,
                url: url,
                error: error.message,
                duration: Date.now() - startTime,
                timestamp: Date.now()
            });
            throw error;
        }
    };

    // Process streaming response chunks
    async function processStreamingResponse(requestId, url, headers, body, startTime, status, statusText) {
        const reader = body.getReader();
        const decoder = new TextDecoder();
        const chunks = [];
        let chunkIndex = 0;
        let totalBytes = 0;
        const maxCaptureSize = 50 * 1024 * 1024; // 50MB max capture

        try {
            while (true) {
                const { done, value } = await reader.read();

                if (done) break;

                const chunkText = decoder.decode(value, { stream: true });
                totalBytes += value.byteLength;

                // Send each chunk to Swift
                postToSwift({
                    type: 'stream_chunk',
                    id: requestId,
                    url: url,
                    chunk: chunkText,
                    chunkIndex: chunkIndex,
                    chunkSize: value.byteLength,
                    timestamp: Date.now()
                });

                // Store chunk for final response assembly (with size limit)
                if (totalBytes < maxCaptureSize) {
                    chunks.push(chunkText);
                }

                chunkIndex++;
            }
        } catch (e) {
            console.error('[APIGhost] Stream reading error:', e);
        }

        // Send complete stream response
        const fullBody = chunks.join('');
        postToSwift({
            type: 'response',
            id: requestId,
            url: url,
            status: status,
            statusText: statusText,
            headers: headers,
            body: totalBytes >= maxCaptureSize ? `[Truncated at ${maxCaptureSize} bytes]` + fullBody : fullBody,
            duration: Date.now() - startTime,
            timestamp: Date.now(),
            isStreaming: true,
            totalChunks: chunkIndex,
            totalBytes: totalBytes
        });
    }

    // ========================================
    // XMLHttpRequest INTERCEPTION
    // ========================================

    const XHR = XMLHttpRequest.prototype;
    const originalOpen = XHR.open;
    const originalSend = XHR.send;
    const originalSetRequestHeader = XHR.setRequestHeader;

    XHR.open = function(method, url, _async, _user, _password) {
        this._apiGhost = {
            id: generateId(),
            method: method.toUpperCase(),
            url: toAbsoluteURL(url),
            headers: {},
            startTime: null
        };
        return originalOpen.apply(this, arguments);
    };

    XHR.setRequestHeader = function(name, value) {
        if (this._apiGhost) {
            this._apiGhost.headers[name.toLowerCase()] = value;
        }
        return originalSetRequestHeader.apply(this, arguments);
    };

    XHR.send = function(body) {
        if (this._apiGhost) {
            const info = this._apiGhost;
            info.startTime = Date.now();

            // Post request
            postToSwift({
                type: 'request',
                id: info.id,
                url: info.url,
                method: info.method,
                headers: info.headers,
                body: body ? String(body) : null,
                timestamp: info.startTime
            });

            // Listen for progress events (for streaming XHR)
            let lastProgressBytes = 0;
            this.addEventListener('progress', function(_e) {
                if (this.responseText && this.responseText.length > lastProgressBytes) {
                    const newData = this.responseText.substring(lastProgressBytes);
                    lastProgressBytes = this.responseText.length;

                    postToSwift({
                        type: 'stream_chunk',
                        id: info.id,
                        url: info.url,
                        chunk: newData,
                        chunkIndex: -1, // XHR progress doesn't have chunk index
                        timestamp: Date.now()
                    });
                }
            });

            // Listen for completion
            this.addEventListener('load', function() {
                const responseHeaders = {};
                const headerStr = this.getAllResponseHeaders();
                if (headerStr) {
                    headerStr.trim().split('\r\n').forEach(line => {
                        const idx = line.indexOf(':');
                        if (idx > 0) {
                            responseHeaders[line.substring(0, idx).trim().toLowerCase()] = line.substring(idx + 1).trim();
                        }
                    });
                }

                postToSwift({
                    type: 'response',
                    id: info.id,
                    url: info.url,
                    status: this.status,
                    statusText: this.statusText,
                    headers: responseHeaders,
                    body: this.responseText,
                    duration: Date.now() - info.startTime,
                    timestamp: Date.now()
                });
            });

            this.addEventListener('error', function() {
                postToSwift({
                    type: 'error',
                    id: info.id,
                    url: info.url,
                    error: 'XHR Error',
                    duration: Date.now() - info.startTime,
                    timestamp: Date.now()
                });
            });

            this.addEventListener('timeout', function() {
                postToSwift({
                    type: 'error',
                    id: info.id,
                    url: info.url,
                    error: 'XHR Timeout',
                    duration: Date.now() - info.startTime,
                    timestamp: Date.now()
                });
            });

            this.addEventListener('abort', function() {
                postToSwift({
                    type: 'error',
                    id: info.id,
                    url: info.url,
                    error: 'XHR Aborted',
                    duration: Date.now() - info.startTime,
                    timestamp: Date.now()
                });
            });
        }
        return originalSend.apply(this, arguments);
    };

    // ========================================
    // EVENTSOURCE (SSE) INTERCEPTION
    // ========================================

    const OriginalEventSource = window.EventSource;

    if (OriginalEventSource) {
        window.EventSource = function(url, config) {
            const connectionId = generateConnectionId('sse');
            const absoluteUrl = toAbsoluteURL(url);
            const startTime = Date.now();

            // Store connection info
            connections.set(connectionId, {
                type: 'sse',
                url: absoluteUrl,
                startTime: startTime,
                messageCount: 0
            });

            // Notify Swift of SSE connection
            postToSwift({
                type: 'sse_connect',
                id: connectionId,
                url: absoluteUrl,
                withCredentials: config?.withCredentials || false,
                timestamp: startTime
            });

            // Create actual EventSource
            const eventSource = new OriginalEventSource(url, config);

            // Wrap onopen
            const originalOnOpen = eventSource.onopen;
            Object.defineProperty(eventSource, 'onopen', {
                get: function() { return originalOnOpen; },
                set: function(handler) {
                    eventSource.addEventListener('open', function(e) {
                        postToSwift({
                            type: 'sse',
                            id: connectionId,
                            url: absoluteUrl,
                            event: 'open',
                            data: null,
                            timestamp: Date.now()
                        });
                        if (handler) handler.call(this, e);
                    });
                }
            });

            // Wrap onerror
            const originalOnError = eventSource.onerror;
            Object.defineProperty(eventSource, 'onerror', {
                get: function() { return originalOnError; },
                set: function(handler) {
                    eventSource.addEventListener('error', function(e) {
                        postToSwift({
                            type: 'sse',
                            id: connectionId,
                            url: absoluteUrl,
                            event: 'error',
                            data: e.message || 'Connection error',
                            readyState: eventSource.readyState,
                            timestamp: Date.now()
                        });
                        if (handler) handler.call(this, e);
                    });
                }
            });

            // Wrap onmessage
            const originalOnMessage = eventSource.onmessage;
            Object.defineProperty(eventSource, 'onmessage', {
                get: function() { return originalOnMessage; },
                set: function(handler) {
                    eventSource.addEventListener('message', function(e) {
                        const connInfo = connections.get(connectionId);
                        if (connInfo) connInfo.messageCount++;

                        postToSwift({
                            type: 'sse',
                            id: connectionId,
                            url: absoluteUrl,
                            event: 'message',
                            data: e.data,
                            lastEventId: e.lastEventId || null,
                            origin: e.origin,
                            timestamp: Date.now()
                        });
                        if (handler) handler.call(this, e);
                    });
                }
            });

            // Wrap addEventListener to capture all event types including custom ones
            const originalAddEventListener = eventSource.addEventListener.bind(eventSource);
            eventSource.addEventListener = function(type, listener, options) {
                // Create a wrapped listener that intercepts the event
                const wrappedListener = function(e) {
                    const connInfo = connections.get(connectionId);
                    if (connInfo) connInfo.messageCount++;

                    postToSwift({
                        type: 'sse',
                        id: connectionId,
                        url: absoluteUrl,
                        event: type,
                        data: e.data || null,
                        lastEventId: e.lastEventId || null,
                        origin: e.origin || null,
                        timestamp: Date.now()
                    });

                    // Call original listener
                    if (typeof listener === 'function') {
                        listener.call(this, e);
                    } else if (listener && typeof listener.handleEvent === 'function') {
                        listener.handleEvent(e);
                    }
                };

                return originalAddEventListener(type, wrappedListener, options);
            };

            // Wrap close method
            const originalClose = eventSource.close.bind(eventSource);
            eventSource.close = function() {
                postToSwift({
                    type: 'sse',
                    id: connectionId,
                    url: absoluteUrl,
                    event: 'close',
                    data: null,
                    duration: Date.now() - startTime,
                    messageCount: connections.get(connectionId)?.messageCount || 0,
                    timestamp: Date.now()
                });

                connections.delete(connectionId);
                return originalClose();
            };

            return eventSource;
        };

        // Preserve static properties
        window.EventSource.CONNECTING = OriginalEventSource.CONNECTING;
        window.EventSource.OPEN = OriginalEventSource.OPEN;
        window.EventSource.CLOSED = OriginalEventSource.CLOSED;
        window.EventSource.prototype = OriginalEventSource.prototype;
    }

    // ========================================
    // WEBSOCKET INTERCEPTION
    // ========================================

    const OriginalWebSocket = window.WebSocket;

    if (OriginalWebSocket) {
        window.WebSocket = function(url, protocols) {
            const connectionId = generateConnectionId('ws');
            const absoluteUrl = toAbsoluteURL(url);
            const startTime = Date.now();
            let messageCount = { sent: 0, received: 0 };

            // Store connection info
            connections.set(connectionId, {
                type: 'websocket',
                url: absoluteUrl,
                startTime: startTime,
                messageCount: messageCount
            });

            // Notify Swift of WebSocket connection attempt
            postToSwift({
                type: 'websocket',
                id: connectionId,
                url: absoluteUrl,
                event: 'connecting',
                protocols: protocols ? (Array.isArray(protocols) ? protocols : [protocols]) : [],
                timestamp: startTime
            });

            // Create actual WebSocket
            const ws = protocols
                ? new OriginalWebSocket(url, protocols)
                : new OriginalWebSocket(url);

            // Intercept onopen
            Object.defineProperty(ws, 'onopen', {
                get: function() { return this._apiGhostOnOpen; },
                set: function(handler) {
                    this._apiGhostOnOpen = handler;
                    this.addEventListener('open', function(_e) {
                        postToSwift({
                            type: 'websocket',
                            id: connectionId,
                            url: absoluteUrl,
                            event: 'open',
                            protocol: ws.protocol,
                            extensions: ws.extensions,
                            timestamp: Date.now()
                        });
                    }, { once: true });
                }
            });

            // Intercept onclose
            Object.defineProperty(ws, 'onclose', {
                get: function() { return this._apiGhostOnClose; },
                set: function(handler) {
                    this._apiGhostOnClose = handler;
                    this.addEventListener('close', function(e) {
                        postToSwift({
                            type: 'websocket',
                            id: connectionId,
                            url: absoluteUrl,
                            event: 'close',
                            code: e.code,
                            reason: e.reason,
                            wasClean: e.wasClean,
                            duration: Date.now() - startTime,
                            messagesSent: messageCount.sent,
                            messagesReceived: messageCount.received,
                            timestamp: Date.now()
                        });
                        connections.delete(connectionId);
                    }, { once: true });
                }
            });

            // Intercept onerror
            Object.defineProperty(ws, 'onerror', {
                get: function() { return this._apiGhostOnError; },
                set: function(handler) {
                    this._apiGhostOnError = handler;
                    this.addEventListener('error', function(_e) {
                        postToSwift({
                            type: 'websocket',
                            id: connectionId,
                            url: absoluteUrl,
                            event: 'error',
                            message: 'WebSocket error',
                            timestamp: Date.now()
                        });
                    }, { once: true });
                }
            });

            // Intercept onmessage
            Object.defineProperty(ws, 'onmessage', {
                get: function() { return this._apiGhostOnMessage; },
                set: function(handler) {
                    this._apiGhostOnMessage = handler;
                    this.addEventListener('message', async function(e) {
                        messageCount.received++;

                        let data = e.data;
                        let messageType = 'text';
                        let dataSize = 0;

                        if (typeof data === 'string') {
                            messageType = 'text';
                            dataSize = data.length;
                        } else if (data instanceof Blob) {
                            messageType = 'binary';
                            dataSize = data.size;
                            // Convert to base64 for small blobs
                            if (data.size < 1024 * 1024) {
                                data = await binaryToBase64(data) || '[Binary data]';
                            } else {
                                data = `[Binary blob: ${data.size} bytes]`;
                            }
                        } else if (data instanceof ArrayBuffer) {
                            messageType = 'binary';
                            dataSize = data.byteLength;
                            if (data.byteLength < 1024 * 1024) {
                                data = binaryToBase64(data) || '[Binary data]';
                            } else {
                                data = `[ArrayBuffer: ${data.byteLength} bytes]`;
                            }
                        }

                        postToSwift({
                            type: 'websocket',
                            id: connectionId,
                            url: absoluteUrl,
                            event: 'message',
                            direction: 'receive',
                            messageType: messageType,
                            data: data,
                            dataSize: dataSize,
                            timestamp: Date.now()
                        });
                    });
                }
            });

            // Intercept send method
            const originalSend = ws.send.bind(ws);
            ws.send = function(data) {
                messageCount.sent++;

                let sendData = data;
                let messageType = 'text';
                let dataSize = 0;

                if (typeof data === 'string') {
                    messageType = 'text';
                    dataSize = data.length;
                } else if (data instanceof Blob) {
                    messageType = 'binary';
                    dataSize = data.size;
                    sendData = `[Binary blob: ${data.size} bytes]`;
                } else if (data instanceof ArrayBuffer) {
                    messageType = 'binary';
                    dataSize = data.byteLength;
                    if (data.byteLength < 1024 * 1024) {
                        sendData = binaryToBase64(data) || '[Binary data]';
                    } else {
                        sendData = `[ArrayBuffer: ${data.byteLength} bytes]`;
                    }
                } else if (ArrayBuffer.isView(data)) {
                    messageType = 'binary';
                    dataSize = data.byteLength;
                    sendData = `[TypedArray: ${data.byteLength} bytes]`;
                }

                postToSwift({
                    type: 'websocket',
                    id: connectionId,
                    url: absoluteUrl,
                    event: 'message',
                    direction: 'send',
                    messageType: messageType,
                    data: sendData,
                    dataSize: dataSize,
                    timestamp: Date.now()
                });

                return originalSend(data);
            };

            // Intercept close method
            const originalClose = ws.close.bind(ws);
            ws.close = function(code, reason) {
                postToSwift({
                    type: 'websocket',
                    id: connectionId,
                    url: absoluteUrl,
                    event: 'closing',
                    code: code,
                    reason: reason,
                    timestamp: Date.now()
                });

                return originalClose(code, reason);
            };

            // Also intercept addEventListener for message events
            const originalAddEventListener = ws.addEventListener.bind(ws);
            ws.addEventListener = function(type, listener, options) {
                if (type === 'message') {
                    const wrappedListener = async function(e) {
                        messageCount.received++;

                        let data = e.data;
                        let messageType = 'text';
                        let dataSize = 0;

                        if (typeof data === 'string') {
                            messageType = 'text';
                            dataSize = data.length;
                        } else if (data instanceof Blob) {
                            messageType = 'binary';
                            dataSize = data.size;
                            if (data.size < 1024 * 1024) {
                                data = await binaryToBase64(data) || '[Binary data]';
                            } else {
                                data = `[Binary blob: ${data.size} bytes]`;
                            }
                        } else if (data instanceof ArrayBuffer) {
                            messageType = 'binary';
                            dataSize = data.byteLength;
                            if (data.byteLength < 1024 * 1024) {
                                data = binaryToBase64(data) || '[Binary data]';
                            } else {
                                data = `[ArrayBuffer: ${data.byteLength} bytes]`;
                            }
                        }

                        postToSwift({
                            type: 'websocket',
                            id: connectionId,
                            url: absoluteUrl,
                            event: 'message',
                            direction: 'receive',
                            messageType: messageType,
                            data: data,
                            dataSize: dataSize,
                            timestamp: Date.now()
                        });

                        if (typeof listener === 'function') {
                            listener.call(this, e);
                        } else if (listener && typeof listener.handleEvent === 'function') {
                            listener.handleEvent(e);
                        }
                    };
                    return originalAddEventListener(type, wrappedListener, options);
                } else if (type === 'open') {
                    const wrappedListener = function(e) {
                        postToSwift({
                            type: 'websocket',
                            id: connectionId,
                            url: absoluteUrl,
                            event: 'open',
                            protocol: ws.protocol,
                            extensions: ws.extensions,
                            timestamp: Date.now()
                        });

                        if (typeof listener === 'function') {
                            listener.call(this, e);
                        } else if (listener && typeof listener.handleEvent === 'function') {
                            listener.handleEvent(e);
                        }
                    };
                    return originalAddEventListener(type, wrappedListener, options);
                } else if (type === 'close') {
                    const wrappedListener = function(e) {
                        postToSwift({
                            type: 'websocket',
                            id: connectionId,
                            url: absoluteUrl,
                            event: 'close',
                            code: e.code,
                            reason: e.reason,
                            wasClean: e.wasClean,
                            duration: Date.now() - startTime,
                            messagesSent: messageCount.sent,
                            messagesReceived: messageCount.received,
                            timestamp: Date.now()
                        });
                        connections.delete(connectionId);

                        if (typeof listener === 'function') {
                            listener.call(this, e);
                        } else if (listener && typeof listener.handleEvent === 'function') {
                            listener.handleEvent(e);
                        }
                    };
                    return originalAddEventListener(type, wrappedListener, options);
                } else if (type === 'error') {
                    const wrappedListener = function(e) {
                        postToSwift({
                            type: 'websocket',
                            id: connectionId,
                            url: absoluteUrl,
                            event: 'error',
                            message: 'WebSocket error',
                            timestamp: Date.now()
                        });

                        if (typeof listener === 'function') {
                            listener.call(this, e);
                        } else if (listener && typeof listener.handleEvent === 'function') {
                            listener.handleEvent(e);
                        }
                    };
                    return originalAddEventListener(type, wrappedListener, options);
                }

                return originalAddEventListener(type, listener, options);
            };

            return ws;
        };

        // Preserve static properties
        window.WebSocket.CONNECTING = OriginalWebSocket.CONNECTING;
        window.WebSocket.OPEN = OriginalWebSocket.OPEN;
        window.WebSocket.CLOSING = OriginalWebSocket.CLOSING;
        window.WebSocket.CLOSED = OriginalWebSocket.CLOSED;
        window.WebSocket.prototype = OriginalWebSocket.prototype;
    }

    // ========================================
    // BEACON API INTERCEPTION
    // ========================================

    if (navigator.sendBeacon) {
        const originalBeacon = navigator.sendBeacon.bind(navigator);

        navigator.sendBeacon = function(url, data) {
            const requestId = generateId();
            const absoluteUrl = toAbsoluteURL(url);

            let bodyData = null;
            if (data) {
                if (typeof data === 'string') {
                    bodyData = data;
                } else if (data instanceof Blob) {
                    bodyData = `[Beacon Blob: ${data.size} bytes, ${data.type}]`;
                } else if (data instanceof FormData) {
                    const entries = [];
                    data.forEach((v, k) => entries.push(`${k}=${v}`));
                    bodyData = entries.join('&');
                } else if (data instanceof URLSearchParams) {
                    bodyData = data.toString();
                } else if (data instanceof ArrayBuffer || ArrayBuffer.isView(data)) {
                    bodyData = `[Beacon Binary: ${data.byteLength} bytes]`;
                }
            }

            postToSwift({
                type: 'request',
                id: requestId,
                url: absoluteUrl,
                method: 'POST',
                headers: { 'content-type': 'text/plain' },
                body: bodyData,
                isBeacon: true,
                timestamp: Date.now()
            });

            const result = originalBeacon(url, data);

            // Beacons don't have responses, but we should note success/failure
            postToSwift({
                type: 'response',
                id: requestId,
                url: absoluteUrl,
                status: result ? 202 : 0,
                statusText: result ? 'Accepted (Beacon)' : 'Failed (Beacon)',
                headers: {},
                body: null,
                isBeacon: true,
                duration: 0,
                timestamp: Date.now()
            });

            return result;
        };
    }

    // ========================================
    // UTILITY: Get active connections info
    // ========================================

    window.__apiGhostGetConnections = function() {
        const result = [];
        connections.forEach((info, id) => {
            result.push({
                id: id,
                type: info.type,
                url: info.url,
                duration: Date.now() - info.startTime,
                messageCount: info.messageCount
            });
        });
        return result;
    };

    // Expose safeStringify for debugging complex objects
    window.__apiGhostStringify = safeStringify;

    console.log('[APIGhost] Comprehensive interceptor installed (fetch, XHR, WebSocket, SSE, Beacon, Streaming)');
})();
