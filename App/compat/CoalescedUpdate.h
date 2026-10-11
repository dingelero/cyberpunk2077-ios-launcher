#import <Foundation/Foundation.h>
#include <stdatomic.h>

// Clear before executing: a request racing with the update queues one follow-up.
// Callers never wait for UIKit; the update itself always runs on its target queue.
static inline BOOL CPRequestCoalescedUpdate(atomic_bool *pending, dispatch_queue_t queue, dispatch_block_t update) {
    if (atomic_exchange_explicit(pending, true, memory_order_acq_rel)) return NO;
    dispatch_async(queue, ^{
        atomic_store_explicit(pending, false, memory_order_release);
        update();
    });
    return YES;
}
