MODULE_NAME='mCloudLogger'  (
                                dev vdvObject,
                                dev dvPort
                            )

(***********************************************************)
#DEFINE USING_NAV_MODULE_BASE_CALLBACKS
#DEFINE USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
#DEFINE USING_NAV_WEBSOCKET_ON_OPEN_CALLBACK
#DEFINE USING_NAV_WEBSOCKET_ON_MESSAGE_CALLBACK
#DEFINE USING_NAV_WEBSOCKET_ON_CLOSE_CALLBACK
#DEFINE USING_NAV_WEBSOCKET_ON_ERROR_CALLBACK
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.ErrorLogUtils.axi'
#include 'NAVFoundation.StringUtils.axi'
#include 'NAVFoundation.SocketUtils.axi'
#include 'NAVFoundation.WebSocket.axi'
#include 'NAVFoundation.Json.axi'
#include 'NAVFoundation.TimelineUtils.axi'
#include 'NAVFoundation.DateTimeUtils.axi'
#include 'NAVFoundation.Url.axi'
#include 'NAVFoundation.CloudLog.axi'
#include 'LibCloudLogger.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2010-2026 Norgate AV

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

constant long TL_WEBSOCKET_CHECK = 1

constant long TL_WEBSOCKET_CHECK_INTERVAL[] = { 5000 }      // 5 seconds


(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

struct _Context {
    char ServerUrl[255]           // WebSocket server URL (e.g., ws://server:port)
    char ClientId[100]            // Client/device identifier
    char RoomName[100]            // Room name/location
    char IsProcessingQueue        // Flag to indicate if queue is being processed
}


(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile _NAVModule module
volatile _Context context
volatile _NAVWebSocket ws
volatile _CloudLogQueue queue


(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)

define_function ConnectToServer() {
    if (!length_array(context.ServerUrl)) {
        NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                    "GetLogPrefix(), 'Server URL is not configured'")
        return
    }

    if (NAVWebSocketIsOpen(ws)) {
        NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                    "GetLogPrefix(), 'Already connected to server'")
        return
    }

    NAVErrorLog(NAV_LOG_LEVEL_INFO,
                "GetLogPrefix(), 'Connecting to WebSocket server: ', context.ServerUrl")

    if (!NAVWebSocketConnect(ws, context.ServerUrl)) {
        NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                    "GetLogPrefix(), 'Failed to initiate WebSocket connection'")
    }
}


define_function DisconnectFromServer() {
    if (!NAVWebSocketIsOpen(ws)) {
        return
    }

    NAVWebSocketClose(ws)
}


define_function MaintainWebSocketConnection() {
    if (NAVWebSocketIsOpen(ws)) {
        return
    }

    NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                "GetLogPrefix(), 'WebSocket not connected, attempting reconnect...'")
    ConnectToServer()
}


define_function ProcessLogQueue() {
    stack_var _NAVCloudLog log
    stack_var char payload[2048]

    // Prevent re-entry
    if (context.IsProcessingQueue) {
        return
    }

    // Check if connected
    if (!NAVWebSocketIsOpen(ws)) {
        // Don't process if not connected - logs will queue up
        return
    }

    context.IsProcessingQueue = true

    // Process items while queue is not empty
    while (!QueueIsEmpty(queue)) {
        if (!QueueDequeue(queue, log)) {
            break
        }

        payload = NAVCloudLogJsonSerialize(log)

        NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                        "GetLogPrefix(), 'Sending log: ', payload")
        NAVWebSocketSend(ws, payload)
    }

    context.IsProcessingQueue = false
}


define_function HandleLogCommand(_NAVSnapiMessage message) {
    stack_var _NAVCloudLog log

    // Parse format: LOG-level,message
    if (length_array(message.Parameter) < 2) {
        NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                    "GetLogPrefix(), 'Invalid LOG command format. Expected: LOG-level,message'")
        return
    }

    if (!NAVCloudLogCreate(context.ClientId,
                           context.RoomName,
                           message.Parameter[1],
                           message.Parameter[2],
                           log)) {
        NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                    "GetLogPrefix(), 'Failed to create log item from command'")
        return
    }

    // Enqueue the log item
    if (!QueueEnqueue(queue, log)) {
        NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                    "GetLogPrefix(), 'Failed to enqueue log - queue is full'")
        return
    }

    NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                "GetLogPrefix(), 'Log enqueued. Queue size: ', itoa(QueueSize(queue))")

    // Process queue immediately if connected
    ProcessLogQueue()
}


#IF_DEFINED USING_NAV_WEBSOCKET_ON_OPEN_CALLBACK
define_function NAVWebSocketOnOpenCallback(_NAVWebSocket websocket, _NAVWebSocketOnOpenResult result) {
    NAVErrorLog(NAV_LOG_LEVEL_INFO,
                "GetLogPrefix(), 'WebSocket connected to ', websocket.Url.Host, ':', itoa(websocket.Url.Port)")

    // Process queued items if any
    if (!QueueIsEmpty(queue)) {
        NAVErrorLog(NAV_LOG_LEVEL_INFO,
                    "GetLogPrefix(), 'Processing queued logs (', itoa(QueueSize(queue)), ' items)'")
        ProcessLogQueue()
    }
}
#END_IF


#IF_DEFINED USING_NAV_WEBSOCKET_ON_MESSAGE_CALLBACK
define_function NAVWebSocketOnMessageCallback(_NAVWebSocket websocket, _NAVWebSocketOnMessageResult result) {
    stack_var _NAVCloudLogResponse response

    NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                "GetLogPrefix(), 'Received message from server: ', result.Data")

    if (!NAVCloudLogResponseParse(result.Data, response)) {
        NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                    "GetLogPrefix(), 'Failed to parse log response from server'")
        return
    }

    NAVErrorLog(NAV_LOG_LEVEL_INFO,
                "GetLogPrefix(), 'Log response received: id=', response.id, ', status=', response.status")
}
#END_IF


#IF_DEFINED USING_NAV_WEBSOCKET_ON_CLOSE_CALLBACK
define_function NAVWebSocketOnCloseCallback(_NAVWebSocket websocket, _NAVWebSocketOnCloseResult result) {
    NAVErrorLog(NAV_LOG_LEVEL_WARNING,
                "GetLogPrefix(), 'WebSocket connection closed: code=', itoa(result.StatusCode), ', reason=', result.Reason")
}
#END_IF


#IF_DEFINED USING_NAV_WEBSOCKET_ON_ERROR_CALLBACK
define_function NAVWebSocketOnErrorCallback(_NAVWebSocket websocket, _NAVWebSocketOnErrorResult result) {
    NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                "GetLogPrefix(), 'WebSocket error: ', result.Message, ' (code: ', itoa(result.ErrorCode), ')'")
}
#END_IF


define_function WebSocketConnectionReset() {
    if (NAVWebSocketIsOpen(ws)) {
        NAVErrorLog(NAV_LOG_LEVEL_INFO,
                    "GetLogPrefix(), 'Resetting WebSocket connection'")
        DisconnectFromServer()
    }

    if (timeline_active(TL_WEBSOCKET_CHECK)) {
        // Reset timeline to attempt reconnect in 5 seconds
        NAVTimelineSetValue(TL_WEBSOCKET_CHECK, 0)
        return
    }

    // Start timeline to check connection
    NAVTimelineStart(TL_WEBSOCKET_CHECK,
                     TL_WEBSOCKET_CHECK_INTERVAL,
                     TIMELINE_ABSOLUTE,
                     TIMELINE_REPEAT)
}


#IF_DEFINED USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
define_function NAVModulePropertyEventCallback(_NAVModulePropertyEvent event) {
    switch (event.Name) {
        case 'SERVER_URL': {
            stack_var _NAVUrl url
            stack_var char urlString[255]

            urlString = NAVTrimString(event.Args[1])

            if (!NAVParseUrl(urlString, url)) {
                NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                            "GetLogPrefix(), 'Invalid SERVER_URL format: ', urlString")
                return
            }

            context.ServerUrl = urlString
            NAVErrorLog(NAV_LOG_LEVEL_INFO,
                        "GetLogPrefix(), 'Server URL set to: ', context.ServerUrl")

            // Reset connection to apply new URL
            WebSocketConnectionReset()
        }
        case 'CLIENT_ID': {
            context.ClientId = NAVTrimString(event.Args[1])
            NAVErrorLog(NAV_LOG_LEVEL_INFO,
                        "GetLogPrefix(), 'Client ID set to: ', context.ClientId")
        }
        case 'ROOM_NAME': {
            context.RoomName = NAVTrimString(event.Args[1])
            NAVErrorLog(NAV_LOG_LEVEL_INFO,
                        "GetLogPrefix(), 'Room name set to: ', context.RoomName")
        }
    }
}
#END_IF


define_function char[NAV_MAX_BUFFER] GetLogPrefix() {
    return "'mCloudLogger [', NAVDeviceToString(dvPort), '] => '"
}


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    NAVModuleInit(module)

    // Initialize WebSocket
    NAVWebSocketInit(ws, dvPort)
    create_buffer dvPort, ws.RxBuffer.Data

    // Initialize log queue
    QueueInit(queue, MAX_LOG_ITEMS)

    NAVErrorLog(NAV_LOG_LEVEL_INFO,
                "GetLogPrefix(), 'Cloud logger module initialized'")
}


(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT

data_event[dvPort] {
    online: {
        NAVWebSocketOnConnect(ws)
    }
    offline: {
        NAVWebSocketOnDisconnect(ws)
    }
    onerror: {
        NAVWebSocketOnError(ws)
        NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                    "GetLogPrefix(), 'Socket error: ', NAVGetSocketError(type_cast(data.number))")
    }
    string: {
        // Process incoming WebSocket data
        NAVWebSocketProcessBuffer(ws)
    }
}


data_event[vdvObject] {
    command: {
        stack_var _NAVSnapiMessage message

        NAVParseSnapiMessage(data.text, message)

        switch (message.Header) {
            case 'LOG': {
                // Incoming log to be queued and sent
                HandleLogCommand(message)
            }
        }
    }
}


timeline_event[TL_WEBSOCKET_CHECK] {
    MaintainWebSocketConnection()
}


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)
