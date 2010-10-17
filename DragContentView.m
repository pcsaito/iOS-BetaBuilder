//
//  DragContentView.m
//  BetaBuilder
//
//  Created by Paulo Cesar Saito on 10/17/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "DragContentView.h"
#import "BuilderController.h"

@implementation DragContentView
@synthesize builderController;

- (void) awakeFromNib {
	[super awakeFromNib];
	NSArray *draggedTypeArray = [NSArray arrayWithObjects:NSFilenamesPboardType, nil];
	[self registerForDraggedTypes:draggedTypeArray];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
	NSString *filename = [[[sender draggingPasteboard] propertyListForType:NSFilenamesPboardType] objectAtIndex:0];
	if (([[filename lowercaseString] rangeOfString:@".app"].location == NSNotFound || 
		[[filename lowercaseString] rangeOfString:@".app.dsym"].location != NSNotFound) && 
		[[filename lowercaseString] rangeOfString:@".ipa"].location == NSNotFound) {
		return NSDragOperationNone;
	}
	
    return NSDragOperationEvery;
}

- (BOOL) prepareForDragOperation:(id <NSDraggingInfo>)sender {
	return YES;
}

- (BOOL)performDragOperation:(id < NSDraggingInfo >)sender {
    NSArray *draggedFilenames = [[sender draggingPasteboard] propertyListForType:NSFilenamesPboardType];
	NSString *filename = [draggedFilenames objectAtIndex:0];
	
	if ([[filename lowercaseString] rangeOfString:@".ipa"].location != NSNotFound)
		[self.builderController setupFromIPAFile:filename];
	else if ([[filename lowercaseString] rangeOfString:@".app"].location != NSNotFound)
		[self.builderController setupFromAPPFile:filename];
	else 
		return NO;

	
	return YES;
}


@end
