//
//  NSString+Lossy.m
//  VadeMecum
//
//  Created by Paulo Cesar Saito on 11/10/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "NSString+Lossy.h"


@implementation NSString(Lossy)

- (NSString *)lossyString {
	self = [[self stringByReplacingOccurrencesOfString:@"(" withString:@""] stringByReplacingOccurrencesOfString:@")" withString:@""];
	self = [[self stringByReplacingOccurrencesOfString:@"." withString:@""] stringByReplacingOccurrencesOfString:@"," withString:@""];
	NSData *lossyData = [self dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
	return [[[NSString alloc] initWithData:lossyData encoding:NSASCIIStringEncoding] autorelease];
}

@end
