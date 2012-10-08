//
//  CLDeleteHiddenOperation.m
//  Syndication
//
//  Created by Calvin Lough on 7/2/11.
//  Copyright 2011 Calvin Lough. All rights reserved.
//

#import "CLConstants.h"
#import "CLDatabaseHelper.h"
#import "CLDeleteHiddenOperation.h"
#import "CLPost.h"
#import "CLSourceListFeed.h"
#import "FMDatabase.h"
#import "FMResultSet.h"

@implementation CLDeleteHiddenOperation

static NSInteger modulo;

@synthesize nonGoogleFeeds;
@synthesize googleFeeds;

+ (void)initialize {
	modulo = ((NSInteger)[[NSDate date] timeIntervalSince1970] % 10);
}

- (void)dealloc {
	[nonGoogleFeeds release];
	[googleFeeds release];
	
	[super dealloc];
}

- (void)main {
	
	@try {
		
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		// note: we only process 1/10 of the feeds each time (that is what the modulo static variable is for)
		
		FMDatabase *db = [FMDatabase databaseWithPath:[CLDatabaseHelper pathForDatabaseFile]];
		
		if (![db open]) {
			CLLog(@"failed to connect to database!");
			[self performSelectorOnMainThread:@selector(dispatchDidFinishDelegateMessage) withObject:nil waitUntilDone:YES];
			[pool drain];
			return;
		}
		
		[db beginTransaction];
		
		NSInteger i = 0;
		
		for (CLSourceListFeed *feed in googleFeeds) {
			if ((i % 10) == modulo) {
				[db executeUpdate:@"DELETE FROM enclosure WHERE PostId IN (SELECT Id FROM post WHERE FeedId=? AND IsHidden=1)", [NSNumber numberWithInteger:[feed dbId]]];
				[db executeUpdate:@"DELETE FROM post WHERE FeedId=? AND IsHidden=1", [NSNumber numberWithInteger:[feed dbId]]];
			}
			
			i++;
		}
		
		// just to be safe, we only delete hidden posts older than 6 months
		NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
		NSInteger olderThan = timestamp - (TIME_INTERVAL_MONTH * 6);
		
		for (CLSourceListFeed *feed in nonGoogleFeeds) {
			if ((i % 10) == modulo) {
				if ([feed lastSyncPosts] == nil || [[feed lastSyncPosts] count] == 0) {
					continue;
				}
				
				NSMutableArray *hiddenPosts = [NSMutableArray array];
				
				FMResultSet *rs = [db executeQuery:@"SELECT post.*, feed.Title AS FeedTitle, feed.Url AS FeedUrlString FROM post, feed WHERE post.FeedId=feed.Id AND feed.Id=? AND post.IsHidden=1 AND post.Received < ?", [NSNumber numberWithInteger:[feed dbId]], [NSNumber numberWithInteger:olderThan]];
				
				while ([rs next]) {
					CLPost *post = [[CLPost alloc] initWithResultSet:rs];
					[hiddenPosts addObject:post];
					[post release];
				}
				
				[rs close];
				
				NSMutableArray *hiddenPostsStillInFeed = [NSMutableArray array];
				
				for (NSMutableDictionary *lastSyncPost in [feed lastSyncPosts]) {
					
					NSString *lastSyncPostGuid = [lastSyncPost objectForKey:@"guid"];
					NSString *lastSyncPostTitle = [lastSyncPost objectForKey:@"title"];
					NSString *lastSyncPostPlainTextContent = [lastSyncPost objectForKey:@"plainTextContent"];
					
					for (CLPost *hiddenPost in hiddenPosts) {
						
						NSString *hiddenPostGuid = [hiddenPost guid];
						NSString *hiddenPostTitle = [hiddenPost title];
						NSString *hiddenPostPlainTextContent = [hiddenPost plainTextContent];
						
						BOOL guidsBothNil = (lastSyncPostGuid == nil && hiddenPostGuid == nil);
						BOOL titlesNonNilAndEqual = (lastSyncPostTitle != nil && hiddenPostTitle != nil && [lastSyncPostTitle isEqual:hiddenPostTitle]);
						BOOL plainTextContentNonNilAndEqual = (lastSyncPostPlainTextContent != nil && hiddenPostPlainTextContent != nil && [lastSyncPostPlainTextContent isEqual:hiddenPostPlainTextContent]);
						BOOL guidsNonNilAndEqual = (lastSyncPostGuid != nil && hiddenPostGuid != nil && [lastSyncPostGuid isEqual:hiddenPostGuid]);
						
						if (((titlesNonNilAndEqual || plainTextContentNonNilAndEqual) && guidsBothNil) || guidsNonNilAndEqual) {
							[hiddenPostsStillInFeed addObject:hiddenPost];
							break;
						}
					}
				}
				
				for (CLPost *stillInFeed in hiddenPostsStillInFeed) {
					[hiddenPosts removeObject:stillInFeed];
				}
				
				if ([hiddenPosts count] > 0) {
					
					for (CLPost *hiddenPost in hiddenPosts) {
						if ([hiddenPost dbId] > 0) {
							CLLog(@"deleting hidden post with dbid = %qi", [hiddenPost dbId]);
							
							[db executeUpdate:@"DELETE FROM enclosure WHERE PostId=?", [NSNumber numberWithInteger:[hiddenPost dbId]]];
							[db executeUpdate:@"DELETE FROM post WHERE Id=?", [NSNumber numberWithInteger:[hiddenPost dbId]]];
						}
					}
				}
			}
			
			i++;
		}
		
		[db commit];
		
		[db close];
		
		modulo = ((modulo + 1) % 10);
		
		[self performSelectorOnMainThread:@selector(dispatchDidFinishDelegateMessage) withObject:nil waitUntilDone:YES];
		
		[pool drain];
		
	} @catch(...) {
		// Do not rethrow exceptions.
	}
}

@end