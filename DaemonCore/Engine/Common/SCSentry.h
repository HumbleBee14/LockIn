#import <Foundation/Foundation.h>

@interface SCSentry : NSObject
+ (void)captureError:(NSError*)error;
+ (void)captureMessage:(NSString*)message;
+ (void)addBreadcrumb:(NSString*)message category:(NSString*)category;
+ (void)startSentry:(NSString*)dsn;
@end
