//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSentMessageTranscript.h"
#import "OWSSignalServiceProtos.pb.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSOutgoingMessage (OWSOutgoingSentMessageTranscript)

/**
 * Normally this is private, but we need to embed this
 * data structure within our own.
 *
 * recipientId is nil when building "sent" sync messages for messages
 * sent to groups.
 */
- (OWSSignalServiceProtosDataMessage *)buildDataMessage:(NSString *_Nullable)recipientId;

@end

@interface OWSOutgoingSentMessageTranscript ()

@property (nonatomic, readonly) TSOutgoingMessage *message;
// sentRecipientId is the recipient of message, for contact thread messages.
// It is used to identify the thread/conversation to desktop.
@property (nonatomic, readonly, nullable) NSString *sentRecipientId;

@end

@implementation OWSOutgoingSentMessageTranscript

- (instancetype)initWithOutgoingMessage:(TSOutgoingMessage *)message
{
    self = [super init];

    if (!self) {
        return self;
    }

    _message = message;
    // This will be nil for groups.
    _sentRecipientId = message.thread.contactIdentifier;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (OWSSignalServiceProtosSyncMessageBuilder *)syncMessageBuilder
{
    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];

    OWSSignalServiceProtosSyncMessageSentBuilder *sentBuilder = [OWSSignalServiceProtosSyncMessageSentBuilder new];
    [sentBuilder setTimestamp:self.message.timestamp];

    [sentBuilder setDestination:self.sentRecipientId];
    [sentBuilder setMessage:[self.message buildDataMessage:self.sentRecipientId]];
    [sentBuilder setExpirationStartTimestamp:self.message.timestamp];

    [syncMessageBuilder setSentBuilder:sentBuilder];

    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
