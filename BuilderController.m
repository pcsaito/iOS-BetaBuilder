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
#import "BetaBuilderAppDelegate.h"
#import "DBAccountInfo.h"
#import "NSString+Lossy.h"

#define kiOSLessThan4Key @"iOSLessThan4"
#define kiOSLessThan4HTMLToken @"DISPLAY_IOS_LESS_THAN_4"
#define kCustomizedHTML @"CUSTOM_HTML"

@implementation BuilderController

@synthesize bundleIdentifierField;
@synthesize bundleVersionField;
@synthesize bundleNameField;
@synthesize webserverDirectoryField;
@synthesize archiveIPAFilenameField;
@synthesize generateFilesButton;
@synthesize mobileProvisionFilePath;
@synthesize deploymentURLField;
@synthesize customizedHTML;

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
    
    self.customizedHTML = @"";
	}
	return self;
}

- (void) awakeFromNib {
	if ([[DBSession sharedSession] isLinked])
	[dbLinkButton setTitle:@"Unlink"];
  
  [iOSLessThan4Checker setState:[[NSUserDefaults standardUserDefaults] boolForKey:kiOSLessThan4Key] ? NSOnState : NSOffState];
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
	
	NSString *appNameString = [[bundleNameField stringValue] lossyString];
	appNameString = [appNameString stringByReplacingOccurrencesOfString:@" " withString:@"_"];

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
	
	NSString *folderURLString = [NSString stringWithFormat:@"http://dl.dropbox.com/u/%@/AdHoc/%@/%@", userId, appNameString, nowString];
	NSString *ipaURLString = [NSString stringWithFormat:@"%@/%@", folderURLString, encodedIpaFilename];
	NSString *htmlURLString = [NSString stringWithFormat:@"%@/%@", folderURLString, [NSString stringWithFormat:@"%@.html", appNameString]];
	NSDictionary *assetsDictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"software-package", @"kind", ipaURLString, @"url", nil];
	NSDictionary *metadataDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[bundleIdentifierField stringValue], @"bundle-identifier", [bundleVersionField stringValue], @"bundle-version", @"software", @"kind", appNameString, @"title", nil];
	NSDictionary *innerManifestDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObject:assetsDictionary], @"assets", metadataDictionary, @"metadata", nil];
	NSDictionary *outerManifestDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[NSArray arrayWithObject:innerManifestDictionary], @"items", nil];
	NSLog(@"Manifest Created");
  
  BOOL createArchiveForiOS3 = [iOSLessThan4Checker state] == NSOnState;
	
	//create html file
	NSString *templatePath = [[NSBundle mainBundle] pathForResource:@"index_template" ofType:@"html"];
	NSString *htmlTemplateString = [NSString stringWithContentsOfFile:templatePath encoding:NSUTF8StringEncoding error:nil];
	htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_NAME]" withString:appNameString];
	htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[BETA_PLIST]" withString:[NSString stringWithFormat:@"%@/%@", folderURLString, @"manifest.plist"]];
	htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[PROVISIONING]" withString:[NSString stringWithFormat:@"%@/%@", folderURLString, @"provisioning.mobileprovision"]];
	htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:@"[ZIP_NAME]" withString:[NSString stringWithFormat:@"%@.zip", appNameString]];
  htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"[%@]", kiOSLessThan4HTMLToken]
                                                                     withString:(createArchiveForiOS3 ? @"inline" : @"none")];
  htmlTemplateString = [htmlTemplateString stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"[%@]", kCustomizedHTML]
                                                                     withString:customizedHTML];
	
	
	NSString *savePath = [NSHomeDirectory() stringByAppendingFormat:@"/Dropbox/Public/AdHoc/%@/%@", appNameString, nowString];
	NSURL *saveDirectoryURL = [NSURL fileURLWithPath:savePath];
	[fileManager createDirectoryAtPath:savePath withIntermediateDirectories:YES attributes:nil error:nil];
	NSError *fileCopyError;
	
  if (createArchiveForiOS3)
  {
    //Create Archived Version for 3.0 Apps
    ZipArchive* zip = [[ZipArchive alloc] init];
    NSString *tempZipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.zip", appNameString]];
    [fileManager removeItemAtPath:tempZipPath error:nil];
    BOOL ret = [zip CreateZipFile2:tempZipPath];
    ret = [zip addFileToZip:[archiveIPAFilenameField stringValue] newname:[NSString stringWithFormat:@"%@.ipa", appNameString]];
    ret = [zip addFileToZip:mobileProvisionFilePath newname:@"provisioning.mobileprovision"];
    if(![zip CloseZipFile2]) {
      NSLog(@"Error Creating 3.x Zip File");
      success = NO;
    }
    [zip release];
    
    //copy zip
    NSURL *zipDestURL = [NSURL fileURLWithPath:[[saveDirectoryURL path] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.zip", appNameString]]];
    NSURL *zipSourceURL = [NSURL fileURLWithPath:tempZipPath];
    BOOL copiedZIPFile = [fileManager copyItemAtURL:zipSourceURL toURL:zipDestURL error:&fileCopyError];
    if (!copiedZIPFile) {
      NSLog(@"Error Copying ZIP File: %@", fileCopyError);
      success = NO;
    }		
  }
	
	//Write Files
	[outerManifestDictionary writeToURL:[saveDirectoryURL URLByAppendingPathComponent:@"manifest.plist"] atomically:YES];
	[htmlTemplateString writeToURL:[saveDirectoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.html", appNameString]] atomically:YES encoding:NSASCIIStringEncoding error:nil];
	
	//Copy IPA
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

	
	if (success) {
		//Play Done Sound / Display Alert
		NSSound *systemSound = [NSSound soundNamed:@"Glass"];
		[systemSound play];
		clipBoardLink = htmlURLString;
    [deploymentURLField setStringValue:clipBoardLink];
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
		
		[accountNameTextField setStringValue:@""];
		[quotaTextField setStringValue:@""];		
	}
}

- (void)loginOkAction:(id)sender {
	NSString *userNameString = [userNameTextField stringValue];
	NSString *passwordString = [passNameTextField stringValue];
	
	if (![sameAccountChecker state]) {
		[[NSApplication sharedApplication] endSheet:dbLoginView];
		[dbLoginView close];

		NSAlert *alert = [NSAlert alertWithMessageText:@"You must use the same account!" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"The App only use your account information to generate the public links, but is the desktop client that upload your files! If diferent accounts are used, the public links will be wrong!"];
		[alert beginSheetModalForWindow:[[NSApplication sharedApplication] mainWindow] modalDelegate:nil didEndSelector:nil contextInfo:nil];
	}
	
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

#pragma mark -
#pragma mark iOS version

- (void)checkediOSLessThan4Button:(id)sender
{
  BOOL checked = [iOSLessThan4Checker state] == NSOnState;
  [[NSUserDefaults standardUserDefaults] setBool:checked forKey:kiOSLessThan4Key];
}

#pragma mark -
#pragma mark HTML customization

- (void)pressedCustomizeHTML:(id)sender
{
  [customizeHTMLWindow makeKeyAndOrderFront:nil];
}

- (void)checkedCustomWhatsNewButton:(id)sender
{
  NSButton *checker = sender;
  NSColor *colour = [sender state] ? [NSColor blackColor] : [NSColor grayColor];
  [customWhatsNewField setEditable:[checker state]];
  [customWhatsNewField setTextColor:colour];
}

- (void)doneCustomizingHTML:(id)sender
{
  NSMutableString *html = [NSMutableString string];
  
  if ([customRequireFreshInstallChecker state])
    [html appendString:@"<p class=\"important\">Remove the previous app from your device before installing this version!</p>\n"];
  
  if ([customWhatsNewChecker state])
  {
    [html appendString:@"<h4>What's new in this version</h4>\n"];
    
    NSMutableArray *lines = [NSMutableArray arrayWithArray:[[customWhatsNewField string] componentsSeparatedByString:@"\n"]];
    [lines filterUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    
    if ([lines count])
    {
      NSString *line = [lines objectAtIndex:0];
      if ([line hasPrefix:@"{"] && [line hasSuffix:@"}"])
      {
        NSRange range;
        range.length = [line length] - 2;
        range.location = 1;
        [html appendFormat:@"<p><strong>%@</strong></p>\n", [line substringWithRange:range]];
        [lines removeObjectAtIndex:0];
      }
    }
    
    if ([lines count])
    {
      [html appendString:@"<ul>\n"];
      for (NSString *line in lines)
      {
        [html appendFormat:@"\t<li>%@</li>\n", line];
      }
      [html appendString:@"</ul>\n"];
    }
    
  }
  
  self.customizedHTML = html;
  
  [customizeHTMLWindow close];
}

#pragma mark -
#pragma mark DBRestClient methods

- (void)restClientDidLogin:(DBRestClient*)client {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *dbPath = [NSHomeDirectory() stringByAppendingFormat:@"/Dropbox"];
	BOOL dbFolderIsFolder;
	BOOL dbFolderExist = [fileManager fileExistsAtPath:dbPath isDirectory:&dbFolderIsFolder];
	if (!dbFolderExist || !dbFolderIsFolder) {
		[[DBSession sharedSession] unlink];
		NSAlert *alert = [NSAlert alertWithMessageText:@"Cannot find the Dropbox folder!" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Your Dropbox does not exists, or is not located in the default location."];
		[alert beginSheetModalForWindow:[[NSApplication sharedApplication] mainWindow] modalDelegate:nil didEndSelector:nil contextInfo:nil];
		[dbLinkButton setTitle:@"Link"];
		[[NSUserDefaults standardUserDefaults] setObject:@"" forKey:@"userID"];
		
		[accountNameTextField setStringValue:@""];
		[quotaTextField setStringValue:@""];		
		
	} else {
		NSAlert *alert = [NSAlert alertWithMessageText:@"Account Linked!" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Your dropbox account has been linked"];
		[alert beginSheetModalForWindow:[[NSApplication sharedApplication] mainWindow] modalDelegate:nil didEndSelector:nil contextInfo:nil];
		
		[dbLinkButton setTitle:@"Unlink"];
		[client loadAccountInfo];
	}
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
    NSLog(@"%@",message);
}

- (void) restClient:(DBRestClient *)client loadedAccountInfo:(DBAccountInfo *)info {	
	[[NSUserDefaults standardUserDefaults] setObject:[info userId] forKey:@"userID"];
	[accountNameTextField setStringValue:[info displayName]];
	long long int quotaSize = [[info quota] totalBytes];
	double quotaSizeFloat = (float)quotaSize/1024.0/1024.0/1024.0;
	long long int consumedQuotaSize = (long long int)[[info quota] normalConsumedBytes]+(long long int)[[info quota] sharedConsumedBytes];
	double consumedQuotaSizeFloat = (float)consumedQuotaSize/1024.0/1024.0/1024.0;
	[quotaTextField setStringValue:[NSString stringWithFormat:@"%.2lfGB/%.2lfGB", consumedQuotaSizeFloat, quotaSizeFloat]];
}


@end
