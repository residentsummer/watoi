//
//  main.m
//  WhatsApp Importer
//
//  Created by Anton S on 17/01/17.
//  Copyright © 2017 Anton S. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@interface Importer : NSObject
- (void) initializeCoreDataWithMomd:(NSString *)momdPath andDatabase:(NSString *)dbPath;
- (void) dumpEntityDescriptions;
- (void) peekMessages;

@property (nonatomic, strong) NSManagedObjectContext *moc;
@property (nonatomic, strong) NSManagedObjectModel *mom;
@property (nonatomic, strong) NSPersistentStore *store;
@end

int main(int argc, const char * argv[]) {
    if (argc < 3) {
        NSLog(@"usage: %s <momd> <iphone sqlite>", argv[0]);
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
        [imp initializeCoreDataWithMomd:[args objectAtIndex:0]
                            andDatabase:[args objectAtIndex:1]];
        //[imp dumpEntityDescriptions];
        [imp peekMessages];
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

- (void) dumpEntityDescriptions {
    NSAssert(self.mom != nil, @"MOM must be initialized to dump descriptions");
    for (NSEntityDescription* desc in self.mom.entities) {
        NSLog(@"%@\n\n", desc.name);
    }
}

- (void) peekMessages {
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

@end
