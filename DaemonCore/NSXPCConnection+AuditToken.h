#import <Foundation/Foundation.h>

@interface NSXPCConnection (LockInAuditToken)
@property (nonatomic, readonly) audit_token_t auditToken;
@end
