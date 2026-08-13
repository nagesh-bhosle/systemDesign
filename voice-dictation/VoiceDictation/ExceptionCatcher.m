#import "ExceptionCatcher.h"

@implementation ExceptionCatcher

+ (BOOL)run:(void (NS_NOESCAPE ^)(NSError *_Nullable *_Nullable))block
      error:(NSError *_Nullable *_Nullable)error
{
    @try {
        NSError *blockError = nil;
        block(&blockError);
        if (blockError != nil) {
            if (error != NULL) {
                *error = blockError;
            }
            return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:exception.name ?: @"AVAudioEngine"
                                         code:1
                                     userInfo:@{
                NSLocalizedDescriptionKey: exception.reason ?: @"Audio engine failed"
            }];
        }
        return NO;
    }
}

@end
