//
//  DragContentView.h
//  BetaBuilder
//
//  Created by Paulo Cesar Saito on 10/17/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
@class BuilderController;

@interface DragContentView : NSWindow {
	BuilderController *builderController;
}

@property (nonatomic, retain) IBOutlet BuilderController *builderController;

@end
