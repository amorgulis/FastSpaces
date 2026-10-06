#pragma once
#include <ApplicationServices/ApplicationServices.h>
typedef struct FSSequence FSSequence;
FSSequence *FSPrepareSwipe(int direction);
void FSPostSwipe(FSSequence *sequence);
void FSReleaseSwipe(FSSequence *sequence);
CGEventRef FSCopySequenceEvent(FSSequence *sequence, int index);

// Read-only boundary queries. Unknown topology is treated as unavailable.
bool FSCanNavigateSnapshot(CFArrayRef displays, CFStringRef display, int direction);
bool FSCanSwitchSpace(int direction);
