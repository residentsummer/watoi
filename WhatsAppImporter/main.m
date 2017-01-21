//
//  main.m
//  WhatsApp Importer
//
//  Created by Anton S on 17/01/17.
//  Copyright © 2017 Anton S. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <sqlite3.h>

@interface Importer : NSObject
- (void) initializeCoreDataWithMomd:(NSString *)momdPath andDatabase:(NSString *)dbPath;
- (void) initializeAndroidStoreFromPath:(NSString *)storePath;
- (void) dumpEntityDescriptions;
- (void) peekAndroidMessages;
- (void) peekiOSMessages;

@property (nonatomic, strong) NSManagedObjectContext *moc;
@property (nonatomic, strong) NSManagedObjectModel *mom;
@property (nonatomic, strong) NSPersistentStore *store;
@property (nonatomic) sqlite3 *androidStore;
@end

int main(int argc, const char * argv[]) {
    if (argc < 4) {
        NSLog(@"usage: %s <android sqlite> <momd> <iphone sqlite>", argv[0]);
        return 1;
    }

    @autoreleasepool {
        NSMutableArray *args = [NSMutableArray new];
        // Skip executable name
        for (unsigned int i = 1; i < argc; ++i) {
            [args addObject:[NSString stringWithCString:argv[i]]];
            NSLog(@"%@", [args objectAtIndex:(i-1)]);
        }

        Importer *imp = [Importer new];
        [imp initializeAndroidStoreFromPath:[args objectAtIndex:0]];
        [imp initializeCoreDataWithMomd:[args objectAtIndex:1]
                            andDatabase:[args objectAtIndex:2]];
        //[imp dumpEntityDescriptions];
        [imp peekAndroidMessages];
    }
    return 0;
}


@implementation Importer

- (void) initializeCoreDataWithMomd:(NSString *)momdPath andDatabase:(NSString *)dbPath {
    NSURL *modelURL = [NSURL fileURLWithPath:momdPath];
    NSManagedObjectModel *mom = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    NSAssert(mom != nil, @"Error initializing Managed Object Model");
    self.mom = mom;

    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];
    NSManagedObjectContext *moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [moc setPersistentStoreCoordinator:psc];
    self.moc = moc;

    NSError *error = nil;
    NSURL *storeURL = [NSURL fileURLWithPath:dbPath];
    NSPersistentStore *store = [psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error];
    NSAssert(store != nil, @"Error initializing PSC: %@\n%@", [error localizedDescription], [error userInfo]);

    self.store = store;
    NSLog(@"CoreData loaded");
}

- (void) initializeAndroidStoreFromPath:(NSString *)storePath {
    sqlite3 *store = nil;

    if (sqlite3_open([storePath UTF8String], &store) != SQLITE_OK) {
        NSLog(@"%s", sqlite3_errmsg(store));
    }

    NSLog(@"Android store loaded");
    self.androidStore = store;
}

- (void) dumpEntityDescriptions {
    NSAssert(self.mom != nil, @"MOM must be initialized to dump descriptions");
    for (NSEntityDescription* desc in self.mom.entities) {
        NSLog(@"%@\n\n", desc.name);
    }
}

- (void) peekiOSMessages {
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"WAMessage"];
    fetchRequest.returnsObjectsAsFaults = NO;
    [fetchRequest setFetchLimit:100];

    NSError *error = nil;
    NSArray *results = [self.moc executeFetchRequest:fetchRequest error:&error];
    if (!results) {
        NSLog(@"Error fetching objects: %@\n%@", [error localizedDescription], [error userInfo]);
        abort();
    }

    for (NSManagedObject *msg in results) {
        NSLog(@"%@", [msg valueForKey:@"text"]);
    }
}

- (NSMutableArray *) executeQuery:(NSString *)query {
    NSMutableArray *results = [NSMutableArray new];
    NSMutableArray *columnNames = nil;
    sqlite3_stmt *prepared;
    int totalColumns = 0;
    int result = FALSE;

    result = sqlite3_prepare_v2(self.androidStore, [query UTF8String], -1, &prepared, NULL);
    totalColumns = sqlite3_column_count(prepared);
    if (result != SQLITE_OK) {
        NSLog(@"%s", sqlite3_errmsg(self.androidStore));
        abort();
    }

    // It's a SELECT
    if (totalColumns > 0) {
        columnNames = [NSMutableArray arrayWithCapacity:totalColumns];
        for (int i = 0; i < totalColumns; ++i) {
            [columnNames addObject:[NSString stringWithUTF8String:sqlite3_column_name(prepared, i)]];
        }
    }

    // Fetching rows one by one
    while ((result = sqlite3_step(prepared)) == SQLITE_ROW) {
        NSMutableArray *row = [NSMutableArray arrayWithCapacity:totalColumns];
        int columnsCount = sqlite3_data_count(prepared);

        for (int i = 0; i < columnsCount; ++i) {
            int columnType = sqlite3_column_type(prepared, i);
            NSObject *value = nil;

            switch (columnType) {
                case SQLITE_INTEGER:
                    value = [NSNumber numberWithInt:sqlite3_column_int(prepared, i)];
                    break;
                case SQLITE_FLOAT:
                    value = [NSNumber numberWithDouble:sqlite3_column_double(prepared, i)];
                    break;
                case SQLITE_TEXT:
                    value = [NSString stringWithUTF8String:(const char *) sqlite3_column_text(prepared, i)];
                    break;
                case SQLITE_BLOB: // Ignore blobs for now
                case SQLITE_NULL:
                    break;
            }

            if (!value) {
                value = [NSNull null];
            }

            [row addObject:value];
        }

        [results addObject:[NSDictionary dictionaryWithObjects:row
                                                       forKeys:columnNames]];
    }

    sqlite3_finalize(prepared);
    return results;
}

- (void) peekAndroidMessages {
    NSMutableArray *results = nil;
    results = [self executeQuery:@"SELECT * FROM messages LIMIT 100;"];

    for (NSDictionary *row in results) {
        NSLog(@"%@", [row objectForKey:@"data"]);
    }
}

@end
