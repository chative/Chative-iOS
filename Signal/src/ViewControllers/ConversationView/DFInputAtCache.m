//
//  DFInputCache.m
//  Signal
//
//  Created by Felix on 2021/7/7.
//

#import "DFInputAtCache.h"

@implementation DFInputAtItem

@end


@interface DFInputAtCache ()

@property (nonatomic, strong) NSMutableArray *items;

@end

@implementation DFInputAtCache

- (instancetype)init
{
    self = [super init];
    if (self) {
        _items = [[NSMutableArray alloc] init];
    }
    return self;
}

- (NSArray *)allAtShowName:(NSString *)sendText {
    NSArray *names = [self matchString:sendText];
    NSMutableArray *uids = [[NSMutableArray alloc] init];
    for (NSString *name in names) {
        DFInputAtItem *item = [self item:name];
        if (item)
        {
            [uids addObject:item];
        }
    }
    return [NSArray arrayWithArray:uids];
}

- (NSArray *)allAtUid:(NSString *)sendText
{
    NSArray *names = [self matchString:sendText];
    NSMutableArray *uids = [[NSMutableArray alloc] init];
    for (NSString *name in names) {
        DFInputAtItem *item = [self item:name];
        if (item)
        {
            [uids addObject:item.uid];
        }
    }
    return [NSArray arrayWithArray:uids];
}


- (void)clean
{
    [self.items removeAllObjects];
}

- (void)addAtItem:(DFInputAtItem *)item
{
    // TODO: 去重
    [_items addObject:item];
}

- (DFInputAtItem *)item:(NSString *)name
{
    __block DFInputAtItem *item;
    [_items enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        DFInputAtItem *object = obj;
        if ([object.name isEqualToString:name])
        {
            item = object;
            *stop = YES;
        }
    }];
    return item;
}

- (DFInputAtItem *)removeName:(NSString *)name
{
    __block DFInputAtItem *item;
    [_items enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        DFInputAtItem *object = obj;
        if ([object.name isEqualToString:name]) {
            item = object;
            *stop = YES;
        }
    }];
    if (item) {
        [_items removeObject:item];
    }
    return item;
}

- (NSArray *)matchString:(NSString *)sendText
{
    NSString *pattern = [NSString stringWithFormat:@"%@([^%@]+)%@",DFInputAtStartChar, DFInputAtEndChar, DFInputAtEndChar];
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    NSArray *results = [regex matchesInString:sendText options:0 range:NSMakeRange(0, sendText.length)];
    NSMutableArray *matchs = [[NSMutableArray alloc] init];
    for (NSTextCheckingResult *result in results) {
        NSString *name = [sendText substringWithRange:result.range];
//        name = [name substringFromIndex:1];
//        name = [name substringToIndex:name.length -1];
        [matchs addObject:name];
    }
    return matchs;
}

@end
