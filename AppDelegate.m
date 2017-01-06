#import "AppDelegate.h"

@interface AppDelegate (PrivateMethods)
- (void)loadUserScripts;
- (void)handleNetworkErrorForWebView:(WebView *)webView;
@end

@implementation AppDelegate

@synthesize window, webView;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification { 
  [webView setFrameLoadDelegate:(id)self];
  [webView setPolicyDelegate:(id)self];
  [webView setUIDelegate:(id)self];

  // webview -> notification center bridge
  notificationProvider = [[NotificationProvider alloc] init];
  [webView _setNotificationProvider:notificationProvider];

  // user agent
  NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
  [webView setApplicationNameForUserAgent:[NSString stringWithFormat:@"irccloud/%@", version]];

  // listen for title changes
  [webView addObserver:self
            forKeyPath:@"mainFrameTitle"
               options:NSKeyValueObservingOptionNew
               context:NULL];

  console = [[JSConsole alloc] init];

  [self loadUserScripts];

  [[NSURLCache sharedURLCache] removeAllCachedResponses];

  url = [[NSUserDefaults standardUserDefaults] valueForKey:@"url"];
  if (!url) url = @"https://www.irccloud.com/";

  NSLog(@"Connecting to %@", url);

  [webView setMainFrameURL:url];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
  if (flag == NO) {
    [window makeKeyAndOrderFront:self];
  }
  return YES;
}

#pragma mark -

- (void)loadUserScripts {
  NSFileManager *fileManager = [NSFileManager defaultManager];

  NSString *folder = @"~/Library/Application Support/irccloud/Scripts/";
  folder = [folder stringByExpandingTildeInPath];

  if ([fileManager fileExistsAtPath:folder] == NO) {
    [fileManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
  }

  NSArray *files = [fileManager contentsOfDirectoryAtPath:folder error:NULL];
  NSMutableArray *scripts = [[NSMutableArray alloc] initWithCapacity:[files count]];

  for (NSString* file in files) {
    [scripts addObject:[folder stringByAppendingPathComponent:file]];
  }

  userScripts = [[NSArray alloc] initWithArray:scripts];
  [scripts release];
}

#pragma mark -

- (void)titleDidChange:(NSString *)title {
  NSUInteger unread = 0;

  if ([title length] == 0) {
    NSLog(@"WARNING: title changed to an empty string.");
    return;
  }
  if ([[title substringToIndex:1] isEqualToString:@"*"]) {
    title = [title substringFromIndex:2];
  } else if ([[title substringToIndex:1] isEqualToString:@"("]) {
    NSRange range = [title rangeOfString:@")"];
    range.length = range.location - 1;
    range.location = 1;
    unread = [[title substringWithRange:range] intValue];
    title = [title substringFromIndex:range.location + range.length + 2];
  }

  NSString *badge = nil;
  if (unread > 0) {
    badge = [NSString stringWithFormat:@"%ld", unread];
  }

  NSRange pipepos = [title rangeOfString:@" | IRCCloud" options:NSBackwardsSearch];
  if (pipepos.location != NSNotFound) {
    title = [title substringToIndex:pipepos.location];
  }

  [[[NSApplication sharedApplication] dockTile] setBadgeLabel:badge];
  [window setTitle:title];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  if ([keyPath isEqualToString:@"mainFrameTitle"]) {
    [self titleDidChange:[change valueForKey:@"new"]];
  }
}

#pragma mark FrameLoadDelegate

- (void)webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)windowScriptObject forFrame:(WebFrame *)frame {
  [windowScriptObject setValue:console forKey:@"console"];
    
  // disable notification sound
  [windowScriptObject evaluateWebScript:@"HTMLAudioElement.prototype.play = function(){}"];

  // inject userscripts
  for (NSString *script in userScripts) {
    NSLog(@"loading script: %@", script);
    [windowScriptObject evaluateWebScript:[NSString stringWithContentsOfFile:script usedEncoding:nil error:NULL]];
  }
}

- (void)handleNetworkError:(NSError *)error forWebView:(WebView *)view {
    NSString *failingURL = [error.userInfo valueForKey:@"NSErrorFailingURLStringKey"];
    if (!failingURL || [failingURL rangeOfString:url options:NSAnchoredSearch].location == NSNotFound) {
        // If the URL isn't an irccloud URL, we don't care if it is down, the irccloud interface should still work.
        return;
    }

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert addButtonWithTitle:@"Retry"];
    [alert addButtonWithTitle:@"Quit"];
    NSArray *buttons = [alert buttons];
    [[buttons objectAtIndex:0] setKeyEquivalent:@"\r"];
    [[buttons objectAtIndex:1] setKeyEquivalent:@"\033"];
    [alert setMessageText:@"Unable to connect to IRCCloud"];
    [alert setInformativeText:@"Check your internet connection."];
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse responseCode) {
        if (responseCode == NSAlertFirstButtonReturn) {
            [view setMainFrameURL:url];
        } else {
            [NSApp stop:self];
        }
    }];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    [self handleNetworkError:error forWebView:sender];
}

- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
    [self handleNetworkError:error forWebView:sender];
}

#pragma mark WebPolicyDelegate

- (void)webView:(WebView *)webView decidePolicyForNewWindowAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request
   newFrameName:(NSString *)frameName decisionListener:(id <WebPolicyDecisionListener>)listener {
  // route all links that request a new window to default browser
  [listener ignore];
  [[NSWorkspace sharedWorkspace] openURL:[request URL]];
}

#pragma mark WebUIDelegate

- (BOOL)webView:(WebView *)sender runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"No"];
    NSArray *buttons = [alert buttons];
    [[buttons objectAtIndex:0] setKeyEquivalent:@"\r"];
    [[buttons objectAtIndex:1] setKeyEquivalent:@"\033"];
    [alert setMessageText:@"Please confirm"];
    [alert setInformativeText:message];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

- (void)webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert addButtonWithTitle:@"Ok"];
    NSArray *buttons = [alert buttons];
    [[buttons objectAtIndex:0] setKeyEquivalent:@"\r"];
    [alert setMessageText:@"irccloud"];
    [alert setInformativeText:message];
    [alert runModal];
}

- (void)webView:(WebView *)webView addMessageToConsole:(NSDictionary *)dictionary {
  NSLog(@"ERROR: %@", [dictionary objectForKey:@"message"]);
}

- (void)webView:(WebView *)sender runOpenPanelForFileButtonWithResultListener:(id < WebOpenPanelResultListener >)resultListener
{
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    [openDlg setCanChooseFiles:YES];
    [openDlg setCanChooseDirectories:NO];
    
    if ([openDlg runModal] == NSModalResponseOK) {
        NSArray* files = [[openDlg URLs] valueForKey:@"relativePath"];
        [resultListener chooseFilenames:files];
    }
}

#pragma mark -

- (void)dealloc {
  [console release];
  [notificationProvider release];
  [userScripts release];
  [super dealloc];
}

@end
