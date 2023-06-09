//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "HomeViewCell.h"
#import "OWSAvatarBuilder.h"
#import "Signal-Swift.h"
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/OWSMath.h>
#import <SignalMessaging/OWSUserProfile.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface HomeViewCell ()

@property (nonatomic) AvatarImageView *avatarView;
@property (nonatomic) UIStackView *topRowView;
@property (nonatomic) UILabel *nameLabel;
@property (nonatomic) UILabel *snippetLabel;
@property (nonatomic) UILabel *dateTimeLabel;
@property (nonatomic) MessageStatusView *messageStatusView;

@property (nonatomic) UIView *unreadBadge;
@property (nonatomic) UILabel *unreadLabel;
@property (nonatomic) UIView *unreadBadgeContainer;

@property (nonatomic, nullable) ThreadViewModel *thread;
@property (nonatomic, nullable) OWSContactsManager *contactsManager;

@property (nonatomic, readonly) NSMutableArray<NSLayoutConstraint *> *viewConstraints;

@end

#pragma mark -

@implementation HomeViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier
{
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self commontInit];
    }
    return self;
}

// `[UIView init]` invokes `[self initWithFrame:...]`.
- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        [self commontInit];
    }

    return self;
}

- (void)commontInit
{
    OWSAssert(!self.avatarView);

    self.backgroundColor = UIColor.ows_themeBackgroundColor;

    _viewConstraints = [NSMutableArray new];

    UIView *selectedBackgroundView = [UIView new];
    selectedBackgroundView.backgroundColor =
        [(UIColor.isThemeEnabled ? [UIColor ows_whiteColor] : [UIColor ows_blackColor]) colorWithAlphaComponent:0.08];

    self.selectedBackgroundView = selectedBackgroundView;

    self.avatarView = [[AvatarImageView alloc] init];
    [self.contentView addSubview:self.avatarView];
    [self.avatarView autoSetDimension:ALDimensionWidth toSize:self.avatarSize];
    [self.avatarView autoSetDimension:ALDimensionHeight toSize:self.avatarSize];
    [self.avatarView autoPinLeadingToSuperviewMargin];
    [self.avatarView autoVCenterInSuperview];
    [self.avatarView setContentHuggingHigh];
    [self.avatarView setCompressionResistanceHigh];
    // Ensure that the cell's contents never overflow the cell bounds.
    [self.avatarView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    [self.avatarView autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];

    self.nameLabel = [UILabel new];
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.nameLabel.font = self.nameFont;
    [self.nameLabel setContentHuggingHorizontalLow];
    [self.nameLabel setCompressionResistanceHorizontalLow];

    self.dateTimeLabel = [UILabel new];
    [self.dateTimeLabel setContentHuggingHorizontalHigh];
    [self.dateTimeLabel setCompressionResistanceHorizontalHigh];

    self.messageStatusView = [MessageStatusView new];
    [self.messageStatusView setContentHuggingHorizontalHigh];
    [self.messageStatusView setCompressionResistanceHorizontalHigh];

    self.topRowView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.nameLabel,
        self.dateTimeLabel,
        self.messageStatusView,
    ]];
    self.topRowView.axis = UILayoutConstraintAxisHorizontal;
    self.topRowView.alignment = UIStackViewAlignmentLastBaseline;
    self.topRowView.spacing = 6.f;

    self.snippetLabel = [UILabel new];
    self.snippetLabel.font = [self snippetFont];
    self.snippetLabel.numberOfLines = 1;
    self.snippetLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.snippetLabel setContentHuggingHorizontalLow];
    [self.snippetLabel setCompressionResistanceHorizontalLow];

    UIStackView *vStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.topRowView,
        self.snippetLabel,
    ]];
    vStackView.axis = UILayoutConstraintAxisVertical;

    self.unreadLabel = [UILabel new];
    self.unreadLabel.textColor = [UIColor ows_whiteColor];
    self.unreadLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.unreadLabel.textAlignment = NSTextAlignmentCenter;
    [self.unreadLabel setContentHuggingHigh];
    [self.unreadLabel setCompressionResistanceHigh];

    self.unreadBadge = [NeverClearView new];
    self.unreadBadge.backgroundColor = [UIColor ows_materialBlueColor];
    [self.unreadBadge addSubview:self.unreadLabel];
    [self.unreadLabel autoCenterInSuperview];
    [self.unreadBadge setContentHuggingHigh];
    [self.unreadBadge setCompressionResistanceHigh];

    self.unreadBadgeContainer = [UIView containerView];
    [self.unreadBadgeContainer addSubview:self.unreadBadge];
    [self.unreadBadge autoPinWidthToSuperview];
    [self.unreadBadgeContainer setContentHuggingHigh];
    [self.unreadBadgeContainer setCompressionResistanceHigh];

    UIStackView *hStackView = [[UIStackView alloc] initWithArrangedSubviews:@[
        vStackView,
        self.unreadBadgeContainer,
    ]];
    hStackView.axis = UILayoutConstraintAxisHorizontal;
    hStackView.spacing = 6.f;
    [self.contentView addSubview:hStackView];
    [hStackView autoPinLeadingToTrailingEdgeOfView:self.avatarView offset:self.avatarHSpacing];
    [hStackView autoVCenterInSuperview];
    // Ensure that the cell's contents never overflow the cell bounds.
    [hStackView autoPinEdgeToSuperviewMargin:ALEdgeTop relation:NSLayoutRelationGreaterThanOrEqual];
    [hStackView autoPinEdgeToSuperviewMargin:ALEdgeBottom relation:NSLayoutRelationGreaterThanOrEqual];
    [hStackView autoPinTrailingToSuperviewMargin];

    [self.unreadBadge autoAlignAxis:ALAxisHorizontal toSameAxisOfView:self.nameLabel];

    hStackView.userInteractionEnabled = NO;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (NSString *)cellReuseIdentifier
{
    return NSStringFromClass([self class]);
}

- (void)initializeLayout
{
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (nullable NSString *)reuseIdentifier
{
    return NSStringFromClass(self.class);
}

- (void)configureWithThread:(ThreadViewModel *)thread
            contactsManager:(OWSContactsManager *)contactsManager
      blockedPhoneNumberSet:(NSSet<NSString *> *)blockedPhoneNumberSet
{
    [self configureWithThread:thread
              contactsManager:contactsManager
        blockedPhoneNumberSet:blockedPhoneNumberSet
              overrideSnippet:nil
                 overrideDate:nil];
}

- (void)configureWithThread:(ThreadViewModel *)thread
            contactsManager:(OWSContactsManager *)contactsManager
      blockedPhoneNumberSet:(NSSet<NSString *> *)blockedPhoneNumberSet
            overrideSnippet:(nullable NSAttributedString *)overrideSnippet
               overrideDate:(nullable NSDate *)overrideDate
{
    OWSAssertIsOnMainThread();
    OWSAssert(thread);
    OWSAssert(contactsManager);
    OWSAssert(blockedPhoneNumberSet);

    self.thread = thread;
    self.contactsManager = contactsManager;

    BOOL hasUnreadMessages = thread.hasUnreadMessages;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationName_OtherUsersProfileDidChange
                                               object:nil];
    [self updateNameLabel];
    [self updateAvatarView];

    // We update the fonts every time this cell is configured to ensure that
    // changes to the dynamic type settings are reflected.
    self.snippetLabel.font = [self snippetFont];

    if (overrideSnippet) {
        self.snippetLabel.attributedText = overrideSnippet;
    } else {
        self.snippetLabel.attributedText =
            [self attributedSnippetForThread:thread blockedPhoneNumberSet:blockedPhoneNumberSet];
    }

    self.dateTimeLabel.text
        = (overrideDate ? [self stringForDate:overrideDate] : [self stringForDate:thread.lastMessageDate]);

    UIColor *textColor = [UIColor ows_themeSecondaryColor];
    if (hasUnreadMessages && overrideSnippet == nil) {
        textColor = [UIColor ows_themeForegroundColor];
        self.dateTimeLabel.font = self.dateTimeFont.ows_mediumWeight;
    } else {
        self.dateTimeLabel.font = self.dateTimeFont;
    }
    self.dateTimeLabel.textColor = textColor;

    NSUInteger unreadCount = thread.unreadCount;
    if (overrideSnippet) {
        // If we're using the home view cell to render search results,
        // don't show "unread badge" or "message status" indicator.
        self.unreadBadgeContainer.hidden = YES;
        self.messageStatusView.hidden = YES;
    } else if (unreadCount > 0) {
        // If there are unread messages, show the "unread badge."
        // The "message status" indicators is redundant.
        self.unreadBadgeContainer.hidden = NO;
        self.messageStatusView.hidden = YES;

        self.unreadLabel.text = [OWSFormat formatInt:(int)unreadCount];
        self.unreadLabel.font = self.unreadFont;
        const int unreadBadgeHeight = (int)ceil(self.unreadLabel.font.lineHeight * 1.5f);
        self.unreadBadge.layer.cornerRadius = unreadBadgeHeight / 2;

        [NSLayoutConstraint autoSetPriority:UILayoutPriorityDefaultHigh
                             forConstraints:^{
                                 // This is a bit arbitrary, but it should scale with the size of dynamic text
                                 CGFloat minMargin = CeilEven(unreadBadgeHeight * .5f);

                                 // Spec check. Should be 12pts (6pt on each side) when using default font size.
                                 OWSAssert(UIFont.ows_dynamicTypeBodyFont.pointSize != 17 || minMargin == 12);

                                 [self.viewConstraints addObjectsFromArray:@[
                                     [self.unreadBadge autoMatchDimension:ALDimensionWidth
                                                              toDimension:ALDimensionWidth
                                                                   ofView:self.unreadLabel
                                                               withOffset:minMargin],
                                     // badge sizing
                                     [self.unreadBadge autoSetDimension:ALDimensionWidth
                                                                 toSize:unreadBadgeHeight
                                                               relation:NSLayoutRelationGreaterThanOrEqual],
                                     [self.unreadBadge autoSetDimension:ALDimensionHeight toSize:unreadBadgeHeight],
                                 ]];
                             }];
    } else {
        UIImage *_Nullable statusIndicatorImage = nil;
        // TODO: Theme, Review with design.
        UIColor *messageStatusViewTintColor
            = (UIColor.isThemeEnabled ? [UIColor ows_dark30Color] : [UIColor ows_light35Color]);
        BOOL shouldAnimateStatusIcon = NO;
        if ([self.thread.lastMessageForInbox isKindOfClass:[TSOutgoingMessage class]]) {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)self.thread.lastMessageForInbox;

            MessageReceiptStatus messageStatus =
                [MessageRecipientStatusUtils recipientStatusWithOutgoingMessage:outgoingMessage];
            switch (messageStatus) {
                case MessageReceiptStatusUploading:
                case MessageReceiptStatusSending:
                    statusIndicatorImage = [UIImage imageNamed:@"message_status_sending"];
                    shouldAnimateStatusIcon = YES;
                    break;
                case MessageReceiptStatusSent:
                case MessageReceiptStatusSkipped:
                    statusIndicatorImage = [UIImage imageNamed:@"message_status_sent"];
                    break;
                case MessageReceiptStatusDelivered:
                    statusIndicatorImage = [UIImage imageNamed:@"message_status_delivered"];
                    break;
                case MessageReceiptStatusRead:
                    statusIndicatorImage = [UIImage imageNamed:@"message_status_read"];
                    break;
                case MessageReceiptStatusFailed:
                    statusIndicatorImage = [UIImage imageNamed:@"message_status_failed"];
                    messageStatusViewTintColor = [UIColor ows_destructiveRedColor];
                    break;
            }
        }
        self.messageStatusView.image = [statusIndicatorImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        self.messageStatusView.tintColor = messageStatusViewTintColor;
        self.messageStatusView.hidden = statusIndicatorImage == nil;
        self.unreadBadgeContainer.hidden = YES;
        if (shouldAnimateStatusIcon) {
            CABasicAnimation *animation;
            animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            animation.toValue = @(M_PI * 2.0);
            const CGFloat kPeriodSeconds = 1.f;
            animation.duration = kPeriodSeconds;
            animation.cumulative = YES;
            animation.repeatCount = HUGE_VALF;
            [self.messageStatusView.layer addAnimation:animation forKey:@"animation"];
        } else {
            [self.messageStatusView.layer removeAllAnimations];
        }
    }
}

- (void)updateAvatarView
{
    OWSContactsManager *contactsManager = self.contactsManager;
    if (contactsManager == nil) {
        OWSFail(@"%@ contactsManager should not be nil", self.logTag);
        self.avatarView.image = nil;
        return;
    }

    ThreadViewModel *thread = self.thread;
    if (thread == nil) {
        OWSFail(@"%@ thread should not be nil", self.logTag);
        self.avatarView.image = nil;
        return;
    }

    self.avatarView.image = [OWSAvatarBuilder buildImageForThread:thread.threadRecord
                                                         diameter:self.avatarSize
                                                  contactsManager:contactsManager];
}

- (NSAttributedString *)attributedSnippetForThread:(ThreadViewModel *)thread
                             blockedPhoneNumberSet:(NSSet<NSString *> *)blockedPhoneNumberSet
{
    OWSAssert(thread);

    BOOL isBlocked = NO;
    if (!thread.isGroupThread) {
        NSString *contactIdentifier = thread.contactIdentifier;
        isBlocked = [blockedPhoneNumberSet containsObject:contactIdentifier];
    }
    BOOL hasUnreadMessages = thread.hasUnreadMessages;

    NSMutableAttributedString *snippetText = [NSMutableAttributedString new];
    if (isBlocked) {
        // If thread is blocked, don't show a snippet or mute status.
        [snippetText
            appendAttributedString:[[NSAttributedString alloc]
                                       initWithString:NSLocalizedString(@"HOME_VIEW_BLOCKED_CONTACT_CONVERSATION",
                                                          @"A label for conversations with blocked users.")
                                           attributes:@{
                                               NSFontAttributeName : self.snippetFont.ows_mediumWeight,
                                               NSForegroundColorAttributeName : [UIColor ows_themeForegroundColor],
                                           }]];
    } else {
        if ([thread isMuted]) {
            [snippetText appendAttributedString:[[NSAttributedString alloc]
                                                    initWithString:@"\ue067  "
                                                        attributes:@{
                                                            NSFontAttributeName : [UIFont ows_elegantIconsFont:9.f],
                                                            NSForegroundColorAttributeName :
                                                                (hasUnreadMessages ? [UIColor ows_themeForegroundColor]
                                                                                   : [UIColor ows_themeSecondaryColor]),
                                                        }]];
        }
        NSString *displayableText = thread.lastMessageText;
        
        if (displayableText) {
            if (hasUnreadMessages && thread.atPersons && [thread.atPersons containsString:[TSAccountManager localNumber]]) {
                [snippetText appendAttributedString:[[NSAttributedString alloc]
                                                        initWithString:@"[有人@你]"
                                                            attributes:@{
                                                                NSFontAttributeName :
                                                                    (hasUnreadMessages ? self.snippetFont.ows_mediumWeight
                                                                                       : self.snippetFont),
                                                                NSForegroundColorAttributeName :
                                                                    (hasUnreadMessages ? [UIColor redColor]
                                                                                       : [UIColor ows_themeSecondaryColor]),
                                                            }]];
            }
            
            [snippetText appendAttributedString:[[NSAttributedString alloc]
                                                    initWithString:displayableText
                                                        attributes:@{
                                                            NSFontAttributeName :
                                                                (hasUnreadMessages ? self.snippetFont.ows_mediumWeight
                                                                                   : self.snippetFont),
                                                            NSForegroundColorAttributeName :
                                                                (hasUnreadMessages ? [UIColor ows_themeForegroundColor]
                                                                                   : [UIColor ows_themeSecondaryColor]),
                                                        }]];
        }
    }

    return snippetText;
}

#pragma mark - Date formatting

- (NSString *)stringForDate:(nullable NSDate *)date
{
    if (date == nil) {
        OWSProdLogAndFail(@"%@ date was unexpectedly nil", self.logTag);
        return @"";
    }

    return [DateUtil formatDateShort:date];
}

#pragma mark - Constants

- (UIFont *)unreadFont
{
    return [UIFont ows_dynamicTypeCaption1Font].ows_mediumWeight;
}

- (UIFont *)dateTimeFont
{
    return [UIFont ows_dynamicTypeCaption1Font];
}

- (UIFont *)snippetFont
{
    return [UIFont ows_dynamicTypeSubheadlineFont];
}

- (UIFont *)nameFont
{
    return [UIFont ows_dynamicTypeBodyFont].ows_mediumWeight;
}

// Used for profile names.
- (UIFont *)nameSecondaryFont
{
    return [UIFont ows_dynamicTypeBodyFont].ows_italic;
}

- (NSUInteger)avatarSize
{
    return 48.f;
}

- (NSUInteger)avatarHSpacing
{
    return 12.f;
}

#pragma mark - Reuse

- (void)prepareForReuse
{
    [super prepareForReuse];

    [NSLayoutConstraint deactivateConstraints:self.viewConstraints];
    [self.viewConstraints removeAllObjects];

    self.thread = nil;
    self.contactsManager = nil;
    self.avatarView.image = nil;

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Name

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    NSString *recipientId = notification.userInfo[kNSNotificationKey_ProfileRecipientId];
    if (recipientId.length == 0) {
        return;
    }

    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        return;
    }

    if (![self.thread.contactIdentifier isEqualToString:recipientId]) {
        return;
    }

    [self updateNameLabel];
    [self updateAvatarView];
}

- (void)updateNameLabel
{
    OWSAssertIsOnMainThread();

    self.nameLabel.font = self.nameFont;
    self.nameLabel.textColor = [UIColor ows_themeForegroundColor];

    ThreadViewModel *thread = self.thread;
    if (thread == nil) {
        OWSFail(@"%@ thread should not be nil", self.logTag);
        self.nameLabel.attributedText = nil;
        return;
    }

    OWSContactsManager *contactsManager = self.contactsManager;
    if (contactsManager == nil) {
        OWSFail(@"%@ contacts manager should not be nil", self.logTag);
        self.nameLabel.attributedText = nil;
        return;
    }

    NSAttributedString *name;
    if (thread.isGroupThread) {
        if (thread.name.length == 0) {
            name = [[NSAttributedString alloc] initWithString:[MessageStrings newGroupDefaultTitle]];
        } else {
            name = [[NSAttributedString alloc] initWithString:thread.name];
        }
    } else {
        name = [contactsManager attributedContactOrProfileNameForPhoneIdentifier:thread.contactIdentifier
                                                                     primaryFont:self.nameFont
                                                                   secondaryFont:self.nameSecondaryFont];
    }

    self.nameLabel.attributedText = name;
}

@end

NS_ASSUME_NONNULL_END
