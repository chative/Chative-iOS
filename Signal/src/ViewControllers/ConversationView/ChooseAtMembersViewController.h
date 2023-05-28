//
//  ChooseAtMembersViewController.h
//  Signal
//
//  Created by 宋立仙 on 2021/6/2.
//

#import "OWSTableViewController.h"

@class TSGroupThread;

@protocol ChooseAtMembersViewControllerDelegate <NSObject>
@optional
- (void)chooseAtPeronsDidSelectRecipientId:(NSString *)recipientId name:(NSString *)name;
- (void)chooseAtPeronsCancel;


@end

@interface ChooseAtMembersViewController : OWSTableViewController
@property (nonatomic, weak) id<ChooseAtMembersViewControllerDelegate> resultDelegate;

+ (ChooseAtMembersViewController *)presentFromViewController:(UIViewController *)viewController thread:(TSGroupThread *)thread delegate:(id<ChooseAtMembersViewControllerDelegate>) theDelegate;
- (void)dismissVC;

@end

