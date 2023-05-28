//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "InviteRegistrationViewController.h"
#import "RegistrationViewController.h"
#import "CodeVerificationViewController.h"
#import "PhoneNumber.h"
#import "PhoneNumberUtil.h"
#import "Signal-Swift.h"
#import "TSAccountManager.h"
#import "UIView+OWS.h"
#import "ViewControllerUtils.h"
#import <SAMKeychain/SAMKeychain.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/NSString+OWS.h>
#import <SignalMessaging/OWSNavigationController.h>


#import <PromiseKit/AnyPromise.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSNetworkManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface InviteRegistrationViewController () <UITextFieldDelegate>

@property (nonatomic, readonly) AccountManager *accountManager;

@property (nonatomic) NSString *inviteCode;
@property (nonatomic) BOOL isDisplaying;

@property (nonatomic) UITextField *inviteCodeTextField;
@property (nonatomic) OWSFlatButton *activateButton;
@property (nonatomic) OWSFlatButton *switchButton;
@property (nonatomic) UIActivityIndicatorView *spinnerView;

@end

#pragma mark -

@implementation InviteRegistrationViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _accountManager = SignalApp.sharedApp.accountManager;

    return self;
}

- (void)loadView
{
    [super loadView];

    [self createViews];
    
    [self updateInviteCodeFromPasteBoard];

    // Do any additional setup after loading the view.
    OWSAssert([self.navigationController isKindOfClass:[OWSNavigationController class]]);
    [SignalApp.sharedApp setSignUpFlowNavigationController:(OWSNavigationController *)self.navigationController];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    OWSProdInfo([OWSAnalyticsEvents registrationBegan]);
    
    [[NSNotificationCenter defaultCenter]addObserver:self
                                     selector:@selector(appDidBecomeActive)
                                         name:UIApplicationDidBecomeActiveNotification
                                       object:nil];
}

- (void)appDidBecomeActive
{
    if (TRUE == _isDisplaying)
    {
        [self updateInviteCodeFromPasteBoard];
    }
}

-(BOOL)validateInviteCode:(NSString *)inviteCode
{
    BOOL valid = FALSE;
    
    do {
        if (!inviteCode) {
            break;
        }
        
        if (inviteCode.length != 32) {
            break;
        }
        
        // only alpha number allowed.
        NSCharacterSet *alphaNumberic = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
        if ([inviteCode  rangeOfCharacterFromSet:alphaNumberic].location != NSNotFound) {
            break;
        }
        
        valid = TRUE;
    } while (false);
    
    return valid;
}

- (NSString *)parseInviteCodeFromString: (NSString*)inputString
                           regexPattern: (NSString*)regexPattern
{
    NSString * inviteCode = NULL;

    do {
        if (!inputString || !regexPattern) {
            break;
        }
        
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexPattern
                                                                               options:NSRegularExpressionCaseInsensitive|NSRegularExpressionAnchorsMatchLines
                                                                                 error:&error];
        if (error || !regex) {
            break;
        }

        // a regex maybe has multi match, every match may be has multi group
        // get first match, first group member.
        NSTextCheckingResult *firstMatch = [regex firstMatchInString:inputString options:kNilOptions range:NSMakeRange(0, [inputString length])];
        if (!firstMatch) {
            break;
        }

        inviteCode = [inputString substringWithRange:[firstMatch rangeAtIndex:1]];
    } while (false);

    return inviteCode;
}

// check invite code from paste board
- (void)updateInviteCodeFromPasteBoard
{
    UIPasteboard* pasteboard = [UIPasteboard generalPasteboard];
    NSString* pasteStr = pasteboard.string;
    if (!pasteStr)
    {
        return;
    }

//    DDLogInfo(@"------------Paste Board Content: %@", pasteStr);
    
    pasteStr = [pasteStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    pasteboard.string = pasteStr;
    
    NSString* tempCode = [self parseInviteCodeFromString:pasteStr regexPattern:@"\\b([a-z0-9A-Z]{32})\\b"];
    if (NULL == tempCode)
    {
        return;
    }
    
    __block UITextField *inviteCodeEditor = [self.view viewWithTag:100001];
    if (inviteCodeEditor && [inviteCodeEditor.text isEqualToString:tempCode])
    {
        return;
    }

    // TODO: supply english notice.
    NSString* confirmMessage = [[NSString alloc] initWithString:[NSString stringWithFormat:@"Invite code detected, autofill in?"]];

    UIAlertController *alertController =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"COMMON_NOTICE_TITLE", @"")
                                        message:confirmMessage
                                 preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"OK", @"")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    if (inviteCodeEditor && ![inviteCodeEditor.text isEqualToString:tempCode])
                    {
                        inviteCodeEditor.text = tempCode;
                    }
                }];

    [alertController addAction:[OWSAlerts cancelAction]];
    [alertController addAction:okAction];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)createViews
{
    self.view.backgroundColor = [UIColor whiteColor];
    self.view.userInteractionEnabled = YES;
    [self.view
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)]];

    UIView *headerWrapper = [UIView containerView];
    [self.view addSubview:headerWrapper];
    headerWrapper.backgroundColor = UIColor.ows_signalBrandBlueColor;
    [headerWrapper autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero excludingEdge:ALEdgeBottom];

    UILabel *headerLabel = [UILabel new];
    headerLabel.text = NSLocalizedString(@"REGISTRATION_INVITE_CODE_TITLE_LABEL", @"");
    headerLabel.textColor = [UIColor whiteColor];
    headerLabel.font = [UIFont ows_mediumFontWithSize:ScaleFromIPhone5To7Plus(20.f, 24.f)];

#ifdef SHOW_LEGAL_TERMS_LINK
    NSString *legalTopMatterFormat = NSLocalizedString(@"REGISTRATION_LEGAL_TOP_MATTER_FORMAT",
        @"legal disclaimer, embeds a tappable {{link title}} which is styled as a hyperlink");
    NSString *legalTopMatterLinkWord = NSLocalizedString(
        @"REGISTRATION_LEGAL_TOP_MATTER_LINK_TITLE", @"embedded in legal topmatter, styled as a link");
    NSString *legalTopMatter = [NSString stringWithFormat:legalTopMatterFormat, legalTopMatterLinkWord];
    NSMutableAttributedString *attributedLegalTopMatter =
        [[NSMutableAttributedString alloc] initWithString:legalTopMatter];
    NSRange linkRange = [legalTopMatter rangeOfString:legalTopMatterLinkWord];
    NSDictionary *linkStyleAttributes = @{
        NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid),
    };
    [attributedLegalTopMatter setAttributes:linkStyleAttributes range:linkRange];

    UILabel *legalTopMatterLabel = [UILabel new];
    legalTopMatterLabel.textColor = UIColor.whiteColor;
    legalTopMatterLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(13.f, 15.f)];
    legalTopMatterLabel.numberOfLines = 0;
    legalTopMatterLabel.textAlignment = NSTextAlignmentCenter;
    legalTopMatterLabel.attributedText = attributedLegalTopMatter;
    legalTopMatterLabel.userInteractionEnabled = YES;

    UITapGestureRecognizer *tapGesture =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapLegalTerms:)];
    [legalTopMatterLabel addGestureRecognizer:tapGesture];
#endif

    UIStackView *headerContent = [[UIStackView alloc] initWithArrangedSubviews:@[ headerLabel ]];
#ifdef SHOW_LEGAL_TERMS_LINK
    [headerContent addArrangedSubview:legalTopMatterLabel];
#endif
    headerContent.axis = UILayoutConstraintAxisVertical;
    headerContent.alignment = UIStackViewAlignmentCenter;
    headerContent.spacing = ScaleFromIPhone5To7Plus(8, 16);
    headerContent.layoutMarginsRelativeArrangement = YES;

    {
        CGFloat topMargin = ScaleFromIPhone5To7Plus(4, 16);
        CGFloat bottomMargin = ScaleFromIPhone5To7Plus(8, 16);
        headerContent.layoutMargins = UIEdgeInsetsMake(topMargin, 40, bottomMargin, 40);
    }

    [headerWrapper addSubview:headerContent];
    [headerContent autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [headerContent autoPinEdgesToSuperviewMarginsExcludingEdge:ALEdgeTop];

    const CGFloat kRowHeight = 60.f;
    const CGFloat kRowHMargin = 20.f;
    const CGFloat kSeparatorHeight = 1.f;
    
    UIView *contentView = [UIView containerView];
    [contentView setHLayoutMargins:kRowHMargin];
    contentView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:contentView];
    [contentView autoPinToBottomLayoutGuideOfViewController:self withInset:0];
    [contentView autoPinWidthToSuperview];
    [contentView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:headerContent];

    // Invite code Row
    UIView *inviteCodeRow = [UIView containerView];
    [contentView addSubview:inviteCodeRow];
    [inviteCodeRow autoPinLeadingAndTrailingToSuperviewMargin];
    [inviteCodeRow autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [inviteCodeRow autoSetDimension:ALDimensionHeight toSize:kRowHeight];

    // Input text field
    UITextField *inviteCodeTextField = [UITextField new];
    inviteCodeTextField.delegate = self;
    inviteCodeTextField.tag = 100001;
    inviteCodeTextField.keyboardType = UIKeyboardTypePhonePad;
    inviteCodeTextField.placeholder = NSLocalizedString(@"REGISTRATION_INVITE_CODE_DEFAULT_TEXT", @"Placeholder text for the phone number textfield");
    inviteCodeTextField.textColor = [UIColor ows_materialBlueColor];
    inviteCodeTextField.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(13.f, 15.f)];
    [inviteCodeRow addSubview:inviteCodeTextField];
    [inviteCodeTextField autoVCenterInSuperview];
    [inviteCodeTextField autoPinLeadingToSuperviewMargin];
    self.inviteCodeTextField = inviteCodeTextField;

    // Activate Button
    const CGFloat kActivateButtonHeight = 47.f;
    // NOTE: We use ows_signalBrandBlueColor instead of ows_materialBlueColor
    //       throughout the onboarding flow to be consistent with the headers.
    OWSFlatButton *activateButton = [OWSFlatButton buttonWithTitle:NSLocalizedString(@"REGISTRATION_VERIFY_DEVICE", @"")
                                                              font:[OWSFlatButton fontForHeight:kActivateButtonHeight]
                                                        titleColor:[UIColor whiteColor]
                                                   backgroundColor:[UIColor ows_signalBrandBlueColor]
                                                            target:self
                                                          selector:@selector(didTapRegisterButton)];
    self.activateButton = activateButton;
    [contentView addSubview:activateButton];
    [activateButton autoPinLeadingAndTrailingToSuperviewMargin];
    [activateButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:inviteCodeRow];
    [activateButton autoSetDimension:ALDimensionHeight toSize:kActivateButtonHeight];

    // process status spinner
    UIActivityIndicatorView *spinnerView =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinnerView = spinnerView;
    [activateButton addSubview:spinnerView];
    [spinnerView autoVCenterInSuperview];
    [spinnerView autoSetDimension:ALDimensionWidth toSize:20.f];
    [spinnerView autoSetDimension:ALDimensionHeight toSize:20.f];
    [spinnerView autoPinTrailingToSuperviewMarginWithInset:20.f];
    [spinnerView stopAnimating];

    // legal terms link button
#ifdef SHOW_LEGAL_TERMS_LINK
    NSString *bottomTermsLinkText = NSLocalizedString(@"REGISTRATION_LEGAL_TERMS_LINK",
        @"one line label below submit button on registration screen, which links to an external webpage.");
    UIButton *bottomLegalLinkButton = [UIButton new];
    bottomLegalLinkButton.titleLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(13.f, 15.f)];
    [bottomLegalLinkButton setTitleColor:UIColor.ows_materialBlueColor forState:UIControlStateNormal];
    [bottomLegalLinkButton setTitle:bottomTermsLinkText forState:UIControlStateNormal];
    [contentView addSubview:bottomLegalLinkButton];
    [bottomLegalLinkButton addTarget:self
                              action:@selector(didTapLegalTerms:)
                    forControlEvents:UIControlEventTouchUpInside];

    [bottomLegalLinkButton autoPinLeadingAndTrailingToSuperviewMargin];
    [bottomLegalLinkButton autoPinEdge:ALEdgeTop
                                toEdge:ALEdgeBottom
                                ofView:activateButton
                            withOffset:ScaleFromIPhone5To7Plus(8, 12)];
    [bottomLegalLinkButton setCompressionResistanceHigh];
    [bottomLegalLinkButton setContentHuggingHigh];
#endif

    // separator
    UIView *separatorView = [UIView new];
    separatorView.backgroundColor = [UIColor colorWithWhite:0.75f alpha:1.f];
    [contentView addSubview:separatorView];
    [separatorView autoPinWidthToSuperview];
    [separatorView autoSetDimension:ALDimensionHeight toSize:kSeparatorHeight];
#ifdef SHOW_LEGAL_TERMS_LINK
    [separatorView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:bottomLegalLinkButton withOffset:50];
#else
    [separatorView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:activateButton withOffset:50];
#endif

    UIView *noticeRow = [UIView containerView];
    [contentView addSubview:noticeRow];
    [noticeRow autoPinLeadingAndTrailingToSuperviewMargin];
    [noticeRow autoSetDimension:ALDimensionHeight toSize:kRowHeight];
    [noticeRow autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:separatorView ];

    // notice label for switch register
    UILabel *noticeLabel = [UILabel new];
    noticeLabel.text
        = NSLocalizedString(@"REGISTRATION_SWITCH_NOTICE", @"Notice for switch register method");
    noticeLabel.textColor = [UIColor blackColor];
    noticeLabel.font = [UIFont ows_regularFontWithSize:ScaleFromIPhone5To7Plus(13.f, 15.f)];
    [noticeRow addSubview:noticeLabel];
    [noticeLabel autoVCenterInSuperview];
    [noticeLabel autoPinLeadingToSuperviewMargin];

    // switch button
    OWSFlatButton *switchButton = [OWSFlatButton buttonWithTitle:NSLocalizedString(@"REGISTRATION_SWITCH_TO_NUMBER", @"")
                                                            font:[OWSFlatButton fontForHeight:kActivateButtonHeight]
                                                      titleColor:[UIColor whiteColor]
                                                 backgroundColor:[UIColor ows_signalBrandBlueColor]
                                                          target:self
                                                        selector:@selector(didTapSwitchButton)];
    self.switchButton = switchButton;
    [contentView addSubview:switchButton];
    [switchButton autoPinLeadingAndTrailingToSuperviewMargin];
    [switchButton autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:noticeRow];
    [switchButton autoSetDimension:ALDimensionHeight toSize:kActivateButtonHeight];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self.activateButton setEnabled:YES];
    [self.spinnerView stopAnimating];
    [self.inviteCodeTextField becomeFirstResponder];
    
    _isDisplaying = TRUE;

    if ([TSAccountManager sharedInstance].isReregistering) {

    }
}

-(void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    _isDisplaying = FALSE;
}

#pragma mark - Actions

- (void)didTapRegisterButton
{
    NSString *inviteCode = [_inviteCodeTextField.text ows_stripped];
    if (inviteCode.length < 1)
    {
        [OWSAlerts
            showAlertWithTitle:NSLocalizedString(@"REGISTRATION_VIEW_NO_INVITE_CODE_TITLE",
                                   @"Title of alert indicating that users needs to enter a invite code to register.")
                       message:
                           NSLocalizedString(@"REGISTRATION_VIEW_NO_INVITE_CODE_MESSAGE",
                               @"Message of alert indicating that users needs to enter a invite code to register.")];
        return;
    }
    
    if (![self validateInviteCode:inviteCode])
    {
        [OWSAlerts
            showAlertWithTitle:NSLocalizedString(@"REGISTRATION_VIEW_INVALID_INVITE_CODE_TITLE",
                                   @"Title of alert indicating that users needs to enter a valid invite code to register.")
                       message:
                           NSLocalizedString(@"REGISTRATION_VIEW_INVALID_INVITE_CODE_MESSAGE",
                               @"Message of alert indicating that users needs to enter a valid invite code to register.")];
        return;
    }
    
    // exchange account by invite code
    [self registerWithInviteCode:inviteCode];
}

- (void)startActivityIndicator
{
    [self.activateButton setEnabled:NO];
    [self.spinnerView startAnimating];
    [self.inviteCodeTextField resignFirstResponder];
}

- (void)stopActivityIndicator
{
    [self.activateButton setEnabled:YES];
    [self.spinnerView stopAnimating];
}

-(void)registerWithInviteCode:(NSString *)inviteCode
{
    [self startActivityIndicator];
    
    __weak InviteRegistrationViewController *weakSelf = self;
    
    [[TSAccountManager
        sharedInstance]
            exchangeAccountWithInviteCode: inviteCode
                                success:^(id responseObject){
                                     BOOL accountOk = FALSE;
                                     do {
                                         if (![responseObject isKindOfClass:[NSDictionary class]]) {
                                             DDLogError(@"%@ Failed retrieval of attachment. Response had unexpected format.", self.logTag);
                                             break;
                                         }
                                         
                                         NSString *number = [(NSDictionary *)responseObject objectForKey:@"account"];
                                         if (!number) {
                                             DDLogError(@"%@ Failed retrieval of attachment. Response had no location.", self.logTag);
                                             break;
                                         }
                                         
                                         NSString *vCode = [(NSDictionary *)responseObject objectForKey:@"vcode"];
                                         if (!vCode) {
                                             DDLogError(@"%@ Failed retrieval of attachment. Response had no location.", self.logTag);
                                             break;
                                         }
                                         
                                         accountOk = TRUE;
                                         [weakSelf preRegisterWithNumber:number vCode:vCode];
                                     } while (false);
                                    
                                     if (FALSE == accountOk)
                                     {
                                        NSError *error = OWSErrorMakeUnableToProcessServerResponseError();
                                        [weakSelf stopActivityIndicator];
                                        [weakSelf presentAlertWithVerificationError:error];
                                     }
                                }
                                failure:^(NSError *error){
                                     [weakSelf stopActivityIndicator];
                                     [weakSelf presentAlertWithVerificationError:error];
                                }
     ];
}

-(void)preRegisterWithNumber:(NSString *)number
                       vCode:(NSString *)vCode
{
    [TSAccountManager registerWithPhoneNumber:number
    success:^{
        __weak InviteRegistrationViewController *weakSelf = self;
        [weakSelf submitVerificationCode:vCode];
    }
    failure:^(NSError *error) {
        if (error.code == 400) {
            [OWSAlerts showAlertWithTitle:NSLocalizedString(@"REGISTRATION_ERROR", nil)
                                  message:NSLocalizedString(@"REGISTRATION_NON_VALID_NUMBER", nil)];
        } else {
            [OWSAlerts showAlertWithTitle:error.localizedDescription message:error.localizedRecoverySuggestion];
        }
    }
    smsVerification:YES];
}

- (void)submitVerificationCode:(NSString *)vCode
{
    [self startActivityIndicator];
    __weak InviteRegistrationViewController *weakSelf = self;
    [self.accountManager registerWithVerificationCode:vCode pin:nil]
        .then(^{
            OWSProdInfo([OWSAnalyticsEvents registrationRegisteringSubmittedCode]);

            DDLogInfo(@"%@ Successfully registered Signal account.", weakSelf.logTag);
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf stopActivityIndicator];
                [weakSelf verificationWasCompleted];
            });
        })
        .catch(^(NSError *error) {
            DDLogError(@"%@ error: %@, %@, %zd", weakSelf.logTag, [error class], error.domain, error.code);
            OWSProdInfo([OWSAnalyticsEvents registrationRegistrationFailed]);
            DDLogError(@"%@ error verifying challenge: %@", weakSelf.logTag, error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf stopActivityIndicator];
                [weakSelf presentAlertWithVerificationError:error];
            });
        });
}

- (void)verificationWasCompleted
{
    [ProfileViewController presentForRegistration:self.navigationController];
}

- (void)presentAlertWithVerificationError:(NSError *)error
{
    UIAlertController *alert;
    alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"REGISTRATION_VERIFICATION_FAILED_TITLE", @"Alert view title")
                         message:error.localizedDescription
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:CommonStrings.dismissButton
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                            }]];

    [self presentViewController:alert animated:YES completion:nil];
}


- (void)didTapSwitchButton
{
    __weak InviteRegistrationViewController *weakSelf = self;

    RegistrationViewController *vc = [RegistrationViewController new];
    [weakSelf.navigationController pushViewController:vc animated:YES];
}

- (void)didTapLegalTerms:(UIButton *)sender
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:kLegalTermsUrlString]];
}

- (void)backgroundTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self.inviteCodeTextField becomeFirstResponder];
    }
}

#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers
{
    UITapGestureRecognizer *outsideTabRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.view addGestureRecognizer:outsideTabRecognizer];
}

- (void)dismissKeyboardFromAppropriateSubView
{
    [self.view endEditing:NO];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

@end

NS_ASSUME_NONNULL_END
