//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHandler.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

// used in log formatting
NSString *envelopeAddress(OWSSignalServiceProtosEnvelope *envelope)
{
    return [NSString stringWithFormat:@"%@.%d", envelope.source, (unsigned int)envelope.sourceDevice];
}

@implementation OWSMessageHandler

- (NSString *)descriptionForEnvelopeType:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert(envelope != nil);
    
    // added: just return "Unkown" if has no type.
    if (!envelope.hasType) {
        return @"Unknown";
    }

    switch (envelope.type) {
        case OWSSignalServiceProtosEnvelopeTypeReceipt:
            return @"DeliveryReceipt";
        case OWSSignalServiceProtosEnvelopeTypeUnknown:
            // Shouldn't happen

            // modified: when an exist user with unread messge try to reregister ,
            // the user who sended message maybe meet this situation.
            // e.g. maybe return this type when contact security code changed
            //OWSProdFail([OWSAnalyticsEvents messageManagerErrorEnvelopeTypeUnknown]);
            return @"Unknown";
        case OWSSignalServiceProtosEnvelopeTypeCiphertext:
            return @"SignalEncryptedMessage";
        case OWSSignalServiceProtosEnvelopeTypeKeyExchange:
            // Unsupported
            OWSProdFail([OWSAnalyticsEvents messageManagerErrorEnvelopeTypeKeyExchange]);
            return @"KeyExchange";
        case OWSSignalServiceProtosEnvelopeTypePrekeyBundle:
            return @"PreKeyEncryptedMessage";
        default:
            // Shouldn't happen
            OWSProdFail([OWSAnalyticsEvents messageManagerErrorEnvelopeTypeOther]);
            return @"Other";
    }
}

- (NSString *)descriptionForEnvelope:(OWSSignalServiceProtosEnvelope *)envelope
{
    OWSAssert(envelope != nil);

    return [NSString stringWithFormat:@"<Envelope type: %@, source: %@, timestamp: %llu content.length: %lu />",
                     [self descriptionForEnvelopeType:envelope],
                     envelopeAddress(envelope),
                     envelope.timestamp,
                     (unsigned long)envelope.content.length];
}

/**
 * We don't want to just log `content.description` because we'd potentially log message bodies for dataMesssages and
 * sync transcripts
 */
- (NSString *)descriptionForContent:(OWSSignalServiceProtosContent *)content
{
    if (content.hasSyncMessage) {
        return [NSString stringWithFormat:@"<SyncMessage: %@ />", [self descriptionForSyncMessage:content.syncMessage]];
    } else if (content.hasDataMessage) {
        return [NSString stringWithFormat:@"<DataMessage: %@ />", [self descriptionForDataMessage:content.dataMessage]];
    } else if (content.hasCallMessage) {
        NSString *callMessageDescription = [self descriptionForCallMessage:content.callMessage];
        return [NSString stringWithFormat:@"<CallMessage %@ />", callMessageDescription];
    } else if (content.hasNullMessage) {
        return [NSString stringWithFormat:@"<NullMessage: %@ />", content.nullMessage];
    } else if (content.hasReceiptMessage) {
        return [NSString stringWithFormat:@"<ReceiptMessage: %@ />", content.receiptMessage];
    } else {
        // Don't fire an analytics event; if we ever add a new content type, we'd generate a ton of
        // analytics traffic.
        OWSFail(@"Unknown content type.");
        return @"UnknownContent";
    }
}

- (NSString *)descriptionForCallMessage:(OWSSignalServiceProtosCallMessage *)callMessage
{
    NSString *messageType;
    UInt64 callId;
    
    if (callMessage.hasOffer) {
        messageType = @"Offer";
        callId = callMessage.offer.id;
    } else if (callMessage.hasBusy) {
        messageType = @"Busy";
        callId = callMessage.busy.id;
    } else if (callMessage.hasAnswer) {
        messageType = @"Answer";
        callId = callMessage.answer.id;
    } else if (callMessage.hasHangup) {
        messageType = @"Hangup";
        callId = callMessage.hangup.id;
    } else if (callMessage.iceUpdate.count > 0) {
        messageType = [NSString stringWithFormat:@"Ice Updates (%lu)", (unsigned long)callMessage.iceUpdate.count];
        callId = callMessage.iceUpdate.firstObject.id;
    } else {
        OWSFail(@"%@ failure: unexpected call message type: %@", self.logTag, callMessage);
        messageType = @"Unknown";
        callId = 0;
    }

    return [NSString stringWithFormat:@"type: %@, id: %llu", messageType, callId];
}

/**
 * We don't want to just log `dataMessage.description` because we'd potentially log message contents
 */
- (NSString *)descriptionForDataMessage:(OWSSignalServiceProtosDataMessage *)dataMessage
{
    NSMutableString *description = [NSMutableString new];

    if (dataMessage.hasGroup) {
        [description appendString:@"(Group:YES) "];
    }

    if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsEndSession) != 0) {
        [description appendString:@"EndSession"];
    } else if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsExpirationTimerUpdate) != 0) {
        [description appendString:@"ExpirationTimerUpdate"];
    } else if ((dataMessage.flags & OWSSignalServiceProtosDataMessageFlagsProfileKeyUpdate) != 0) {
        [description appendString:@"ProfileKey"];
    } else if (dataMessage.attachments.count > 0) {
        [description appendString:@"MessageWithAttachment"];
    } else {
        [description appendString:@"Plain"];
    }

    return [NSString stringWithFormat:@"<%@ />", description];
}

/**
 * We don't want to just log `syncMessage.description` because we'd potentially log message contents in sent transcripts
 */
- (NSString *)descriptionForSyncMessage:(OWSSignalServiceProtosSyncMessage *)syncMessage
{
    NSMutableString *description = [NSMutableString new];
    if (syncMessage.hasSent) {
        [description appendString:@"SentTranscript"];
    } else if (syncMessage.hasRequest) {
        if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeContacts) {
            [description appendString:@"ContactRequest"];
        } else if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeGroups) {
            [description appendString:@"GroupRequest"];
        } else if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeBlocked) {
            [description appendString:@"BlockedRequest"];
        } else if (syncMessage.request.type == OWSSignalServiceProtosSyncMessageRequestTypeConfiguration) {
            [description appendString:@"ConfigurationRequest"];
        } else {
            // Shouldn't happen
            OWSFail(@"Unknown sync message request type");
            [description appendString:@"UnknownRequest"];
        }
    } else if (syncMessage.hasBlocked) {
        [description appendString:@"Blocked"];
    } else if (syncMessage.read.count > 0) {
        [description appendString:@"ReadReceipt"];
    } else if (syncMessage.hasVerified) {
        NSString *verifiedString =
            [NSString stringWithFormat:@"Verification for: %@", syncMessage.verified.destination];
        [description appendString:verifiedString];
    } else {
        // Shouldn't happen
        OWSFail(@"Unknown sync message type");
        [description appendString:@"Unknown"];
    }

    return description;
}

@end

NS_ASSUME_NONNULL_END
