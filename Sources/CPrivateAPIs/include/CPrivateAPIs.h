#ifndef CPRIVATEAPIS_H
#define CPRIVATEAPIS_H

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <mach/mach.h>

CF_IMPLICIT_BRIDGING_ENABLED
CF_ASSUME_NONNULL_BEGIN

// IOKit exports these HID functions but the SDK doesn't declare them. They're
// the only way to read Apple Silicon temperature sensors without root, and are
// what Stats and similar monitors use.
typedef struct CF_BRIDGED_TYPE(id) __IOHIDEvent *IOHIDEventRef;

IOHIDEventSystemClientRef _Nullable IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
IOHIDEventRef _Nullable IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
double IOHIDEventGetFloatValue(IOHIDEventRef event, uint32_t field);

CF_ASSUME_NONNULL_END
CF_IMPLICIT_BRIDGING_DISABLED

/// `mach_task_self()` is a macro over a mutable global, which Swift 6 rejects.
static inline mach_port_t allset_mach_task_self(void) { return mach_task_self(); }

#endif
