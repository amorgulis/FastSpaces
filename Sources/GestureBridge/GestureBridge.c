// Adapted from joshuarli/iss (0BSD). See THIRD_PARTY_NOTICES.md.
#include "GestureBridge.h"
#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <float.h>
#include <mach/mach_time.h>
#include <signal.h>
#include <string.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/sysctl.h>
#include <dlfcn.h>
#include <dispatch/dispatch.h>

// These are private CGEvent fields used by the WindowServer and Dock for
// trackpad gesture routing. They were discovered via reverse engineering.
static const CGEventField kCGSEventTypeField            = 55;  // real event type
static const CGEventField kCGEventGestureHIDType        = 110; // IOHIDEventType
static const CGEventField kCGEventGestureScrollY        = 119;
static const CGEventField kCGEventGestureSwipeMotion    = 123; // horiz vs vert
static const CGEventField kCGEventGestureSwipeProgress  = 124; // cumulative distance
static const CGEventField kCGEventGestureSwipeVelocityX = 129;
static const CGEventField kCGEventGestureSwipeVelocityY = 130;
static const CGEventField kCGEventGesturePhase          = 132; // began/changed/ended
static const CGEventField kCGEventScrollGestureFlagBits = 135; // direction hint
static const CGEventField kCGEventGestureZoomDeltaX     = 139; // required, reason unknown
static const CGEventField kCGEventGestureSwipeMask      = 115;
static const CGEventField kCGEventGestureSwipePositionX = 125;
static const CGEventField kCGEventGestureSwipePositionY = 126;
static const CGEventField kCGEventGesturePhaseAlias     = 134;
static const CGEventField kCGEventGestureZoomDeltaY     = 138;
static const CGEventField kCGEventSourceProcessAlias    = 169;
static const CGEventField kCGEventRawIOHIDPayload       = 4205;

enum { kCGSEventGesture = 29, kCGSEventDockControl = 30 };
enum { kIOHIDEventTypeDockSwipe = 23 };
enum { kCGGestureMotionHorizontal = 1, kCGGestureMotionVertical = 2 };
enum { kGestureBegan = 1, kGestureChanged = 2, kGestureEnded = 4, kGestureCancelled = 8 };

// macOS 26 reports horizontal swipe direction opposite to earlier releases.
#if defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 260000
#define ISS_SWIPE_DIRECTION_REVERSED 1
#else
#define ISS_SWIPE_DIRECTION_REVERSED 0
#endif





// macOS 27 validates synthetic dock swipes against this serialized IOHID
// queue payload, which is attached to CGEvent field 4205.
#pragma pack(push, 1)

typedef struct {
    uint32_t size;
    uint32_t type;
    uint32_t options;
    uint8_t depth;
    uint8_t reserved[3];
} IOHIDEventBase;

typedef struct {
    IOHIDEventBase base;
    int32_t position_x;
    int32_t position_y;
    int32_t position_z;
    uint32_t swipe_mask;
    uint16_t gesture_motion;
    uint16_t gesture_flavor;
    int32_t swipe_progress;
} IOHIDFluidTouchGestureData;

typedef struct {
    IOHIDEventBase base;
    int32_t velocity_x;
    int32_t velocity_y;
    int32_t velocity_z;
} IOHIDVelocityEventData;

typedef struct {
    uint64_t timestamp;
    uint64_t sender_id;
    uint32_t options;
    uint32_t attribute_length;
    uint32_t event_count;
} IOHIDSystemQueueElementHeader;

#pragma pack(pop)

_Static_assert(sizeof(IOHIDEventBase) == 16, "unexpected IOHID event base layout");
_Static_assert(sizeof(IOHIDFluidTouchGestureData) == 40,
               "unexpected IOHID fluid gesture layout");
_Static_assert(sizeof(IOHIDVelocityEventData) == 28,
               "unexpected IOHID velocity layout");
_Static_assert(sizeof(IOHIDSystemQueueElementHeader) == 28,
               "unexpected IOHID queue header layout");

static const uint32_t kIOHIDEventTypeVelocity = 9;
static const uint32_t kIOHIDEventTypeFluidTouchGesture = 23;
static const uint16_t kIOHIDGestureFlavorDockPrimary = 3;

static int32_t double_to_fixed1616(double value) {
    int32_t fixed = (int32_t)(value * 65536.0);
    if (fixed == 0 && value != 0.0) return value > 0.0 ? 1 : -1;
    return fixed;
}

static uint8_t *generate_iohid_payload(CGEventRef event, size_t *out_length) {
    int64_t phase = CGEventGetIntegerValueField(event, (CGEventField)132);
    int64_t motion = CGEventGetIntegerValueField(event, (CGEventField)123);
    double progress = CGEventGetDoubleValueField(event, (CGEventField)124);
    double pos_x = CGEventGetDoubleValueField(event, kCGEventGestureSwipePositionX);
    double pos_y = CGEventGetDoubleValueField(event, kCGEventGestureSwipePositionY);
    double vel_x = CGEventGetDoubleValueField(event, (CGEventField)129);
    double vel_y = CGEventGetDoubleValueField(event, (CGEventField)130);
    int64_t swipe_mask = CGEventGetIntegerValueField(event, kCGEventGestureSwipeMask);

    bool include_velocity = (vel_x != 0.0 || vel_y != 0.0 || phase == 4);
    uint32_t event_count = include_velocity ? 2 : 1;
    size_t payload_length = sizeof(IOHIDSystemQueueElementHeader)
                          + sizeof(IOHIDFluidTouchGestureData);
    if (include_velocity) payload_length += sizeof(IOHIDVelocityEventData);

    uint8_t *payload = malloc(payload_length);
    if (!payload) return NULL;
    memset(payload, 0, payload_length);

    IOHIDSystemQueueElementHeader *header = (IOHIDSystemQueueElementHeader *)payload;
    uint64_t timestamp = CGEventGetTimestamp(event);
    // CGEvent timestamps are nanoseconds; IOHID queue headers use Mach ticks.
    // Native captures confirm the timebase conversion on Apple silicon.
    mach_timebase_info_data_t timebase;
    if (timestamp && mach_timebase_info(&timebase) == KERN_SUCCESS && timebase.numer) {
        header->timestamp = (uint64_t)(((__uint128_t)timestamp * timebase.denom) / timebase.numer);
    } else {
        header->timestamp = mach_absolute_time();
    }
    header->event_count = event_count;

    IOHIDFluidTouchGestureData *fluid =
        (IOHIDFluidTouchGestureData *)(payload + sizeof(IOHIDSystemQueueElementHeader));
    fluid->base.size = sizeof(IOHIDFluidTouchGestureData);
    fluid->base.type = kIOHIDEventTypeFluidTouchGesture;
    fluid->base.options = (uint32_t)((phase & 0xFF) << 24);
    fluid->position_x = double_to_fixed1616(pos_x);
    fluid->position_y = double_to_fixed1616(pos_y);
    fluid->swipe_mask = (uint32_t)swipe_mask;
    fluid->gesture_motion = (uint16_t)motion;
    fluid->gesture_flavor = kIOHIDGestureFlavorDockPrimary;
    fluid->swipe_progress = double_to_fixed1616(progress);

    if (include_velocity) {
        IOHIDVelocityEventData *velocity = (IOHIDVelocityEventData *)
            (payload + sizeof(IOHIDSystemQueueElementHeader)
             + sizeof(IOHIDFluidTouchGestureData));
        velocity->base.size = sizeof(IOHIDVelocityEventData);
        velocity->base.type = kIOHIDEventTypeVelocity;
        velocity->base.depth = 1;
        velocity->velocity_x = double_to_fixed1616(vel_x);
        velocity->velocity_y = double_to_fixed1616(vel_y);
    }

    *out_length = payload_length;
    return payload;
}

// Adds the raw IOHID payload needed for synthetic dock swipes on macOS 27.
static CGEventRef augment_dock_swipe_event(CGEventRef event) {
    if (!event) return NULL;

    CFDataRef data = CGEventCreateData(kCFAllocatorDefault, event);
    if (!data) return NULL;

    const uint8_t *bytes = CFDataGetBytePtr(data);
    CFIndex length = CFDataGetLength(data);
    if (length < 4 || bytes[0] != 0 || bytes[1] != 0
        || bytes[2] != 0 || bytes[3] != 2) {
        CFRelease(data);
        return NULL;
    }

    size_t payload_length = 0;
    uint8_t *payload = generate_iohid_payload(event, &payload_length);
    if (!payload) {
        CFRelease(data);
        return NULL;
    }

    size_t new_length = (size_t)length + 4 + payload_length;
    uint8_t *new_bytes = malloc(new_length);
    if (!new_bytes) {
        free(payload);
        CFRelease(data);
        return NULL;
    }

    memcpy(new_bytes, bytes, length);
    new_bytes[length] = (uint8_t)(payload_length >> 8);
    new_bytes[length + 1] = (uint8_t)payload_length;
    new_bytes[length + 2] = (uint8_t)(kCGEventRawIOHIDPayload >> 8);
    new_bytes[length + 3] = (uint8_t)kCGEventRawIOHIDPayload;
    memcpy(new_bytes + length + 4, payload, payload_length);

    free(payload);
    CFRelease(data);

    CFDataRef new_data = CFDataCreate(kCFAllocatorDefault, new_bytes, (CFIndex)new_length);
    free(new_bytes);
    if (!new_data) return NULL;

    CGEventRef result = CGEventCreateFromData(kCFAllocatorDefault, new_data);
    CFRelease(new_data);
    return result;
}

static CGEventRef make_augmented_dock_event(int phase, int direction) {
    bool vertical = direction == 2;
    // Vertical up uses positive progress; do not reuse the reversed
    // horizontal Space-switch convention for Mission Control.
    bool negative = direction == 1;
    CGEventRef ev = CGEventCreate(NULL);
    if (!ev) return NULL;

    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || !timebase.denom) {
        CFRelease(ev);
        return NULL;
    }
    CGEventSetTimestamp(ev, (uint64_t)(((__uint128_t)mach_absolute_time() * timebase.numer) / timebase.denom));
    CGEventSetIntegerValueField(ev, kCGSEventTypeField, kCGSEventDockControl);
    CGEventSetIntegerValueField(ev, kCGEventGestureHIDType, kIOHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(ev, kCGEventGesturePhase, phase);
    // Captured native vertical IOHID payloads begin near +0.01 and advance.
    // The CGEvent accessor reports the opposite sign on macOS 27.
    double progress = vertical && phase == kGestureBegan ? 0.009765625 : (negative ? -1.0 : 1.0);
    CGEventSetDoubleValueField(ev, kCGEventGestureSwipeProgress, progress);
    CGEventSetIntegerValueField(ev, kCGEventGestureSwipeMotion, vertical ? kCGGestureMotionVertical : kCGGestureMotionHorizontal);
    CGEventSetIntegerValueField(ev, kCGEventGesturePhaseAlias, phase);
    CGEventSetDoubleValueField(ev, kCGEventGestureZoomDeltaY, 3.0);
    CGEventSetDoubleValueField(ev, kCGEventSourceProcessAlias,
                               (double)mach_absolute_time());
    CGEventSetDoubleValueField(ev, kCGEventGestureSwipePositionX, 0.1);
    if (phase == kGestureEnded) {
        double velocity = negative ? -9999.0 : 9999.0;
        CGEventSetDoubleValueField(ev, kCGEventGestureSwipeVelocityX, velocity);
        // Native vertical swipes carry identical X/Y velocity child fields.
        if (vertical) CGEventSetDoubleValueField(ev, kCGEventGestureSwipeVelocityY, velocity);
    }
    return ev;
}


struct FSSequence { CGEventRef events[16]; int direction; int count; unsigned int phase_delay_us; };
void FSReleaseSwipe(FSSequence *sequence) {
 if (!sequence) return;
 for (int i=0;i<16;i++) if(sequence->events[i]) CFRelease(sequence->events[i]);
 free(sequence);
}
FSSequence *FSPrepareSwipe(int direction) {
 if (direction != -1 && direction != 1 && direction != 2) return NULL;
 FSSequence *sequence = calloc(1, sizeof(FSSequence));
 if (!sequence) return NULL;
 sequence->direction = direction;
 sequence->count = 6;
 const int phases[3] = {1,2,4};
 for (int i=0;i<3;i++) {
  CGEventRef raw = make_augmented_dock_event(phases[i], direction);
  if (!raw) goto failed;
  sequence->events[i*2] = augment_dock_swipe_event(raw);
  CFRelease(raw);
  if (!sequence->events[i*2]) goto failed;
  sequence->events[i*2+1] = CGEventCreate(NULL);
  if (!sequence->events[i*2+1]) goto failed;
  CGEventSetIntegerValueField(sequence->events[i*2+1], kCGSEventTypeField, kCGSEventGesture);
  CGEventSetIntegerValueField(sequence->events[i*2], kCGEventSourceUserData, 0x46535043);
  CGEventSetIntegerValueField(sequence->events[i*2+1], kCGEventSourceUserData, 0x46535043);
 }
 return sequence;
failed:
 FSReleaseSwipe(sequence);
 return NULL;
}
void FSPostSwipe(FSSequence *sequence) {
 // Mission Control does not require an adjacent Space, even on a single desktop.
 if (!sequence) return;
 if (sequence->direction == 3 && !FSIsOverviewActive()) return;
 if ((sequence->direction == -1 || sequence->direction == 1) && !FSCanSwitchSpace(sequence->direction)) return;
 for (int i=0;i<sequence->count;i++) {
  if (i > 0 && i % 2 == 0 && sequence->phase_delay_us) usleep(sequence->phase_delay_us);
  CGEventPost(kCGSessionEventTap, sequence->events[i]);
 }
}
CGEventRef FSCopySequenceEvent(FSSequence *sequence, int index) {
 if (!sequence || index < 0 || index >= sequence->count) return NULL;
 return CGEventCreateCopy(sequence->events[index]);
}

static CFTypeRef dictionary_value(CFTypeRef object, CFStringRef key) {
 if (!object || CFGetTypeID(object) != CFDictionaryGetTypeID()) return NULL;
 return CFDictionaryGetValue((CFDictionaryRef)object, key);
}
static uint64_t space_id(CFTypeRef object) {
 CFTypeRef number = dictionary_value(object, CFSTR("id64"));
 int64_t value = 0;
 if (!number || CFGetTypeID(number) != CFNumberGetTypeID()
     || !CFNumberGetValue(number, kCFNumberSInt64Type, &value)) return 0;
 return (uint64_t)value;
}
bool FSCanNavigateSnapshot(CFArrayRef displays, CFStringRef display, int direction) {
 if (!displays || !display || (direction != -1 && direction != 1)
     || CFGetTypeID(displays) != CFArrayGetTypeID()) return false;
 for (CFIndex i = 0; i < CFArrayGetCount(displays); i++) {
  CFTypeRef entry = CFArrayGetValueAtIndex(displays, i);
  CFTypeRef identifier = dictionary_value(entry, CFSTR("Display Identifier"));
  if (!identifier || !CFEqual(identifier, display)) continue;
  uint64_t current = space_id(dictionary_value(entry, CFSTR("Current Space")));
  CFArrayRef spaces = dictionary_value(entry, CFSTR("Spaces"));
  if (!current || !spaces || CFGetTypeID(spaces) != CFArrayGetTypeID()) return false;
  CFIndex count = CFArrayGetCount(spaces);
  for (CFIndex j = 0; j < count; j++) {
   if (space_id(CFArrayGetValueAtIndex(spaces, j)) != current) continue;
   CFIndex target = j + direction;
   return target >= 0 && target < count
       && space_id(CFArrayGetValueAtIndex(spaces, target)) != 0;
  }
  return false;
 }
 return false;
}

// Read-only SkyLight functions, resolved dynamically so missing symbols cannot
// prevent app startup. Never inject a swipe when its destination is unknown.
static int (*main_connection)(void);
static CFArrayRef (*copy_display_spaces)(int);
static CFStringRef (*copy_display_for_point)(int, CGPoint);
static dispatch_once_t space_api_once;
static void load_space_api(void *unused) {
 void *library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
 if (!library) return;
 main_connection = dlsym(library, "SLSMainConnectionID");
 copy_display_spaces = dlsym(library, "SLSCopyManagedDisplaySpaces");
 copy_display_for_point = dlsym(library, "SLSCopyBestManagedDisplayForPoint");
}
bool FSCanSwitchSpace(int direction) {
 dispatch_once_f(&space_api_once, NULL, load_space_api);
 if (!main_connection || !copy_display_spaces || !copy_display_for_point) return false;
 CGEventRef cursor = CGEventCreate(NULL);
 if (!cursor) return false;
 CGPoint point = CGEventGetLocation(cursor);
 CFRelease(cursor);
 int connection = main_connection();
 CFStringRef display = copy_display_for_point(connection, point);
 CFArrayRef spaces = copy_display_spaces(connection);
 bool allowed = FSCanNavigateSnapshot(spaces, display, direction);
 if (spaces) CFRelease(spaces);
 if (display) CFRelease(display);
 return allowed;
}

static FSSequence *prepare_vertical_overview(bool downward) {
 FSSequence *sequence = calloc(1, sizeof(FSSequence));
 if (!sequence) return NULL;
 sequence->direction = downward ? 4 : 2;
 sequence->count = 16;
 sequence->phase_delay_us = 4000;
 double previous = 0.0;
 for (int step = 0; step < 8; step++) {
  int phase = step == 0 ? kGestureBegan : (step == 7 ? kGestureEnded : kGestureChanged);
  double t = (step + 1) / 8.0;
  double progress = (downward ? -1.0 : 1.0) * t * t * (3.0 - 2.0 * t);
  CGEventRef raw = make_augmented_dock_event(phase, 2);
  if (!raw) goto failed;
  CGEventSetDoubleValueField(raw, kCGEventGestureSwipeProgress, progress);
  CGEventSetDoubleValueField(raw, kCGEventGestureSwipePositionX, 0.0);
  CGEventSetDoubleValueField(raw, kCGEventGestureSwipePositionY, -(progress - previous));
  CGEventSetIntegerValueField(raw, (CGEventField)136, 1);
  if (phase == kGestureEnded && downward) {
   CGEventSetDoubleValueField(raw, kCGEventGestureSwipeVelocityX, -9999.0);
   CGEventSetDoubleValueField(raw, kCGEventGestureSwipeVelocityY, -9999.0);
  }
  sequence->events[step * 2] = augment_dock_swipe_event(raw);
  CFRelease(raw);
  if (!sequence->events[step * 2]) goto failed;
  CGEventRef companion = CGEventCreate(NULL);
  if (!companion) goto failed;
  CGEventSetIntegerValueField(companion, kCGSEventTypeField, kCGSEventGesture);
  sequence->events[step * 2 + 1] = companion;
  previous = progress;
 }
 return sequence;
failed:
 FSReleaseSwipe(sequence);
 return NULL;
}

FSSequence *FSPrepareMissionControl(void) { return prepare_vertical_overview(false); }
FSSequence *FSPrepareAppExpose(void) { return prepare_vertical_overview(true); }

// Empirical Dock overlay pattern; unknown/unavailable state is false.
static bool is_overview_snapshot(CFArrayRef windows, bool include_expose) {
 if (!windows || CFGetTypeID(windows) != CFArrayGetTypeID()) return false;
 int layer18 = 0, layer20 = 0;
 for (CFIndex i = 0; i < CFArrayGetCount(windows); i++) {
  CFTypeRef entry = CFArrayGetValueAtIndex(windows, i);
  CFTypeRef owner = dictionary_value(entry, kCGWindowOwnerName);
  if (!owner || !CFEqual(owner, CFSTR("Dock"))) continue;
  CFTypeRef number = dictionary_value(entry, kCGWindowLayer);
  int layer = 0;
  if (!number || CFGetTypeID(number) != CFNumberGetTypeID() || !CFNumberGetValue(number, kCFNumberIntType, &layer)) continue;
  if (layer == 18) layer18++;
  if (layer == 20) layer20++;
 }
 // macOS 27 live trace: Mission Control presents a lone layer-20 window.
 bool active = layer20 > 0 && (include_expose || layer18 == 0 || layer20 > layer18);
 if (getenv("FASTSPACES_TRACE")) fprintf(stderr, "Mission Control detection: Dock layer18=%d layer20=%d active=%d\n", layer18, layer20, active);
 return active;
}
bool FSIsMissionControlSnapshot(CFArrayRef windows) { return is_overview_snapshot(windows, false); }
bool FSIsOverviewSnapshot(CFArrayRef windows) { return is_overview_snapshot(windows, true); }
static bool is_overview_active(bool include_expose) {
 CFArrayRef windows = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
 bool active = is_overview_snapshot(windows, include_expose);
 if (windows) CFRelease(windows);
 return active;
}
bool FSIsMissionControlActive(void) { return is_overview_active(false); }
bool FSIsOverviewActive(void) { return is_overview_active(true); }
FSSequence *FSPrepareMissionControlDismissal(void) {
 FSSequence *sequence = calloc(1, sizeof(FSSequence));
 if (!sequence) return NULL;
 sequence->direction = 3;
 sequence->count = 2;
 for (int i = 0; i < 2; i++) {
  sequence->events[i] = CGEventCreateKeyboardEvent(NULL, 53, i == 0);
  if (!sequence->events[i]) { FSReleaseSwipe(sequence); return NULL; }
  CGEventSetFlags(sequence->events[i], 0);
  CGEventSetIntegerValueField(sequence->events[i], kCGEventSourceUserData, 0x46535043);
 }
 return sequence;
}
