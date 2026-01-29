PROGRAM_NAME='LibCloudLogger'

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

#IF_NOT_DEFINED __LIB_CLOUD_LOGGER__
#DEFINE __LIB_CLOUD_LOGGER__ 'LibCloudLogger'

#include 'NAVFoundation.Core.h.axi'
#include 'NAVFoundation.ErrorLogUtils.axi'
#include 'NAVFoundation.CloudLog.axi'
#include 'NAVFoundation.Json.axi'

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

#IF_NOT_DEFINED MAX_LOG_ITEMS
constant integer MAX_LOG_ITEMS = 500
#END_IF


(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

/**
 * Queue structure for log items using circular buffer
 */
struct _CloudLogQueue {
    integer Head           // Index of front of queue
    integer Tail           // Index of rear of queue
    integer Capacity       // Maximum number of items
    integer Count          // Current number of items
    _NAVCloudLog Items[MAX_LOG_ITEMS]
}


(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)

/**
 * Initialize a log queue with the specified capacity
 *
 * @param {_CloudLogQueue} queue - The queue structure to initialize
 * @param {integer} initCapacity - Maximum number of items (defaults to MAX_LOG_ITEMS if invalid)
 */
define_function QueueInit(_CloudLogQueue queue, integer initCapacity) {
    stack_var integer x
    stack_var integer capacity

    capacity = initCapacity

    if (capacity <= 0 || capacity > MAX_LOG_ITEMS) {
        capacity = MAX_LOG_ITEMS
    }

    queue.Capacity = capacity
    // Initialize Head and Tail to capacity (last position)
    // First enqueue will wrap to index 1
    queue.Head = capacity
    queue.Tail = capacity
    queue.Count = 0

    // Initialize all items
    for (x = 1; x <= MAX_LOG_ITEMS; x++) {
        NAVCloudLogInit(queue.Items[x])
    }
}


/**
 * Add a log item to the rear of the queue
 *
 * @param {_CloudLogQueue} queue - The queue to add the item to
 * @param {_NAVCloudLog} item - The log item to add
 * @returns {char} True (1) if successful, False (0) if queue is full
 */
define_function char QueueEnqueue(_CloudLogQueue queue, _NAVCloudLog item) {
    // If queue is full, remove oldest item to make room
    if (queue.Count >= queue.Capacity) {
        NAVErrorLog(NAV_LOG_LEVEL_WARNING,
                    "'Queue is full (', itoa(queue.Capacity), ' items). Dropping oldest log to make room.'")
        // Advance Head to drop oldest item (don't need to retrieve it)
        queue.Head = (queue.Head % queue.Capacity) + 1
        queue.Count--
    }

    // This cycles: 1 -> 2 -> 3 -> ... -> capacity -> 1
    queue.Tail = (queue.Tail % queue.Capacity) + 1
    queue.Items[queue.Tail] = item
    queue.Count++

    return true
}


/**
 * Remove and return the item at the front of the queue
 *
 * @param {_CloudLogQueue} queue - The queue to remove from
 * @param {_NAVCloudLog} item - Output parameter to receive the dequeued item
 * @returns {char} True (1) if successful, False (0) if queue is empty
 */
define_function char QueueDequeue(_CloudLogQueue queue, _NAVCloudLog item) {
    if (queue.Count == 0) {
        return false
    }

    queue.Head = (queue.Head % queue.Capacity) + 1
    item = queue.Items[queue.Head]
    queue.Count--

    // Clear the dequeued slot
    NAVCloudLogInit(queue.Items[queue.Head])

    return true
}


/**
 * Get the item at the front of the queue without removing it
 *
 * @param {_CloudLogQueue} queue - The queue to peek at
 * @param {_NAVCloudLog} item - Output parameter to receive the peeked item
 * @returns {char} True (1) if successful, False (0) if queue is empty
 */
define_function char QueuePeek(_CloudLogQueue queue, _NAVCloudLog item) {
    stack_var integer nextIndex

    if (queue.Count == 0) {
        return false
    }

    nextIndex = (queue.Head % queue.Capacity) + 1
    item = queue.Items[nextIndex]
    return true
}


/**
 * Check if the queue is empty
 *
 * @param {_CloudLogQueue} queue - The queue to check
 * @returns {integer} True (1) if empty, False (0) otherwise
 */
define_function char QueueIsEmpty(_CloudLogQueue queue) {
    return (queue.Count == 0)
}


/**
 * Check if the queue is full
 *
 * @param {_CloudLogQueue} queue - The queue to check
 * @returns {integer} True (1) if full, False (0) otherwise
 */
define_function char QueueIsFull(_CloudLogQueue queue) {
    return (queue.Count >= queue.Capacity)
}


/**
 * Get the current number of items in the queue
 *
 * @param {_CloudLogQueue} queue - The queue to check
 * @returns {integer} Number of items in the queue
 */
define_function integer QueueSize(_CloudLogQueue queue) {
    return queue.Count
}


/**
 * Clear all items from the queue
 *
 * @param {_CloudLogQueue} queue - The queue to clear
 */
define_function QueueClear(_CloudLogQueue queue) {
    stack_var integer x

    // Reset to initial state - both at capacity
    queue.Head = queue.Capacity
    queue.Tail = queue.Capacity
    queue.Count = 0

    for (x = 1; x <= MAX_LOG_ITEMS; x++) {
        NAVCloudLogInit(queue.Items[x])
    }
}


#END_IF // __LIB_CLOUD_LOGGER__
