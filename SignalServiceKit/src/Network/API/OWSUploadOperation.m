//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSUploadOperation.h"
#import "Cryptography.h"
#import "MIMETypeUtil.h"
#import "NSError+MessageSending.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSError.h"
#import "OWSOperation.h"
#import "OWSRequestFactory.h"
#import "TSAttachmentStream.h"
#import "TSNetworkManager.h"
#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kAttachmentUploadProgressNotification = @"kAttachmentUploadProgressNotification";
NSString *const kAttachmentUploadProgressKey = @"kAttachmentUploadProgressKey";
NSString *const kAttachmentUploadAttachmentIDKey = @"kAttachmentUploadAttachmentIDKey";

// Use a slightly non-zero value to ensure that the progress
// indicator shows up as quickly as possible.
static const CGFloat kAttachmentUploadProgressTheta = 0.001f;

@interface OWSUploadOperation ()

@property (readonly, nonatomic) NSString *attachmentId;
@property (readonly, nonatomic) YapDatabaseConnection *dbConnection;
@property (readonly, nonatomic) TSAttachmentStream *attachment;

@property NSString *location;

@end

@implementation OWSUploadOperation

- (instancetype)initWithAttachmentId:(NSString *)attachmentId
                        dbConnection:(YapDatabaseConnection *)dbConnection
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.remainingRetries = 4;
    _attachmentId = attachmentId;
    _dbConnection = dbConnection;
    _attachment = nil;

    return self;
}

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment
{
    self = [super init];
    if (!self) {
        return self;
    }
    
    self.remainingRetries = 4;
    _attachmentId = @"1234567890";
    _dbConnection = nil;
    _attachment = attachment;
    
    return self;
    
}

- (TSNetworkManager *)networkManager
{
    return [TSNetworkManager sharedManager];
}

- (void)uploadAvatarWithServerId:(UInt64)serverId
                  location:(NSString *)location
          avatarStream:(TSAttachmentStream *)avatarStream
{
    DDLogDebug(@"%@ started uploading data for avatar: %@", self.logTag, self.attachmentId);
    NSError *error;
    NSData *attachmentData = [avatarStream readDataFromFileWithError:&error];
    if (error) {
        DDLogError(@"%@ Failed to read avatar data with error: %@", self.logTag, error);
        error.isRetryable = YES;
        [self reportError:error];
        return;
    }
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:location]];
    request.HTTPMethod = @"PUT";
    
    // some oss servers require "Content-Type: Data" whoes value is MIME Type usually.
    // donot set this header maybe ok, so, just comment this.
    //[request setValue:OWSMimeTypeApplicationOctetStream forHTTPHeaderField:@"Content-Type"];
    
    AFURLSessionManager *manager = [[AFURLSessionManager alloc]
                                    initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    
    NSURLSessionUploadTask *uploadTask;
    uploadTask = [manager uploadTaskWithRequest:request
                                       fromData:attachmentData
                                       progress:^(NSProgress *_Nonnull uploadProgress) {
                                           [self fireNotificationWithProgress:uploadProgress.fractionCompleted];
                                       }
                              completionHandler:^(NSURLResponse *_Nonnull response, id _Nullable responseObject, NSError *_Nullable error) {
                                  OWSAssertIsOnMainThread();
                                  if (error) {
                                      error.isRetryable = YES;
                                      [self reportError:error];
                                      return;
                                  }
                                  
                                  NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
                                  BOOL isValidResponse = (statusCode >= 200) && (statusCode < 400);
                                  if (!isValidResponse) {
                                      DDLogError(@"%@ Unexpected server response: %d", self.logTag, (int)statusCode);
                                      NSError *invalidResponseError = OWSErrorMakeUnableToProcessServerResponseError();
                                      invalidResponseError.isRetryable = YES;
                                      [self reportError:invalidResponseError];
                                      return;
                                  }
                                  
                                  DDLogInfo(@"%@ Uploaded avatar: %p.", self.logTag, avatarStream.uniqueId);
                                  avatarStream.serverId = serverId;
                                  avatarStream.isUploaded = YES;
                                  [avatarStream saveAsyncWithCompletionBlock:^{
                                      [self reportSuccess];
                                  }];
                              }];
    
    [uploadTask resume];
}

- (void)syncrun
{
    __block TSAttachmentStream *attachmentStream;
    
    if(self.attachment){
        attachmentStream = self.attachment;
    }
    
    if (!attachmentStream) {
        OWSProdError([OWSAnalyticsEvents messageSenderErrorCouldNotLoadAttachment]);
        NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
        // Not finding local attachment is a terminal failure.
        error.isRetryable = NO;
        [self reportError:error];
        return;
    }
    
    if (attachmentStream.isUploaded) {
        DDLogDebug(@"%@ Attachment previously uploaded.", self.logTag);
        [self reportSuccess];
        return;
    }
    
    [self fireNotificationWithProgress:0];
    
    DDLogDebug(@"%@ alloc attachment: %@", self.logTag, self.attachmentId);
    
    // firstly, request the uploading url for the avatar from server.
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    TSRequest *request = [OWSRequestFactory profileAvatarUploadUrlRequest:nil];
    [self.networkManager makeRequest:request
         success:^(NSURLSessionDataTask *task, id responseObject) {
             if (![responseObject isKindOfClass:[NSDictionary class]]) {
                 dispatch_group_leave(group);
                 DDLogError(@"%@ unexpected response from server: %@", self.logTag, responseObject);
                 NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                 error.isRetryable = YES;
                 [self reportError:error];
                 return;
             }
             
             NSDictionary *responseDict = (NSDictionary *)responseObject;
             UInt64 serverId = ((NSDecimalNumber *)[responseDict objectForKey:@"id"]).unsignedLongLongValue;
             NSString *location = [responseDict objectForKey:@"location"];
             
             self.location = location;
             dispatch_group_leave(group);
             
             // just upload the avatar to the server.
             [self uploadAvatarWithServerId:serverId location:location avatarStream:attachmentStream];
         }
         failure:^(NSURLSessionDataTask *task, NSError *error) {
             dispatch_group_leave(group);
             DDLogError(@"%@ Failed to allocate attachment with error: %@", self.logTag, error);
             error.isRetryable = YES;
             [self reportError:error];
         }];
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    
    return;
}

- (void)run
{
    __block TSAttachmentStream *attachmentStream;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        attachmentStream = [TSAttachmentStream fetchObjectWithUniqueID:self.attachmentId transaction:transaction];
    }];
    
    if(self.attachment){
        attachmentStream = self.attachment;
    }

    if (!attachmentStream) {
        OWSProdError([OWSAnalyticsEvents messageSenderErrorCouldNotLoadAttachment]);
        NSError *error = OWSErrorMakeFailedToSendOutgoingMessageError();
        // Not finding local attachment is a terminal failure.
        error.isRetryable = NO;
        [self reportError:error];
        return;
    }

    if (attachmentStream.isUploaded) {
        DDLogDebug(@"%@ Attachment previously uploaded.", self.logTag);
        [self reportSuccess];
        return;
    }
    
    [self fireNotificationWithProgress:0];

    DDLogDebug(@"%@ alloc attachment: %@", self.logTag, self.attachmentId);
    TSRequest *request = [OWSRequestFactory allocAttachmentRequest];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            if (![responseObject isKindOfClass:[NSDictionary class]]) {
                DDLogError(@"%@ unexpected response from server: %@", self.logTag, responseObject);
                NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                error.isRetryable = YES;
                [self reportError:error];
                return;
            }

            NSDictionary *responseDict = (NSDictionary *)responseObject;
            UInt64 serverId = ((NSDecimalNumber *)[responseDict objectForKey:@"id"]).unsignedLongLongValue;
            NSString *location = [responseDict objectForKey:@"location"];
            
            self.location = location;

            dispatch_async([OWSDispatch attachmentsQueue], ^{
                [self uploadWithServerId:serverId location:location attachmentStream:attachmentStream];
            });
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            DDLogError(@"%@ Failed to allocate attachment with error: %@", self.logTag, error);
            error.isRetryable = YES;
            [self reportError:error];
        }];
}

- (void)uploadWithServerId:(UInt64)serverId
                  location:(NSString *)location
          attachmentStream:(TSAttachmentStream *)attachmentStream
{
    DDLogDebug(@"%@ started uploading data for attachment: %@", self.logTag, self.attachmentId);
    NSError *error;
    NSData *attachmentData = [attachmentStream readDataFromFileWithError:&error];
    if (error) {
        DDLogError(@"%@ Failed to read attachment data with error: %@", self.logTag, error);
        error.isRetryable = YES;
        [self reportError:error];
        return;
    }

    NSData *encryptionKey;
    NSData *digest;
    NSData *_Nullable encryptedAttachmentData =
        [Cryptography encryptAttachmentData:attachmentData outKey:&encryptionKey outDigest:&digest];
    if (!encryptedAttachmentData) {
        OWSProdLogAndFail(@"%@ could not encrypt attachment data.", self.logTag);
        error = OWSErrorMakeFailedToSendOutgoingMessageError();
        error.isRetryable = YES;
        [self reportError:error];
        return;
    }
    attachmentStream.encryptionKey = encryptionKey;
    attachmentStream.digest = digest;

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:location]];
    request.HTTPMethod = @"PUT";
    
    // some oss servers require "Content-Type: Data" whoes value is MIME Type usually.
    // maybe donot set this header is ok, so, just comment this.
    //[request setValue:OWSMimeTypeApplicationOctetStream forHTTPHeaderField:@"Content-Type"];

    AFURLSessionManager *manager = [[AFURLSessionManager alloc]
        initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

    NSURLSessionUploadTask *uploadTask;
    uploadTask = [manager uploadTaskWithRequest:request
        fromData:encryptedAttachmentData
        progress:^(NSProgress *_Nonnull uploadProgress) {
            [self fireNotificationWithProgress:uploadProgress.fractionCompleted];
        }
        completionHandler:^(NSURLResponse *_Nonnull response, id _Nullable responseObject, NSError *_Nullable error) {
            OWSAssertIsOnMainThread();
            if (error) {
                error.isRetryable = YES;
                [self reportError:error];
                return;
            }

            NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
            BOOL isValidResponse = (statusCode >= 200) && (statusCode < 400);
            if (!isValidResponse) {
                DDLogError(@"%@ Unexpected server response: %d", self.logTag, (int)statusCode);
                NSError *invalidResponseError = OWSErrorMakeUnableToProcessServerResponseError();
                invalidResponseError.isRetryable = YES;
                [self reportError:invalidResponseError];
                return;
            }

            DDLogInfo(@"%@ Uploaded attachment: %p.", self.logTag, attachmentStream.uniqueId);
            attachmentStream.serverId = serverId;
            attachmentStream.isUploaded = YES;
            [attachmentStream saveAsyncWithCompletionBlock:^{
                [self reportSuccess];
            }];
        }];

    [uploadTask resume];
}

- (void)fireNotificationWithProgress:(CGFloat)aProgress
{
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];

    CGFloat progress = MAX(kAttachmentUploadProgressTheta, aProgress);
    [notificationCenter postNotificationNameAsync:kAttachmentUploadProgressNotification
                                           object:nil
                                         userInfo:@{
                                             kAttachmentUploadProgressKey : @(progress),
                                             kAttachmentUploadAttachmentIDKey : self.attachmentId
                                         }];
}

@end

NS_ASSUME_NONNULL_END
