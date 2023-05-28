//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AppSettingsViewController.h"
#import "AboutTableViewController.h"
#import "AdvancedSettingsTableViewController.h"
#import "DebugUITableViewController.h"
#import "NotificationSettingsViewController.h"
#import "OWSBackup.h"
#import "OWSBackupSettingsViewController.h"
#import "OWSLinkedDevicesTableViewController.h"
#import "OWSNavigationController.h"
#import "PrivacySettingsTableViewController.h"
#import "ProfileViewController.h"
#import "PushManager.h"
#import "RegistrationUtils.h"
#import "Signal-Swift.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSSocketManager.h>

@interface AppSettingsViewController ()

@property (nonatomic, readonly) OWSContactsManager *contactsManager;

@end

#pragma mark -

@implementation AppSettingsViewController

/**
 * We always present the settings controller modally, from within an OWSNavigationController
 */
+ (OWSNavigationController *)inModalNavigationController
{
    AppSettingsViewController *viewController = [AppSettingsViewController new];
    OWSNavigationController *navController =
        [[OWSNavigationController alloc] initWithRootViewController:viewController];

    return navController;
}

+ (OWSNavigationController *)inNormalNavigationController
{
    AppSettingsViewController *viewController = [AppSettingsViewController new];
    viewController.modalPresentationStyle = UIModalPresentationFullScreen;
    OWSNavigationController *navController =
        [[OWSNavigationController alloc] initWithRootViewController:viewController];

    return navController;
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _contactsManager = [Environment current].contactsManager;

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _contactsManager = [Environment current].contactsManager;

    return self;
}

- (void)loadView
{
    self.tableViewStyle = UITableViewStylePlain;
    [super loadView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationItem setHidesBackButton:YES];

    OWSAssert([self.navigationController isKindOfClass:[OWSNavigationController class]]);

//    self.navigationItem.leftBarButtonItem =
//        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
//                                                      target:self
//                                                      action:@selector(dismissWasPressed:)];

    [self observeNotifications];

    self.title = NSLocalizedString(@"SETTINGS_NAV_BAR_TITLE", @"Title for settings activity");

    [self updateTableContents];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self updateTableContents];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak AppSettingsViewController *weakSelf = self;

#ifdef INTERNAL
    OWSTableSection *internalSection = [OWSTableSection new];
    [section addItem:[OWSTableItem softCenterLabelItemWithText:@"Internal Build"]];
    [contents addSection:internalSection];
#endif

    OWSTableSection *section = [OWSTableSection new];
    [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
        return [weakSelf profileHeaderCell];
    }
                         customRowHeight:100.f
                         actionBlock:^{
                             [weakSelf showProfile];
                         }]];

    if (OWSSignalService.sharedInstance.isCensorshipCircumventionActive) {
        [section
            addItem:[OWSTableItem disclosureItemWithText:
                                      NSLocalizedString(@"NETWORK_STATUS_CENSORSHIP_CIRCUMVENTION_ACTIVE",
                                          @"Indicates to the user that censorship circumvention has been activated.")
                                             actionBlock:^{
                                                 [weakSelf showAdvanced];
                                             }]];
    } else {
        [section addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 UITableViewCell *cell = [OWSTableItem newCell];
                                 cell.textLabel.text = NSLocalizedString(@"NETWORK_STATUS_HEADER", @"");
                                 cell.selectionStyle = UITableViewCellSelectionStyleNone;
                                 UILabel *accessoryLabel = [UILabel new];
                                 accessoryLabel.font = [UIFont ows_regularFontWithSize:18.f];
                                 if (TSAccountManager.sharedInstance.isDeregistered) {
                                     accessoryLabel.text = NSLocalizedString(@"NETWORK_STATUS_DEREGISTERED",
                                         @"Error indicating that this device is no longer registered.");
                                     accessoryLabel.textColor = [UIColor ows_redColor];
                                 } else {
                                     switch ([TSSocketManager sharedManager].state) {
                                         case SocketManagerStateClosed:
                                             accessoryLabel.text = NSLocalizedString(@"NETWORK_STATUS_OFFLINE", @"");
                                             accessoryLabel.textColor = [UIColor ows_redColor];
                                             break;
                                         case SocketManagerStateConnecting:
                                             accessoryLabel.text = NSLocalizedString(@"NETWORK_STATUS_CONNECTING", @"");
                                             accessoryLabel.textColor = [UIColor ows_yellowColor];
                                             break;
                                         case SocketManagerStateOpen:
                                             accessoryLabel.text = NSLocalizedString(@"NETWORK_STATUS_CONNECTED", @"");
                                             accessoryLabel.textColor = [UIColor ows_greenColor];
                                             break;
                                     }
                                 }
                                 [accessoryLabel sizeToFit];
                                 cell.accessoryView = accessoryLabel;
                                 return cell;
                             }
                                         actionBlock:nil]];
    }
    
    // added: add share contact card button
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_SHARE_YOUR_CONTACT_CARD_TITLE",
                                                              @"Settings table view cell label")
                                              actionBlock:^{
                                                  [weakSelf showShareFlow];
                                              }]];
    
    // added: add invite friends button
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_INVITE_TITLE",
                                                              @"Settings table view cell label")
                                              actionBlock:^{
                                                  [weakSelf showInviteFlow];
                                              }]];
    
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_PRIVACY_TITLE",
                                                              @"Settings table view cell label")
                                              actionBlock:^{
                                                  [weakSelf showPrivacy];
                                              }]];
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_NOTIFICATIONS", nil)
                                              actionBlock:^{
                                                  [weakSelf showNotifications];
                                              }]];
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"LINKED_DEVICES_TITLE",
                                                              @"Menu item and navbar title for the device manager")
                                              actionBlock:^{
                                                  [weakSelf showLinkedDevices];
                                              }]];
    
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_ADVANCED_TITLE", @"")
                                              actionBlock:^{
                                                  [weakSelf showAdvanced];
                                              }]];
    // Show backup UI in debug builds OR if backup has already been enabled.
    //
    // NOTE: Backup format is not yet finalized and backups are not yet
    //       properly encrypted, so these debug backups should only be
    //       done on test devices and will not be usable if/when we ship
    //       backup to production.
    //
    // TODO: Always show backup when we go to production.
    BOOL isBackupEnabled = [OWSBackup.sharedManager isBackupEnabled];
    BOOL showBackup = isBackupEnabled;
#ifdef DEBUG
    // changed: hide backup button
    showBackup = NO;
#endif
    if (showBackup) {
        [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_BACKUP",
                                                                  @"Label for the backup view in app settings.")
                                                  actionBlock:^{
                                                      [weakSelf showBackup];
                                                  }]];
    }
    [section addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"SETTINGS_ABOUT", @"")
                                              actionBlock:^{
                                                  [weakSelf showAbout];
                                              }]];

#ifdef USE_DEBUG_UI
    [section addItem:[OWSTableItem disclosureItemWithText:@"Debug UI"
                                              actionBlock:^{
                                                  [weakSelf showDebugUI];
                                              }]];
#endif

    if (TSAccountManager.sharedInstance.isDeregistered) {
        [section addItem:[self destructiveButtonItemWithTitle:NSLocalizedString(@"SETTINGS_REREGISTER_BUTTON",
                                                                  @"Label for re-registration button.")
                                                     selector:@selector(reregisterUser)
                                                        color:[UIColor ows_materialBlueColor]]];
        [section addItem:[self destructiveButtonItemWithTitle:NSLocalizedString(@"SETTINGS_DELETE_DATA_BUTTON",
                                                                  @"Label for 'delete data' button.")
                                                     selector:@selector(deleteUnregisterUserData)
                                                        color:[UIColor ows_destructiveRedColor]]];
    } else {
        [section addItem:[self destructiveButtonItemWithTitle:NSLocalizedString(@"SETTINGS_DELETE_ACCOUNT_BUTTON", @"")
                                                     selector:@selector(unregisterUser)
                                                        color:[UIColor ows_destructiveRedColor]]];
    }

    [contents addSection:section];

    self.contents = contents;
}

- (OWSTableItem *)destructiveButtonItemWithTitle:(NSString *)title selector:(SEL)selector color:(UIColor *)color
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
                                                   backgroundColor:color
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

- (UITableViewCell *)profileHeaderCell
{
    UITableViewCell *cell = [OWSTableItem newCell];
    cell.preservesSuperviewLayoutMargins = YES;
    cell.contentView.preservesSuperviewLayoutMargins = YES;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    const NSUInteger kAvatarSize = 68;
    // TODO: Replace this icon.
    UIImage *_Nullable localProfileAvatarImage = [OWSProfileManager.sharedManager localProfileAvatarImage];
    UIImage *avatarImage = (localProfileAvatarImage
            ?: [[UIImage imageNamed:@"profile_avatar_default"]
                   imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]);
    OWSAssert(avatarImage);

    AvatarImageView *avatarView = [[AvatarImageView alloc] initWithImage:avatarImage];
    if (!localProfileAvatarImage) {
        avatarView.tintColor = [UIColor colorWithRGBHex:0x888888];
    }
    [cell.contentView addSubview:avatarView];
    [avatarView autoVCenterInSuperview];
    [avatarView autoPinLeadingToSuperviewMargin];
    [avatarView autoSetDimension:ALDimensionWidth toSize:kAvatarSize];
    [avatarView autoSetDimension:ALDimensionHeight toSize:kAvatarSize];

    if (!localProfileAvatarImage) {
        UIImage *cameraImage = [UIImage imageNamed:@"settings-avatar-camera"];
        UIImageView *cameraImageView = [[UIImageView alloc] initWithImage:cameraImage];
        [cell.contentView addSubview:cameraImageView];
        [cameraImageView autoPinTrailingToEdgeOfView:avatarView];
        [cameraImageView autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:avatarView];
    }

    UIView *nameView = [UIView containerView];
    [cell.contentView addSubview:nameView];
    [nameView autoVCenterInSuperview];
    [nameView autoPinLeadingToTrailingEdgeOfView:avatarView offset:16.f];

    UILabel *titleLabel = [UILabel new];
    NSString *_Nullable localProfileName = [OWSProfileManager.sharedManager localProfileName];
    if (localProfileName.length > 0) {
        titleLabel.text = localProfileName;
        titleLabel.textColor = [UIColor ows_themeForegroundColor];
        titleLabel.font = [UIFont ows_dynamicTypeTitle2Font];
    } else {
        titleLabel.text = NSLocalizedString(
            @"APP_SETTINGS_EDIT_PROFILE_NAME_PROMPT", @"Text prompting user to edit their profile name.");
        titleLabel.textColor = [UIColor ows_materialBlueColor];
        titleLabel.font = [UIFont ows_dynamicTypeHeadlineFont];
    }
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [nameView addSubview:titleLabel];
    [titleLabel autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [titleLabel autoPinWidthToSuperview];

    const CGFloat kSubtitlePointSize = 12.f;
    UILabel *subtitleLabel = [UILabel new];
    subtitleLabel.textColor = [UIColor ows_themeSecondaryColor];
    subtitleLabel.font = [UIFont ows_regularFontWithSize:kSubtitlePointSize];
    subtitleLabel.attributedText = [[NSAttributedString alloc]
        initWithString:[PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:[TSAccountManager
                                                                                                       localNumber]]];
    subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [nameView addSubview:subtitleLabel];
    [subtitleLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:titleLabel];
    [subtitleLabel autoPinLeadingToSuperviewMargin];
    [subtitleLabel autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    UIImage *disclosureImage = [UIImage imageNamed:(CurrentAppContext().isRTL ? @"NavBarBack" : @"NavBarBackRTL")];
    OWSAssert(disclosureImage);
    UIImageView *disclosureButton =
        [[UIImageView alloc] initWithImage:[disclosureImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    disclosureButton.tintColor = [UIColor colorWithRGBHex:0xcccccc];
    [cell.contentView addSubview:disclosureButton];
    [disclosureButton autoVCenterInSuperview];
    [disclosureButton autoPinTrailingToSuperviewMargin];
    [disclosureButton autoPinLeadingToTrailingEdgeOfView:nameView offset:16.f];
    [disclosureButton setContentCompressionResistancePriority:(UILayoutPriorityDefaultHigh + 1)
                                                      forAxis:UILayoutConstraintAxisHorizontal];

    return cell;
}

- (void)presentAlertWithErrorDescription:(NSString *)description
{
    UIAlertController *alert;
    alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"COMMON_NOTICE_TITLE", @"Alert view title")
                         message:description
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                // do nothing
                                            }]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showInviteFlow
{
    DDLogDebug(@"%@ Inviting friends", self.logTag);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(void) {
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            // get invite code
            [[TSAccountManager sharedInstance] getInviteCodeSuccess:^(id responseObject){
                BOOL        codeFormatOk = FALSE;
                NSString    *inviteCode  = nil;
                // invite code chars must be in 0-9,a-z,A-Z with fixed length 32.
                NSUInteger  fixedCodeLen = 32;
                NSNumber    *remained    = nil;
                NSNumber    *total       = nil;
                
                do {
                    if (![responseObject isKindOfClass:[NSDictionary class]]) {
                        DDLogError(@"%@ Failed retrieval of invite code. Response had unexpected format.", self.logTag);
                        break;
                    }
                    
                        inviteCode = [(NSDictionary *)responseObject objectForKey:@"code"];
                    if (!inviteCode) {
                        DDLogError(@"%@ Failed retrieval of invite code. Response had no code.", self.logTag);
                        break;
                    }
                
                    // trim invite code whitespace and newline
                    inviteCode = [inviteCode stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (0 < inviteCode.length && fixedCodeLen != inviteCode.length) {
                        DDLogError(@"%@ Error format of invite code: %@", self.logTag, inviteCode);
                        break;
                    }

                    total = [(NSDictionary *)responseObject objectForKey:@"total"];
                    if (!total) {
                        DDLogError(@"%@ Failed retrieval of invite code. Response had no total.", self.logTag);
                        break;
                    }
                    
                    remained = [(NSDictionary *)responseObject objectForKey:@"remaining"];
                    if (!remained) {
                        DDLogError(@"%@ Failed retrieval of invite code. Response had no remaining.", self.logTag);
                        break;
                    }
                    codeFormatOk = TRUE;
                } while (FALSE);
                
                __weak AppSettingsViewController *weakSelf = self;

                if (FALSE == codeFormatOk) {
                    // invite code format is incorrect.
                    [weakSelf presentAlertWithErrorDescription:OWSErrorMakeUnableToProcessServerResponseError().localizedDescription];
                } else if ([remained isEqualToNumber:[NSNumber numberWithInt:0]] && inviteCode.length == 0) {
                    // there is no more avaliable invite code.
                    [weakSelf presentAlertWithErrorDescription:NSLocalizedString(@"SETTINGS_NO_MORE_INVITE_CODE", @"Invite code")];
                } else {
                    // got invite code successfully.
                    NSString* inviteMessage = [[NSString alloc] initWithString:[NSString stringWithFormat:@"安全沟通 ：https://Chative.optillel.com \n您的邀请码为：%@", inviteCode]];
                    UIActivityViewController *activityController =
                    [[UIActivityViewController alloc] initWithActivityItems:@[ inviteMessage ]
                                                      applicationActivities:@[]];
                    
                    activityController.completionWithItemsHandler = ^void(UIActivityType __nullable activityType,
                                                                          BOOL completed,
                                                                          NSArray *__nullable returnedItems,
                                                                          NSError *__nullable activityError) {
                        // complete handler
                        DDLogDebug(@"share result:%d", completed);
                    };
                    
                    [weakSelf presentViewController:activityController animated:YES completion:nil];
                }
            } failure:^(NSError *error){
                // should be network problems.
                __weak AppSettingsViewController *weakSelf = self;
                [weakSelf presentAlertWithErrorDescription:error.localizedDescription];
            }];
        });
    });
 
    //InviteFriendsViewController *vc = [[InviteFriendsViewController alloc] init];
    //[self.navigationController pushViewController:vc animated:YES];
}

- (void)showShareFlow
{
    NSString *localNumber = [TSAccountManager localNumber];
    NSString *_Nullable showName = [OWSProfileManager.sharedManager localProfileName];
    
    if (showName.length <= 0)
    {
        // should set profile name if there is not one.
        UIAlertController *alertController = [UIAlertController
                                              alertControllerWithTitle:NSLocalizedString(@"COMMON_NOTICE_TITLE", @"Alert view title")
                                              message:NSLocalizedString(@"SETTINGS_NO_PROFILE_NAME", @"No profile name")
                                              preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction
                                   actionWithTitle:NSLocalizedString(@"OK", @"")
                                   style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action) {
                                       [self showProfile];
                                   }];
        
        [alertController addAction:[OWSAlerts cancelAction]];
        [alertController addAction:okAction];
        
        [self presentViewController:alertController animated:YES completion:nil];
        
        return;
    }
    
    NSString *shareNameCard = [[NSString alloc]
        initWithString:[NSString stringWithFormat:@"%@\n%@%@\n%@%@",
            NSLocalizedString(@"CONTACT_SHARE_MYSELF_DESCRIPTION_HEADER", @"Share myself contact card decription header"),
            NSLocalizedString(@"CONTACT_PROFILENAME_DESCRIPTION_HEADER", @"Profile name description header"),
            showName,
            NSLocalizedString(@"CONTACT_NUMBER_DESCRIPTION_HEADER", @"Number description header"),
            localNumber]];

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

- (void)showPrivacy
{
    PrivacySettingsTableViewController *vc = [[PrivacySettingsTableViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showNotifications
{
    NotificationSettingsViewController *vc = [[NotificationSettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showLinkedDevices
{
    OWSLinkedDevicesTableViewController *vc =
        [[UIStoryboard main] instantiateViewControllerWithIdentifier:@"OWSLinkedDevicesTableViewController"];
    vc.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showProfile
{
    [ProfileViewController presentForAppSettings:self.navigationController];
}

- (void)showAdvanced
{
    AdvancedSettingsTableViewController *vc = [[AdvancedSettingsTableViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAbout
{
    AboutTableViewController *vc = [[AboutTableViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showBackup
{
    OWSBackupSettingsViewController *vc = [OWSBackupSettingsViewController new];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showDebugUI
{
    [DebugUITableViewController presentDebugUIFromViewController:self];
}

- (void)dismissWasPressed:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Unregister & Re-register

- (void)unregisterUser
{
    [self showDeleteAccountUI:YES];
}

- (void)deleteUnregisterUserData
{
    [self showDeleteAccountUI:NO];
}

- (void)showDeleteAccountUI:(BOOL)isRegistered
{
    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"CONFIRM_ACCOUNT_DESTRUCTION_TITLE", @"")
                                            message:NSLocalizedString(@"CONFIRM_ACCOUNT_DESTRUCTION_TEXT", @"")
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"PROCEED_BUTTON", @"")
                                                        style:UIAlertActionStyleDestructive
                                                      handler:^(UIAlertAction *action) {
                                                          [self deleteAccount:isRegistered];
                                                      }]];
    [alertController addAction:[OWSAlerts cancelAction]];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)deleteAccount:(BOOL)isRegistered
{
    if (isRegistered) {
        [ModalActivityIndicatorViewController
            presentFromViewController:self
                            canCancel:NO
                      backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                          [TSAccountManager
                              unregisterTextSecureWithSuccess:^{
                                  [SignalApp resetAppData];
                              }
                              failure:^(NSError *error) {
                                  dispatch_async(dispatch_get_main_queue(), ^{
                                      [modalActivityIndicator dismissWithCompletion:^{
                                          [OWSAlerts
                                              showAlertWithTitle:NSLocalizedString(@"UNREGISTER_SIGNAL_FAIL", @"")];
                                      }];
                                  });
                              }];
                      }];
    } else {
        [SignalApp resetAppData];
    }
}

- (void)reregisterUser
{
    [RegistrationUtils showReregistrationUIFromViewController:self];
}

#pragma mark - Socket Status Notifications

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(socketStateDidChange)
                                                 name:kNSNotification_SocketManagerStateDidChange
                                               object:nil];
}

- (void)socketStateDidChange
{
    OWSAssertIsOnMainThread();

    [self updateTableContents];
}

-(BOOL)hidesBottomBarWhenPushed
{
    return NO;
}

@end
