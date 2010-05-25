//
//  VLCTVShowInfoGrabber.m
//  Lunettes
//
//  Created by Pierre d'Herbemont on 5/6/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "VLCTVShowInfoGrabber.h"
#import "NSXMLNode_Additions.h"
#import "TheTVDBGrabber.h"

@interface VLCTVShowInfoGrabber ()
@property (readwrite, retain) NSArray *results;
@end

@implementation VLCTVShowInfoGrabber
@synthesize delegate=_delegate;
@synthesize results=_results;
- (void)dealloc
{
    [_data release];
    [_connection release];
    [_results release];
    [super dealloc];
}

- (void)lookUpForTitle:(NSString *)title
{
    NSString *escapedString = [title stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:TVDB_QUERY_SEARCH, TVDB_HOSTNAME, escapedString]];
    NSLog(@"Accessing %@", url);
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:url cachePolicy:NSURLCacheStorageAllowedInMemoryOnly timeoutInterval:15];
    [_connection cancel];
    [_connection release];

    [_data release];
    _data = [[NSMutableData alloc] init];

    // Keep a reference to ourself while we are alive.
    [self retain];

    _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    [request release];
}

- (void)lookUpForTitle:(NSString *)title andExecuteBlock:(void (^)())block
{
    Block_release(_block);
    _block = Block_copy(block);
    [self lookUpForTitle:title];
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    if ([_delegate respondsToSelector:@selector(movieInfoGrabber:didFailWithError:)])
        [_delegate tvShowInfoGrabber:self didFailWithError:error];

    // Release the eventual block. This prevents ref cycle.
    if (_block) {
        Block_release(_block);
        _block = NULL;
    }

    // This balances the -retain in -lookupForTitle
    [self autorelease];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [_data appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:_data options:0 error:nil];

    [_data release];
    _data = nil;

    NSLog(@"here");
    NSError *error = nil;
    NSArray *nodes = [xmlDoc nodesForXPath:@"./Data/Series" error:&error];
    NSLog(@"%@", nodes);

    if ([nodes count] > 0 ) {
        NSMutableArray *array = [NSMutableArray arrayWithCapacity:[nodes count]];
        for (NSXMLNode *node in nodes) {
            NSString *id = [node stringValueForXPath:@"./seriesid"];
            if (!id)
                continue;
            NSString *title = [node stringValueForXPath:@"./SeriesName"];
            NSString *release = [node stringValueForXPath:@"./FirstAired"];
            NSDateFormatter *inputFormatter = [[[NSDateFormatter alloc] init] autorelease];
            [inputFormatter setDateFormat:@"yyyy-MM-dd"];
            NSDateFormatter *outputFormatter = [[[NSDateFormatter alloc] init] autorelease];
            [outputFormatter setDateFormat:@"yyyy"];
            NSDate *releaseDate = [inputFormatter dateFromString:release];
            NSString *releaseYear = releaseDate ? [outputFormatter stringFromDate:releaseDate] : nil;

            //NSLog(@"%@", title);
            //NSLog(TMDB_QUERY_INFO, TMDB_HOSTNAME, id, TMDB_API_KEY);
            NSString *artworkURL = [node stringValueForXPath:@"./banner"];
            NSString *shortSummary = [node stringValueForXPath:@"./Overview"];
            [array addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                              title, @"title",
                              id, @"id",
                              shortSummary ?: @"", @"shortSummary",
                              releaseYear ?: @"", @"releaseYear",
                              [NSString stringWithFormat:TVDB_COVERS_URL, TVDB_IMAGES_HOSTNAME, artworkURL], @"artworkURL",
                              nil]];
        }
        self.results = array;
    }
    else
        self.results = nil;

    [xmlDoc release];

    if (_block) {
        _block();
        Block_release(_block);
        _block = NULL;
    }

    if ([_delegate respondsToSelector:@selector(movieInfoGrabberDidFinishGrabbing:)])
        [_delegate tvShowInfoGrabberDidFinishGrabbing:self];

    // This balances the -retain in -lookupForTitle
    [self autorelease];
}

@end