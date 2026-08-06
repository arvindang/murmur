#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MurmurAudioCompletionHandler)(void);

/// Schedules a PCM buffer and calls completion only after it reaches the output device.
FOUNDATION_EXPORT void MurmurScheduleBufferUntilPlayedBack(
    AVAudioPlayerNode *player,
    AVAudioPCMBuffer *buffer,
    MurmurAudioCompletionHandler completion
);

NS_ASSUME_NONNULL_END
