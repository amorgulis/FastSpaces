#pragma once
#include <ApplicationServices/ApplicationServices.h>
typedef struct FSSequence FSSequence;
// Actions: -1 previous Space, 1 next Space, 2 Mission Control (upward).
FSSequence *FSPrepareSwipe(int direction);
void FSPostSwipe(FSSequence *sequence);
void FSReleaseSwipe(FSSequence *sequence);
CGEventRef FSCopySequenceEvent(FSSequence *sequence, int index);

// Read-only boundary queries. Unknown topology is treated as unavailable.
bool FSCanNavigateSnapshot(CFArrayRef displays, CFStringRef display, int direction);
bool FSCanSwitchSpace(int direction);

// Capture-free eight-phase vertical gesture with 4 ms phase spacing.
FSSequence *FSPrepareMissionControl(void);
