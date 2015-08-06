//
//  SnowplowEventStore.h
//  Snowplow
//
//  Copyright (c) 2013-2014 Snowplow Analytics Ltd. All rights reserved.
//
//  This program is licensed to you under the Apache License Version 2.0,
//  and you may not use this file except in compliance with the Apache License
//  Version 2.0. You may obtain a copy of the Apache License Version 2.0 at
//  http://www.apache.org/licenses/LICENSE-2.0.
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the Apache License Version 2.0 is distributed on
//  an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
//  express or implied. See the Apache License Version 2.0 for the specific
//  language governing permissions and limitations there under.
//
//  Authors: Jonathan Almeida
//  Copyright: Copyright (c) 2013-2014 Snowplow Analytics Ltd
//  License: Apache License Version 2.0
//

#import "SnowplowEventStore.h"
#import "SnowplowPayload.h"
#import "SnowplowUtils.h"
#import <FMDB.h>

@implementation SnowplowEventStore {
    @private
    NSString *           _dbPath;
    FMDatabaseQueue *    _queue;
}

static NSString * const _queryCreateTable               = @"CREATE TABLE IF NOT EXISTS 'events' (id INTEGER PRIMARY KEY, eventData BLOB, pending INTEGER, dateCreated TIMESTAMP DEFAULT CURRENT_TIMESTAMP)";
static NSString * const _querySelectAll                 = @"SELECT * FROM 'events'";
static NSString * const _querySelectCount               = @"SELECT Count(*) FROM 'events'";
static NSString * const _querySelectCountPending        = @"SELECT Count(*) FROM 'events' WHERE pending=1";
static NSString * const _querySelectCountNonPending     = @"SELECT Count(*) FROM 'events' WHERE pending=0";
static NSString * const _queryInsertEvent               = @"INSERT INTO 'events' (eventData, pending) VALUES (?, 0)";
static NSString * const _querySelectId                  = @"SELECT * FROM 'events' WHERE id=?";
static NSString * const _queryDeleteId                  = @"DELETE FROM 'events' WHERE id=?";
static NSString * const _querySelectPending             = @"SELECT * FROM 'events' WHERE pending=1";
static NSString * const _querySelectNonPending          = @"SELECT * FROM 'events' WHERE pending=0";
static NSString * const _querySetPending                = @"UPDATE events SET pending=1 WHERE id=?";
static NSString * const _querySetNonPending             = @"UPDATE events SET pending=0 WHERE id=?";


@synthesize appId;

- (id) init {
    self = [super init];
    NSString *libraryPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    _dbPath = [libraryPath stringByAppendingPathComponent:@"snowplowEvents.sqlite"];
    if (self){
        _queue = [FMDatabaseQueue databaseQueueWithPath:_dbPath];
        [self createTable];
    }
    return self;
}

- (void) dealloc {
    [_queue close];
}

- (BOOL) createTable {
    __block BOOL res = false;
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db open]) {
            res = [db executeStatements:_queryCreateTable];
        } else {
            res = false;
        }
    }];
    return res;
}

- (long long int) insertEvent:(SnowplowPayload *)payload {
    return [self insertDictionaryData:[payload getPayloadAsDictionary]];
}

- (long long int) insertDictionaryData:(NSDictionary *)dict {
    __block long long int res = -1;
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db open]) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:[self getCleanDictionary:dict] options:0 error:nil];
            [db executeUpdate:_queryInsertEvent, data];
            res = (long long int) [db lastInsertRowId];
        } else {
            res = -1;
        }
    }];
    return res;
}

- (NSDictionary *) getCleanDictionary:(NSDictionary *)dict {
    NSMutableDictionary *cleanDictionary = [NSMutableDictionary dictionary];
    for (NSString * key in [dict allKeys]) {
        if (![[dict objectForKey:key] isKindOfClass:[NSNull class]]) {
            [cleanDictionary setObject:[dict objectForKey:key] forKey:key];
        }
    }
    return cleanDictionary;
}

- (BOOL) removeEventWithId:(long long int)id_ {
    __block BOOL res = false;
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db open]) {
            DLog(@"Removing %lld from database now.", id_);
            res = [db executeUpdate:_queryDeleteId, [NSNumber numberWithLongLong:id_]];
        } else {
            res = false;
        }
    }];
    return res;
}

- (void) removeAllEvents {
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db open]) {
            FMResultSet *s = [db executeQuery:_querySelectAll];
            while ([s next]) {
                long long int index = [s longLongIntForColumn:@"ID"];
                [self removeEventWithId:index];
            }
        }
    }];
}

- (BOOL) setPendingWithId:(long long int)id_ {
    __block BOOL res = false;
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db open]) {
            res = [db executeUpdate:_querySetPending, id_];
        } else {
            res = false;
        }
    }];
    return res;
}

- (BOOL) removePendingWithId:(long long int)id_ {
    __block BOOL res = false;
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db open]) {
            res = [db executeUpdate:_querySetNonPending, id_];
        } else {
            res = false;
        }
    }];
    return res;
}

- (NSUInteger) count {
    __block NSUInteger num = 0;
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db open]) {
            FMResultSet *s = [db executeQuery:_querySelectCount];
            while ([s next]) {
                num = [[NSNumber numberWithInt:[s intForColumnIndex:0]] integerValue];
            }
        }
    }];
    return num;
}

- (NSUInteger) countPending {
    __block NSUInteger num = 0;
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db open]) {
            FMResultSet *s = [db executeQuery:_querySelectCountPending];
            while ([s next]) {
                num = [[NSNumber numberWithInt:[s intForColumnIndex:0]] integerValue];
            }
        }
    }];
    return num;
}

- (NSUInteger) countNonPending {
    __block NSUInteger num = 0;
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db open]) {
            FMResultSet *s = [db executeQuery:_querySelectCountNonPending];
            while ([s next]) {
                num = [[NSNumber numberWithInt:[s intForColumnIndex:0]] integerValue];
            }
        }
    }];
    return num;
}

- (NSDictionary *) getEventWithId:(long long int)id_ {
    __block NSDictionary *dict = nil;
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db open]) {
            FMResultSet *s = [db executeQuery:_querySelectId, [NSNumber numberWithLongLong:id_]];
            while ([s next]) {
                NSData * data = [s dataForColumn:@"eventData"];
                DLog(@"Item: %d %@ %@",
                     [s intForColumn:@"ID"],
                     [s dateForColumn:@"dateCreated"],
                     [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
                dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:0];
            }
        }
    }];
    return dict;
}

- (NSArray *) getAllEvents {
    return [self getAllEventsWithQuery:_querySelectAll];
}

- (NSArray *) getAllNonPendingEvents {
    return [self getAllEventsWithQuery:_querySelectNonPending];
}

- (NSArray *) getAllNonPendingEventsLimited:(NSUInteger)limit {
    NSString *query = [NSString stringWithFormat:@"%@ LIMIT %lu", _querySelectNonPending, (unsigned long)limit];
    return [self getAllEventsWithQuery:query];
}

- (NSArray *) getAllPendingEvents {
    __block NSMutableArray *res = [[NSMutableArray alloc] init];
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db open]) {
            FMResultSet *s = [db executeQuery:_querySelectPending];
            while ([s next]) {
                [res addObject:[s dataForColumn:@"eventData"]];
            }
        }
    }];
    return res;
}

- (NSArray *) getAllEventsWithQuery:(NSString *)query {
    __block NSMutableArray *res = [[NSMutableArray alloc] init];
    [_queue inDatabase:^(FMDatabase *db) {
        if ([db open]) {
            FMResultSet *s = [db executeQuery:query];
            while ([s next]) {
                long long int index = [s longLongIntForColumn:@"ID"];
                NSData * data =[s dataForColumn:@"eventData"];
                NSDate * date = [s dateForColumn:@"dateCreated"];
                DLog(@"Item: %lld %@ %@",
                     index,
                     [date description],
                     [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
                NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:0];
                NSMutableDictionary * eventWithSqlMetadata = [[NSMutableDictionary alloc] init];
                [eventWithSqlMetadata setValue:dict forKey:@"eventData"];
                [eventWithSqlMetadata setValue:[NSNumber numberWithLongLong:index] forKey:@"ID"];
                [eventWithSqlMetadata setValue:date forKey:@"dateCreated"];
                [res addObject:eventWithSqlMetadata];
            }
        }
    }];
    return res;
}

- (long long int) getLastInsertedRowId {
    __block long long int res = -1;
    [_queue inDatabase:^(FMDatabase *db) {
        res = [db lastInsertRowId];
    }];
    return res;
}

@end
