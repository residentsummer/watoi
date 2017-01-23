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
- (void) import;
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
        [imp import];
    }
    return 0;
}

// The meat

@interface Importer ()
@property (nonatomic, strong) NSManagedObjectContext *moc;
@property (nonatomic, strong) NSManagedObjectModel *mom;
@property (nonatomic, strong) NSPersistentStore *store;
@property (nonatomic) sqlite3 *androidStore;

@property (nonatomic, strong) NSMutableDictionary *chats;
@property (nonatomic, strong) NSMutableDictionary *chatMembers;

- (void) importChats;
- (void) saveCoreData;

// Debug stuff
- (void) dumpEntityDescriptions;
- (void) peekAndroidMessages;
- (void) peekiOSMessages;
@end

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

- (void) import {
    //[self dumpEntityDescriptions];
    [self importChats];
}

- (void) dumpEntityDescriptions {
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
        NSString *sender = [[msg valueForKey:@"isFromMe"] intValue] ?
                            @"me" : [msg valueForKey:@"fromJID"];
        NSLog(@"%@: %@", sender, [msg valueForKey:@"text"]);
    }
}

- (NSMutableArray *) executeQuery:(NSString *)query {
    NSNull *null = [NSNull null];  // Stupid singleton
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
                    value = [NSNumber numberWithLongLong:sqlite3_column_int64(prepared, i)];
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
                value = null;
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
        NSString *sender = [[row objectForKey:@"key_from_me"] intValue] ?
                            @"me" : [row objectForKey:@"key_remote_jid"];
        NSLog(@"%@: %@", sender, [row objectForKey:@"data"]);
    }
}

- (void) importChats {
    NSArray * androidChats = [self executeQuery:@"SELECT * FROM chat_list"];
    NSNull *null = [NSNull null];  // Stupid singleton

    // Support structures for messages import
    self.chats = [NSMutableDictionary new];
    self.chatMembers = [NSMutableDictionary new];

    for (NSDictionary *achat in androidChats) {
        NSManagedObject *chat = [NSEntityDescription insertNewObjectForEntityForName:@"WAChatSession"
                                                               inManagedObjectContext:self.moc];
        BOOL isGroup = ([achat objectForKey:@"subject"] != null);
        NSString *chatJID = [achat objectForKey:@"key_remote_jid"];

        [chat setValue:chatJID forKey:@"contactJID"];

        NSNumber *archived = [NSNumber numberWithBool:([achat objectForKey:@"archived"] != null)];
        [chat setValue:archived forKey:@"archived"];

        // This field should contain contact name for non-groups
        NSString *partnerName = [achat objectForKey:@"subject"];
        if ((id) partnerName == null) {
            partnerName = @"";
        }
        [chat setValue:partnerName forKey:@"partnerName"];

        // FIXME
        [chat setValue:@0 forKey:@"messageCounter"];

        // We'll use this dict to link messages with chats
        [self.chats setObject:chat forKey:chatJID];

        if (!isGroup) {
            continue;
        }

        // Group chats should have associated GroupInfo objects
        NSManagedObject *group = [NSEntityDescription insertNewObjectForEntityForName:@"WAGroupInfo"
                                                               inManagedObjectContext:self.moc];
        // It's stored in millis in android db
        double sinceEpoch = ([[achat objectForKey:@"creation"] doubleValue] / 1000.0);
        [group setValue:[NSDate dateWithTimeIntervalSince1970:sinceEpoch] forKey:@"creationDate"];

        [group setValue:chat forKey:@"chatSession"];

        // Messages in groups are linked to members
        NSMutableDictionary *members = [NSMutableDictionary new];
        [self.chatMembers setObject:members forKey:chatJID];

        // Insert group members
        NSString *query = @"SELECT * from group_participants WHERE gjid == '%@'";
        NSMutableArray *amembers = [self executeQuery:[NSString stringWithFormat:query, chatJID]];
        for (NSDictionary *amember in amembers) {
            NSString *memberJID = [amember objectForKey:@"jid"];
            if ([memberJID isEqualToString:@""]) {
                // This entry corresponds to our account, should add it as well.
                // But how to get the JID?
                continue;
            }

            NSManagedObject *member = [NSEntityDescription insertNewObjectForEntityForName:@"WAGroupMember"
                                                                    inManagedObjectContext:self.moc];

            [member setValue:memberJID forKey:@"memberJID"];
            [member setValue:[amember objectForKey:@"admin"] forKey:@"isAdmin"];
            // Inactive members are in group_participants_history, I guess
            [member setValue:@YES forKey:@"isActive"];

            // FIXME Take it from wa.db
            NSString *fakeContactName = [memberJID componentsSeparatedByString:@"@"][0];
            [member setValue:fakeContactName forKey:@"contactName"];

            // Associate with current chat
            [member setValue:chat forKey:@"chatSession"];
            [members setObject:member forKey:memberJID];
        }
    }

    [self saveCoreData];
    NSLog(@"Loaded %lu chat(s)", (unsigned long)[androidChats count]);
}

- (void) saveCoreData {
    NSError *error = nil;
    if ([self.moc save:&error] == NO) {
        NSAssert(NO, @"Error saving context: %@\n%@", [error localizedDescription], [error userInfo]);
    }
}

@end
