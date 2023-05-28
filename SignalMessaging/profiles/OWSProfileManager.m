//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSProfileManager.h"
#import "Environment.h"
#import "NSString+OWS.h"
#import "OWSUserProfile.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/Cryptography.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/NSData+Image.h>
#import <SignalServiceKit/NSData+hexString.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/NSNotificationCenter+OWS.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/OWSProfileKeyMessage.h>
#import <SignalServiceKit/OWSRequestBuilder.h>
#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/SecurityUtils.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSThread.h>
#import <SignalServiceKit/TSYapDatabaseObject.h>
#import <SignalServiceKit/TextSecureKitEnv.h>
#import <SignalServiceKit/UIImage+OWS.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kNSNotificationName_ProfileWhitelistDidChange = @"kNSNotificationName_ProfileWhitelistDidChange";

NSString *const kOWSProfileManager_UserWhitelistCollection = @"kOWSProfileManager_UserWhitelistCollection";
NSString *const kOWSProfileManager_GroupWhitelistCollection = @"kOWSProfileManager_GroupWhitelistCollection";

// The max bytes for a user's profile name, encoded in UTF8.
// Before encrypting and submitting we NULL pad the name data to this length.
const NSUInteger kOWSProfileManager_NameDataLength = 26;
const NSUInteger kOWSProfileManager_MaxAvatarDiameter = 640;

@interface OWSProfileManager ()

@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OWSIdentityManager *identityManager;

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) OWSUserProfile *localUserProfile;

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) NSCache<NSString *, UIImage *> *profileAvatarImageCache;

// This property can be accessed on any thread, while synchronized on self.
@property (atomic, readonly) NSMutableSet<NSString *> *currentAvatarDownloads;

@end

#pragma mark -

// Access to most state should happen while synchronized on the profile manager.
// Writes should happen off the main thread, wherever possible.
@implementation OWSProfileManager

@synthesize localUserProfile = _localUserProfile;

+ (instancetype)sharedManager
{
    static OWSProfileManager *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];
    OWSMessageSender *messageSender = [Environment current].messageSender;
    TSNetworkManager *networkManager = [Environment current].networkManager;

    return [self initWithPrimaryStorage:primaryStorage messageSender:messageSender networkManager:networkManager];
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
                         messageSender:(OWSMessageSender *)messageSender
                        networkManager:(TSNetworkManager *)networkManager
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSAssertIsOnMainThread();
    OWSAssert(primaryStorage);
    OWSAssert(messageSender);
    OWSAssert(messageSender);

    _messageSender = messageSender;
    _dbConnection = primaryStorage.newDatabaseConnection;
    _networkManager = networkManager;

    _profileAvatarImageCache = [NSCache new];
    _currentAvatarDownloads = [NSMutableSet new];

    OWSSingletonAssert();

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (AFHTTPSessionManager *)avatarHTTPManager
{
    return [OWSSignalService sharedInstance].CDNSessionManager;
}

- (OWSIdentityManager *)identityManager
{
    return [OWSIdentityManager sharedManager];
}

#pragma mark - User Profile Accessor

- (void)ensureLocalProfileCached
{
    // Since localUserProfile can create a transaction, we want to make sure it's not called for the first
    // time unexpectedly (e.g. in a nested transaction.)
    __unused OWSUserProfile *profile = [self localUserProfile];
}

#pragma mark - Local Profile

- (OWSUserProfile *)localUserProfile
{
    @synchronized(self)
    {
        if (!_localUserProfile) {
            _localUserProfile = [OWSUserProfile getOrBuildUserProfileForRecipientId:kLocalProfileUniqueId
                                                                       dbConnection:self.dbConnection];
        }
    }

    OWSAssert(_localUserProfile.profileKey);

    return _localUserProfile;
}

- (BOOL)localProfileExists
{
    return [OWSUserProfile localUserProfileExists:self.dbConnection];
}

- (OWSAES256Key *)localProfileKey
{
    OWSAssert(self.localUserProfile.profileKey.keyData.length == kAES256_KeyByteLength);

    return self.localUserProfile.profileKey;
}

- (BOOL)hasLocalProfile
{
    return (self.localProfileName.length > 0 || self.localProfileAvatarImage != nil);
}

- (nullable NSString *)localProfileName
{
    return self.localUserProfile.profileName;
}

- (nullable UIImage *)localProfileAvatarImage
{
    return [self loadProfileAvatarWithFilename:self.localUserProfile.avatarFileName];
}

- (void)updateLocalProfileName:(nullable NSString *)profileName
                   avatarImage:(nullable UIImage *)avatarImage
                       success:(void (^)(void))successBlockParameter
                       failure:(void (^)(void))failureBlockParameter
{
    OWSAssert(successBlockParameter);
    OWSAssert(failureBlockParameter);

    // Ensure that the success and failure blocks are called on the main thread.
    void (^failureBlock)(void) = ^{
        DDLogError(@"%@ Updating service with profile failed.", self.logTag);

        dispatch_async(dispatch_get_main_queue(), ^{
            failureBlockParameter();
        });
    };
    void (^successBlock)(void) = ^{
        DDLogInfo(@"%@ Successfully updated service with profile.", self.logTag);

        dispatch_async(dispatch_get_main_queue(), ^{
            successBlockParameter();
        });
    };

    // The final steps are to:
    //
    // * Try to update the service.
    // * Update client state on success.
    void (^tryToUpdateService)(NSString *_Nullable, NSString *_Nullable) = ^(
        NSString *_Nullable avatarUrlPath, NSString *_Nullable avatarFileName) {
        [self updateServiceWithProfileName:profileName
            success:^{
                OWSUserProfile *userProfile = self.localUserProfile;
                OWSAssert(userProfile);
                NSURL *url = [NSURL URLWithString:avatarUrlPath];
                NSString* avatarId = url.path.lastPathComponent;
                
                DDLogInfo(@"tryToUpdateService profileName:%@ avatarId:%@ avatarFileName:%@",
                          profileName, avatarId, avatarFileName);
                
                [userProfile updateWithProfileName:profileName
                                     avatarUrlPath:avatarId
                                    avatarFileName:avatarFileName
                                      dbConnection:self.dbConnection
                                        completion:^{
                                            if (avatarFileName) {
                                                [self updateProfileAvatarCache:avatarImage filename:avatarFileName];
                                            }

                                            successBlock();
                                        }];
            }
            failure:^{
                failureBlock();
            }];
    };

    OWSUserProfile *userProfile = self.localUserProfile;
    OWSAssert(userProfile);

    if (avatarImage) {
        // modified: new avatar image
        // write it to disk, encrypt it, upload it to oss server
        // send the avatar info including oss storage url to server.
        if (self.localProfileAvatarImage != avatarImage) {
            DDLogVerbose(@"%@ Updating local profile on service with new avatar.", self.logTag);
            [self writeAvatarToDisk:avatarImage
                success:^(NSData *data, NSString *fileName) {
                    [self uploadAvatarToService:fileName
                         avatarData:data
                            success:^(NSString *_Nullable avatarUrlPath) {
                                tryToUpdateService(avatarUrlPath, fileName);
                            }
                            failure:^{
                                failureBlock();
                            }];
                }
                failure:^{
                    failureBlock();
                }];
        } else {
            // If the avatar hasn't changed, reuse the existing metadata.
            
            OWSAssert(userProfile.avatarUrlPath.length > 0);
            OWSAssert(userProfile.avatarFileName.length > 0);
            
            DDLogVerbose(@"%@ Updating local profile on service with unchanged avatar.", self.logTag);
            tryToUpdateService(userProfile.avatarUrlPath, userProfile.avatarFileName);
        }
    }
// modified: misunderstanding this one ?????
//        else if (userProfile.avatarUrlPath) {
//        DDLogVerbose(@"%@ Updating local profile on service with cleared avatar.", self.logTag);
//        [self uploadAvatarToService:nil
//            avatarData:nil
//            success:^(NSString *_Nullable avatarUrlPath) {
//                tryToUpdateService(nil, nil);
//            }
//            failure:^{
//                failureBlock();
//            }];
//    }
    else {
        DDLogVerbose(@"%@ Updating local profile on service with no avatar.", self.logTag);
        tryToUpdateService(nil, nil);
    }
}

- (void)writeAvatarToDisk:(UIImage *)avatar
                  success:(void (^)(NSData *data, NSString *fileName))successBlock
                  failure:(void (^)(void))failureBlock
{
    OWSAssert(avatar);
    OWSAssert(successBlock);
    OWSAssert(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (avatar) {
            NSData *data = [self processedImageDataForRawAvatar:avatar];
            OWSAssert(data);
            if (data) {
                NSString *fileName = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"jpg"];
                NSString *filePath = [self.profileAvatarsDirPath stringByAppendingPathComponent:fileName];
                BOOL success = [data writeToFile:filePath atomically:YES];
                OWSAssert(success);
                if (success) {
                    successBlock(data, fileName);
                    return;
                }
            }
        }
        failureBlock();
    });
}

- (NSData *)processedImageDataForRawAvatar:(UIImage *)image
{
    NSUInteger kMaxAvatarBytes = 5 * 1000 * 1000;

    if (image.size.width != kOWSProfileManager_MaxAvatarDiameter
        || image.size.height != kOWSProfileManager_MaxAvatarDiameter) {
        // To help ensure the user is being shown the same cropping of their avatar as
        // everyone else will see, we want to be sure that the image was resized before this point.
        OWSFail(@"Avatar image should have been resized before trying to upload");
        image = [image resizedImageToFillPixelSize:CGSizeMake(kOWSProfileManager_MaxAvatarDiameter,
                                                       kOWSProfileManager_MaxAvatarDiameter)];
    }

    NSData *_Nullable data = UIImageJPEGRepresentation(image, 0.95f);
    if (data.length > kMaxAvatarBytes) {
        // Our avatar dimensions are so small that it's incredibly unlikely we wouldn't be able to fit our profile
        // photo. e.g. generating pure noise at our resolution compresses to ~200k.
        OWSFail(@"Suprised to find profile avatar was too large. Was it scaled properly? image: %@", image);
    }

    return data;
}

// modified: upload the avatar image to oss server as a attachment
//      what is different is avatar in oss using differet bucket name.
- (void)uploadAvatarToService:(NSString *_Nullable)avatarFileName
                             avatarData:(NSData *_Nullable)avatarData
                      success:(void (^)(NSString *_Nullable avatarUrlPath))successBlock
                      failure:(void (^)(void))failureBlock
{
    OWSAssert(successBlock);
    OWSAssert(failureBlock);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        // 1 encrypt avatar data
        NSData *encryptedAvatarData = [self encryptProfileData:avatarData];
        
        // 2 request upload url from server, and then upload it.
        TSAttachmentStream *attachmentStream =
        [[TSAttachmentStream alloc] initWithContentType:OWSMimeTypeImageJpeg
                                              byteCount:(UInt32)encryptedAvatarData.length
                                         sourceFilename:avatarFileName];
        
        DataSource *_Nullable dataSource = [DataSourceValue dataSourceWithData:encryptedAvatarData fileExtension:@"jpg"];

        if (![attachmentStream writeDataSource:dataSource]) {
            OWSProdError([OWSAnalyticsEvents messageSenderErrorCouldNotWriteAttachment]);
            failureBlock();
        }
        
        //[attachmentStream save];
        
        OWSUploadOperation *uploadAttachmentOperation =
            [[OWSUploadOperation alloc] initWithAttachment:attachmentStream];
        
        [uploadAttachmentOperation syncrun];
        
        successBlock(uploadAttachmentOperation.location);
    });

    return;
}


- (void)updateServiceWithProfileName:(nullable NSString *)localProfileName
                             success:(void (^)(void))successBlock
                             failure:(void (^)(void))failureBlock
{
    OWSAssert(successBlock);
    OWSAssert(failureBlock);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *_Nullable encryptedPaddedName = [self encryptProfileNameWithUnpaddedName:localProfileName];

        TSRequest *request = [OWSRequestBuilder profileNameSetRequestWithEncryptedPaddedName:encryptedPaddedName];
        [self.networkManager makeRequest:request
            success:^(NSURLSessionDataTask *task, id responseObject) {
                TSRequest* plainRequest = [OWSRequestBuilder profileNameSetRequestWithPlainText:localProfileName];
                [self.networkManager makeRequest:plainRequest
                    success:^(NSURLSessionDataTask *task, id responseObject) {
                        successBlock();
                    }
                    failure:^(NSURLSessionDataTask *task, NSError *error) {
                        DDLogError(@"%@ Failed to update profile with error: %@", self.logTag, error);
                        failureBlock();
                    }];
            }
            failure:^(NSURLSessionDataTask *task, NSError *error) {
                DDLogError(@"%@ Failed to update profile with error: %@", self.logTag, error);
                failureBlock();
            }];
    });
}

- (void)fetchLocalUsersProfile
{
    OWSAssertIsOnMainThread();

    NSString *_Nullable localNumber = [TSAccountManager sharedInstance].localNumber;
    if (!localNumber) {
        return;
    }
    [ProfileFetcherJob runWithRecipientId:localNumber networkManager:self.networkManager ignoreThrottling:YES];
}

#pragma mark - Profile Whitelist

- (void)clearProfileWhitelist
{
    DDLogWarn(@"%@ Clearing the profile whitelist.", self.logTag);

    [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction removeAllObjectsInCollection:kOWSProfileManager_UserWhitelistCollection];
        [transaction removeAllObjectsInCollection:kOWSProfileManager_GroupWhitelistCollection];
        OWSAssert(0 == [transaction numberOfKeysInCollection:kOWSProfileManager_UserWhitelistCollection]);
        OWSAssert(0 == [transaction numberOfKeysInCollection:kOWSProfileManager_GroupWhitelistCollection]);
    }];
}

- (void)logProfileWhitelist
{
    [self.dbConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
        DDLogError(@"kOWSProfileManager_UserWhitelistCollection: %zd",
            [transaction numberOfKeysInCollection:kOWSProfileManager_UserWhitelistCollection]);
        [transaction enumerateKeysInCollection:kOWSProfileManager_UserWhitelistCollection
                                    usingBlock:^(NSString *_Nonnull key, BOOL *_Nonnull stop) {
                                        DDLogError(@"\t profile whitelist user: %@", key);
                                    }];
        DDLogError(@"kOWSProfileManager_GroupWhitelistCollection: %zd",
            [transaction numberOfKeysInCollection:kOWSProfileManager_GroupWhitelistCollection]);
        [transaction enumerateKeysInCollection:kOWSProfileManager_GroupWhitelistCollection
                                    usingBlock:^(NSString *_Nonnull key, BOOL *_Nonnull stop) {
                                        DDLogError(@"\t profile whitelist group: %@", key);
                                    }];
    }];
}

- (void)regenerateLocalProfile
{
    OWSUserProfile *userProfile = self.localUserProfile;
    [userProfile clearWithProfileKey:[OWSAES256Key generateRandomKey] dbConnection:self.dbConnection completion:nil];
}

- (void)addUserToProfileWhitelist:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    [self addUsersToProfileWhitelist:@[ recipientId ]];
}

- (void)addUsersToProfileWhitelist:(NSArray<NSString *> *)recipientIds
{
    OWSAssert(recipientIds);

    NSMutableSet<NSString *> *newRecipientIds = [NSMutableSet new];
    [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        for (NSString *recipientId in recipientIds) {
            NSNumber *_Nullable oldValue =
                [transaction objectForKey:recipientId inCollection:kOWSProfileManager_UserWhitelistCollection];
            if (oldValue && oldValue.boolValue) {
                continue;
            }
            [transaction setObject:@(YES) forKey:recipientId inCollection:kOWSProfileManager_UserWhitelistCollection];
            [newRecipientIds addObject:recipientId];
        }
    }
        completionBlock:^{
            for (NSString *recipientId in newRecipientIds) {
                [[NSNotificationCenter defaultCenter]
                    postNotificationNameAsync:kNSNotificationName_ProfileWhitelistDidChange
                                       object:nil
                                     userInfo:@{
                                         kNSNotificationKey_ProfileRecipientId : recipientId,
                                     }];
            }
        }];
}

- (BOOL)isUserInProfileWhitelist:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    __block BOOL result = NO;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        NSNumber *_Nullable oldValue =
            [transaction objectForKey:recipientId inCollection:kOWSProfileManager_UserWhitelistCollection];
        result = (oldValue && oldValue.boolValue);
    }];
    return result;
}

- (void)addGroupIdToProfileWhitelist:(NSData *)groupId
{
    OWSAssert(groupId.length > 0);

    NSString *groupIdKey = [groupId hexadecimalString];

    __block BOOL didChange = NO;
    [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSNumber *_Nullable oldValue =
            [transaction objectForKey:groupIdKey inCollection:kOWSProfileManager_GroupWhitelistCollection];
        if (oldValue && oldValue.boolValue) {
            // Do nothing.
        } else {
            [transaction setObject:@(YES) forKey:groupIdKey inCollection:kOWSProfileManager_GroupWhitelistCollection];
            didChange = YES;
        }
    }
        completionBlock:^{
            if (didChange) {
                [[NSNotificationCenter defaultCenter]
                    postNotificationNameAsync:kNSNotificationName_ProfileWhitelistDidChange
                                       object:nil
                                     userInfo:@{
                                         kNSNotificationKey_ProfileGroupId : groupId,
                                     }];
            }
        }];
}

- (void)addThreadToProfileWhitelist:(TSThread *)thread
{
    OWSAssert(thread);

    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSData *groupId = groupThread.groupModel.groupId;
        [self addGroupIdToProfileWhitelist:groupId];

        // When we add a group to the profile whitelist, we might as well
        // also add all current members to the profile whitelist
        // individually as well just in case delivery of the profile key
        // fails.
        for (NSString *recipientId in groupThread.recipientIdentifiers) {
            [self addUserToProfileWhitelist:recipientId];
        }
    } else {
        NSString *recipientId = thread.contactIdentifier;
        [self addUserToProfileWhitelist:recipientId];
    }
}

- (BOOL)isGroupIdInProfileWhitelist:(NSData *)groupId
{
    OWSAssert(groupId.length > 0);

    NSString *groupIdKey = [groupId hexadecimalString];

    __block BOOL result = NO;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        NSNumber *_Nullable oldValue =
            [transaction objectForKey:groupIdKey inCollection:kOWSProfileManager_GroupWhitelistCollection];
        result = (oldValue && oldValue.boolValue);
    }];
    return result;
}

- (BOOL)isThreadInProfileWhitelist:(TSThread *)thread
{
    OWSAssert(thread);

    if (thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)thread;
        NSData *groupId = groupThread.groupModel.groupId;
        return [self isGroupIdInProfileWhitelist:groupId];
    } else {
        NSString *recipientId = thread.contactIdentifier;
        return [self isUserInProfileWhitelist:recipientId];
    }
}

- (void)setContactRecipientIds:(NSArray<NSString *> *)contactRecipientIds
{
    OWSAssert(contactRecipientIds);

    [self addUsersToProfileWhitelist:contactRecipientIds];
}

#pragma mark - Other User's Profiles

- (void)logUserProfiles
{
    [self.dbConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
        DDLogError(@"logUserProfiles: %zd", [transaction numberOfKeysInCollection:OWSUserProfile.collection]);
        [transaction
            enumerateKeysAndObjectsInCollection:OWSUserProfile.collection
                                     usingBlock:^(NSString *_Nonnull key, id _Nonnull object, BOOL *_Nonnull stop) {
                                         OWSAssert([object isKindOfClass:[OWSUserProfile class]]);
                                         OWSUserProfile *userProfile = object;
                                         DDLogError(@"\t [%@]: has profile key: %d, has avatar URL: %d, has "
                                                    @"avatar file: %d, name: %@",
                                             userProfile.recipientId,
                                             userProfile.profileKey != nil,
                                             userProfile.avatarUrlPath != nil,
                                             userProfile.avatarFileName != nil,
                                             userProfile.profileName);
                                     }];
    }];
}

- (void)setProfileKeyData:(NSData *)profileKeyData forRecipientId:(NSString *)recipientId
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OWSAES256Key *_Nullable profileKey = [OWSAES256Key keyWithData:profileKeyData];
        if (profileKey == nil) {
            OWSFail(@"Failed to make profile key for key data");
            return;
        }

        OWSUserProfile *userProfile =
            [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId dbConnection:self.dbConnection];

        OWSAssert(userProfile);
        if (userProfile.profileKey && [userProfile.profileKey.keyData isEqual:profileKey.keyData]) {
            // Ignore redundant update.
            return;
        }

        [userProfile clearWithProfileKey:profileKey
                            dbConnection:self.dbConnection
                              completion:^{
                                  dispatch_async(dispatch_get_main_queue(), ^(void) {
                                      [ProfileFetcherJob runWithRecipientId:recipientId
                                                             networkManager:self.networkManager
                                                           ignoreThrottling:YES];
                                  });
                              }];
    });
}

- (nullable NSData *)profileKeyDataForRecipientId:(NSString *)recipientId
{
    return [self profileKeyForRecipientId:recipientId].keyData;
}

- (nullable OWSAES256Key *)profileKeyForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    OWSUserProfile *userProfile =
        [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId dbConnection:self.dbConnection];
    OWSAssert(userProfile);

    return userProfile.profileKey;
}

- (nullable NSString *)profileNameForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    OWSUserProfile *userProfile =
        [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId dbConnection:self.dbConnection];

    return userProfile.profileName;
}

- (nullable UIImage *)profileAvatarForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    OWSUserProfile *userProfile =
        [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId dbConnection:self.dbConnection];

    if (userProfile.avatarFileName.length > 0) {
        return [self loadProfileAvatarWithFilename:userProfile.avatarFileName];
    }

    if (userProfile.avatarUrlPath.length > 0) {
        [self downloadAvatarForUserProfile:userProfile];
    }

    return nil;
}

- (nullable NSData *)profileAvatarDataForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    OWSUserProfile *userProfile =
        [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId dbConnection:self.dbConnection];

    if (userProfile.avatarFileName.length > 0) {
        return [self loadProfileDataWithFilename:userProfile.avatarFileName];
    }

    return nil;
}

- (void)downloadAvatarForUserProfile:(OWSUserProfile *)userProfile
{
    OWSAssert(userProfile);

    __block OWSBackgroundTask *backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (userProfile.avatarUrlPath.length < 1) {
            OWSFail(@"%@ Malformed avatar URL: %@", self.logTag, userProfile.avatarUrlPath);
            return;
        }
        NSString *_Nullable avatarUrlPathAtStart = userProfile.avatarUrlPath;

        if (userProfile.profileKey.keyData.length < 1 || userProfile.avatarUrlPath.length < 1) {
            return;
        }

        OWSAES256Key *profileKeyAtStart = userProfile.profileKey;

        NSString *fileName = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"jpg"];
        NSString *filePath = [self.profileAvatarsDirPath stringByAppendingPathComponent:fileName];

        @synchronized(self.currentAvatarDownloads)
        {
            if ([self.currentAvatarDownloads containsObject:userProfile.recipientId]) {
                // Download already in flight; ignore.
                return;
            }
            [self.currentAvatarDownloads addObject:userProfile.recipientId];
        }

        DDLogVerbose(@"%@ downloading profile avatar: %@", self.logTag, userProfile.uniqueId);

        NSString *tempDirectory = NSTemporaryDirectory();
        NSString *tempFilePath = [tempDirectory stringByAppendingPathComponent:fileName];

        void (^completionHandler)(NSURLResponse *_Nonnull, NSURL *_Nullable, NSError *_Nullable) = ^(
            NSURLResponse *_Nonnull response, NSURL *_Nullable filePathParam, NSError *_Nullable error) {
            // Ensure disk IO and decryption occurs off the main thread.
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // 3 decrypt avatar data
                NSData *_Nullable encryptedData = (error ? nil : [NSData dataWithContentsOfFile:tempFilePath]);
                NSData *_Nullable decryptedData = [self decryptProfileData:encryptedData profileKey:profileKeyAtStart];
                UIImage *_Nullable image = nil;
                if (decryptedData) {
                    BOOL success = [decryptedData writeToFile:filePath atomically:YES];
                    if (success) {
                        image = [UIImage imageWithContentsOfFile:filePath];
                    }
                }
                DDLogInfo(@"filePathParam %@ ", filePathParam);
                DDLogInfo(@"decryptedData %@-->%@", tempFilePath, filePath);

                @synchronized(self.currentAvatarDownloads)
                {
                    [self.currentAvatarDownloads removeObject:userProfile.recipientId];
                }

                OWSUserProfile *latestUserProfile =
                    [OWSUserProfile getOrBuildUserProfileForRecipientId:userProfile.recipientId
                                                           dbConnection:self.dbConnection];
                if (latestUserProfile.profileKey.keyData.length < 1
                    || ![latestUserProfile.profileKey isEqual:userProfile.profileKey]) {
                    DDLogWarn(@"%@ Ignoring avatar download for obsolete user profile.", self.logTag);
                } else if (![avatarUrlPathAtStart isEqualToString:latestUserProfile.avatarUrlPath]) {
                    DDLogInfo(@"%@ avatar url has changed during download", self.logTag);
                    if (latestUserProfile.avatarUrlPath.length > 0) {
                        [self downloadAvatarForUserProfile:latestUserProfile];
                    }
                } else if (error) {
                    DDLogError(@"%@ avatar download failed: %@", self.logTag, error);
                } else if (!encryptedData) {
                    DDLogError(@"%@ avatar encrypted data could not be read.", self.logTag);
                } else if (!decryptedData) {
                    DDLogError(@"%@ avatar data could not be decrypted.", self.logTag);
                } else if (!image) {
                    DDLogError(@"%@ avatar image could not be loaded: %@", self.logTag, error);
                } else {
                    [self updateProfileAvatarCache:image filename:fileName];

                    [latestUserProfile updateWithAvatarFileName:fileName dbConnection:self.dbConnection completion:nil];
                }

                // If we're updating the profile that corresponds to our local number,
                // update the local profile as well.
                NSString *_Nullable localNumber = [TSAccountManager sharedInstance].localNumber;
                if (localNumber && [localNumber isEqualToString:userProfile.recipientId]) {
                    OWSUserProfile *localUserProfile = self.localUserProfile;
                    OWSAssert(localUserProfile);
                    [localUserProfile updateWithAvatarFileName:fileName dbConnection:self.dbConnection completion:nil];
                    [self updateProfileAvatarCache:image filename:fileName];
                }

                OWSAssert(backgroundTask);
                backgroundTask = nil;
            });
        };

        // todo，从服务器上下载Avatar。
        // modified: download avatar
        //    1 retrive download url from signal server by avatarUrlPath which was generated when uploading.
        __block NSString* url = nil;
        dispatch_group_t group = dispatch_group_create();
        dispatch_group_enter(group);
        TSRequest *req = [OWSRequestFactory profileAvatarUploadUrlRequest:userProfile.avatarUrlPath];
        [self.networkManager makeRequest:req
             success:^(NSURLSessionDataTask *task, id responseObject) {
                 if (![responseObject isKindOfClass:[NSDictionary class]]) {
                     dispatch_group_leave(group);
                     DDLogError(@"%@ unexpected response from server: %@", self.logTag, responseObject);
                     NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                     error.isRetryable = YES;
                     return;
                 }
                 
                 NSDictionary *responseDict = (NSDictionary *)responseObject;
                 NSString* location = [responseDict objectForKey:@"location"];
                 url = [[NSString alloc]initWithString:location];
                 
                 dispatch_group_leave(group);
             }
             failure:^(NSURLSessionDataTask *task, NSError *error) {
                 dispatch_group_leave(group);
                 DDLogError(@"%@ Failed to allocate attachment with error: %@", self.logTag, error);
                 error.isRetryable = YES;
             }];
        
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        
        if (!url) {
            return;
        }
        
        // 2 download the avatar image
        NSURL *avatarUrlPath = [NSURL URLWithString:url];
        NSURLRequest *request = [NSURLRequest requestWithURL:avatarUrlPath];
        AFURLSessionManager *manager = [[AFURLSessionManager alloc]
            initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        NSURLSessionDownloadTask *downloadTask = [manager downloadTaskWithRequest:request
            progress:^(NSProgress *_Nonnull downloadProgress) {
                DDLogVerbose(
                    @"Downloading avatar for %@ %f", userProfile.recipientId, downloadProgress.fractionCompleted);
            }
            destination:^NSURL *_Nonnull(NSURL *_Nonnull targetPath, NSURLResponse *_Nonnull response) {
                return [NSURL fileURLWithPath:tempFilePath];
            }
            completionHandler:completionHandler];

        [downloadTask resume];
    });
}

- (void)updateProfileForRecipientId:(NSString *)recipientId
               profileNameEncrypted:(nullable NSData *)profileNameEncrypted
                      avatarUrlPath:(nullable NSString *)avatarUrlPath
{
    OWSAssert(recipientId.length > 0);

    DDLogDebug(@"%@ update profile for: %@ name: %@ avatar: %@",
        self.logTag,
        recipientId,
        profileNameEncrypted,
        avatarUrlPath);

    // Ensure decryption, etc. off main thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        OWSUserProfile *userProfile =
            [OWSUserProfile getOrBuildUserProfileForRecipientId:recipientId dbConnection:self.dbConnection];

        if (!userProfile.profileKey) {
            return;
        }

        NSString *_Nullable profileName =
            [self decryptProfileNameData:profileNameEncrypted profileKey:userProfile.profileKey];

        [userProfile updateWithProfileName:profileName
                             avatarUrlPath:avatarUrlPath
                              dbConnection:self.dbConnection
                                completion:nil];

        // If we're updating the profile that corresponds to our local number,
        // update the local profile as well.
        NSString *_Nullable localNumber = [TSAccountManager sharedInstance].localNumber;
        if (localNumber && [localNumber isEqualToString:recipientId]) {
            OWSUserProfile *localUserProfile = self.localUserProfile;
            OWSAssert(localUserProfile);

            [localUserProfile updateWithProfileName:profileName
                                      avatarUrlPath:avatarUrlPath
                                       dbConnection:self.dbConnection
                                         completion:nil];
        }

        // Whenever we change avatarUrlPath, OWSUserProfile clears avatarFileName.
        // So if avatarUrlPath is set and avatarFileName is not set, we should to
        // download this avatar. downloadAvatarForUserProfile will de-bounce
        // downloads.
        if (userProfile.avatarUrlPath.length > 0 && userProfile.avatarFileName.length < 1) {
            [self downloadAvatarForUserProfile:userProfile];
        }
    });
}

- (BOOL)isNullableDataEqual:(NSData *_Nullable)left toData:(NSData *_Nullable)right
{
    if (left == nil && right == nil) {
        return YES;
    } else if (left == nil || right == nil) {
        return YES;
    } else {
        return [left isEqual:right];
    }
}

- (BOOL)isNullableStringEqual:(NSString *_Nullable)left toString:(NSString *_Nullable)right
{
    if (left == nil && right == nil) {
        return YES;
    } else if (left == nil || right == nil) {
        return YES;
    } else {
        return [left isEqualToString:right];
    }
}

#pragma mark - Profile Encryption

- (nullable NSData *)encryptProfileData:(nullable NSData *)encryptedData profileKey:(OWSAES256Key *)profileKey
{
    OWSAssert(profileKey.keyData.length == kAES256_KeyByteLength);

    if (!encryptedData) {
        return nil;
    }

    return [Cryptography encryptAESGCMWithData:encryptedData key:profileKey];
}

- (nullable NSData *)decryptProfileData:(nullable NSData *)encryptedData profileKey:(OWSAES256Key *)profileKey
{
    OWSAssert(profileKey.keyData.length == kAES256_KeyByteLength);

    if (!encryptedData) {
        return nil;
    }

    return [Cryptography decryptAESGCMWithData:encryptedData key:profileKey];
}

- (nullable NSString *)decryptProfileNameData:(nullable NSData *)encryptedData profileKey:(OWSAES256Key *)profileKey
{
    OWSAssert(profileKey.keyData.length == kAES256_KeyByteLength);

    NSData *_Nullable decryptedData = [self decryptProfileData:encryptedData profileKey:profileKey];
    if (decryptedData.length < 1) {
        return nil;
    }


    // Unpad profile name.
    NSUInteger unpaddedLength = 0;
    const char *bytes = decryptedData.bytes;

    // Work through the bytes until we encounter our first
    // padding byte (our padding scheme is NULL bytes)
    for (NSUInteger i = 0; i < decryptedData.length; i++) {
        if (bytes[i] == 0x00) {
            break;
        }
        unpaddedLength = i + 1;
    }

    NSData *unpaddedData = [decryptedData subdataWithRange:NSMakeRange(0, unpaddedLength)];

    return [[NSString alloc] initWithData:unpaddedData encoding:NSUTF8StringEncoding];
}

- (nullable NSData *)encryptProfileData:(nullable NSData *)data
{
    return [self encryptProfileData:data profileKey:self.localProfileKey];
}

- (BOOL)isProfileNameTooLong:(nullable NSString *)profileName
{
    OWSAssertIsOnMainThread();

    NSData *nameData = [profileName dataUsingEncoding:NSUTF8StringEncoding];
    return nameData.length > kOWSProfileManager_NameDataLength;
}

- (nullable NSData *)encryptProfileNameWithUnpaddedName:(NSString *)name
{
    NSData *nameData = [name dataUsingEncoding:NSUTF8StringEncoding];
    if (nameData.length > kOWSProfileManager_NameDataLength) {
        OWSFail(@"%@ name data is too long with length:%lu", self.logTag, (unsigned long)nameData.length);
        return nil;
    }

    NSUInteger paddingByteCount = kOWSProfileManager_NameDataLength - nameData.length;

    NSMutableData *paddedNameData = [nameData mutableCopy];
    // Since we want all encrypted profile names to be the same length on the server, we use `increaseLengthBy`
    // to pad out any remaining length with 0 bytes.
    [paddedNameData increaseLengthBy:paddingByteCount];
    OWSAssert(paddedNameData.length == kOWSProfileManager_NameDataLength);

    return [self encryptProfileData:[paddedNameData copy] profileKey:self.localProfileKey];
}

#pragma mark - Avatar Disk Cache

- (nullable NSData *)loadProfileDataWithFilename:(NSString *)filename
{
    OWSAssert(filename.length > 0);

    NSString *filePath = [self.profileAvatarsDirPath stringByAppendingPathComponent:filename];
    return [NSData dataWithContentsOfFile:filePath];
}

- (nullable UIImage *)loadProfileAvatarWithFilename:(NSString *)filename
{
    if (filename.length == 0) {
        return nil;
    }

    UIImage *_Nullable image = nil;
    @synchronized(self.profileAvatarImageCache)
    {
        image = [self.profileAvatarImageCache objectForKey:filename];
    }
    if (image) {
        return image;
    }

    NSData *data = [self loadProfileDataWithFilename:filename];
    if (![data ows_isValidImage]) {
        return nil;
    }
    image = [UIImage imageWithData:data];
    [self updateProfileAvatarCache:image filename:filename];
    return image;
}

- (void)updateProfileAvatarCache:(nullable UIImage *)image filename:(NSString *)filename
{
    OWSAssert(filename.length > 0);
    OWSAssert(image);

    @synchronized(self.profileAvatarImageCache)
    {
        if (image) {
            [self.profileAvatarImageCache setObject:image forKey:filename];
        } else {
            [self.profileAvatarImageCache removeObjectForKey:filename];
        }
    }
}

+ (NSString *)legacyProfileAvatarsDirPath
{
    return [[OWSFileSystem appDocumentDirectoryPath] stringByAppendingPathComponent:@"ProfileAvatars"];
}

+ (NSString *)sharedDataProfileAvatarsDirPath
{
    return [[OWSFileSystem appSharedDataDirectoryPath] stringByAppendingPathComponent:@"ProfileAvatars"];
}

+ (nullable NSError *)migrateToSharedData
{
    DDLogInfo(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    return [OWSFileSystem moveAppFilePath:self.legacyProfileAvatarsDirPath
                       sharedDataFilePath:self.sharedDataProfileAvatarsDirPath];
}

- (NSString *)profileAvatarsDirPath
{
    static NSString *profileAvatarsDirPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        profileAvatarsDirPath = OWSProfileManager.sharedDataProfileAvatarsDirPath;
        
        [OWSFileSystem ensureDirectoryExists:profileAvatarsDirPath];
    });
    return profileAvatarsDirPath;
}

// TODO: We may want to clean up this directory in the "orphan cleanup" logic.

- (void)resetProfileStorage
{
    OWSAssertIsOnMainThread();

    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self profileAvatarsDirPath] error:&error];
    if (error) {
        DDLogError(@"Failed to delete database: %@", error.description);
    }
}

#pragma mark - User Interface

- (void)presentAddThreadToProfileWhitelist:(TSThread *)thread
                        fromViewController:(UIViewController *)fromViewController
                                   success:(void (^)(void))successHandler
{
    OWSAssertIsOnMainThread();

    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *shareTitle = NSLocalizedString(@"CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE",
        @"Button to confirm that user wants to share their profile with a user or group.");
    [alertController addAction:[UIAlertAction actionWithTitle:shareTitle
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *_Nonnull action) {
                                                          [self userAddedThreadToProfileWhitelist:thread
                                                                                          success:successHandler];
                                                      }]];
    [alertController addAction:[OWSAlerts cancelAction]];

    [fromViewController presentViewController:alertController animated:YES completion:nil];
}

- (void)userAddedThreadToProfileWhitelist:(TSThread *)thread success:(void (^)(void))successHandler
{
    OWSAssertIsOnMainThread();

    OWSProfileKeyMessage *message =
        [[OWSProfileKeyMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:thread];

    BOOL isFeatureEnabled = NO;
    if (!isFeatureEnabled) {
        DDLogWarn(
            @"%@ skipping sending profile-key message because the feature is not yet fully available.", self.logTag);
        [OWSProfileManager.sharedManager addThreadToProfileWhitelist:thread];
        successHandler();
        return;
    }

    [self.messageSender enqueueMessage:message
        success:^{
            DDLogInfo(@"%@ Successfully sent profile key message to thread: %@", self.logTag, thread);
            [OWSProfileManager.sharedManager addThreadToProfileWhitelist:thread];

            dispatch_async(dispatch_get_main_queue(), ^{
                successHandler();
            });
        }
        failure:^(NSError *_Nonnull error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                DDLogError(@"%@ Failed to send profile key message to thread: %@", self.logTag, thread);
            });
        }];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    // TODO: Sync if necessary.
}

@end

NS_ASSUME_NONNULL_END
