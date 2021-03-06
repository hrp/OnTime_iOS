//
//  OnTimeAbstractStationStore.m
//  OnTime
//
//  Created by Daisuke Fujiwara on 12/19/12.
//  Copyright (c) 2012 HDProject. All rights reserved.
//

#import "OnTimeAbstractStationStore.h"
#import "OnTimeConnection.h"
#import "OnTimeConstants.h"
#import "OnTimeUIStringFactory.h"

@implementation OnTimeAbstractStationStore

@synthesize nearbyStations = nearbyStations_;
@synthesize locationManager = locationManager_;

- (id)init {
    self = [super init];
    if (self) {
        locationManager_ = [[CLLocationManager alloc] init];
    }
    return self;
}

- (void)issueNearbyStationRequest:(NSString *)urlString
                   withCompletion:(void (^)(NSDictionary *, NSError *))block {
    // set up the HTTP GET request to retrieve nearby stations of the given
    // location.
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    OnTimeConnection *connection = [[OnTimeConnection alloc] initWithRequest:req];

    [connection setCompletionBlock:block];
    [connection start];
    NSLog(@"requesting stations at %@", urlString);
}

- (void)issueNotificationRequest:(NSString *)urlString
                        withData:(NSDictionary *)requestData
                  withCompletion:(void (^)(NSDictionary *notificationData, NSError *err))block {
    // set up the HTTP POST request for the notification request
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    NSData *postData = [NSJSONSerialization dataWithJSONObject:requestData
                                                       options:0
                                                         error:nil];

    [req setHTTPMethod:@"POST"];
    [req setHTTPBody:postData];
    [req setValue:@"application/json" forHTTPHeaderField:@"content-type"];

    OnTimeConnection *connection = [[OnTimeConnection alloc] initWithRequest:req];
    [connection setCompletionBlock:block];
    [connection start];
    NSLog(@"request notification for %@", requestData);
}



#pragma mark - user location related methods


- (NSDictionary *)currentUserLocation {
    CLLocationCoordinate2D coords = self.locationManager.location.coordinate;
    NSString *longitude = [NSString stringWithFormat:@"%f", coords.longitude];
    NSString *latitude = [NSString stringWithFormat:@"%f", coords.latitude];
    return @{kLongitudeKey: longitude, kLatitudeKey: latitude};
}


#pragma mark - transit notification related methods


- (NSDateFormatter *)dateFormatter {
    static NSDateFormatter *formatter = nil;
    if (!formatter) {
        formatter = [[NSDateFormatter alloc] init];
        NSLocale *locale = [NSLocale currentLocale];
        NSString *dateFormat = [NSDateFormatter dateFormatFromTemplate:@"hh:mm a"
                                                               options:0
                                                                locale:locale];
        [formatter setDateFormat:dateFormat];
        [formatter setLocale:locale];
    }
    return formatter;
}


- (void)displayTransitNotification:(NSString *)notificationMessage {
    // Create the alert to inform users what time they will have to leave for
    // the station.
    UIAlertView *av = [[UIAlertView alloc]
                       initWithTitle:[OnTimeUIStringFactory notificationTitle]
                       message:notificationMessage
                       delegate:nil
                       cancelButtonTitle:[OnTimeUIStringFactory okButtonLabel]
                       otherButtonTitles:nil];
    [av show];
}


- (void)scheduleTransitReminderNotification:(NSString *)notificationMessage
                                     atTime:(NSDate *)scheduledTime
                                   withInfo:(NSDictionary *)userInfo {

    // Create local notification to notify at the appropriate time.
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    [notification setFireDate:scheduledTime];
    [notification setAlertAction:[OnTimeUIStringFactory snoozeLabel]];
    [notification setAlertBody:notificationMessage];
    [notification setHasAction:YES];
    [notification setUserInfo:userInfo];
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
}


#pragma mark - protocol implementations

+ (OnTimeAbstractStationStore *)sharedStore {
    return nil;
}

- (void)getNearbyStations:(CLLocation *)currentLocation
           withCompletion: (void (^)(NSError *err))block {
    return;
}

- (void)requestNotification:(NSDictionary *)requestData
             withCompletion:(void (^)(NSError *err))block {
    return;
}

- (void)processPendingNotification:(NSDictionary *)notificationData {
    return;
}

- (NSArray *)nearbyStations:(NSInteger)numStations {
    NSArray *stations = self.nearbyStations;
    // making sure that numStations never exceeds the available station number
    numStations = numStations > [stations count] ? [stations count] : numStations;

    NSRange range;
    range.location = 0;
    range.length = numStations;
    return [stations subarrayWithRange:range];
}

@end
