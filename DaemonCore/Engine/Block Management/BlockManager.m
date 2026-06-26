//
//  BlockManager.m
//  SelfControl
//
//  Created by Charles Stigler on 2/5/13.
//  Copyright 2009 Eyebeam.

// This file is part of SelfControl.
//
// SelfControl is free software:  you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#import "BlockManager.h"
#import "AllowlistScraper.h"
#import "SCBlockEntry.h"
#include <sys/socket.h>
#include <netdb.h>
#import "HostFileBlockerSet.h"
#import "SCHelperToolUtilities.h"

@implementation BlockManager

BOOL appendMode = NO;

- (BlockManager*)init {
	return [self initAsAllowlist: NO allowLocal: YES includeCommonSubdomains: YES];
}

- (BlockManager*)initAsAllowlist:(BOOL)allowlist {
	return [self initAsAllowlist: allowlist allowLocal: YES includeCommonSubdomains: YES];
}

- (BlockManager*)initAsAllowlist:(BOOL)allowlist allowLocal:(BOOL)local {
	return [self initAsAllowlist: allowlist allowLocal: local includeCommonSubdomains: YES];
}
- (BlockManager*)initAsAllowlist:(BOOL)allowlist allowLocal:(BOOL)local includeCommonSubdomains:(BOOL)blockCommon {
	return [self initAsAllowlist: allowlist allowLocal: local includeCommonSubdomains: blockCommon includeLinkedDomains: YES];
}

- (BlockManager*)initAsAllowlist:(BOOL)allowlist allowLocal:(BOOL)local includeCommonSubdomains:(BOOL)blockCommon includeLinkedDomains:(BOOL)includeLinked {
	if(self = [super init]) {
		opQueue = [[NSOperationQueue alloc] init];   // hosts-file writes
		[opQueue setMaxConcurrentOperationCount: 35];
		pfQueue = [[NSOperationQueue alloc] init];   // DNS resolution + pf rules
		[pfQueue setMaxConcurrentOperationCount: 35];

		pf = [[PacketFilter alloc] initAsAllowlist: allowlist];
		hostBlockerSet = [[HostFileBlockerSet alloc] init];
		hostsBlockingEnabled = NO;

		isAllowlist = allowlist;
		allowLocal = local;
		includeCommonSubdomains = blockCommon;
		includeLinkedDomains = includeLinked;
        addedBlockEntries = [NSMutableSet set];
	}

	return self;
}

- (void)prepareToAddBlock {
    for (HostFileBlocker* blocker in hostBlockerSet.blockers) {
        if([blocker containsSelfControlBlock]) {
            [blocker removeSelfControlBlock];
            [blocker writeNewFileContents];
        }
    }

	if(!isAllowlist && ![hostBlockerSet.defaultBlocker containsSelfControlBlock]) {
        // never edit /etc/hosts unless we have a recoverable backup
        if([hostBlockerSet createBackupHostsFile]) {
            [hostBlockerSet addSelfControlBlockHeader];
            hostsBlockingEnabled = YES;
        } else {
            NSLog(@"ERROR: hosts backup failed; skipping hosts blocking to stay recoverable");
            hostsBlockingEnabled = NO;
        }
	} else {
		hostsBlockingEnabled = NO;
	}
}

- (void)enterAppendMode {
    if (isAllowlist) {
        NSLog(@"ERROR: can't append to allowlist block");
        return;
    }
    if(![hostBlockerSet.defaultBlocker containsSelfControlBlock]) {
        NSLog(@"ERROR: can't append to hosts block that doesn't yet exist");
        return;
    }
    
    hostsBlockingEnabled = YES;
    appendMode = YES;
    [pf enterAppendMode];
}
- (void)finishAppending {
    // both queues must finish before closing the pf append handle
    [opQueue waitUntilAllOperationsAreFinished];
    [pfQueue waitUntilAllOperationsAreFinished];

    [hostBlockerSet writeNewFileContents];
    [pf finishAppending];
    [pf refreshPFRules];
    appendMode = NO;

    [SCHelperToolUtilities clearOSDNSCache];
}

- (void)finalizeBlock {
	HostFileBlockerSet* hosts = hostBlockerSet;
	BOOL writeHosts = hostsBlockingEnabled;
	NSOperationQueue* pq = pfQueue;
	PacketFilter* p = pf;

	// hosts synchronously: it's fast, and the caller verifies the lock via /etc/hosts right after this returns
	[opQueue waitUntilAllOperationsAreFinished];
	if (writeHosts) { [hosts addSelfControlBlockFooter]; [hosts writeNewFileContents]; }
	[SCHelperToolUtilities clearOSDNSCache];

	if (isAllowlist) {
		// allowlist is pf-only (no hosts gate), so its caller needs the pf result; lists are small
		[pq waitUntilAllOperationsAreFinished];
		_pfDidEnable = ([p startBlock] == 0);
		[SCHelperToolUtilities clearOSDNSCache];
		return;
	}

	// blocklist pf is best-effort and slow — harden it in the background; we don't gate success on it
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		[pq waitUntilAllOperationsAreFinished];
		[p startBlock];
		[SCHelperToolUtilities clearOSDNSCache];
	});
}

- (void)enqueueBlockEntry:(SCBlockEntry*)entry {
	NSBlockOperation* op = [NSBlockOperation blockOperationWithBlock:^{
        [self addBlockEntry: entry];
	}];
	[opQueue addOperation: op];
}

- (void)addBlockEntry:(SCBlockEntry*)entry {
    // nil entries = something didn't parse right
    if (entry == nil) return;

    // NSMutableSet is NOT thread-safe
    @synchronized (addedBlockEntries) {
        // don't try to block the same thing twice
        if ([addedBlockEntries containsObject: entry]) {
            return;
        }
        [addedBlockEntries addObject: entry];
    }

	BOOL isIP = [entry.hostname isValidIPAddress];

	if(hostsBlockingEnabled && ![entry.hostname isEqualToString: @"*"] && !entry.port && !isIP) {
        if (appendMode) {
            [hostBlockerSet appendExistingBlockWithRuleForDomain: entry.hostname];
        } else {
            [hostBlockerSet addRuleBlockingDomain: entry.hostname];
        }
	}

	[self enqueuePFRuleForEntry: entry];   // pf rules carry the DNS cost — kept off the hosts queue
}

- (void)addPFRuleForEntry:(SCBlockEntry*)entry {
	BOOL isIP = [entry.hostname isValidIPAddress];
	BOOL isIPv4 = [entry.hostname isValidIPv4Address];

	if([entry.hostname isEqualToString: @"*"]) {
		[pf addRuleWithIP: nil port: entry.port maskLen: 0];
	} else if(isIPv4) { // no ipfw blocking for IPv6
		[pf addRuleWithIP: entry.hostname port: entry.port maskLen: entry.maskLen];
	} else if(!isIP) {
        if ([self domainIsGoogle: entry.hostname]) {
            if (isAllowlist) [self addGoogleIPsToPF];
            // blocklist: skip Google by IP (would over-block Search/Mail); rely on hosts
        } else {
            NSArray* addresses = [BlockManager ipAddressesForDomainName: entry.hostname];
            for (NSString* ip in addresses) {
                [pf addRuleWithIP: ip port: entry.port maskLen: entry.maskLen];
            }
        }
	}
}

- (void)enqueuePFRuleForEntry:(SCBlockEntry*)entry {
	NSBlockOperation* op = [NSBlockOperation blockOperationWithBlock:^{
		[self addPFRuleForEntry: entry];
	}];
	[pfQueue addOperation: op];
}

- (void)addBlockEntryFromString:(NSString*)entryString {
    SCBlockEntry* entry = [SCBlockEntry entryFromString: entryString];

    // nil means that we don't have anything valid to block in this entry
    if (entry == nil) return;

    // enqueue new entries _before_ running this one, so they can happen in parallel
    NSArray<SCBlockEntry*>* relatedEntries = [self relatedBlockEntriesForEntry: entry];
    for (SCBlockEntry* relatedEntry in relatedEntries) {
        [self enqueueBlockEntry: relatedEntry];
    }

    [self addBlockEntry: entry];
}

- (void)addBlockEntriesFromStrings:(NSArray<NSString*>*)blockList {
	for(NSUInteger i = 0; i < [blockList count]; i++) {
		NSBlockOperation* op = [NSBlockOperation blockOperationWithBlock:^{
			[self addBlockEntryFromString: blockList[i]];
		}];
		[opQueue addOperation: op];
	}
}

- (BOOL)resetHostsToDefault {
	[pf stopBlock: true];
	BOOL hostSuccess = [hostBlockerSet writeDefaultHostsFile];
	[SCHelperToolUtilities clearOSDNSCache];
	return hostSuccess;
}

- (BOOL)clearBlock {
	[pf stopBlock: false];
	BOOL pfSuccess = ![pf containsSelfControlBlock];

	[hostBlockerSet removeSelfControlBlock];
	BOOL hostSuccess = [hostBlockerSet writeNewFileContents];
	// Revert the host file blocker's file contents to disk so we can check
	// whether or not it still contains the block (aka we messed up).
	[hostBlockerSet revertFileContentsToDisk];
	hostSuccess = hostSuccess && ![hostBlockerSet containsSelfControlBlock];

	BOOL clearedSuccessfully = hostSuccess && pfSuccess;

	if(clearedSuccessfully)
		NSLog(@"INFO: Block successfully cleared.");
	else {
		if (!pfSuccess) {
			NSLog(@"WARNING: Error clearing pf block. Tring to clear using force.");
			[pf stopBlock: true];
		}
		if (!hostSuccess) {
			NSLog(@"WARNING: Error removing hostfile block.  Attempting to restore host file backup.");
			[hostBlockerSet restoreBackupHostsFile];
		}

		clearedSuccessfully = ![self blockIsActive];

		if ([hostBlockerSet.defaultBlocker containsSelfControlBlock]) {
			NSLog(@"ERROR: Host file backup could not be restored.  This may result in a permanent block.");
		}
		if ([pf containsSelfControlBlock]) {
			NSLog(@"ERROR: Firewall rules could not be cleared.  This may result in a permanent block.");
		}
		if (clearedSuccessfully) {
			NSLog(@"INFO: Firewall rules successfully cleared.");
		}
	}

	[hostBlockerSet deleteBackupHostsFile];

	[SCHelperToolUtilities clearOSDNSCache];

	return clearedSuccessfully;
}

- (BOOL)forceClearBlock {
	[pf stopBlock: YES];
	BOOL pfSuccess = ![pf containsSelfControlBlock];

	[hostBlockerSet removeSelfControlBlock];
	BOOL hostSuccess = [hostBlockerSet writeNewFileContents];
	// Revert the host file blocker's file contents to disk so we can check
	// whether or not it still contains the block (aka we messed up).
	[hostBlockerSet revertFileContentsToDisk];
	hostSuccess = hostSuccess && ![hostBlockerSet containsSelfControlBlock];

	BOOL clearedSuccessfully = hostSuccess && pfSuccess;

	if(clearedSuccessfully)
		NSLog(@"INFO: Block successfully cleared.");
	else {
		if (!pfSuccess) {
			NSLog(@"ERROR: Error clearing pf block. This may result in a permanent block.");
		}
		if (!hostSuccess) {
			NSLog(@"WARNING: Error removing hostfile block.  Attempting to restore host file backup.");
			[hostBlockerSet restoreBackupHostsFile];
		}

		clearedSuccessfully = ![self blockIsActive];

		if ([hostBlockerSet.defaultBlocker containsSelfControlBlock]) {
			NSLog(@"ERROR: Host file backup could not be restored.  This may result in a permanent block.");
		}
		if (clearedSuccessfully) {
			NSLog(@"INFO: Firewall rules successfully cleared.");
		}
	}

	[SCHelperToolUtilities clearOSDNSCache];

	return clearedSuccessfully;
}

- (BOOL)blockIsActive {
	return [hostBlockerSet.defaultBlocker containsSelfControlBlock] || [pf containsSelfControlBlock];
}

// by Jakob Egger, taken from: https://eggerapps.at/blog/2014/hostname-lookups.html
+ (NSString*)stringForAddress:(NSData*)addressData error:(NSError**)outError {
    char hbuf[NI_MAXHOST];
    int gai_error = getnameinfo(addressData.bytes, (socklen_t)addressData.length, hbuf, NI_MAXHOST, NULL, 0, NI_NUMERICHOST);
    if (gai_error) {
        if (outError) *outError = [NSError errorWithDomain:@"MyDomain" code:gai_error userInfo:@{NSLocalizedDescriptionKey:@(gai_strerror(gai_error))}];
        return nil;
    }
    return [NSString stringWithUTF8String:hbuf];
}
// hard cap per DNS lookup so a hung resolve can't wedge the queue (75K no-timeout lookups froze the daemon)
static const CFTimeInterval kDNSResolveTimeout = 2.0;

+ (NSArray*)ipAddressesForDomainName:(NSString*)domainName {
    if(domainName == nil) return @[];

	NSDate* startedResolving = [NSDate date];
    // dedicated thread + timed semaphore: a worker-queue run loop won't service the CFHost source (deadlocks)
    __block NSArray<NSData*>* addresses = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSThread* resolver = [[NSThread alloc] initWithBlock:^{
        CFHostRef host = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)domainName);
        CFStreamError err;
        CFHostScheduleWithRunLoop(host, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        if (CFHostStartInfoResolution(host, kCFHostAddresses, &err)) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, kDNSResolveTimeout, false);
            Boolean ok = false;
            NSArray* result = (__bridge NSArray*)CFHostGetAddressing(host, &ok);
            if (ok && result) addresses = [result copy];
        }
        CFHostUnscheduleFromRunLoop(host, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        CFRelease(host);
        dispatch_semaphore_signal(done);
    }];
    [resolver start];

    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)((kDNSResolveTimeout + 0.5) * NSEC_PER_SEC))) != 0 || addresses == nil) {
        NSLog(@"BlockManager: DNS resolve timed out/failed for %@ (%.1fs cap) — skipping pf, hosts still blocks it", domainName, kDNSResolveTimeout);
        return @[];
    }

    NSMutableArray* stringAddresses = [NSMutableArray array];
    if (addresses != NULL) {
        for (NSData* addrData in addresses) {
            NSError* parseErr;
            NSString* ipStr = [BlockManager stringForAddress: addrData error: &parseErr];
            if (ipStr) {
                [stringAddresses addObject: ipStr];
            } else {
                NSLog(@"BlockManager: Warning: Failed to parse IP struct for domain %@ with error %@", domainName, parseErr);
            }
        }
    } else {
        NSLog(@"BlockManager: Warning: failed to resolve addresses for %@", domainName);
    }

	// log slow resolutions
	NSDate* finishedResolving  = [NSDate date];
	NSTimeInterval resolutionTime = [finishedResolving timeIntervalSinceDate: startedResolving];
	if (resolutionTime > 2.5) {
		NSLog(@"BlockManager: Warning: took %f seconds to resolve %@", resolutionTime, domainName);
	}

	return stringAddresses;
}

+ (NSPredicate*)googleTesterPredicate {
    static NSPredicate* pred = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* googleRegex = @"^([a-z0-9]+\\.)*(google|youtube|picasa|sketchup|blogger|blogspot)\\.([a-z]{1,3})(\\.[a-z]{1,3})?$";
        pred = [NSPredicate
                 predicateWithFormat: @"SELF MATCHES %@",
                 googleRegex
                 ];
    });
    
    return pred;
}
- (BOOL)domainIsGoogle:(NSString*)domainName {
	return [[BlockManager googleTesterPredicate] evaluateWithObject: domainName];
}

- (NSArray<SCBlockEntry*>*)relatedBlockEntriesForEntry:(SCBlockEntry*)entry {
    // nil means that we don't have anything valid to block in this entry, therefore no related entries either
    if (entry == nil) return @[];
    
    NSMutableArray<SCBlockEntry*>* relatedEntries = [NSMutableArray array];

    if (isAllowlist && includeLinkedDomains && ![entry.hostname isValidIPAddress]) {
        NSDate* startedScraping  = [NSDate date];
        NSArray<SCBlockEntry*>* scrapedEntries = [[AllowlistScraper relatedBlockEntries: entry.hostname] allObjects];
        NSDate* finishedScraping  = [NSDate date];
        NSTimeInterval resolutionTime = [finishedScraping timeIntervalSinceDate: startedScraping];
        if (resolutionTime > 5.0) {
            NSLog(@"BlockManager: Warning: allowlist scraper took %f seconds on %@", resolutionTime, entry.hostname);
        }
        [relatedEntries addObjectsFromArray: scrapedEntries];
    }

    // expansion (www pairing, CDN) happens in Swift before entries reach the engine
    return relatedEntries;
}

- (void)addGoogleIPsToPF {
    [pf addRuleWithIP: @"8.8.4.0" port: 0 maskLen: 24];
    [pf addRuleWithIP: @"8.34.208.0" port: 0 maskLen: 20];
    [pf addRuleWithIP: @"8.35.192.0" port: 0 maskLen: 20];
    [pf addRuleWithIP: @"23.236.48.0" port: 0 maskLen: 240];
    [pf addRuleWithIP: @"23.251.128.0" port: 0 maskLen: 19];
    [pf addRuleWithIP: @"34.64.0.0" port: 0 maskLen: 10];
    [pf addRuleWithIP: @"8.8.4.0" port: 0 maskLen: 24];
    [pf addRuleWithIP: @"8.8.4.0" port: 0 maskLen: 24];
    [pf addRuleWithIP: @"8.8.4.0" port: 0 maskLen: 24];
    [pf addRuleWithIP: @"8.8.4.0" port: 0 maskLen: 24];
    [pf addRuleWithIP: @"8.8.4.0" port: 0 maskLen: 24];
    [pf addRuleWithIP: @"34.128.0.0" port: 0 maskLen: 10];
    [pf addRuleWithIP: @"35.184.0.0" port: 0 maskLen: 13];
    [pf addRuleWithIP: @"35.192.0.0" port: 0 maskLen: 14];
    [pf addRuleWithIP: @"35.196.0.0" port: 0 maskLen: 15];
    [pf addRuleWithIP: @"35.198.0.0" port: 0 maskLen: 16];
    [pf addRuleWithIP: @"35.199.0.0" port: 0 maskLen: 17];
    [pf addRuleWithIP: @"35.199.128.0" port: 0 maskLen: 18];
    [pf addRuleWithIP: @"35.200.0.0" port: 0 maskLen: 13];
    [pf addRuleWithIP: @"35.208.0.0" port: 0 maskLen: 12];
    [pf addRuleWithIP: @"35.224.0.0" port: 0 maskLen: 12];
    [pf addRuleWithIP: @"35.240.0.0" port: 0 maskLen: 13];
    [pf addRuleWithIP: @"64.15.112.0" port: 0 maskLen: 20];
    [pf addRuleWithIP: @"64.233.160.0" port: 0 maskLen: 19];
    [pf addRuleWithIP: @"66.102.0.0" port: 0 maskLen: 20];
    [pf addRuleWithIP: @"66.249.64.0" port: 0 maskLen: 19];
    [pf addRuleWithIP: @"70.32.128.0" port: 0 maskLen: 19];
    [pf addRuleWithIP: @"72.14.192.0" port: 0 maskLen: 18];
    [pf addRuleWithIP: @"74.114.24.0" port: 0 maskLen: 21];
    [pf addRuleWithIP: @"74.125.0.0" port: 0 maskLen: 16];
    [pf addRuleWithIP: @"104.154.0.0" port: 0 maskLen: 16];
    [pf addRuleWithIP: @"104.196.0.0" port: 0 maskLen: 14];
    [pf addRuleWithIP: @"104.237.160.0" port: 0 maskLen: 19];
    [pf addRuleWithIP: @"107.167.160.0" port: 0 maskLen: 19];
    [pf addRuleWithIP: @"107.178.192.0" port: 0 maskLen: 18];
    [pf addRuleWithIP: @"108.59.80.0" port: 0 maskLen: 20];
    [pf addRuleWithIP: @"108.170.192.0" port: 0 maskLen: 18];
    [pf addRuleWithIP: @"108.177.0.0" port: 0 maskLen: 17];
    [pf addRuleWithIP: @"130.211.0.0" port: 0 maskLen: 16];
    [pf addRuleWithIP: @"136.112.0.0" port: 0 maskLen: 12];
    [pf addRuleWithIP: @"142.250.0.0" port: 0 maskLen: 15];
    [pf addRuleWithIP: @"146.148.0.0" port: 0 maskLen: 17];
    [pf addRuleWithIP: @"162.216.148.0" port: 0 maskLen: 22];
    [pf addRuleWithIP: @"162.222.176.0" port: 0 maskLen: 21];
    [pf addRuleWithIP: @"172.110.32.0" port: 0 maskLen: 21];
    [pf addRuleWithIP: @"172.217.0.0" port: 0 maskLen: 16];
    [pf addRuleWithIP: @"172.253.0.0" port: 0 maskLen: 16];
    [pf addRuleWithIP: @"173.194.0.0" port: 0 maskLen: 16];
    [pf addRuleWithIP: @"173.255.112.0" port: 0 maskLen: 20];
    [pf addRuleWithIP: @"192.158.28.0" port: 0 maskLen: 22];
    [pf addRuleWithIP: @"192.178.0.0" port: 0 maskLen: 15];
    [pf addRuleWithIP: @"193.186.4.0" port: 0 maskLen: 24];
    [pf addRuleWithIP: @"199.36.154.0" port: 0 maskLen: 23];
    [pf addRuleWithIP: @"199.36.156.0" port: 0 maskLen: 24];
    [pf addRuleWithIP: @"199.192.112.0" port: 0 maskLen: 22];
    [pf addRuleWithIP: @"199.223.232.0" port: 0 maskLen: 21];
    [pf addRuleWithIP: @"207.223.160.0" port: 0 maskLen: 20];
    [pf addRuleWithIP: @"208.65.152.0" port: 0 maskLen: 22];
    [pf addRuleWithIP: @"208.68.108.0" port: 0 maskLen: 22];
    [pf addRuleWithIP: @"208.81.188.0" port: 0 maskLen: 22];
    [pf addRuleWithIP: @"208.117.224.0" port: 0 maskLen: 19];
    [pf addRuleWithIP: @"209.85.128.0" port: 0 maskLen: 17];
    [pf addRuleWithIP: @"216.58.192.0" port: 0 maskLen: 19];
    [pf addRuleWithIP: @"216.73.80.0" port: 0 maskLen: 20];
    [pf addRuleWithIP: @"216.239.32.0" port: 0 maskLen: 19];
    [pf addRuleWithIP: @"2001:4860::" port: 0 maskLen: 32];
    [pf addRuleWithIP: @"2404:6800::" port: 0 maskLen: 32];
    [pf addRuleWithIP: @"2404:f340::" port: 0 maskLen: 32];
    [pf addRuleWithIP: @"2600:1900::" port: 0 maskLen: 28];
    [pf addRuleWithIP: @"2606:73c0::" port: 0 maskLen: 32];
    [pf addRuleWithIP: @"2607:f8b0::" port: 0 maskLen: 32];
    [pf addRuleWithIP: @"2620:11a:a000::" port: 0 maskLen: 40];
    [pf addRuleWithIP: @"2620:120:e000::" port: 0 maskLen: 40];
    [pf addRuleWithIP: @"2800:3f0::" port: 0 maskLen: 32];
    [pf addRuleWithIP: @"2a00:1450::" port: 0 maskLen: 32];
    [pf addRuleWithIP: @"2c0f:fb50::" port: 0 maskLen: 32];
}

@end
