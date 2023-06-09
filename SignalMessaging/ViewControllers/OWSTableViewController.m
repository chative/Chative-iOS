//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"
#import "OWSNavigationController.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

const CGFloat kOWSTable_DefaultCellHeight = 45.f;

@interface OWSTableContents ()

@property (nonatomic) NSMutableArray<OWSTableSection *> *sections;

@end

#pragma mark -

@implementation OWSTableContents

- (instancetype)init
{
    if (self = [super init]) {
        _sections = [NSMutableArray new];
    }
    return self;
}

- (void)addSection:(OWSTableSection *)section
{
    OWSAssert(section);

    [_sections addObject:section];
}

@end

#pragma mark -

@interface OWSTableSection ()

@property (nonatomic) NSMutableArray<OWSTableItem *> *items;

@end

#pragma mark -

@implementation OWSTableSection

+ (OWSTableSection *)sectionWithTitle:(nullable NSString *)title items:(NSArray<OWSTableItem *> *)items
{
    OWSTableSection *section = [OWSTableSection new];
    section.headerTitle = title;
    section.items = [items mutableCopy];
    return section;
}

- (instancetype)init
{
    if (self = [super init]) {
        _items = [NSMutableArray new];
    }
    return self;
}

- (void)addItem:(OWSTableItem *)item
{
    OWSAssert(item);

    [_items addObject:item];
}

- (NSUInteger)itemCount
{
    return _items.count;
}

@end

#pragma mark -

@interface OWSTableItem ()

@property (nonatomic, nullable) NSString *title;
@property (nonatomic, nullable) OWSTableActionBlock actionBlock;

@property (nonatomic) OWSTableCustomCellBlock customCellBlock;
@property (nonatomic) UITableViewCell *customCell;
@property (nonatomic) NSNumber *customRowHeight;

@end

#pragma mark -

@implementation OWSTableItem

+ (UITableViewCell *)newCell
{
    UITableViewCell *cell = [UITableViewCell new];
    cell.backgroundColor = [UIColor ows_themeBackgroundColor];
    cell.contentView.backgroundColor = [UIColor ows_themeBackgroundColor];
    cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
    cell.textLabel.textColor = [UIColor ows_themeForegroundColor];
    return cell;
}

+ (OWSTableItem *)itemWithTitle:(NSString *)title actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(title.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.title = title;
    return item;
}

+ (OWSTableItem *)itemWithCustomCell:(UITableViewCell *)customCell
                     customRowHeight:(CGFloat)customRowHeight
                         actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(customCell);
    OWSAssert(customRowHeight > 0 || customRowHeight == UITableViewAutomaticDimension);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCell = customCell;
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                          customRowHeight:(CGFloat)customRowHeight
                              actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(customRowHeight > 0 || customRowHeight == UITableViewAutomaticDimension);

    OWSTableItem *item = [self itemWithCustomCellBlock:customCellBlock actionBlock:actionBlock];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                              actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(customCellBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = customCellBlock;
    return item;
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self itemWithText:text actionBlock:actionBlock accessoryType:UITableViewCellAccessoryDisclosureIndicator];
}

+ (OWSTableItem *)checkmarkItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self itemWithText:text actionBlock:actionBlock accessoryType:UITableViewCellAccessoryCheckmark];
}

+ (OWSTableItem *)itemWithText:(NSString *)text
                   actionBlock:(nullable OWSTableActionBlock)actionBlock
                 accessoryType:(UITableViewCellAccessoryType)accessoryType
{
    OWSAssert(text.length > 0);
    OWSAssert(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;
        cell.accessoryType = accessoryType;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                         customRowHeight:(CGFloat)customRowHeight
                             actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(customRowHeight > 0 || customRowHeight == UITableViewAutomaticDimension);

    OWSTableItem *item = [self disclosureItemWithText:text actionBlock:actionBlock];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                              detailText:(NSString *)detailText
                             actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(text.length > 0);
    OWSAssert(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = ^{
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                       reuseIdentifier:@"UITableViewCellStyleValue1"];
        cell.textLabel.text = text;
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor ows_themeForegroundColor];
        cell.backgroundColor = [UIColor ows_themeBackgroundColor];
        cell.contentView.backgroundColor = [UIColor ows_themeBackgroundColor];
        cell.detailTextLabel.text = detailText;
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        return cell;
    };
    return item;
}

+ (OWSTableItem *)subPageItemWithText:(NSString *)text actionBlock:(nullable OWSTableSubPageBlock)actionBlock
{
    OWSAssert(text.length > 0);
    OWSAssert(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    __weak OWSTableItem *weakItem = item;
    item.actionBlock = ^{
        OWSTableItem *strongItem = weakItem;
        OWSAssert(strongItem);
        OWSAssert(strongItem.tableViewController);

        if (actionBlock) {
            actionBlock(strongItem.tableViewController);
        }
    };
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)subPageItemWithText:(NSString *)text
                      customRowHeight:(CGFloat)customRowHeight
                          actionBlock:(nullable OWSTableSubPageBlock)actionBlock
{
    OWSAssert(customRowHeight > 0 || customRowHeight == UITableViewAutomaticDimension);

    OWSTableItem *item = [self subPageItemWithText:text actionBlock:actionBlock];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)actionItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(text.length > 0);
    OWSAssert(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)softCenterLabelItemWithText:(NSString *)text
{
    OWSAssert(text.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;
        // These cells look quite different.
        //
        // Smaller font.
        cell.textLabel.font = [UIFont ows_regularFontWithSize:15.f];
        // Soft color.
        // TODO: Theme, review with design.
        cell.textLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
        // Centered.
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.userInteractionEnabled = NO;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)softCenterLabelItemWithText:(NSString *)text customRowHeight:(CGFloat)customRowHeight
{
    OWSAssert(customRowHeight > 0 || customRowHeight == UITableViewAutomaticDimension);

    OWSTableItem *item = [self softCenterLabelItemWithText:text];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)labelItemWithText:(NSString *)text
{
    OWSAssert(text.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;
        cell.userInteractionEnabled = NO;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)labelItemWithText:(NSString *)text accessoryText:(NSString *)accessoryText
{
    OWSAssert(text.length > 0);
    OWSAssert(accessoryText.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;

        UILabel *accessoryLabel = [UILabel new];
        accessoryLabel.text = accessoryText;
        accessoryLabel.textColor = [UIColor ows_themeSecondaryColor];
        accessoryLabel.font = [UIFont ows_regularFontWithSize:16.0f];
        accessoryLabel.textAlignment = NSTextAlignmentRight;
        [accessoryLabel sizeToFit];
        cell.accessoryView = accessoryLabel;

        cell.userInteractionEnabled = NO;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)switchItemWithText:(NSString *)text isOn:(BOOL)isOn target:(id)target selector:(SEL)selector
{
    return [self switchItemWithText:text isOn:isOn isEnabled:YES target:target selector:selector];
}

+ (OWSTableItem *)switchItemWithText:(NSString *)text
                                isOn:(BOOL)isOn
                           isEnabled:(BOOL)isEnabled
                              target:(id)target
                            selector:(SEL)selector
{
    OWSAssert(text.length > 0);
    OWSAssert(target);
    OWSAssert(selector);

    OWSTableItem *item = [OWSTableItem new];
    __weak id weakTarget = target;
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;

        UISwitch *cellSwitch = [UISwitch new];
        cell.accessoryView = cellSwitch;
        [cellSwitch setOn:isOn];
        [cellSwitch addTarget:weakTarget action:selector forControlEvents:UIControlEventValueChanged];
        cellSwitch.enabled = isEnabled;

        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        return cell;
    };
    return item;
}

- (nullable UITableViewCell *)customCell
{
    if (_customCell) {
        return _customCell;
    }
    if (_customCellBlock) {
        UITableViewCell* cell = _customCellBlock();
        
        cell.backgroundColor = [UIColor ows_themeBackgroundColor];
        cell.contentView.backgroundColor = [UIColor ows_themeBackgroundColor];
        
        return cell;
    }
    return nil;
}

@end

#pragma mark -

@interface OWSTableViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic) UITableView *tableView;

@end

#pragma mark -

NSString *const kOWSTableCellIdentifier = @"kOWSTableCellIdentifier";

@implementation OWSTableViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self owsTableCommonInit];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self owsTableCommonInit];

    return self;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
        return self;
    }

    [self owsTableCommonInit];

    return self;
}

- (void)owsTableCommonInit
{
    _contents = [OWSTableContents new];
    self.tableViewStyle = UITableViewStyleGrouped;
    self.canEditRow = NO;
}

- (void)loadView
{
    [super loadView];

    OWSAssert(self.contents);

    if (self.contents.title.length > 0) {
        self.title = self.contents.title;
    }

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:self.tableViewStyle];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    [self.view addSubview:self.tableView];

    if ([self.tableView applyScrollViewInsetsFix]) {
        // if applyScrollViewInsetsFix disables contentInsetAdjustmentBehavior,
        // we need to pin to the top and bottom layout guides since UIKit
        // won't adjust our content insets.
        [self.tableView autoPinToTopLayoutGuideOfViewController:self withInset:0];
        [self.tableView autoPinToBottomLayoutGuideOfViewController:self withInset:0];
        [self.tableView autoPinWidthToSuperview];

        // We don't need a top or bottom insets, since we pin to the top and bottom layout guides.
        self.automaticallyAdjustsScrollViewInsets = NO;
    } else {
        [self.tableView autoPinEdgesToSuperviewEdges];
    }

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kOWSTableCellIdentifier];

    [self applyTheme];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:NSNotificationNameThemeDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (OWSTableSection *)sectionForIndex:(NSInteger)sectionIndex
{
    OWSAssert(self.contents);
    OWSAssert(sectionIndex >= 0 && sectionIndex < (NSInteger)self.contents.sections.count);

    OWSTableSection *section = self.contents.sections[(NSUInteger)sectionIndex];
    return section;
}

- (OWSTableItem *)itemForIndexPath:(NSIndexPath *)indexPath
{
    OWSAssert(self.contents);
    OWSAssert(indexPath.section >= 0 && indexPath.section < (NSInteger)self.contents.sections.count);

    OWSTableSection *section = self.contents.sections[(NSUInteger)indexPath.section];
    OWSAssert(indexPath.item >= 0 && indexPath.item < (NSInteger)section.items.count);
    OWSTableItem *item = section.items[(NSUInteger)indexPath.item];

    return item;
}

- (void)setContents:(OWSTableContents *)contents
{
    OWSAssert(contents);
    OWSAssertIsOnMainThread();

    _contents = contents;

    [self.tableView reloadData];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    OWSAssert(self.contents);
    return (NSInteger)self.contents.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    OWSAssert(section.items);
    return (NSInteger)section.items.count;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.headerTitle;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    // Background color
    // R:0.46 G:0.46 B:0.5 A:0.24
    view.tintColor = [UIColor colorWithRed:0.46 green:0.46 blue:0.5 alpha:0.24];
    
    if([view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        // Text Color
        UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
        [header.textLabel setTextColor:[UIColor blackColor]];
   }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.footerTitle;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];

    item.tableViewController = self;

    UITableViewCell *customCell = [item customCell];
    if (customCell) {
        return customCell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kOWSTableCellIdentifier];
    OWSAssert(cell);

    cell.textLabel.text = item.title;

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (item.customRowHeight) {
        return [item.customRowHeight floatValue];
    }
    return kOWSTable_DefaultCellHeight;
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.customHeaderView;
    
//    UIView *tempView=[[UIView alloc]initWithFrame:CGRectMake(0,200,300,244)];
//    tempView.backgroundColor=[UIColor redColor];
//    return tempView;
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.customFooterView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *_Nullable section = [self sectionForIndex:sectionIndex];

    if (!section) {
        OWSFail(@"Section index out of bounds.");
        return 0;
    }

    if (section.customHeaderHeight) {
        OWSAssert([section.customHeaderHeight floatValue] > 0);
        return [section.customHeaderHeight floatValue];
    } else if (section.headerTitle.length > 0) {
        return UITableViewAutomaticDimension;
    } else {
        return 0;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)sectionIndex
{
    OWSTableSection *_Nullable section = [self sectionForIndex:sectionIndex];
    if (!section) {
        OWSFail(@"Section index out of bounds.");
        return 0;
    }

    if (section.customFooterHeight) {
        OWSAssert([section.customFooterHeight floatValue] > 0);
        return [section.customFooterHeight floatValue];
    } else if (section.footerTitle.length > 0) {
        return UITableViewAutomaticDimension;
    } else {
        return 0;
    }
}

// Called before the user changes the selection. Return a new indexPath, or nil, to change the proposed selection.
- (nullable NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (!item.actionBlock) {
        return nil;
    }

    return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (item.actionBlock) {
        item.actionBlock();
    }
}

#pragma mark Index

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index
{
    if (self.contents.sectionForSectionIndexTitleBlock) {
        return self.contents.sectionForSectionIndexTitleBlock(title, index);
    } else {
        return 0;
    }
}

- (nullable NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    if (self.contents.sectionIndexTitlesForTableViewBlock) {
        return self.contents.sectionIndexTitlesForTableViewBlock();
    } else {
        return 0;
    }
}

- (nullable UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
 trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath API_AVAILABLE(ios(11.0)) API_UNAVAILABLE(tvos)
 {
    // delete action
    UIContextualAction *deleteAction = [UIContextualAction
                                        contextualActionWithStyle:UIContextualActionStyleDestructive
                                        title:NSLocalizedString(@"TXT_DELETE_TITLE", nil)
                                        handler:^(UIContextualAction * _Nonnull action,
                                                  __kindof UIView * _Nonnull sourceView,
                                                  void (^ _Nonnull completionHandler)(BOOL))
                                        {
                                            [self tableViewCellTappedDelete:indexPath];
                                            completionHandler(true);
                                        }];
    
    UIContextualAction *detailsAction = [UIContextualAction
                                       contextualActionWithStyle:UIContextualActionStyleNormal
                                       title:NSLocalizedString(@"TEXT_DETAILS_TITLE", nil)
                                       handler:^(UIContextualAction * _Nonnull action,
                                                 __kindof UIView * _Nonnull sourceView,
                                                 void (^ _Nonnull completionHandler)(BOOL))
                                       {
                                            [self tableViewCellTappedDetails:indexPath];
                                            completionHandler(true);
                                       }];
    
    detailsAction.backgroundColor = [UIColor ows_signalBlueColor];
    
    UISwipeActionsConfiguration *actions =
        [UISwipeActionsConfiguration configurationWithActions:@[deleteAction,detailsAction]];
    actions.performsFirstActionWithFullSwipe = NO;
    
    return actions;
}

- (nullable NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewRowAction *deleteAction =
        [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDefault
                                           title:NSLocalizedString(@"TXT_DELETE_TITLE", nil)
                                         handler:^(UITableViewRowAction *action, NSIndexPath *swipedIndexPath) {
                                             [self tableViewCellTappedDelete:swipedIndexPath];
                                         }];
    
    UITableViewRowAction *detailsAction =
        [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDefault
                                           title:NSLocalizedString(@"TEXT_DETAILS_TITLE", nil)
                                         handler:^(UITableViewRowAction *action, NSIndexPath *swipedIndexPath) {
                                             [self tableViewCellTappedDetails:swipedIndexPath];
                                         }];
    detailsAction.backgroundColor = [UIColor ows_signalBlueColor];
    
    return @[ deleteAction, detailsAction ];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return self.canEditRow;
}

- (void)tableViewCellTappedDelete:(NSIndexPath *)indexPath
{
    [self.delegate tableViewPressDeleteAtRowIndex:indexPath];
}

- (void)tableViewCellTappedDetails:(NSIndexPath *)indexPath
{
    [self.delegate tableViewPressDetailsAtRowIndex:indexPath];
}

#pragma mark - Presentation

- (void)presentFromViewController:(UIViewController *)fromViewController
{
    OWSAssert(fromViewController);

    OWSNavigationController *navigationController = [[OWSNavigationController alloc] initWithRootViewController:self];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(donePressed:)];

    [fromViewController presentViewController:navigationController animated:YES completion:nil];
}

- (void)donePressed:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [self.delegate tableViewWillBeginDragging];
}

#pragma mark - Theme

- (void)themeDidChange:(id)notification
{
    OWSAssertIsOnMainThread();

    [self applyTheme];
    [self.tableView reloadData];
}

- (void)applyTheme
{
    OWSAssertIsOnMainThread();

    self.view.backgroundColor = UIColor.ows_themeBackgroundColor;
    self.tableView.backgroundColor = UIColor.ows_themeBackgroundColor;
}

-(BOOL)hidesBottomBarWhenPushed
{
    return YES;
}

@end

NS_ASSUME_NONNULL_END
