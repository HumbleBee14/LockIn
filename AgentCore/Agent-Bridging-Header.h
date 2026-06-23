#import <Foundation/Foundation.h>

@interface NSXPCConnection (LockInAgentAuditToken)
@property (nonatomic, readonly) audit_token_t auditToken;
@end
