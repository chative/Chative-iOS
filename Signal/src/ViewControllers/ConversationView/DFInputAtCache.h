//
//  DFInputCache.h
//  Signal
//
//  Created by Felix on 2021/7/7.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define DFInputAtStartChar  @"@"
#define DFInputAtEndChar    @" "

@interface DFInputAtItem : NSObject

@property (nonatomic,copy) NSString *name;

@property (nonatomic,copy) NSString *uid;

@property (nonatomic,assign) NSRange range;

@end


@interface DFInputAtCache : NSObject

- (NSArray *)allAtShowName:(NSString *)sendText;

- (NSArray *)allAtUid:(NSString *)sendText;

- (void)clean;

- (void)addAtItem:(DFInputAtItem *)item;

- (DFInputAtItem *)item:(NSString *)name;

- (DFInputAtItem *)removeName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
