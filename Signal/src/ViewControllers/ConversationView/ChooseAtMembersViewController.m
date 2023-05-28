//
//  ChooseAtMembersViewController.m
//  Signal
//
//  Created by 宋立仙 on 2021/6/2.
//

#import "ChooseAtMembersViewController.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import "ViewControllerUtils.h"
#import <SignalMessaging/BlockListUIUtils.h>
#import <SignalMessaging/ContactTableViewCell.h>
#import <SignalMessaging/ContactsViewHelper.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSGroupThread.h>


@import ContactsUI;

NS_ASSUME_NONNULL_BEGIN
@interface ChooseAtMembersViewController () <UISearchBarDelegate>

@property (nonatomic, readonly) TSGroupThread *thread;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;
@property (nonatomic, readonly) ConversationSearcher *conversationSearcher;

@property (nonatomic, nullable) NSSet<NSString *> *memberRecipientIds;

@property (nonatomic, strong) UISearchBar *searchBar;

@end

@implementation ChooseAtMembersViewController
+ (ChooseAtMembersViewController *)presentFromViewController:(UIViewController *)viewController thread:(TSGroupThread *)thread delegate:(id<ChooseAtMembersViewControllerDelegate>) theDelegate
{
    OWSAssert(thread);
    ChooseAtMembersViewController *vc = [ChooseAtMembersViewController new];
    [vc configWithThread:thread];
    vc.resultDelegate = theDelegate;
    OWSNavigationController *navigationController =
        [[OWSNavigationController alloc] initWithRootViewController:vc];
    [viewController presentViewController:navigationController animated:YES completion:nil];
    return vc;
}
- (void)dismissVC
{
    [self dismissViewControllerAnimated:YES completion:nil];
    if ([self.resultDelegate respondsToSelector:@selector(chooseAtPeronsCancel)]) {
        [self.resultDelegate chooseAtPeronsCancel];
    }
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


- (void)commonInit
{
    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];
    _conversationSearcher = ConversationSearcher.shared;

    [self observeNotifications];
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

- (void)configWithThread:(TSGroupThread *)thread
{

    _thread = thread;

    OWSAssert(self.thread);
    OWSAssert(self.thread.groupModel);
    OWSAssert(self.thread.groupModel.groupMemberIds);

    self.memberRecipientIds = [NSSet setWithArray:self.thread.groupModel.groupMemberIds];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(dismissVC)];
    OWSAssert([self.navigationController isKindOfClass:[OWSNavigationController class]]);

    self.title = NSLocalizedString(@"LIST_GROUP_MEMBERS_ACTION", @"title for show group members view");
    
    [self configUI];

    [self updateTableContents];
}

- (void)configUI {
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 45;
    
    UISearchBar *searchBar = [UISearchBar new];
    _searchBar = searchBar;
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    // TODO: 修改搜索框 placeholder
    searchBar.placeholder = NSLocalizedString(@"HOME_VIEW_CONVERSATION_SEARCHBAR_PLACEHOLDER",
        @"Placeholder text for search bar which filters @ contracts.");
    searchBar.backgroundColor = UIColor.ows_themeBackgroundColor;
    if (UIColor.isThemeEnabled) {
        searchBar.barStyle = UIBarStyleBlack;
    } else {
        searchBar.barStyle = UIBarStyleDefault;
    }

    searchBar.delegate = self;
    [searchBar sizeToFit];

    self.tableView.tableHeaderView = searchBar;
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSAssert(self.thread);

    OWSTableContents *contents = [OWSTableContents new];

    __weak ChooseAtMembersViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;

    OWSTableSection *membersSection = [OWSTableSection new];
    
    NSString *searchText = [self.searchBar text];
    BOOL hasSearchText = searchText.length > 0;
    
    if (hasSearchText) {
        // Group Members

        // If there are "no longer verified" members of the group,
        // highlight them in a special section.
        NSArray<NSString *> *noLongerVerifiedRecipientIds = [self noLongerVerifiedRecipientIds];
        
        NSMutableArray<SignalAccount *> *noLongerVerifiedAccounts = @[].mutableCopy;
        for (NSString *noLongerVerifiedRecipientId in noLongerVerifiedRecipientIds) {
            SignalAccount *account = [self.contactsViewHelper signalAccountForRecipientId: noLongerVerifiedRecipientId];
            if (account) { [noLongerVerifiedAccounts addObject:account]; }
        }
        
        if (noLongerVerifiedAccounts.count > 0) {
            NSArray<SignalAccount *> *filtedNoLongerVerifiedAccounts = [self.conversationSearcher filterSignalAccounts:noLongerVerifiedAccounts withSearchText:searchText];
            
            OWSTableSection *noLongerVerifiedSection = [OWSTableSection new];
            noLongerVerifiedSection.headerTitle = NSLocalizedString(@"GROUP_MEMBERS_SECTION_TITLE_NO_LONGER_VERIFIED",
                @"Title for the 'no longer verified' section of the 'group members' view.");
            membersSection.headerTitle = NSLocalizedString(
                @"GROUP_MEMBERS_SECTION_TITLE_MEMBERS", @"Title for the 'members' section of the 'group members' view.");
            [noLongerVerifiedSection
                addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"GROUP_MEMBERS_RESET_NO_LONGER_VERIFIED",
                                                                 @"Label for the button that clears all verification "
                                                                 @"errors in the 'group members' view.")
                                             customRowHeight:UITableViewAutomaticDimension
                                                 actionBlock:^{
                                                     [weakSelf offerResetAllNoLongerVerified];
                                                 }]];
            [self addMembers:filtedNoLongerVerifiedAccounts toSection:noLongerVerifiedSection useVerifyAction:YES];
            [contents addSection:noLongerVerifiedSection];
        }

        NSMutableSet *memberRecipientIds = [self.memberRecipientIds mutableCopy];
        [memberRecipientIds removeObject:[helper localNumber]];
        
        NSMutableArray<SignalAccount *> *memberAccounts = @[].mutableCopy;
        for (NSString *member in memberRecipientIds) {
            SignalAccount *account = [self.contactsViewHelper signalAccountForRecipientId: member];
            if (account) { [memberAccounts addObject:account]; }
        }
        
        if (memberAccounts.count > 0) {
            NSArray<SignalAccount *> *filtedMemberAccounts = [self.conversationSearcher filterSignalAccounts:memberAccounts withSearchText:searchText];
            
            [self addMembers:filtedMemberAccounts toSection:membersSection useVerifyAction:NO];
        }
        
        [contents addSection:membersSection];
    } else {
        // Group Members

        // If there are "no longer verified" members of the group,
        // highlight them in a special section.
        NSArray<NSString *> *noLongerVerifiedRecipientIds = [self noLongerVerifiedRecipientIds];
        
        NSMutableArray<SignalAccount *> *noLongerVerifiedAccounts = @[].mutableCopy;
        for (NSString *noLongerVerifiedRecipientId in noLongerVerifiedRecipientIds) {
            SignalAccount *account = [self.contactsViewHelper signalAccountForRecipientId: noLongerVerifiedRecipientId];
            if (account) { [noLongerVerifiedAccounts addObject:account]; }
        }
        
        if (noLongerVerifiedAccounts.count > 0) {
            OWSTableSection *noLongerVerifiedSection = [OWSTableSection new];
            noLongerVerifiedSection.headerTitle = NSLocalizedString(@"GROUP_MEMBERS_SECTION_TITLE_NO_LONGER_VERIFIED",
                @"Title for the 'no longer verified' section of the 'group members' view.");
            membersSection.headerTitle = NSLocalizedString(
                @"GROUP_MEMBERS_SECTION_TITLE_MEMBERS", @"Title for the 'members' section of the 'group members' view.");
            [noLongerVerifiedSection
                addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"GROUP_MEMBERS_RESET_NO_LONGER_VERIFIED",
                                                                 @"Label for the button that clears all verification "
                                                                 @"errors in the 'group members' view.")
                                             customRowHeight:UITableViewAutomaticDimension
                                                 actionBlock:^{
                                                     [weakSelf offerResetAllNoLongerVerified];
                                                 }]];
            [self addMembers:noLongerVerifiedAccounts toSection:noLongerVerifiedSection useVerifyAction:YES];
            [contents addSection:noLongerVerifiedSection];
        }

        NSMutableSet *memberRecipientIds = [self.memberRecipientIds mutableCopy];
        [memberRecipientIds removeObject:[helper localNumber]];
        
        NSMutableArray<SignalAccount *> *memberAccounts = @[].mutableCopy;
        for (NSString *member in memberRecipientIds) {
            SignalAccount *account = [self.contactsViewHelper signalAccountForRecipientId: member];
            if (account) { [memberAccounts addObject:account]; }
        }
            
        [self addMembers:memberAccounts toSection:membersSection useVerifyAction:NO];
        [contents addSection:membersSection];
    }

    self.contents = contents;
}

- (void)addMembers:(NSArray<SignalAccount *> *)accounts
          toSection:(OWSTableSection *)section
    useVerifyAction:(BOOL)useVerifyAction
{
    OWSAssert(accounts);
    OWSAssert(section);

    __weak ChooseAtMembersViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;
    // Sort the group members using contacts manager.
    NSArray<SignalAccount *> *sortedAccounts =
        [accounts sortedArrayUsingComparator:^NSComparisonResult(SignalAccount *signalAccountA, SignalAccount *signalAccountB) {
            return [helper.contactsManager compareSignalAccount:signalAccountA withSignalAccount:signalAccountB];
        }];
    for (SignalAccount *signalAccount in sortedAccounts) {
        [section addItem:[OWSTableItem
                          itemWithCustomCellBlock:^{
                                                    ChooseAtMembersViewController *strongSelf = weakSelf;
                                                    OWSCAssert(strongSelf);
                                                    
                                                    ContactTableViewCell *cell = [ContactTableViewCell new];
                                                    OWSVerificationState verificationState =
                                                    [[OWSIdentityManager sharedManager] verificationStateForRecipientId:signalAccount.recipientId];
                                                    BOOL isVerified = verificationState == OWSVerificationStateVerified;
                                                    BOOL isNoLongerVerified = verificationState == OWSVerificationStateNoLongerVerified;
                                                    BOOL isBlocked = [helper isRecipientIdBlocked:signalAccount.recipientId];
                                                    if (isNoLongerVerified) {
                                                        cell.accessoryMessage = NSLocalizedString(@"CONTACT_CELL_IS_NO_LONGER_VERIFIED",
                                                                                                  @"An indicator that a contact is no longer verified.");
                                                    } else if (isBlocked) {
                                                        cell.accessoryMessage = NSLocalizedString(
                                                                                                  @"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
                                                    }
                                                    
                                                    if (signalAccount) {
                                                        [cell configureWithSignalAccount:signalAccount
                                                                         contactsManager:strongSelf.contactsViewHelper.contactsManager];
                                                    } else {
                                                        [cell configureWithRecipientId:signalAccount.recipientId contactsManager:strongSelf.contactsViewHelper.contactsManager];
                                                    }
                                                    
                                                    if (isVerified) {
                                                        [cell setAttributedSubtitle:cell.verifiedSubtitle];
                                                    } else {
                                                        [cell setAttributedSubtitle:nil];
                                                    }
                                                    
                                                    return cell;
                                                    }
                          customRowHeight:UITableViewAutomaticDimension
                          actionBlock:^{
                                        NSString *nameDisplay = [weakSelf.contactsViewHelper.contactsManager nameFromSystemContactsForRecipientId:signalAccount.recipientId];
                                        if ([weakSelf.resultDelegate respondsToSelector:@selector(chooseAtPeronsDidSelectRecipientId:name:)]) {
                                            [weakSelf.resultDelegate chooseAtPeronsDidSelectRecipientId:signalAccount.recipientId name:nameDisplay];
                                        }
        }]];
    }
}

- (void)offerResetAllNoLongerVerified
{
    OWSAssertIsOnMainThread();

    UIAlertController *actionSheetController = [UIAlertController
        alertControllerWithTitle:nil
                         message:NSLocalizedString(@"GROUP_MEMBERS_RESET_NO_LONGER_VERIFIED_ALERT_MESSAGE",
                                     @"Label for the 'reset all no-longer-verified group members' confirmation alert.")
                  preferredStyle:UIAlertControllerStyleAlert];

    __weak ChooseAtMembersViewController *weakSelf = self;
    UIAlertAction *verifyAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                           style:UIAlertActionStyleDestructive
                                                         handler:^(UIAlertAction *_Nonnull action) {
                                                             [weakSelf resetAllNoLongerVerified];
                                                         }];
    [actionSheetController addAction:verifyAction];
    [actionSheetController addAction:[OWSAlerts cancelAction]];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)resetAllNoLongerVerified
{
    OWSAssertIsOnMainThread();

    OWSIdentityManager *identityManger = [OWSIdentityManager sharedManager];
    NSArray<NSString *> *recipientIds = [self noLongerVerifiedRecipientIds];
    for (NSString *recipientId in recipientIds) {
        OWSVerificationState verificationState = [identityManger verificationStateForRecipientId:recipientId];
        if (verificationState == OWSVerificationStateNoLongerVerified) {
            NSData *identityKey = [identityManger identityKeyForRecipientId:recipientId];
            if (identityKey.length < 1) {
                OWSFail(@"Missing identity key for: %@", recipientId);
                continue;
            }
            [identityManger setVerificationState:OWSVerificationStateDefault
                                     identityKey:identityKey
                                     recipientId:recipientId
                           isUserInitiatedChange:YES];
        }
    }

    [self updateTableContents];
}

// Returns a collection of the group members who are "no longer verified".
- (NSArray<NSString *> *)noLongerVerifiedRecipientIds
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    for (NSString *recipientId in self.thread.recipientIdentifiers) {
        if ([[OWSIdentityManager sharedManager] verificationStateForRecipientId:recipientId]
            == OWSVerificationStateNoLongerVerified) {
            [result addObject:recipientId];
        }
    }
    return [result copy];
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];
}

- (BOOL)shouldHideLocalNumber
{
    return YES;
}

#pragma mark - Notifications

- (void)identityStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateTableContents];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [self searchTextDidChange];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [self searchTextDidChange];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [self searchTextDidChange];
}

- (void)searchBarResultsListButtonClicked:(UISearchBar *)searchBar
{
    [self searchTextDidChange];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope
{
    [self searchTextDidChange];
}

- (void)searchTextDidChange
{
//    [self updateSearchPhoneNumbers];

    [self updateTableContents];
}

@end

NS_ASSUME_NONNULL_END
