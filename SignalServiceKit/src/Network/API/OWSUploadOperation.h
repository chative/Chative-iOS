//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOperation.h"

NS_ASSUME_NONNULL_BEGIN

@class TSOutgoingMessage;
@class YapDatabaseConnection;
@class TSAttachmentStream;

extern NSString *const kAttachmentUploadProgressNotification;
extern NSString *const kAttachmentUploadProgressKey;
extern NSString *const kAttachmentUploadAttachmentIDKey;

@interface OWSUploadOperation : OWSOperation

@property (nullable, readonly) NSError *lastError;
@property (readonly) NSString *location;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAttachmentId:(NSString *)attachmentId
                        dbConnection:(YapDatabaseConnection *)dbConnection NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment;

- (void)syncrun;

@end

NS_ASSUME_NONNULL_END
