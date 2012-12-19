//
//  OnTimeViewController.m
//  OnTime
//
//  Created by Daisuke Fujiwara on 9/23/12.
//  Copyright (c) 2012 HDProject. All rights reserved.
//

#import "BartViewController.h"
#import "StationChoiceViewController.h"
#import "BartStationStore.h"
#import "OnTimeNotification.h"
#import "OnTimeStationMapAnnotation.h"
#import "OnTimeUIStringFactory.h"

// Navigation bar related constants
static NSString * const OnTimeTitle = @"Bart";

// Table view constants

// Error messages
static NSString * const invalidTripTitle = @"Not a valid trip";
static NSString * const missingStationMessage =
    @"Please select source and destination.";
static NSString * const identicalStationMessage =
    @"Please pick two different stations.";

static NSString * const nearbyStationErrorTitle = @"Could not get nearby stations.";
static NSString * const notificationErrorTitle = @"Could not submit notification request.";
static NSString * const errorMessage = @"Please try again later.";

static NSString * const missingParameterMessage = @"Not all parameters were provided.";
static NSString * const failedToCreateNoficationMessage = @"Failed to create notification.";
static NSString * const noTimeAvailableMessage = @"No time is available.";
static NSString * const defaultNotificationErrorMessage= @"An error occurred. Please try again.";

// Notification data dictionary keys
static NSString * const successKey = @"success";
static NSString * const errorCodeKey = @"errorCode";

// Distance threshold for the updated user location relative to
// the previously recorded user location. If this threshold is exceeded, the
// updated user location is processed. This is expressed in meters.
const static CLLocationDistance userLocationDistanceThreshold = 200;

@interface BartViewController () {
    NSMutableSet *tableRowsToUpdate_;
    OnTimeStationMapAnnotation *sourceStationAnnotation_;
    OnTimeStationMapAnnotation *targetStationAnnotation_;
    CLLocation *lastRecordedLocation_;
    UIView *distanceLabelBackgroundView_;
}

// Handles the notification data retrieved from the server response.
- (void)handleNotificationData:(NSDictionary *)notificationData;

// Makes a notification request to the server with the given request data.
- (void)makeNotificationRequest:(NSDictionary *)requestData;

// Configures the UI given the current state of the view controlloer.
- (void)configureUI;

// Calculates the distance between the given two locations and
// updates the distance label on the map to indicate how far the user is
// from the selected starting station.
- (void)updateDistanceToStationFrom:(CLLocation *)fromLocation
                                 to:(CLLocation *)stationLocation;

@end

@implementation BartViewController


# pragma mark - inits


// designated initializer
- (id)initWithNibName:(NSString *)nibNameOrNil
               bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialize the set of rows to update when the view appears.
        // This is used for cases like when users has made a source station.
        tableRowsToUpdate_ = [NSMutableSet set];

        // Set navigation bar title.
        self.navigationItem.title = OnTimeTitle;

        sourceStationAnnotation_ = [[OnTimeStationMapAnnotation alloc] init];
        targetStationAnnotation_ = [[OnTimeStationMapAnnotation alloc] init];
    }
    return self;
}


#pragma mark - view cycle methods


- (void)viewDidLoad {
    [userMapView setShowsUserLocation:YES];

    distanceLabelBackgroundView_ = [[UIView alloc] initWithFrame:distanceLabel.frame];
    distanceLabelBackgroundView_.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
    UIViewAutoresizingFlexibleTopMargin;
    distanceLabelBackgroundView_.backgroundColor = [UIColor colorWithWhite:0.58
                                                                     alpha:.75];
    [userMapView addSubview:distanceLabelBackgroundView_];

    // UI needs to be configured approriately when the view is loaded (e.g.
    // enable or disable based on the previous state).
    [self configureUI];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // Update the rows that needs to be updated.
    if ([tableRowsToUpdate_ count] > 0) {
        NSIndexPath *sourceStationIndexPath = [NSIndexPath indexPathForRow:0
                                                                inSection:0];
        if ([tableRowsToUpdate_ containsObject:sourceStationIndexPath]) {
            // Animate the map region change since when the table rows update is
            // required, then it also means that the map annotation location
            // has changed.
            MKMapPoint currentPoint = MKMapPointForCoordinate(userMapView.userLocation.coordinate);
            MKMapPoint stationPoint = MKMapPointForCoordinate(sourceStationAnnotation_.coordinate);

            // Generate map rect from those two map points.
            MKMapRect mapRect = MKMapRectMake (fmin(currentPoint.x, stationPoint.x),
                                          fmin(currentPoint.y, stationPoint.y),
                                          fabs(currentPoint.x - stationPoint.x),
                                          fabs(currentPoint.y - stationPoint.y));

            // Determine the mid point in the map rect.
            MKMapPoint middlePoint;
            middlePoint.x = MKMapRectGetMidX(mapRect);
            middlePoint.y = MKMapRectGetMidY(mapRect);
            CLLocationCoordinate2D centerCoordinate = MKCoordinateForMapPoint(middlePoint);


            // Calculate the distance between those two points.
            CLLocation *stationLocation =
                [[CLLocation alloc] initWithCoordinate:sourceStationAnnotation_.coordinate
                                              altitude:0
                                    horizontalAccuracy:0
                                      verticalAccuracy:-1
                                             timestamp:[NSDate date]];
            CLLocationDistance distance = [userMapView.userLocation.location
                                           distanceFromLocation:stationLocation];
            MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(centerCoordinate,
                                                                           distance,
                                                                           distance);
            [userMapView setRegion:region animated:YES];

            // Also update the distance label to the source station.
            [self updateDistanceToStationFrom:userMapView.userLocation.location
                                           to:stationLocation];
        }

        // Animate the row updates
        [tableView reloadRowsAtIndexPaths:[tableRowsToUpdate_ allObjects]
                         withRowAnimation:UITableViewRowAnimationRight];
        [tableRowsToUpdate_ removeAllObjects];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}


#pragma mark - map view delegate methods


- (void)mapView:(MKMapView *)view didUpdateUserLocation:(MKUserLocation *)userLocation {
    // Check if the updated location is farther than the thredhold distance
    // from the previously recorded location. If not, then simply do nothing.
    if (lastRecordedLocation_) {
        CLLocationDistance distance =
            [lastRecordedLocation_ distanceFromLocation:userLocation.location];
        if (distance <= userLocationDistanceThreshold) {
            NSLog(@"Not processing the user location because the distance is %f <= %f",
                  distance, userLocationDistanceThreshold);
            return;
        }
    }

    [activityIndicator startAnimating];
    lastRecordedLocation_ = [userLocation location];

    CLLocationCoordinate2D coords = lastRecordedLocation_.coordinate;
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coords, 500, 500);
    [userMapView setRegion:region animated:YES];

    // callback method
    void (^displayNearbyStations)(NSArray *nearbyStations, NSError *err) =
    ^void(NSArray *nearbyStations, NSError *err){
        [activityIndicator stopAnimating];
        if (err) {
            // display the error message if retrieve nearby stations was
            // not successful
            UIAlertView *errorAlert = [[UIAlertView alloc]
                                       initWithTitle:nearbyStationErrorTitle
                                       message:errorMessage
                                       delegate:nil
                                       cancelButtonTitle:[OnTimeUIStringFactory okButtonLabel]
                                       otherButtonTitles:nil];
            [errorAlert show];
        } else {
            // Also update the distance label to the source station if the
            // selection has been made.
            BartStation *sourceStation = (BartStation *)[[BartStationStore sharedStore]
                                                         getSelectedStation:0];
            if (sourceStation) {
                CLLocation *stationLocation =
                    [[CLLocation alloc] initWithCoordinate:sourceStation.location
                                                  altitude:0
                                        horizontalAccuracy:0
                                          verticalAccuracy:-1
                                                 timestamp:[NSDate date]];
                [self updateDistanceToStationFrom:userMapView.userLocation.location
                                               to:stationLocation];
            }
        }
    };
    [[BartStationStore sharedStore] getNearbyStations:lastRecordedLocation_
                                       withCompletion:displayNearbyStations];
}


#pragma mark - table view data source overrides


// table view data source overrides
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    // currently only holds one row in each section
    return 1;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    // currently there are two sections: source and destination
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"UITableViewCell"];
    if (!cell){
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"UITableViewCell"];
        [cell setAccessoryType:UITableViewCellAccessoryDetailDisclosureButton];
    }

    NSString *cellText = [OnTimeUIStringFactory prefixStationPrefix:indexPath.section];

    // if station is selected show the station name as the cell text
    Station *station = [[BartStationStore sharedStore] getSelectedStation:indexPath.section];
    if (station){
        cellText = [cellText stringByAppendingString:station.stationName];
    }
    cell.textLabel.text = cellText;
    return cell;
}


#pragma mark - table view delegate overrides


- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger groupIndex = indexPath.section;
    
    NSArray *stations = nil;
    NSString *titleString = nil;
    Station *selectedStation = nil;
    if (groupIndex == 0) {
        stations = [[BartStationStore sharedStore] nearbyStations:limitedStationNumber];
        titleString = [OnTimeUIStringFactory fromHeaderString];
        selectedStation = [[BartStationStore sharedStore] getSelectedStation:0];
    } else {
        stations = [[BartStationStore sharedStore] nearbyStations];
        titleString = [OnTimeUIStringFactory toHeaderString];
        selectedStation = [[BartStationStore sharedStore] getSelectedStation:1];
    }
    
    // block code to execute when the selection is made
    void (^stationSelectionMade)() = ^void(NSInteger stationIndex) {
        [[BartStationStore sharedStore] selectStation:stationIndex
                                              inGroup:groupIndex];
        // Record that the table row designated by the given index path needs to
        // be updated.
        [tableRowsToUpdate_ addObject:indexPath];

        // Create a map annotation that points to the selected station
        // destination.
        Station *selectedStation =
            [[BartStationStore sharedStore] getSelectedStation:groupIndex];

        OnTimeStationMapAnnotation *stationAnnotation = nil;
        if (groupIndex == 0) {
            stationAnnotation =  sourceStationAnnotation_;
        } else {
            stationAnnotation = targetStationAnnotation_;
        }

        // Simply update the annotation coordinate which will get relfected
        // in the map view.
        stationAnnotation.coordinate = selectedStation.location;
        stationAnnotation.title = selectedStation.stationName;
        stationAnnotation.subtitle = selectedStation.streetAddress;

        // If the callout view showing the station address is displayed,
        // deselecting the annotation closes it. This is done so that
        // the call out view is not going to be consistently shown even when we
        // change the annotation title dynamically.
        if ([userMapView.annotations containsObject:stationAnnotation]) {
            [userMapView deselectAnnotation:stationAnnotation
                                   animated:YES];
        } else {
            [userMapView addAnnotation:stationAnnotation];
        }

        // Since the station selection has been made, the UI needs to be
        // configured (e.g. enabled appropriately).
        [self configureUI];
    };
    StationChoiceViewController *scvc = [[StationChoiceViewController alloc]
                                         initWithStations:stations
                                         withTitle:titleString
                                         withSelection:selectedStation
                                         withCompletion:stationSelectionMade];
    [self.navigationController pushViewController:scvc animated:YES];

    // Deselect the row to avoid having the row highlighted
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
}


#pragma mark - action methods


- (IBAction)requestNotification:(id)sender {
    NSMutableDictionary *requestData = [NSMutableDictionary dictionary];

    // Method to get to the station is shared constants between the client
    // and the server.
    requestData[distanceModeKey] = @(methodToGetToStation.selectedSegmentIndex);
    
    BartStation *sourceStation = (BartStation *)[[BartStationStore sharedStore]
                                                 getSelectedStation:0];
    BartStation *destinationStation = (BartStation *)[[BartStationStore sharedStore]
                                                      getSelectedStation:1];
    // error checking
    if (!sourceStation || !destinationStation){
        UIAlertView *av = [[UIAlertView alloc]
                           initWithTitle:invalidTripTitle
                           message:missingStationMessage
                           delegate:nil
                           cancelButtonTitle:[OnTimeUIStringFactory okButtonLabel]
                           otherButtonTitles:nil];
        [av show];
        return;
    } else if (sourceStation == destinationStation) {
        UIAlertView *av = [[UIAlertView alloc]
                           initWithTitle:invalidTripTitle
                           message:identicalStationMessage
                           delegate:nil
                           cancelButtonTitle:[OnTimeUIStringFactory okButtonLabel]
                           otherButtonTitles:nil];
        [av show];
        return;
    }
    
    requestData[sourceStationKey] = sourceStation.stationId;
    requestData[destinationStationKey] = destinationStation.stationId;
    
    CLLocationCoordinate2D coords = userMapView.userLocation.coordinate;
    NSString *longitude = [NSString stringWithFormat:@"%f", coords.longitude];
    NSString *latitude = [NSString stringWithFormat:@"%f", coords.latitude];
    requestData[longitudeKey] = longitude;
    requestData[latitudeKey] = latitude;

    [self makeNotificationRequest:requestData];
}


#pragma mark - private helper methods


- (void)configureUI {
    BartStation *sourceStation = (BartStation *)[[BartStationStore sharedStore]
                                                 getSelectedStation:0];
    BartStation *destinationStation = (BartStation *)[[BartStationStore sharedStore]
                                                      getSelectedStation:1];
    if (!sourceStation || !destinationStation){
        requestNotificationButton.enabled = NO;
        distanceLabel.hidden = YES;
        distanceLabelBackgroundView_.hidden = YES;
    } else {
        requestNotificationButton.enabled = YES;
    }
}

- (void)updateDistanceToStationFrom:(CLLocation *)fromLocation
                                 to:(CLLocation *)stationLocation {
    static CGFloat conversionRateFromMetersToMiles = 0.000621371;
    CLLocationDistance distance = [fromLocation
                                   distanceFromLocation:stationLocation];
    CGFloat distanceInMiles = distance * conversionRateFromMetersToMiles;
    NSLog(@"distance is %f", distanceInMiles);
    NSString *distanceStringTemplate = @"%.1f mi";
    distanceLabel.text = [NSString stringWithFormat:distanceStringTemplate,
                          distanceInMiles];
    distanceLabel.hidden = NO;
    distanceLabelBackgroundView_.hidden = NO;
}

- (void)makeNotificationRequest:(NSDictionary *)requestData {
    void (^registerNotification)(NSDictionary *notificationData, NSError *err) =
    ^void(NSDictionary *notificationData, NSError *err) {
        if (err){
            // display the error message if retrieve nearby stations was
            // not successful
            UIAlertView *errorAlert = [[UIAlertView alloc]
                                       initWithTitle:notificationErrorTitle
                                       message:errorMessage
                                       delegate:nil
                                       cancelButtonTitle:[OnTimeUIStringFactory okButtonLabel]
                                       otherButtonTitles:nil];
            [errorAlert show];
            return;
        }
        [self handleNotificationData:notificationData];

    };
    [[BartStationStore sharedStore] requestNotification:requestData
                                         withCompletion:registerNotification];
}

- (void)handleNotificationData:(NSDictionary *)notificationData {
    NSLog(@"response data is %@", notificationData);

    id successValue = notificationData[successKey];
    if (![successValue boolValue]){
        int errorCode = [notificationData[errorCodeKey] intValue];
        NSString *noNotificationErrorMessage = nil;
        switch (errorCode){
            case 1:
                noNotificationErrorMessage = missingStationMessage;
                break;
            case 2:
                noNotificationErrorMessage = failedToCreateNoficationMessage;
                break;
            case 3:
                noNotificationErrorMessage = noTimeAvailableMessage;
                break;
            default:
                noNotificationErrorMessage = defaultNotificationErrorMessage;
                break;
        }
        UIAlertView *errorAlert = [[UIAlertView alloc]
                                   initWithTitle:[OnTimeUIStringFactory notificationTitle]
                                   message:noNotificationErrorMessage
                                   delegate:nil
                                   cancelButtonTitle:[OnTimeUIStringFactory okButtonLabel]
                                   otherButtonTitles:nil];
        [errorAlert show];
        return;
    }

    // Schedule the first available notification
    OnTimeNotification *notification =
        [[OnTimeNotification alloc] initWithNotificationData:notificationData];
    [notification scheduleNotification:0];

    // Reset current selection since the notification was successful
    [[BartStationStore sharedStore] resetCurrentSelectedStations];
    [tableView reloadData];

    // Reset the segment control.
    methodToGetToStation.selectedSegmentIndex = 0;

    // Also remove the map annotations since the station selections are now
    // resetted.
    [userMapView removeAnnotations:@[sourceStationAnnotation_,
                                     targetStationAnnotation_]];

    // Since the station selection has been reset, the UI needs to be
    // configured to be disabled.
    [self configureUI];
}

- (void)processPendingNotification:(NSDictionary *)notificationData {
    if (notificationData) {
        NSLog(@"processing pending notification");
        NSMutableDictionary *requestData = [NSMutableDictionary dictionary];

        NSString *startStationId = nil;
        NSArray *nearbyStations = [[BartStationStore sharedStore] nearbyStations:1];
        if ([nearbyStations count] > 0) {
            BartStation *nearbyStation = nearbyStations[0];
            startStationId = nearbyStation.stationId;
        } else {
            startStationId = notificationData[kStartId];
        }
        requestData[sourceStationKey] = startStationId;
        requestData[destinationStationKey] = notificationData[kDestinationId];

        requestData[distanceModeKey] = notificationData[kTravelModeKey];
        // TODO: Duplicated code.
        CLLocationCoordinate2D coords = userMapView.userLocation.coordinate;
        NSString *longitude = [NSString stringWithFormat:@"%f", coords.longitude];
        NSString *latitude = [NSString stringWithFormat:@"%f", coords.latitude];
        requestData[longitudeKey] = longitude;
        requestData[latitudeKey] = latitude;

        [self makeNotificationRequest:requestData];
    }
}

@end