//
//  OnTimeNotification.m
//  OnTime
//
//  Created by Daisuke Fujiwara on 10/12/12.
//  Copyright (c) 2012 HDProject. All rights reserved.
//

#import "OnTimeNotification.h"

static NSString * const notificationTitle = @"OnTime!";
static NSString * const snoozeLabel = @"Snooze";
static NSString * const notificationMessage =
    @"Leave at %@ to catch %@ at %@; %@ there will take %d minute(s).";
static NSString * const reminderMessage =
    @"Leave now to catch %@ at %@; %@ there will take %d minute(s).";

static NSString * const arrivalTimeKey = @"arrivalTimeInMinutes";
static NSString * const destinationKey = @"destination";

// date format is specified to be "12:14 AM"
static NSString * const dateFormatTempalte = @"hh:mm a";

// notification data dictionary keys
static NSString * const bufferTimeKey = @"bufferTime";
static NSString * const durationKey = @"duration";
static NSString * const modeKey = @"mode";
static NSString * const startInfoKey = @"startInfo";
static NSString * const destinationInfoKey = @"destinationInfo";
static NSString * const estimateKey = @"arrivalEstimates";

// notification data sub dictionary keys
static NSString * const stationNameKey = @"name";
static NSString * const stationIdKey = @"id";

// user info dictionary key
NSString * const kStartId = @"startId";
NSString * const kDestinationId = @"destinationId";
NSString * const kSnoozableKey = @"isSnoozable";


@interface OnTimeNotification () {
    NSArray *notificationEstimates;
    NSNumber *durationTime;
    NSNumber *bufferTime;
    NSString *mode;
    NSDictionary *startStationInfo;
    NSDictionary *destinationStationInfo;
}
@end

@implementation OnTimeNotification

- (id)initWithNotificationData:(NSDictionary *)notificationData {
    self = [super init];
    if (self) {
        bufferTime = [notificationData objectForKey:bufferTimeKey];
        durationTime = [notificationData objectForKey:durationKey];
        mode = [notificationData objectForKey:modeKey];
        startStationInfo = [notificationData objectForKey:startInfoKey];
        destinationStationInfo = [notificationData objectForKey:destinationInfoKey];
        notificationEstimates = [notificationData objectForKey:estimateKey];
    }
    return self;
}

- (id)init {
    [NSException raise:@"Default init failed"
                format:@"Reason: init is not supported by %@", [self class]];
    return nil;
}

- (void)scheduleNotification:(NSInteger)notificationIndex {
    NSDictionary *notificationData =
        [notificationEstimates objectAtIndex:notificationIndex];

    NSString *destination = [notificationData objectForKey:destinationKey];
    NSInteger arrivalTimeInSeconds =
        [[notificationData objectForKey:arrivalTimeKey] intValue] * 60;
    NSInteger scheduledTimeInSeconds = arrivalTimeInSeconds -
    [durationTime intValue] - [bufferTime intValue];
    NSDate *scheduledTime = [NSDate dateWithTimeIntervalSinceNow:scheduledTimeInSeconds];
    //NSDate *scheduledTime = [NSDate dateWithTimeIntervalSinceNow:15];

    // setting up date formatter
    NSLocale *locale = [NSLocale currentLocale];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    NSString *dateFormat = [NSDateFormatter dateFormatFromTemplate:dateFormatTempalte
                                                           options:0
                                                            locale:locale];
    [formatter setDateFormat:dateFormat];
    [formatter setLocale:locale];
    NSString *scheduledTimeString = [formatter stringFromDate:scheduledTime];

    UIAlertView *av = [[UIAlertView alloc] initWithTitle:notificationTitle
                                                 message:[NSString stringWithFormat:notificationMessage,
                                                          scheduledTimeString,
                                                          destination,
                                                          [startStationInfo objectForKey:stationNameKey],
                                                          mode,
                                                          [durationTime intValue] / 60]
                                                delegate:nil
                                       cancelButtonTitle:@"OK"
                                       otherButtonTitles:nil];
    [av show];

    // create local notification to notify at the appropriate time

    // first create user info dictionary
    NSDictionary *userInfo = @{kStartId: startStationInfo[stationIdKey],
                               kDestinationId: destinationStationInfo[stationIdKey],
                               kSnoozableKey: @YES};
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    [notification setFireDate:scheduledTime];
    [notification setAlertAction:snoozeLabel];
    [notification setAlertBody:[NSString stringWithFormat:reminderMessage,
                                destination,
                                [startStationInfo objectForKey:stationNameKey],
                                mode,
                                [durationTime intValue] / 60]];
    [notification setHasAction:YES];
    [notification setUserInfo:userInfo];
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
}
@end