#import <Foundation/Foundation.h>

@interface SCMigrationUtilities : NSObject
+ (BOOL)legacyLockFileExists;
+ (BOOL)legacyBlockIsRunningInSettingsFile:(NSURL*)settingsFileURL;
@end
