//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSRequestBuilder.h"
#import "TSRequest.h"
#import "TSConstants.h"
#import "NSData+Base64.h"

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kEncodedNameLength = 72;

@implementation OWSRequestBuilder

+ (TSRequest *)profileNameSetRequestWithEncryptedPaddedName:(nullable NSData *)encryptedPaddedName
{
    NSString *urlString;

    NSString *base64EncodedName = [encryptedPaddedName base64EncodedString];
    // name length must match exactly
    if (base64EncodedName.length == kEncodedNameLength) {
        // Remove any "/" in the base64 (all other base64 chars are URL safe.
        // Apples built-in `stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URL*]]` doesn't offer a
        // flavor for encoding "/".
        NSString *urlEncodedName = [base64EncodedName stringByReplacingOccurrencesOfString:@"/" withString:@"%2F"];
        urlString = [NSString stringWithFormat:textSecureSetProfileNameAPIFormat, urlEncodedName];
    } else {
        // if name length doesn't match exactly, assume blank name
        OWSAssert(encryptedPaddedName == nil);
        urlString = [NSString stringWithFormat:textSecureSetProfileNameAPIFormat, @""];
    }
    
    NSURL *url = [NSURL URLWithString:urlString];
    TSRequest *request = [[TSRequest alloc] initWithURL:url];
    request.HTTPMethod = @"PUT";
    
    return request;
}

+ (TSRequest *)profileNameSetRequestWithPlainText:(NSString*) profileName
{
    NSCharacterSet * queryKVSet = [NSCharacterSet characterSetWithCharactersInString:@":/?&=;+!@#$()',*% []"].invertedSet;
    NSString * encodedString = [profileName stringByAddingPercentEncodingWithAllowedCharacters:queryKVSet];
    
    NSString *path = [NSString stringWithFormat:@"%@/%@/%@", textSecureDirectoryAPI, @"internal/name", encodedString];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path]
                              method:@"PUT"
                          parameters:@{}
            ];
}

@end

NS_ASSUME_NONNULL_END
