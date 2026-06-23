#import "SCMigrationUtilities.h"

@implementation SCMigrationUtilities
+ (BOOL)legacyLockFileExists { return NO; }
+ (BOOL)legacyBlockIsRunningInSettingsFile:(NSURL*)settingsFileURL { return NO; }
@end
