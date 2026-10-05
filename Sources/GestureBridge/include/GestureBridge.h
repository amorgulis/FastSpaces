#pragma once
#include <ApplicationServices/ApplicationServices.h>
typedef struct FSSequence FSSequence;
FSSequence *FSPrepareSwipe(int direction);
void FSPostSwipe(FSSequence *sequence);
void FSReleaseSwipe(FSSequence *sequence);
CGEventRef FSCopySequenceEvent(FSSequence *sequence, int index);
