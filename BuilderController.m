//
//  BuilderController.m
//  BetaBuilder
//
//  Created by Hunter Hillegas on 8/7/10.
//  Copyright 2010 Hunter Hillegas. All rights reserved.
//

/* 
 iOS BetaBuilder - a tool for simpler iOS betas
 Version 1.0, August 2010
 
 Condition of use and distribution:
 
 This software is provided 'as-is', without any express or implied
 warranty.  In no event will the authors be held liable for any damages
 arising from the use of this software.
 
 Permission is granted to anyone to use this software for any purpose,
 including commercial applications, and to alter it and redistribute it
 freely, subject to the following restrictions:
 
 1. The origin of this software must not be misrepresented; you must not
 claim that you wrote the original software. If you use this software
 in a product, an acknowledgment in the product documentation would be
 appreciated but is not required.
 2. Altered source versions must be plainly marked as such, and must not be
 misrepresented as being the original software.
 3. This notice may not be removed or altered from any source distribution.
 */

#import "BuilderController.h"
#import "ZipArchive.h"
#import "DBSession.h"

@implementation BuilderController

@synthesize bundleIdentifierField;
@synthesize bundleVersionField;
@synthesize bundleNameField;
@synthesize webserverDirectoryField;
@synthesize archiveIPAFilenameField;
@synthesize generateFilesButton;
@synthesize mobileProvisionFilePath;

- (id) init {
	self = [super init];
	if (self) {
		NSString* consumerKey = @"pnbt19p4knzht9w";
		NSString* consumerSecret = @"dvrgk9c78uep5bg";
		
		DBSession* session = [[DBSession alloc] initWithConsumerKey:consumerKey consumerSecret:consumerSecret];
		//session.delegate = self; // DBSessionDelegate methods allow you to handle re-authenticating
		[DBSession setSharedSession:session];
		[session release];
		
		restClient = [[DBRestClient alloc] initWithSession:session];
        restClient.delegate = self;
		[restClient loadAccountInfo];
	}
	return self;
}

- (void) awakeFromNib {
	if ([[DBSession sharedSession] isLinked])
	[dbLinkButton setTitle:@"Unlink"];
}

- (IBAction)specifyIPAFile:(id)sender {
	NSOpenPanel *openDlg = [NSOpenPanel openPanel];
	[openDlg setCanChooseFiles:YES];
	[openDlg setCanChooseDirectories:NO];
	[openDlg setAllowsMultipleSelection:NO];
	
	if ([openDlg runModalForDirectory:nil file:nil] == NSOKButton) {
		NSArray *files = [openDlg filenames];
		
		for (int i = 0; i < [files count]; i++ ) {
			NSString *fileName = [files objectAtIndex:i];
			if ([[fileName lowercaseString] rangeOfString:@".ipa"].location != NSNotFound)
				[self setupFromIPAFile:[files objectAtIndex:i]];
			else if ([[fileName lowercaseString] rangeOfString:@".app"].location != NSNotFound)
				[self setupFromAPPFile:[files objectAtIndex:i]];
		}
	}
}

- (void)setupFromIPAFile:(NSString *)ipaFilename {
	[archiveIPAFilenameField setStringValue:ipaFilename];
	
	//Attempt to pull values
	NSError *fileCopyError;
	NSError *fileDeleteError;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSURL *ipaSourceURL = [NSURL fileURLWithPath:[archiveIPAFilenameField stringValue]];
	NSURL *ipaDestinationURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@%@", NSTemporaryDirectory(), [[archiveIPAFilenameField stringValue] lastPathComponent]]];
	[fileManager removeItemAtURL:ipaDestinationURL error:&fileDeleteError];
	BOOL copiedIPAFile = [fileManager copyItemAtURL:ipaSourceURL toURL:ipaDestinationURL error:&fileCopyError];
	if (!copiedIPAFile) {
		NSLog(@"Error Copying IPA File: %@", fileCopyError);
	} else {
		//Remove Existing Trash in Temp Directory
		[fileManager removeItemAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"extracted_app"] error:nil];
		
		ZipArchive *za = [[ZipArchive alloc] init];
		if ([za UnzipOpenFile:[ipaDestinationURL path]]) {
			BOOL ret = [za UnzipFileTo:[NSTemporaryDirectory() stringByAppendingPathComponent:@"extracted_app"] overWrite:YES];
			if (NO == ret){} [za UnzipCloseFile];
		}
		[za release];
		
		//read the Info.plist file
		NSString *appDirectoryPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"extracted_app"] stringByAppendingPathComponent:@"Payload"];
		NSArray *payloadContents = [fileManager contentsOfDirectoryAtPath:appDirectoryPath error:nil];
		if ([payloadContents count] > 0) {
			NSString *plistPath = [[payloadContents objectAtIndex:0] stringByAppendingPathComponent:@"Info.plist"];
			NSDictionary *bundlePlistFile = [NSDictionary dictionaryWithContentsOfFile:[appDirectoryPath stringByAppendingPathComponent:plistPath]];
			
			if (bundlePlistFile) {
				[bundleVersionField setStringValue:[bundlePlistFile valueForKey:@"CFBundleVersion"]];
				[bundleIdentifierField setStringValue:[bundlePlistFile valueForKey:@"CFBundleIdentifier"]];
				[bundleNameField setStringValue:[bundlePlistFile valueForKey:@"CFBundleDisplayName"]];
			}
			
			//set mobile provision file
			mobileProvisionFilePath = [appDirectoryPath stringByAppendingPathComponent:[[payloadContents objectAtIndex:0] stringByAppendingPathComponent:@"embedded.mobileprovision"]];
		}
	}
	
	[generateFilesButton setEnabled:YES];
}

- (void)setupFromAPPFile:(NSString *)appFilename {
	NSString *ipaFilename = appFilename; 
	if ([ipaFilename length] > 4) {
		ipaFilename = [ipaFilename substringToIndex:[ipaFilename length]-3];
		ipaFilename = [ipaFilename stringByAppendingString:@"ipa"];
	} else {
		return;
	}	
	
	NSError *tmpError;
	NSError *fileCopyError;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSURL *appSourceURL = [NSURL fileURLWithPath:appFilename];
	NSURL *appDestinationURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@", NSTemporaryDirectory(), [appFilename lastPathComponent]]];
	NSURL *ipaDestinationURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/fromAppTmp/%@", NSTemporaryDirectory(), [ipaFilename lastPathComponent]]];
	[fileManager removeItemAtPath:[appDestinationURL path] error:&tmpError];
	[fileManager removeItemAtPath:[ipaDestinationURL path] error:&tmpError];
	[fileManager createDirectoryAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"fromAppTmp"] withIntermediateDirectories:YES attributes:nil error:nil];
	
	
	BOOL copiedAPPFile = [fileManager copyItemAtURL:appSourceURL toURL:appDestinationURL error:&fileCopyError];
	if (!copiedAPPFile) {
		NSLog(@"Error Copying IPA File: %@", fileCopyError);
	} else {
		BOOL success = NO;
		ZipArchive *za = [[ZipArchive alloc] init];
		if ([za CreateZipFile2:[ipaDestinationURL path]]) {
			
			success = [self addFile:[appDestinationURL path] recursivePath:[NSString stringWithFormat:@"Payload/%@", [appFilename lastPathComponent]] toZip:za];
			if (success) {
				if ([za CloseZipFile2]) {
					success = YES;
				}
			}
		}
		
		if (!success) {
			NSLog(@"Error Creating IPA File");
		} else {
			[self setupFromIPAFile:[ipaDestinationURL path]];
		}
		
		[za release];
	}
}

- (BOOL)addFile:(NSString *)aFilePath recursivePath:(NSString *)aPath toZip:(ZipArchive *)aZipArchive {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	if (!aPath) aPath = @"";
	BOOL success = NO;
	BOOL isDir;
	if ([fileManager fileExistsAtPath:aFilePath isDirectory:&isDir]) {
		if (isDir) {
			NSArray *files = [fileManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:aFilePath] includingPropertiesForKeys:nil options:0 error:nil];
			for (NSURL *eachFilePath in files) {
				success = [self addFile:[eachFilePath path] recursivePath:[NSString stringWithFormat:@"%@/%@",aPath,[eachFilePath lastPathComponent]] toZip:aZipArchive];
			}
		} else {
			success = [aZipArchive addFileToZip:aFilePath newname:aPath];
		}
	}
	return success;
}

- (IBAction)generateFiles:(id)sender {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	BOOL success = YES;

	//create plist
	NSString *encodedIpaFilename = [[[archiveIPAFilenameField stringValue] lastPathComponent] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]; //this isn't the most robust way to do this
	NSString *userId = [[NSUserDefaults standardUserDefaults] objectForKey:@"userID"];
	if (!userId || [userId isEqualToString:@""]) {
		[self noDBError];
		return;
	}
	NSDate *now = [NSDate date];
	NSDateFormatter *dateFormatter = [NSDateFormatter new];
	[dateFormatter setDateFormat:@"yyyyMMddHHmm"];
	NSString *nowString = [dateFormatter stringFromDate:now];
	
	NSString *folderURLString = [NSString stringWithFormat:@"http://dl.dropbox.com/u/%@/AdHoc/%@/%@", userId, [bundleNameField stringValue], nowString];
	NSString *ipaURLString = [NSString stringWithFormat:@"%@/%@", folderURLString, encodedIpaFilename];
	NSString *htmlURLString = [NSString stringWithFormat:@"%@/%@", folderURLString, [NSString stringWithFormat:@"%@.html", [bundleNameField stringValue]]];
	NSDictionary *assetsDictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"software-package", @"kind", ipaURLString, @"url", nil];
	NSDictionary *metadataDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[bundleIdentifierField stringValue], @"bundle-identifier", [bundleVersionField stringValue], @"bundle-version", @"software", @"kind", [bundleNameField stringValue], @"title", nil];
	NSDictionary *innerManifestDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObject:assetsDictionary], @"assets", metadataDictionary, @"metadata", nil];
	NSDictionary *outerManifestDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObject:innerManifestDictionary], @"items", nil];
	NSLog(@"Manifest Created");
	
	//create html file
	NSString *templatePath = [[NSBundle mainBundle] pathForResource:@"index_template" ofType:@"html"];
	NSString *htmlTemplateString = [NSString stringWithContentsOfFile:templatePath encoding:NSUTF8StringEncoding error:nil];
	htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_NAME]" withString:[bundleNameField stringValue]];
	htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_PLIST]" withString:[NSString stringWithFormat:@"%@/%@", folderURLString, @"manifest.plist"]];
	htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[PROVISIONING]" withString:[NSString stringWithFormat:@"%@/%@", folderURLString, @"provisioning.mobileprovision"]];
	htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[ZIP_NAME]" withString:[NSString stringWithFormat:@"%@.zip", [bundleNameField stringValue]]];
	
	NSString *savePath = [NSHomeDirectory() stringByAppendingFormat:@"/Dropbox/Public/AdHoc/%@/%@", [bundleNameField stringValue], nowString];
	NSURL *saveDirectoryURL = [NSURL fileURLWithPath:savePath];
	[fileManager createDirectoryAtPath:savePath withIntermediateDirectories:YES attributes:nil error:nil];
	
	//Write Files
	[outerManifestDictionary writeToURL:[saveDirectoryURL URLByAppendingPathComponent:@"manifest.plist"] atomically:YES];
	[htmlTemplateString writeToURL:[saveDirectoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.html", [bundleNameField stringValue]]] atomically:YES encoding:NSASCIIStringEncoding error:nil];
	
	//Copy IPA
	NSError *fileCopyError;
	NSURL *ipaSourceURL = [NSURL fileURLWithPath:[archiveIPAFilenameField stringValue]];
	NSURL *ipaDestinationURL = [saveDirectoryURL URLByAppendingPathComponent:[[archiveIPAFilenameField stringValue] lastPathComponent]];
	BOOL copiedIPAFile = [fileManager copyItemAtURL:ipaSourceURL toURL:ipaDestinationURL error:&fileCopyError];
	if (!copiedIPAFile) {
		NSLog(@"Error Copying IPA File: %@", fileCopyError);
		success = NO;
	}
	BOOL copiedProvFile = [fileManager copyItemAtPath:mobileProvisionFilePath toPath:[savePath stringByAppendingPathComponent:@"provisioning.mobileprovision"] error:nil];
	if (!copiedProvFile) {
		NSLog(@"Error Copying Prov File: %@", fileCopyError);
		success = NO;
	}
		
	//Create Archived Version for 3.0 Apps
	ZipArchive* zip = [[ZipArchive alloc] init];
	BOOL ret = [zip CreateZipFile2:[[saveDirectoryURL path] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.zip", [bundleNameField stringValue]]]];
	ret = [zip addFileToZip:[archiveIPAFilenameField stringValue] newname:@"application.ipa"];
	ret = [zip addFileToZip:mobileProvisionFilePath newname:@"beta_provision.mobileprovision"];
	if(![zip CloseZipFile2]) {
		NSLog(@"Error Creating 3.x Zip File");
		success = NO;
	}
	[zip release];
	
	if (success) {
		//Play Done Sound / Display Alert
		NSSound *systemSound = [NSSound soundNamed:@"Glass"];
		[systemSound play];
		clipBoardLink = htmlURLString;
		[self copyToPasteBoard:self];
	} else {
		NSAlert *alert = [NSAlert alertWithMessageText:@"Error" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"An error occurred!"];
		[alert beginSheetModalForWindow:[[NSApplication sharedApplication] mainWindow] modalDelegate:nil didEndSelector:nil contextInfo:nil];
	}
}

- (IBAction)copyToPasteBoard:(id)sender {
	if ([clipBoardChecker state] == NSOnState && clipBoardLink && ![clipBoardLink isEqualToString:@""]) {
		NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
		[pasteBoard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
		[pasteBoard setString:clipBoardLink forType:NSStringPboardType];
	}
}

- (void)noDBError {
	NSAlert *alert = [NSAlert alertWithMessageText:@"No Account Linked!" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Please link a Dropbox Account!"];
	[alert beginSheetModalForWindow:[[NSApplication sharedApplication] mainWindow] modalDelegate:nil didEndSelector:nil contextInfo:nil];

}

- (IBAction)linkDropBox:(id)sender {
	if (![[DBSession sharedSession] isLinked]) {
		[[NSApplication sharedApplication] beginSheet:dbLoginView modalForWindow:[[NSApplication sharedApplication] mainWindow] modalDelegate:nil didEndSelector:nil contextInfo:nil];
	} else {
		[[DBSession sharedSession] unlink];
		NSAlert *alert = [NSAlert alertWithMessageText:@"Account Unlinked!" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Your dropbox account has been unlinked"];
		[alert beginSheetModalForWindow:[[NSApplication sharedApplication] mainWindow] modalDelegate:nil didEndSelector:nil contextInfo:nil];
		[dbLinkButton setTitle:@"Link"];
		[[NSUserDefaults standardUserDefaults] setObject:@"" forKey:@"userID"];
	}
}

- (void)loginOkAction:(id)sender {
	NSString *userNameString = [userNameTextField stringValue];
	NSString *passwordString = [passNameTextField stringValue];
	
	if (userNameString && passwordString && ![userNameString isEqualToString:@""] && ![passwordString isEqualToString:@""]) {
		[restClient loginWithEmail:userNameString password:passwordString];
		[[NSApplication sharedApplication] endSheet:dbLoginView];
		[dbLoginView close];

	} else {
		[[NSApplication sharedApplication] endSheet:dbLoginView];
		[dbLoginView close];

		NSAlert *alert = [NSAlert alertWithMessageText:@"No Account Linked!" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Please check your usernamer or password!"];
		[alert beginSheetModalForWindow:[[NSApplication sharedApplication] mainWindow] modalDelegate:nil didEndSelector:nil contextInfo:nil];
	}

}

#pragma mark DBRestClient methods

- (void)restClientDidLogin:(DBRestClient*)client {
	NSAlert *alert = [NSAlert alertWithMessageText:@"Account Linked!" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Your dropbox account has been linked"];
	[alert beginSheetModalForWindow:[[NSApplication sharedApplication] mainWindow] modalDelegate:nil didEndSelector:nil contextInfo:nil];

	[dbLinkButton setTitle:@"Unlink"];
	[client loadAccountInfo];
}


- (void)restClient:(DBRestClient*)client loginFailedWithError:(NSError*)error {
	NSAlert *alert = [NSAlert alertWithMessageText:@"Account Not Linked!" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Your dropbox account cannot be linked"];
	[alert beginSheetModalForWindow:[[NSApplication sharedApplication] mainWindow] modalDelegate:nil didEndSelector:nil contextInfo:nil];
	[dbLinkButton setTitle:@"Link"];
	
    NSString* message;
    if ([error.domain isEqual:NSURLErrorDomain]) {
        message = @"There was an error connecting to Dropbox.";
    } else {
        NSObject* errorResponse = [[error userInfo] objectForKey:@"error"];
        if ([errorResponse isKindOfClass:[NSString class]]) {
            message = (NSString*)errorResponse;
        } else if ([errorResponse isKindOfClass:[NSDictionary class]]) {
            NSDictionary* errorDict = (NSDictionary*)errorResponse;
            message = [errorDict objectForKey:[[errorDict allKeys] objectAtIndex:0]];
        } else {
            message = @"An unknown error has occurred.";
        }
    }
    NSLog(message);
}

- (void) restClient:(DBRestClient *)client loadedAccountInfo:(DBAccountInfo *)info {	
	[[NSUserDefaults standardUserDefaults] setObject:[info userId] forKey:@"userID"];
}


@end
