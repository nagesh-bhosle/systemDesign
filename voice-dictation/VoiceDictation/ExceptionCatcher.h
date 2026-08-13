#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ExceptionCatcher : NSObject

/// Runs `block`, converting thrown NSExceptions into NSError. Returns NO on failure.
+ (BOOL)run:(void (NS_NOESCAPE ^)(NSError *_Nullable *_Nullable))block
      error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
