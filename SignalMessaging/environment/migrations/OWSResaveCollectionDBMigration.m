//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSResaveCollectionDBMigration.h"
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseTransaction.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSResaveCollectionDBMigration

- (void)resaveDBCollection:(NSString *)collection
                    filter:(nullable DBRecordFilterBlock)filter
              dbConnection:(YapDatabaseConnection *)dbConnection
                completion:(OWSDatabaseMigrationCompletion)completion
{
    OWSAssert(collection.length > 0);
    OWSAssert(dbConnection);
    OWSAssert(completion);

    NSMutableArray<NSString *> *recordIds = [NSMutableArray new];
    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [recordIds addObjectsFromArray:[transaction allKeysInCollection:collection]];
        DDLogInfo(@"%@ Migrating %zd records from: %@.", self.logTag, recordIds.count, collection);
    }
        completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
        completionBlock:^{
            [self resaveBatch:recordIds
                   collection:collection
                       filter:filter
                 dbConnection:dbConnection
                   completion:completion];
        }];
}

- (void)resaveBatch:(NSMutableArray<NSString *> *)recordIds
         collection:(NSString *)collection
             filter:(nullable DBRecordFilterBlock)filter
       dbConnection:(YapDatabaseConnection *)dbConnection
         completion:(OWSDatabaseMigrationCompletion)completion
{
    OWSAssert(recordIds);
    OWSAssert(collection.length > 0);
    OWSAssert(dbConnection);
    OWSAssert(completion);

    DDLogVerbose(@"%@ %s: %zd", self.logTag, __PRETTY_FUNCTION__, recordIds.count);

    if (recordIds.count < 1) {
        completion();
        return;
    }

    [dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        const int kBatchSize = 1000;
        for (int i = 0; i < kBatchSize && recordIds.count > 0; i++) {
            NSString *messageId = [recordIds lastObject];
            [recordIds removeLastObject];
            id record = [transaction objectForKey:messageId inCollection:collection];
            if (filter && !filter(record)) {
                continue;
            }
            TSYapDatabaseObject *entity = (TSYapDatabaseObject *)record;
            [entity saveWithTransaction:transaction];
        }
    }
        completionBlock:^{
            // Process the next batch.
            [self resaveBatch:recordIds
                   collection:collection
                       filter:filter
                 dbConnection:dbConnection
                   completion:completion];
        }];
}

@end

NS_ASSUME_NONNULL_END
