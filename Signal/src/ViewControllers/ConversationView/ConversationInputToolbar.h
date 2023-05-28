//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DFInputAtCache.h"

NS_ASSUME_NONNULL_BEGIN

@class ConversationStyle;
@class OWSQuotedReplyModel;
@class SignalAttachment;

@protocol ConversationInputToolbarDelegate <NSObject>

- (void)sendButtonPressed;

- (void)attachmentButtonPressed;

- (void)atIsActive;

#pragma mark - Voice Memo

- (void)voiceMemoGestureDidStart;

- (void)voiceMemoGestureDidEnd;

- (void)voiceMemoGestureDidCancel;

- (void)voiceMemoGestureDidChange:(CGFloat)cancelAlpha;

@end

#pragma mark -

@class ConversationInputTextView;

@protocol ConversationInputTextViewDelegate;

@interface ConversationInputToolbar : UIView

@property (nonatomic, strong) DFInputAtCache *atCache;

- (instancetype)initWithConversationStyle:(ConversationStyle *)conversationStyle NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)aDecoder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;

@property (nonatomic, weak) id<ConversationInputToolbarDelegate> inputToolbarDelegate;

- (void)beginEditingTextMessage;
- (void)endEditingTextMessage;
- (BOOL)isInputTextViewFirstResponder;

- (void)setInputTextViewDelegate:(id<ConversationInputTextViewDelegate>)value;

/// 返回 textView trimmed 文本
- (NSString *)messageText;

/// 返回 textView 未经过处理的文本
- (NSString *)originMessageText;

- (void)setMessageText:(NSString *_Nullable)value animated:(BOOL)isAnimated;
- (void)clearTextMessageAnimated:(BOOL)isAnimated;
- (void)toggleDefaultKeyboard;

- (void)updateFontSizes;


#pragma mark - Voice Memo

- (void)showVoiceMemoUI;

- (void)hideVoiceMemoUI:(BOOL)animated;

- (void)setVoiceMemoUICancelAlpha:(CGFloat)cancelAlpha;

- (void)cancelVoiceMemoIfNecessary;

@property (nonatomic, nullable) OWSQuotedReplyModel *quotedReply;

@end

NS_ASSUME_NONNULL_END
