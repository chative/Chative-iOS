//
//  ContactDetailsViewController.h
//  Signal
//
//  Created by anonoymous on 2021/3/20.
//  Copyright © 2021 anonoymous. All rights reserved.
//

#import <SignalMessaging/SignalMessaging.h>

NS_ASSUME_NONNULL_BEGIN

@interface ContactDetailsViewController : OWSTableViewController

- (void)configureWithRecipientId:(NSString *)recipientId;

@end

NS_ASSUME_NONNULL_END
