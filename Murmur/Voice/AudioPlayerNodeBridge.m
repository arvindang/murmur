#import "AudioPlayerNodeBridge.h"

void MurmurScheduleBufferUntilPlayedBack(
    AVAudioPlayerNode *player,
    AVAudioPCMBuffer *buffer,
    MurmurAudioCompletionHandler completion
) {
    [player scheduleBuffer:buffer
        completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack
        completionHandler:^(__unused AVAudioPlayerNodeCompletionCallbackType callbackType) {
            completion();
        }];
}
