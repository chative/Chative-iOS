//
//  ContactDetailsViewController.m
//  Signal
//
//  Created by anonoymous on 2021/3/20.
//  Copyright © 2021 anonoymous. All rights reserved.
//

#import "ContactDetailsViewController.h"
#import "ContactsViewHelper.h"
#import "BlockListUIUtils.h"
#import "OWSBlockingManager.h"
#import "ContactEditingViewController.h"
#import "FingerprintViewController.h"
#import "PhoneNumber.h"

#import "SignalApp.h"

#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
//#import <SignalMessaging/OWSProfileManager.h>

#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/SignalAccount.h>

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kIconViewLength;

@interface ContactDetailsViewController () <ContactsViewHelperDelegate>

@property (nonatomic) NSString *recipientId;
@property (nonatomic) TSThread *thread;
@property (nonatomic, readonly) TSAccountManager *accountManager;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;
@property (nonatomic, readonly) UIImageView *avatarView;

@end

@implementation ContactDetailsViewController

- (void)commonInit
{
    _accountManager = [TSAccountManager sharedInstance];
    _contactsManager = [Environment current].contactsManager;
    _blockingManager = [OWSBlockingManager sharedManager];
    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];

    [self observeNotifications];
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(identityStateDidChange:)
                                                 name:kNSNotificationName_IdentityStateDidChange
                                               object:nil];
}

- (void)identityStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateTableContents];
}

- (void)configureWithRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);
    
    _recipientId = recipientId;

    self.thread = [TSContactThread getOrCreateThreadWithContactId:_recipientId];

    [self updateEditButton];
}

- (void)updateEditButton
{
    if (self.hasExistingContact && ![self isLocalNumber]) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"EDIT_TXT", nil)
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(didTapEditButton)];
    }
}

- (void)presentContactInfoViewController
{
    OWSAssert(_recipientId.length > 0);
    ContactEditingViewController *viewController = [ContactEditingViewController new];
    [viewController configureWithRecipientId:_recipientId];
    [self.navigationController pushViewController:viewController animated:YES];
}

- (void)didTapEditButton
{
    // edit button: only support change remark name.
    [self presentContactInfoViewController];
}

- (BOOL)isLocalNumber
{
    OWSAssert(_recipientId.length > 0);
    return [_recipientId isEqualToString:[TSAccountManager localNumber]];
}

- (BOOL)hasExistingContact
{
    OWSAssert(_recipientId.length > 0);
    return [self.contactsManager hasSignalAccountForRecipientId:_recipientId];
}

- (NSString *)threadName
{
    NSString *threadName = self.thread.name;
    if ([threadName isEqualToString:self.thread.contactIdentifier]) {
        threadName =
            [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:self.thread.contactIdentifier];
    }

    return threadName;
}


#pragma mark - View Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = NSLocalizedString(@"CONTACT_DETAILS_VIEW_TITLE", @"Title for the contact remark view.");
    self.tableView.estimatedRowHeight = 45;
    self.tableView.rowHeight = UITableViewAutomaticDimension;

    [self updateTableContents];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];
    contents.title = NSLocalizedString(@"CONVERSATION_SETTINGS", @"title for conversation settings screen");

    __weak ContactDetailsViewController *weakSelf = self;

    // Main section.
    
    OWSTableSection *mainSection = [OWSTableSection new];

    mainSection.customHeaderView = [self mainSectionHeader];
    mainSection.customHeaderHeight = @(100.f);

    if (self.hasExistingContact) {
        [mainSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            return [weakSelf
                    disclosureCellWithName: NSLocalizedString(@"CONTACT_SHARE_CONTACT_TO_FRIENTS",
                                                      @"Settings table view cell label")
                                  iconName: @"table_ic_share_contact"];
        }
                                                      actionBlock:^{
                                                          [weakSelf showShareFlow];
                                                      }]];
    } else {
        [mainSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            return [weakSelf
                    disclosureCellWithName:NSLocalizedString(@"CONVERSATION_SETTINGS_NEW_CONTACT",
                                                             @"Label for 'new contact' button in conversation settings view.")
                    iconName:@"table_ic_new_contact"];
        }
                                                       actionBlock:^{
                                                           [weakSelf presentAddContactSheet];
                                                       }]];
    }

    if (self.thread.hasSafetyNumbers) {
        [mainSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            return [weakSelf
                    disclosureCellWithName:
                    NSLocalizedString(@"VERIFY_PRIVACY",
                                      @"Label for button or row which allows users to verify the safety number of another user.")
                    iconName:@"table_ic_not_verified"];
        }
                                                       actionBlock:^{
                                                           [weakSelf showVerificationView];
                                                       }]];
    }

    if ([OWSProfileManager.sharedManager isThreadInProfileWhitelist:self.thread]) {
        [mainSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            return [weakSelf
                labelCellWithName:(NSLocalizedString(@"CONVERSATION_SETTINGS_VIEW_PROFILE_IS_SHARED_WITH_USER",
                                                @"Indicates that user's profile has been shared with a user."))
                         iconName:@"table_ic_share_profile"];
        }
                                                       actionBlock:nil]];
    } else {
        [mainSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            return
                [weakSelf disclosureCellWithName:(NSLocalizedString(
                                                               @"CONVERSATION_SETTINGS_VIEW_SHARE_PROFILE_WITH_USER",
                                                               @"Action that shares user profile with a user."))
                                        iconName:@"table_ic_share_profile"];
        }
                                 actionBlock:^{
                                     [weakSelf showShareProfileAlert];
                                 }]];
    }

    // Block user section.

    BOOL isBlocked = [[_blockingManager blockedPhoneNumbers] containsObject:_recipientId];
    
    mainSection.footerTitle = NSLocalizedString(
        @"BLOCK_BEHAVIOR_EXPLANATION", @"An explanation of the consequences of blocking another user.");
    [mainSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
                                        UITableViewCell *cell =
                                        [weakSelf disclosureCellWithName:NSLocalizedString(@"CONVERSATION_SETTINGS_BLOCK_THIS_USER",
                                                                                           @"table cell label in conversation settings")
                                                                iconName:@"table_ic_block"];
                                        ContactDetailsViewController *strongSelf = weakSelf;
                                        OWSCAssert(strongSelf);
                                        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
                                        UISwitch *blockUserSwitch = [UISwitch new];
                                        blockUserSwitch.on = isBlocked;
                                        [blockUserSwitch addTarget:strongSelf
                                                            action:@selector(blockUserSwitchDidChange:)
                                                  forControlEvents:UIControlEventValueChanged];
                                        cell.accessoryView = blockUserSwitch;
                                        return cell;
                                    }
                                               actionBlock:nil]];

    [contents addSection:mainSection];
    
    OWSTableSection *buttonSection = [OWSTableSection new];
    [buttonSection addItem:[self destructiveButtonItemWithTitle:NSLocalizedString(@"GROUP_MEMBERS_SEND_MESSAGE",
                                                                            @"Button label for the 'send message to group member' button")
                                                      selector:@selector(newConversation)
                                                 ]];
    
    [contents addSection:buttonSection];
    
    self.contents = contents;
}

- (OWSTableItem *)destructiveButtonItemWithTitle:(NSString *)title selector:(SEL)selector
{
    return [OWSTableItem
        itemWithCustomCellBlock:^{
            UITableViewCell *cell = [OWSTableItem newCell];
            cell.preservesSuperviewLayoutMargins = YES;
            cell.contentView.preservesSuperviewLayoutMargins = YES;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            const CGFloat kButtonHeight = 40.f;
            OWSFlatButton *button = [OWSFlatButton buttonWithTitle:title
                                                              font:[OWSFlatButton fontForHeight:kButtonHeight]
                                                        titleColor:[UIColor whiteColor]
                                                   backgroundColor:[UIColor ows_signalBrandBlueColor]
                                                            target:self
                                                          selector:selector];
            [cell.contentView addSubview:button];
            [button autoSetDimension:ALDimensionHeight toSize:kButtonHeight];
            [button autoVCenterInSuperview];
            [button autoPinLeadingAndTrailingToSuperviewMargin];

            return cell;
        }
                customRowHeight:90.f
                    actionBlock:nil];
}

- (CGFloat)iconSpacing
{
    return 12.f;
}

- (UITableViewCell *)cellWithName:(NSString *)name iconName:(NSString *)iconName
{
    OWSAssert(iconName.length > 0);
    UIImageView *iconView = [self viewForIconWithName:iconName];
    return [self cellWithName:name iconView:iconView];
}

- (UITableViewCell *)cellWithName:(NSString *)name iconView:(UIView *)iconView
{
    OWSAssert(name.length > 0);

    UITableViewCell *cell = [UITableViewCell new];
    cell.preservesSuperviewLayoutMargins = YES;
    cell.contentView.preservesSuperviewLayoutMargins = YES;

    UILabel *rowLabel = [UILabel new];
    rowLabel.text = name;
    rowLabel.textColor = [UIColor blackColor];
    rowLabel.font = [UIFont ows_dynamicTypeBodyFont];
    rowLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    UIStackView *contentRow = [[UIStackView alloc] initWithArrangedSubviews:@[ iconView, rowLabel ]];
    contentRow.spacing = self.iconSpacing;

    [cell.contentView addSubview:contentRow];
    [contentRow autoPinEdgesToSuperviewMargins];

    return cell;
}

- (UITableViewCell *)disclosureCellWithName:(NSString *)name iconName:(NSString *)iconName
{
    UITableViewCell *cell = [self cellWithName:name iconName:iconName];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)labelCellWithName:(NSString *)name iconName:(NSString *)iconName
{
    UITableViewCell *cell = [self cellWithName:name iconName:iconName];
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (UIImageView *)viewForIconWithName:(NSString *)iconName
{
    UIImage *icon = [UIImage imageNamed:iconName];

    OWSAssert(icon);
    UIImageView *iconView = [UIImageView new];
    iconView.image = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    iconView.tintColor = [UIColor ows_darkIconColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    iconView.layer.minificationFilter = kCAFilterTrilinear;
    iconView.layer.magnificationFilter = kCAFilterTrilinear;

    [iconView autoSetDimensionsToSize:CGSizeMake(kIconViewLength, kIconViewLength)];

    return iconView;
}


- (UIView *)mainSectionHeader
{
    UIView *mainSectionHeader = [UIView new];
    UIView *contactInfoView = [UIView containerView];
    [mainSectionHeader addSubview:contactInfoView];
    [contactInfoView autoPinWidthToSuperviewWithMargin:16.f];
    [contactInfoView autoPinHeightToSuperviewWithMargin:16.f];

    const NSUInteger kAvatarSize = 68;
    UIImage *avatarImage =
        [OWSAvatarBuilder buildImageForThread:self.thread diameter:kAvatarSize contactsManager:self.contactsManager];
    OWSAssert(avatarImage);

    AvatarImageView *avatarView = [[AvatarImageView alloc] initWithImage:avatarImage];
    _avatarView = avatarView;
    [contactInfoView addSubview:avatarView];
    [avatarView autoVCenterInSuperview];
    [avatarView autoPinLeadingToSuperviewMargin];
    [avatarView autoSetDimension:ALDimensionWidth toSize:kAvatarSize];
    [avatarView autoSetDimension:ALDimensionHeight toSize:kAvatarSize];

    UIView *threadNameView = [UIView containerView];
    [contactInfoView addSubview:threadNameView];
    [threadNameView autoVCenterInSuperview];
    [threadNameView autoPinTrailingToSuperviewMargin];
    [threadNameView autoPinLeadingToTrailingEdgeOfView:avatarView offset:16.f];

    UILabel *threadTitleLabel = [UILabel new];
    threadTitleLabel.text = self.threadName;
    threadTitleLabel.textColor = [UIColor blackColor];
    threadTitleLabel.font = [UIFont ows_dynamicTypeTitle2Font];
    threadTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [threadNameView addSubview:threadTitleLabel];
    [threadTitleLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [threadTitleLabel autoPinWidthToSuperview];

    __block UIView *lastTitleView = threadTitleLabel;

        const CGFloat kSubtitlePointSize = 12.f;
        void (^addSubtitle)(NSAttributedString *) = ^(NSAttributedString *subtitle) {
            UILabel *subtitleLabel = [UILabel new];
            subtitleLabel.textColor = [UIColor ows_darkGrayColor];
            subtitleLabel.font = [UIFont ows_regularFontWithSize:kSubtitlePointSize];
            subtitleLabel.attributedText = subtitle;
            subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            [threadNameView addSubview:subtitleLabel];
            [subtitleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:lastTitleView];
            [subtitleLabel autoPinLeadingToSuperviewMargin];
            lastTitleView = subtitleLabel;
        };

        NSString *recipientId = self.thread.contactIdentifier;

        BOOL hasName = ![self.thread.name isEqualToString:recipientId];
        if (hasName) {
            NSString * subtitleString;
            SignalAccount* signalAccount = [self.contactsManager signalAccountForRecipientId:recipientId];
            if (signalAccount.remarkName.length > 0) {
                // 如果有备注，则需要将profilename显示
                NSString *_Nullable profileName = [self.contactsManager profileNameForRecipientId:recipientId];
                if (profileName.length > 0) {
                    subtitleString = [[NSString alloc]
                        initWithString:[NSString stringWithFormat:@"%@%@",
                            NSLocalizedString(@"CONTACT_PROFILENAME_DESCRIPTION_HEADER", @"Profile name description header"),
                            profileName]];
                    if (subtitleString.length > 0) {
                        addSubtitle([[NSAttributedString alloc] initWithString:subtitleString]);
                    }
                }
            }
            
            subtitleString = [[NSString alloc]
                initWithString:[NSString stringWithFormat:@"%@%@",
                    NSLocalizedString(@"CONTACT_NUMBER_DESCRIPTION_HEADER", @"Number header description header"),
                    [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:recipientId]]];
            
            addSubtitle([[NSAttributedString alloc] initWithString:subtitleString]);
        } else {
            NSString *_Nullable profileName = [self.contactsManager formattedProfileNameForRecipientId:recipientId];
            if (profileName) {
                addSubtitle([[NSAttributedString alloc] initWithString:profileName]);
            }
        }

        BOOL isVerified = [[OWSIdentityManager sharedManager] verificationStateForRecipientId:recipientId]
            == OWSVerificationStateVerified;
        if (isVerified) {
            NSMutableAttributedString *subtitle = [NSMutableAttributedString new];
            // "checkmark"
            [subtitle appendAttributedString:[[NSAttributedString alloc]
                                                 initWithString:@"\uf00c "
                                                     attributes:@{
                                                         NSFontAttributeName :
                                                             [UIFont ows_fontAwesomeFont:kSubtitlePointSize],
                                                     }]];
            [subtitle appendAttributedString:[[NSAttributedString alloc]
                                                 initWithString:NSLocalizedString(@"PRIVACY_IDENTITY_IS_VERIFIED_BADGE",
                                                                    @"Badge indicating that the user is verified.")]];
            addSubtitle(subtitle);
        }

    [lastTitleView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    [mainSectionHeader
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(conversationNameTouched:)]];
    mainSectionHeader.userInteractionEnabled = YES;

    return mainSectionHeader;
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];
}

#pragma mark Actions

- (void)showShareFlow
{
    NSString *_Nullable profileName = [self.contactsManager profileNameForRecipientId:_recipientId];

    NSString *shareNameCard = [[NSString alloc]
            initWithString:[NSString stringWithFormat:@"%@\n%@%@\n%@%@",
            NSLocalizedString(@"CONTACT_SHARE_DESCRIPTION_HEADER", @"Contact share description header"),
            NSLocalizedString(@"CONTACT_PROFILENAME_DESCRIPTION_HEADER", @"Profile name description header"),
            profileName,
            NSLocalizedString(@"CONTACT_NUMBER_DESCRIPTION_HEADER", @"Number description header"),
            _recipientId]];
    
    UIActivityViewController *activityController =
    [[UIActivityViewController alloc] initWithActivityItems:@[ shareNameCard ]
                                      applicationActivities:@[]];

    activityController.completionWithItemsHandler = ^void(UIActivityType __nullable activityType,
                                                          BOOL completed,
                                                          NSArray *__nullable returnedItems,
                                                          NSError *__nullable activityError) {
        if (completed)
        {
            
        }
    };

    [self presentViewController:activityController animated:YES completion:nil];
}


- (void)presentAddContactSheet
{
    NSString *recipientId = _recipientId;
    NSString *title =
        [NSString stringWithFormat:NSLocalizedString(@"ADD_OFFER_ACTIONSHEET_TITLE_FORMAT",
                                       @"Title format for action sheet that offers to add an unknown user."
                                       @"Embeds {{the unknown user's name or phone number}}."),
                  [BlockListUIUtils formatDisplayNameForAlertTitle:recipientId]];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheetController addAction:[OWSAlerts cancelAction]];

    UIAlertAction *blockAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(
                            @"ADD_OFFER_ACTIONSHEET_ADD_ACTION", @"Action sheet that will block an unknown user.")
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    DDLogInfo(@"%@ Adding an unknown user to contact list.", self.logTag);
                    // add user contact to contact list
                    NSString *fullName = [[OWSProfileManager sharedManager] profileNameForRecipientId:recipientId];
                    Contact * newContact = [[Contact alloc] initWithFullName:fullName phoneNumber:recipientId];
                    __weak ContactDetailsViewController *weakSelf = self;
                    [self.contactsManager addUnknownContact:newContact addSuccess:^(NSString * _Nonnull result) {
                        UIAlertController *alert = [UIAlertController
                            alertControllerWithTitle:NSLocalizedString(@"COMMON_NOTICE_TITLE", @"Alert view title")
                                             message:NSLocalizedString(result, @"Add contact result description")
                                      preferredStyle:UIAlertControllerStyleAlert];
                        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"")
                                                                  style:UIAlertActionStyleDefault
                                                                handler:nil
                                                                ]];

                        [weakSelf presentViewController:alert animated:YES completion:nil];
                    }];
                }];
    [actionSheetController addAction:blockAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)showShareProfileAlert
{
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];

    [OWSProfileManager.sharedManager presentAddThreadToProfileWhitelist:self.thread
                                                     fromViewController:self
                                                                success:^{
                                                                    [self updateTableContents];
                                                                }];
}


- (void)showVerificationView
{
    OWSAssert(_recipientId.length > 0);

    [FingerprintViewController presentFromViewController:self recipientId:_recipientId];
}

- (void)conversationNameTouched:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        if ([self hasExistingContact] && ![self isLocalNumber]) {
            // 点击名字，弹出修改界面
            [self presentContactInfoViewController];
        }
    }
}

- (void)blockUserSwitchDidChange:(id)sender
{
    if (![sender isKindOfClass:[UISwitch class]]) {
        OWSFail(@"%@ Unexpected sender for block user switch: %@", self.logTag, sender);
    }
    UISwitch *blockUserSwitch = (UISwitch *)sender;

    BOOL isCurrentlyBlocked = [[_blockingManager blockedPhoneNumbers] containsObject:self.thread.contactIdentifier];

    if (blockUserSwitch.isOn) {
        OWSAssert(!isCurrentlyBlocked);
        if (isCurrentlyBlocked) {
            return;
        }
        [BlockListUIUtils showBlockPhoneNumberActionSheet:self.thread.contactIdentifier
                                       fromViewController:self
                                          blockingManager:_blockingManager
                                          contactsManager:_contactsManager
                                          completionBlock:^(BOOL isBlocked) {
                                              // Update switch state if user cancels action.
                                              blockUserSwitch.on = isBlocked;
                                          }];
    } else {
        OWSAssert(isCurrentlyBlocked);
        if (!isCurrentlyBlocked) {
            return;
        }
        [BlockListUIUtils showUnblockPhoneNumberActionSheet:self.thread.contactIdentifier
                                         fromViewController:self
                                            blockingManager:_blockingManager
                                            contactsManager:_contactsManager
                                            completionBlock:^(BOOL isBlocked) {
                                                // Update switch state if user cancels action.
                                                blockUserSwitch.on = isBlocked;
                                            }];
    }
}

- (void)newConversation
{
    OWSAssert(_thread);

    [SignalApp.sharedApp presentConversationForThread:_thread action:ConversationViewActionCompose];
}


@end

NS_ASSUME_NONNULL_END
