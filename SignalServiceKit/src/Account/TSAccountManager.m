//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSAccountManager.h"
#import "AppContext.h"
#import "NSData+Base64.h"
#import "NSData+hexString.h"
#import "NSNotificationCenter+OWS.h"
#import "NSURLSessionDataTask+StatusCode.h"
#import "OWSError.h"
#import "OWSPrimaryStorage+SessionStore.h"
#import "OWSRequestFactory.h"
#import "SecurityUtils.h"
#import "TSNetworkManager.h"
#import "TSPreKeyManager.h"
#import "TSVerifyCodeRequest.h"
#import "YapDatabaseConnection+OWS.h"
#import "YapDatabaseTransaction+OWS.h"
#import <YapDatabase/YapDatabase.h>
#import "Contact.h"
#import "PhoneNumber.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const TSRegistrationErrorDomain = @"TSRegistrationErrorDomain";
NSString *const TSRegistrationErrorUserInfoHTTPStatus = @"TSHTTPStatus";
NSString *const RegistrationStateDidChangeNotification = @"RegistrationStateDidChangeNotification";
NSString *const DeregistrationStateDidChangeNotification = @"DeregistrationStateDidChangeNotification";
NSString *const kNSNotificationName_LocalNumberDidChange = @"kNSNotificationName_LocalNumberDidChange";

NSString *const TSAccountManager_RegisteredNumberKey = @"TSStorageRegisteredNumberKey";
NSString *const TSAccountManager_IsDeregisteredKey = @"TSAccountManager_IsDeregisteredKey";
NSString *const TSAccountManager_ReregisteringPhoneNumberKey = @"TSAccountManager_ReregisteringPhoneNumberKey";
NSString *const TSAccountManager_LocalRegistrationIdKey = @"TSStorageLocalRegistrationId";

NSString *const TSAccountManager_UserAccountCollection = @"TSStorageUserAccountCollection";
NSString *const TSAccountManager_ServerAuthToken = @"TSStorageServerAuthToken";
NSString *const TSAccountManager_ServerSignalingKey = @"TSStorageServerSignalingKey";

@interface TSAccountManager ()

@property (nonatomic, readonly) BOOL isRegistered;

// This property is exposed publicly for testing purposes only.
#ifndef DEBUG
@property (nonatomic, nullable) NSString *phoneNumberAwaitingVerification;
#endif

@property (nonatomic, nullable) NSString *cachedLocalNumber;
@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@property (nonatomic, nullable) NSNumber *cachedIsDeregistered;

@end

#pragma mark -

@implementation TSAccountManager

@synthesize isRegistered = _isRegistered;

- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager
                        primaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];
    if (!self) {
        return self;
    }

    _networkManager = networkManager;
    _dbConnection = [primaryStorage newDatabaseConnection];

    OWSSingletonAssert();

    if (!CurrentAppContext().isMainApp) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModifiedExternally:)
                                                     name:YapDatabaseModifiedExternallyNotification
                                                   object:nil];
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    static id sharedInstance = nil;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initWithNetworkManager:[TSNetworkManager sharedManager]
                                               primaryStorage:[OWSPrimaryStorage sharedManager]];
    });

    return sharedInstance;
}

- (void)setPhoneNumberAwaitingVerification:(NSString *_Nullable)phoneNumberAwaitingVerification
{
    _phoneNumberAwaitingVerification = phoneNumberAwaitingVerification;

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:kNSNotificationName_LocalNumberDidChange
                                                             object:nil
                                                           userInfo:nil];
}

+ (BOOL)isRegistered
{
    return [[self sharedInstance] isRegistered];
}

- (BOOL)isRegistered
{
    if (_isRegistered) {
        return YES;
    } else {
        @synchronized (self) {
            // Cache this once it's true since it's called alot, involves a dbLookup, and once set - it doesn't change.
            _isRegistered = [self storedLocalNumber] != nil;
        }
    }
    return _isRegistered;
}

- (void)didRegister
{
    DDLogInfo(@"%@ didRegister", self.logTag);
    NSString *phoneNumber = self.phoneNumberAwaitingVerification;

    if (!phoneNumber) {
        OWSRaiseException(@"RegistrationFail", @"Internal Corrupted State");
    }

    [self storeLocalNumber:phoneNumber];

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:RegistrationStateDidChangeNotification
                                                             object:nil
                                                           userInfo:nil];

    // Warm these cached values.
    [self isRegistered];
    [self localNumber];
    [self isDeregistered];
}

+ (nullable NSString *)localNumber
{
    return [[self sharedInstance] localNumber];
}

- (nullable NSString *)localNumber
{
    NSString *awaitingVerif = self.phoneNumberAwaitingVerification;
    if (awaitingVerif) {
        return awaitingVerif;
    }

    // Cache this since we access this a lot, and once set it will not change.
    @synchronized(self)
    {
        if (self.cachedLocalNumber == nil) {
            self.cachedLocalNumber = self.storedLocalNumber;
        }
    }

    return self.cachedLocalNumber;
}

- (nullable NSString *)storedLocalNumber
{
    @synchronized (self) {
        return [self.dbConnection stringForKey:TSAccountManager_RegisteredNumberKey
                                  inCollection:TSAccountManager_UserAccountCollection];
    }
}

- (void)storeLocalNumber:(NSString *)localNumber
{
    @synchronized (self) {
        [self.dbConnection setObject:localNumber
                              forKey:TSAccountManager_RegisteredNumberKey
                        inCollection:TSAccountManager_UserAccountCollection];

        [self.dbConnection removeObjectForKey:TSAccountManager_ReregisteringPhoneNumberKey
                                 inCollection:TSAccountManager_UserAccountCollection];

        self.phoneNumberAwaitingVerification = nil;

        self.cachedLocalNumber = localNumber;
    }
}

+ (uint32_t)getOrGenerateRegistrationId
{
    return [[self sharedInstance] getOrGenerateRegistrationId];
}

+ (uint32_t)getOrGenerateRegistrationId:(YapDatabaseReadWriteTransaction *)transaction
{
    return [[self sharedInstance] getOrGenerateRegistrationId:transaction];
}

- (uint32_t)getOrGenerateRegistrationId
{
    __block uint32_t result;
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        result = [self getOrGenerateRegistrationId:transaction];
    }];
    return result;
}

- (uint32_t)getOrGenerateRegistrationId:(YapDatabaseReadWriteTransaction *)transaction
{
    @synchronized(self)
    {
        uint32_t registrationID = [[transaction objectForKey:TSAccountManager_LocalRegistrationIdKey
                                                inCollection:TSAccountManager_UserAccountCollection] unsignedIntValue];

        if (registrationID == 0) {
            registrationID = (uint32_t)arc4random_uniform(16380) + 1;
            DDLogWarn(@"%@ Generated a new registrationID: %u", self.logTag, registrationID);

            [transaction setObject:[NSNumber numberWithUnsignedInteger:registrationID]
                            forKey:TSAccountManager_LocalRegistrationIdKey
                      inCollection:TSAccountManager_UserAccountCollection];
        }
        return registrationID;
    }
}

- (void)registerForPushNotificationsWithPushToken:(NSString *)pushToken
                                        voipToken:(NSString *)voipToken
                                          success:(void (^)(void))successHandler
                                          failure:(void (^)(NSError *))failureHandler
{
    [self registerForPushNotificationsWithPushToken:pushToken
                                          voipToken:voipToken
                                            success:successHandler
                                            failure:failureHandler
                                   remainingRetries:3];
}

- (void)registerForPushNotificationsWithPushToken:(NSString *)pushToken
                                        voipToken:(NSString *)voipToken
                                          success:(void (^)(void))successHandler
                                          failure:(void (^)(NSError *))failureHandler
                                 remainingRetries:(int)remainingRetries
{
    TSRequest *request =
        [OWSRequestFactory registerForPushRequestWithPushIdentifier:pushToken voipIdentifier:voipToken];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            successHandler();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (remainingRetries > 0) {
                [self registerForPushNotificationsWithPushToken:pushToken
                                                      voipToken:voipToken
                                                        success:successHandler
                                                        failure:failureHandler
                                               remainingRetries:remainingRetries - 1];
            } else {
                if (!IsNSErrorNetworkFailure(error)) {
                    OWSProdError([OWSAnalyticsEvents accountsErrorRegisterPushTokensFailed]);
                }
                failureHandler(error);
            }
        }];
}

+ (void)registerWithPhoneNumber:(NSString *)phoneNumber
                        success:(void (^)(void))successBlock
                        failure:(void (^)(NSError *error))failureBlock
                smsVerification:(BOOL)isSMS

{
    if ([self isRegistered]) {
        failureBlock([NSError errorWithDomain:@"tsaccountmanager.verify" code:4000 userInfo:nil]);
        return;
    }

    // The country code of TSAccountManager.phoneNumberAwaitingVerification is used to
    // determine whether or not to use domain fronting, so it needs to be set _before_
    // we make our verification code request.
    TSAccountManager *manager = [self sharedInstance];
    manager.phoneNumberAwaitingVerification = phoneNumber;

    TSRequest *request =
        [OWSRequestFactory requestVerificationCodeRequestWithPhoneNumber:phoneNumber
                                                               transport:(isSMS ? TSVerificationTransportSMS
                                                                                : TSVerificationTransportVoice)];
    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            DDLogInfo(@"%@ Successfully requested verification code request for number: %@ method:%@",
                self.logTag,
                phoneNumber,
                isSMS ? @"SMS" : @"Voice");
            successBlock();
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents accountsErrorVerificationCodeRequestFailed]);
            }
            DDLogError(@"%@ Failed to request verification code request with error:%@", self.logTag, error);
            failureBlock(error);
        }];
}

+ (void)rerequestSMSWithSuccess:(void (^)(void))successBlock failure:(void (^)(NSError *error))failureBlock
{
    TSAccountManager *manager = [self sharedInstance];
    NSString *number          = manager.phoneNumberAwaitingVerification;

    OWSAssert(number);

    [self registerWithPhoneNumber:number success:successBlock failure:failureBlock smsVerification:YES];
}

+ (void)rerequestVoiceWithSuccess:(void (^)(void))successBlock failure:(void (^)(NSError *error))failureBlock
{
    TSAccountManager *manager = [self sharedInstance];
    NSString *number          = manager.phoneNumberAwaitingVerification;

    OWSAssert(number);

    [self registerWithPhoneNumber:number success:successBlock failure:failureBlock smsVerification:NO];
}

- (void)registerForManualMessageFetchingWithSuccess:(void (^)(void))successBlock
                                            failure:(void (^)(NSError *error))failureBlock
{
    TSRequest *request = [OWSRequestFactory updateAttributesRequestWithManualMessageFetching:YES];
    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *_Nonnull task, id _Nonnull responseObject) {
            DDLogInfo(@"%@ updated server with account attributes to enableManualFetching", self.logTag);
            successBlock();
        }
        failure:^(NSURLSessionDataTask *_Nonnull task, NSError *_Nonnull error) {
            DDLogInfo(@"%@ failed to updat server with account attributes with error: %@", self.logTag, error);
            failureBlock(error);
        }];
}

- (void)verifyAccountWithCode:(NSString *)verificationCode
                          pin:(nullable NSString *)pin
                      success:(void (^)(void))successBlock
                      failure:(void (^)(NSError *error))failureBlock
{
    NSString *authToken = [[self class] generateNewAccountAuthenticationToken];
    NSString *signalingKey = [[self class] generateNewSignalingKeyToken];
    NSString *phoneNumber = self.phoneNumberAwaitingVerification;

    OWSAssert(signalingKey);
    OWSAssert(authToken);
    OWSAssert(phoneNumber);

    TSVerifyCodeRequest *request = [[TSVerifyCodeRequest alloc] initWithVerificationCode:verificationCode
                                                                               forNumber:phoneNumber
                                                                                     pin:pin
                                                                            signalingKey:signalingKey
                                                                                 authKey:authToken];

    [self.networkManager makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            long statuscode = response.statusCode;

            switch (statuscode) {
                case 200:
                case 204: {
                    DDLogInfo(@"%@ Verification code accepted.", self.logTag);
                    [self storeServerAuthToken:authToken signalingKey:signalingKey];
                    [TSPreKeyManager registerPreKeysWithMode:RefreshPreKeysMode_SignedAndOneTime
                                                     success:successBlock
                                                     failure:failureBlock];
                    break;
                }
                default: {
                    DDLogError(@"%@ Unexpected status while verifying code: %ld", self.logTag, statuscode);
                    NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                    failureBlock(error);
                    break;
                }
            }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents accountsErrorVerifyAccountRequestFailed]);
            }
            OWSAssert([error.domain isEqualToString:TSNetworkManagerDomain]);

            DDLogWarn(@"%@ Error verifying code: %@", self.logTag, error.debugDescription);

            switch (error.code) {
                case 403: {
                    NSError *userError = OWSErrorWithCodeDescription(OWSErrorCodeUserError,
                        NSLocalizedString(@"REGISTRATION_VERIFICATION_FAILED_WRONG_CODE_DESCRIPTION",
                            "Error message indicating that registration failed due to a missing or incorrect "
                            "verification code."));
                    failureBlock(userError);
                    break;
                }
                case 413: {
                    // In the case of the "rate limiting" error, we want to show the
                    // "recovery suggestion", not the error's "description."
                    NSError *userError
                        = OWSErrorWithCodeDescription(OWSErrorCodeUserError, error.localizedRecoverySuggestion);
                    failureBlock(userError);
                    break;
                }
                case 423: {
                    NSString *localizedMessage = NSLocalizedString(@"REGISTRATION_VERIFICATION_FAILED_WRONG_PIN",
                        "Error message indicating that registration failed due to a missing or incorrect 2FA PIN.");
                    DDLogError(@"%@ 2FA PIN required: %ld", self.logTag, error.code);
                    NSError *error
                        = OWSErrorWithCodeDescription(OWSErrorCodeRegistrationMissing2FAPIN, localizedMessage);
                    failureBlock(error);
                    break;
                }
                default: {
                    DDLogError(@"%@ verifying code failed with unknown error: %@", self.logTag, error);
                    failureBlock(error);
                    break;
                }
            }
        }];
}

#pragma mark Server keying material

+ (NSString *)generateNewAccountAuthenticationToken {
    NSData *authToken        = [SecurityUtils generateRandomBytes:16];
    NSString *authTokenPrint = [[NSData dataWithData:authToken] hexadecimalString];
    return authTokenPrint;
}

+ (NSString *)generateNewSignalingKeyToken {
    /*The signalingKey is 32 bytes of AES material (256bit AES) and 20 bytes of
     * Hmac key material (HmacSHA1) concatenated into a 52 byte slug that is
     * base64 encoded. */
    NSData *signalingKeyToken        = [SecurityUtils generateRandomBytes:52];
    NSString *signalingKeyTokenPrint = [[NSData dataWithData:signalingKeyToken] base64EncodedString];
    return signalingKeyTokenPrint;
}

+ (nullable NSString *)signalingKey
{
    return [[self sharedInstance] signalingKey];
}

- (nullable NSString *)signalingKey
{
    return [self.dbConnection stringForKey:TSAccountManager_ServerSignalingKey
                              inCollection:TSAccountManager_UserAccountCollection];
}

+ (nullable NSString *)serverAuthToken
{
    return [[self sharedInstance] serverAuthToken];
}

- (nullable NSString *)serverAuthToken
{
    return [self.dbConnection stringForKey:TSAccountManager_ServerAuthToken
                              inCollection:TSAccountManager_UserAccountCollection];
}

- (void)storeServerAuthToken:(NSString *)authToken signalingKey:(NSString *)signalingKey
{
    [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:authToken
                        forKey:TSAccountManager_ServerAuthToken
                  inCollection:TSAccountManager_UserAccountCollection];
        [transaction setObject:signalingKey
                        forKey:TSAccountManager_ServerSignalingKey
                  inCollection:TSAccountManager_UserAccountCollection];

    }];
}

+ (void)unregisterTextSecureWithSuccess:(void (^)(void))success failure:(void (^)(NSError *error))failureBlock
{
    TSRequest *request = [OWSRequestFactory unregisterAccountRequest];
    [[TSNetworkManager sharedManager] makeRequest:request
        success:^(NSURLSessionDataTask *task, id responseObject) {
            DDLogInfo(@"%@ Successfully unregistered", self.logTag);
            success();

            // This is called from `[AppSettingsViewController proceedToUnregistration]` whose
            // success handler calls `[Environment resetAppData]`.
            // This method, after calling that success handler, fires
            // `RegistrationStateDidChangeNotification` which is only safe to fire after
            // the data store is reset.

            [[NSNotificationCenter defaultCenter] postNotificationNameAsync:RegistrationStateDidChangeNotification
                                                                     object:nil
                                                                   userInfo:nil];
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (!IsNSErrorNetworkFailure(error)) {
                OWSProdError([OWSAnalyticsEvents accountsErrorUnregisterAccountRequestFailed]);
            }
            DDLogError(@"%@ Failed to unregister with error: %@", self.logTag, error);
            failureBlock(error);
        }];
}

- (void)yapDatabaseModifiedExternally:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    // Any database write by the main app might reflect a deregistration,
    // so clear the cached "is registered" state.  This will significantly
    // erode the value of this cache in the SAE.
    @synchronized(self)
    {
        _isRegistered = NO;
    }
}

#pragma mark - De-Registration

- (BOOL)isDeregistered
{
    // Cache this since we access this a lot, and once set it will not change.
    @synchronized(self) {
        if (self.cachedIsDeregistered == nil) {
            self.cachedIsDeregistered = @([self.dbConnection boolForKey:TSAccountManager_IsDeregisteredKey
                                                           inCollection:TSAccountManager_UserAccountCollection
                                                           defaultValue:NO]);
        }

        OWSAssert(self.cachedIsDeregistered);
        return self.cachedIsDeregistered.boolValue;
    }
}

- (void)setIsDeregistered:(BOOL)isDeregistered
{
    @synchronized(self) {
        if (self.cachedIsDeregistered && self.cachedIsDeregistered.boolValue == isDeregistered) {
            return;
        }

        DDLogWarn(@"%@ isDeregistered: %d", self.logTag, isDeregistered);

        self.cachedIsDeregistered = @(isDeregistered);
    }

    [self.dbConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:@(isDeregistered)
                        forKey:TSAccountManager_IsDeregisteredKey
                  inCollection:TSAccountManager_UserAccountCollection];
    }];

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:DeregistrationStateDidChangeNotification
                                                             object:nil
                                                           userInfo:nil];
}

#pragma mark - Re-registration

- (BOOL)resetForReregistration
{
    @synchronized(self) {
        NSString *_Nullable localNumber = self.localNumber;
        if (!localNumber) {
            OWSFail(@"%@ can't re-register without valid local number.", self.logTag);
            return NO;
        }

        _isRegistered = NO;
        _cachedLocalNumber = nil;
        _phoneNumberAwaitingVerification = nil;
        _cachedIsDeregistered = nil;
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [transaction removeAllObjectsInCollection:TSAccountManager_UserAccountCollection];

            [[OWSPrimaryStorage sharedManager] resetSessionStore:transaction];

            [transaction setObject:localNumber
                            forKey:TSAccountManager_ReregisteringPhoneNumberKey
                      inCollection:TSAccountManager_UserAccountCollection];
        }];
        return YES;
    }
}

- (NSString *)reregisterationPhoneNumber
{
    OWSAssert([self isReregistering]);

    NSString *_Nullable result = [self.dbConnection stringForKey:TSAccountManager_ReregisteringPhoneNumberKey
                                                    inCollection:TSAccountManager_UserAccountCollection];
    OWSAssert(result);
    return result;
}

- (BOOL)isReregistering
{
    return nil !=
        [self.dbConnection stringForKey:TSAccountManager_ReregisteringPhoneNumberKey
                           inCollection:TSAccountManager_UserAccountCollection];
}

- (void)getInternalContactSuccess:(void (^)(NSArray* array))successHandler
                          failure:(void (^)(NSError *error))failureHandler
{
    OWSAssert(successHandler);
    OWSAssert(failureHandler);

    TSRequest *request = [OWSRequestFactory getInternalContactsRequest];
    [self.networkManager makeRequest:request
                             success:^(NSURLSessionDataTask *task, id responseObject) {
                                if (![responseObject isKindOfClass:[NSDictionary class]]) {
                                    DDLogError(@"%@ Failed retrieval of accounts. Response had unexpected format.", self.logTag);
                                    NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                                    return failureHandler(error);
                                }

                                NSArray *accountDicts = [(NSDictionary *)responseObject objectForKey:@"accounts"];
                                if (![accountDicts isKindOfClass:[NSArray class]]) {
                                    DDLogError(@"%@ Failed retrieval of accounts. Response had no accounts.", self.logTag);
                                    NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                                    return failureHandler(error);
                                }

                                NSMutableArray *accountArray = [[NSMutableArray alloc] initWithCapacity:500];
                                for (NSDictionary *dict in accountDicts) {
                                    NSString *fullName = [dict objectForKey:@"name"];
                                    if (!fullName) {
                                        DDLogError(@"%@ Failed retrieval of accounts. Response had no name.", self.logTag);
                                        NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                                        return failureHandler(error);
                                    }
                                    
                                    NSString *number = [dict objectForKey:@"number"];
                                    if (!number) {
                                        DDLogError(@"%@ Failed retrieval of accounts. Response had no number.", self.logTag);
                                        NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                                        return failureHandler(error);
                                    }
                                    
                                    [accountArray addObject:[[Contact alloc] initWithFullName:fullName phoneNumber:number]];
                                }

                                successHandler(accountArray);
                            }
                             failure:^(NSURLSessionDataTask *task, NSError *error) {
                                if (!IsNSErrorNetworkFailure(error)) {
                                    OWSProdError([OWSAnalyticsEvents errorAttachmentRequestFailed]);
                                }
                                
                                return failureHandler(error);
                            }];
}

- (void)getInviteCodeSuccess:(void (^)(id responseObject))successHandler
                     failure:(void (^)(NSError *error))failureHandler
{
    OWSAssert(successHandler);
    OWSAssert(failureHandler);

    TSRequest *request = [OWSRequestFactory getInviteCodeRequest: [NSString string]];
    [self.networkManager makeRequest:request
                             success:^(NSURLSessionDataTask *task, id responseObject){
                                 if (![responseObject isKindOfClass:[NSDictionary class]]) {
                                     DDLogError(@"%@ Failed retrieval of invite code. Response had unexpected format.", self.logTag);
                                     NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                                     return failureHandler(error);
                                 }
                                 successHandler(responseObject);
                             }
                             failure:^(NSURLSessionDataTask *task, NSError *error) {
                                 if (!IsNSErrorNetworkFailure(error)) {
                                     OWSProdError([OWSAnalyticsEvents errorAttachmentRequestFailed]);
                                 }
                                 return failureHandler(error);
                             }];
}

- (void)exchangeAccountWithInviteCode:(NSString *)inviteCode
                              success:(void (^)(id responseObject))successHandler
                              failure:(void (^)(NSError *error))failureHandler
{
    OWSAssert(inviteCode);
    OWSAssert(successHandler);
    OWSAssert(failureHandler);

    TSRequest *request = [OWSRequestFactory exchangeAccountRequest: inviteCode];
    [self.networkManager makeRequest:request
                             success:^(NSURLSessionDataTask *task, id responseObject){
                                 if (![responseObject isKindOfClass:[NSDictionary class]]) {
                                     DDLogError(@"%@ Failed exchange account. Response had unexpected format.", self.logTag);
                                     NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                                     return failureHandler(error);
                                 }
                                 successHandler(responseObject);
                             }
                             failure:^(NSURLSessionDataTask *task, NSError *error) {
                                 if (!IsNSErrorNetworkFailure(error)) {
                                     OWSProdError([OWSAnalyticsEvents errorAttachmentRequestFailed]);
                                 }
                                 return failureHandler(error);
                             }];
}

@end

NS_ASSUME_NONNULL_END
